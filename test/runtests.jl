using Pkg
Pkg.develop(; path=joinpath(@__DIR__, "TestPkg"))
Pkg.precompile()
using ExplicitImports
using ExplicitImports: analyze_all_names, has_ancestor, should_skip,
                       module_path, explicit_imports_nonrecursive, using_statement,
                       inspect_session, get_parent
using Test
using DataFrames
using Aqua
using Logging
using AbstractTrees
using ExplicitImports: is_function_definition_arg, SyntaxNodeWrapper, get_val
using TestPkg

# DataFrames version of `filter_to_module`
function restrict_to_module(df, mod)
    mod_path = module_path(mod)
    return subset(df,
                  :module_path => ByRow(ms -> all(Base.splat(isequal), zip(ms, mod_path))))
end

function drop_location(nt::@NamedTuple{name::Symbol,source::Module,location::String})
    return (; nt.name, nt.source)
end
function drop_location(nt::@NamedTuple{name::Symbol,location::String})
    return (; nt.name)
end
drop_location(::Nothing) = nothing
drop_location(v::Vector) = drop_location.(v)
drop_location(p::Pair) = first(p) => drop_location(last(p))

include("Exporter.jl")
include("TestModA.jl")
include("test_mods.jl")
include("DynMod.jl")
include("TestModArgs.jl")
include("examples.jl")

# package extension support needs Julia 1.9+
if VERSION > v"1.9-"
    @testset "Extensions" begin
        submods = ExplicitImports.find_submodules(TestPkg)
        @test length(submods) == 2
        DataFramesExt = Base.get_extension(TestPkg, :DataFramesExt)
        @test haskey(Dict(submods), DataFramesExt)

        ext_imports = Dict(drop_location(explicit_imports(TestPkg)))[DataFramesExt]
        @test ext_imports == [(; name=:DataFrames, source=DataFrames),
                              (; name=:DataFrame, source=DataFrames),
                              (; name=:groupby, source=DataFrames)]
    end
end

@testset "TestModArgs" begin
    # don't detect `a`!
    statements = using_statement.(explicit_imports_nonrecursive(TestModArgs,
                                                                "TestModArgs.jl"))
    @test statements ==
          ["using .Exporter4: Exporter4", "using .Exporter4: A", "using .Exporter4: Z"]

    statements = using_statement.(explicit_imports_nonrecursive(ThreadPinning,
                                                                "examples.jl"))

    @test statements == ["using LinearAlgebra: LinearAlgebra"]
end

@testset "is_function_definition_arg" begin
    cursor = TreeCursor(SyntaxNodeWrapper("TestModArgs.jl"))
    leaves = collect(Leaves(cursor))
    purported_function_args = filter(is_function_definition_arg, leaves)
    # we have 9*4  functions with one argument `a`:

    # written this way to get clearer test failure messages
    vals = unique(get_val.(purported_function_args))
    @test vals == [:a]

    @test length(purported_function_args) == 9 * 4
    non_function_args = filter(!is_function_definition_arg, leaves)
    missed = filter(x -> get_val(x) === :a, non_function_args)
    @test isempty(missed)
end

@testset "has_ancestor" begin
    @test has_ancestor(TestModA.SubModB, TestModA)
    @test !has_ancestor(TestModA, TestModA.SubModB)

    @test should_skip(Base.Iterators; skip=(Base, Core))
end

function get_per_scope(per_usage_info)
    per_usage_df = DataFrame(per_usage_info)
    subset!(per_usage_df, :qualified => ByRow(!), :import_type => ByRow(==(:not_import)))
    return combine(groupby(per_usage_df, [:name, :scope_path, :module_path, :global_scope]),
                   :is_assignment => first => :assigned_first)
end

# TODO- unit tests for `analyze_import_type`, `is_qualified`, `analyze_name`, etc.

@testset "file not found" begin
    for f in (check_no_implicit_imports, check_no_stale_explicit_imports, explicit_imports,
              explicit_imports_nonrecursive, print_explicit_imports,
              print_stale_explicit_imports, stale_explicit_imports,
              stale_explicit_imports_nonrecursive)
        @test_throws FileNotFoundException f(TestModA)
    end
    str = sprint(Base.showerror, FileNotFoundException())
    @test contains(str, "module which is not top-level in a package")
end

@testset "ExplicitImports.jl" begin
    @test using_statement.(explicit_imports_nonrecursive(TestModA, "TestModA.jl")) ==
          ["using .Exporter: Exporter", "using .Exporter: exported_a",
           "using .Exporter2: Exporter2", "using .Exporter3: Exporter3"]

    per_usage_info, _ = analyze_all_names("TestModA.jl")
    df = get_per_scope(per_usage_info)
    locals = contains.(string.(df.name), Ref("local"))
    @test all(!, df.global_scope[locals])

    # we use `x` in two scopes; first time is global scope, second time is local
    xs = subset(df, :name => ByRow(==(:x)))
    @test xs[1, :global_scope]
    @test !xs[2, :global_scope]
    @test xs[2, :assigned_first]

    # we use `exported_a` in two scopes; both times refer to the global name
    exported_as = subset(df, :name => ByRow(==(:exported_a)))
    @test exported_as[1, :global_scope]
    @test !exported_as[2, :global_scope]
    @test !exported_as[2, :assigned_first]

    # Test submodules
    @test using_statement.(explicit_imports_nonrecursive(TestModA.SubModB, "TestModA.jl")) ==
          ["using .Exporter3: Exporter3", "using .Exporter3: exported_b",
           "using .TestModA: f"]

    mod_path = module_path(TestModA.SubModB)
    @test mod_path == [:SubModB, :TestModA]
    sub_df = restrict_to_module(df, TestModA.SubModB)

    h = only(subset(sub_df, :name => ByRow(==(:h))))
    @test h.global_scope
    @test !h.assigned_first

    # Nested submodule with same name as outer module...
    @test using_statement.(explicit_imports_nonrecursive(TestModA.SubModB.TestModA,
                                                         "TestModA.jl")) ==
          ["using .Exporter3: Exporter3", "using .Exporter3: exported_b"]

    # Check we are getting innermost names and not outer ones
    subsub_df = restrict_to_module(df, TestModA.SubModB.TestModA)
    @test :inner_h in subsub_df.name
    @test :h ∉ subsub_df.name
    # ...we do currently get the outer ones when the module path prefixes collide
    @test_broken :f ∉ subsub_df.name
    @test_broken :func ∉ subsub_df.name

    # starts from innermost
    @test module_path(TestModA.SubModB.TestModA.TestModC) ==
          [:TestModC, :TestModA, :SubModB, :TestModA]

    from_outer_file = @test_logs (:warn, r"stale") using_statement.(explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                                                  "TestModA.jl"))
    from_inner_file = @test_logs (:warn, r"stale") using_statement.(explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                                                  "TestModC.jl"))
    @test from_inner_file == from_outer_file
    @test "using .TestModA: f" in from_inner_file
    # This one isn't needed bc all usages are fully qualified
    @test "using .Exporter: exported_a" ∉ from_inner_file

    # This one isn't needed; it is already explicitly imported
    @test "using .Exporter: exported_b" ∉ from_inner_file

    # This one shouldn't be there; we never use it, only explicitly import it.
    # So actually it should be on a list of unnecessary imports. BUT it can show up
    # because by importing it, we have the name in the file, so we used to detect it.
    @test "using .Exporter: exported_c" ∉ from_inner_file

    @test from_inner_file == ["using .TestModA: TestModA", "using .TestModA: f"]

    # No logs when `warn_stale=false`
    @test_logs explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                             "TestModC.jl"; warn_stale=false)

    @test drop_location(stale_explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                            "TestModC.jl")) ==
          [(; name=:exported_c), (; name=:exported_d)]

    # Recursive version
    lookup = Dict(drop_location(stale_explicit_imports(TestModA, "TestModA.jl")))
    @test lookup[TestModA.SubModB.TestModA.TestModC] ==
          [(; name=:exported_c), (; name=:exported_d)]
    @test isempty(lookup[TestModA])

    # Printing
    str = sprint(print_stale_explicit_imports, TestModA, "TestModA.jl")
    @test contains(str, "TestModA has no stale explicit imports")
    @test contains(str, "TestModC has stale explicit imports for these unused names")

    @test using_statement.(explicit_imports_nonrecursive(TestMod1,
                                                         "test_mods.jl")) ==
          ["using ExplicitImports: print_explicit_imports"]

    # Recursion
    nested = @test_logs (:warn, r"stale") explicit_imports(TestModA, "TestModA.jl")
    @test nested isa Vector{Pair{Module,
                                 Vector{@NamedTuple{name::Symbol,source::Module,location::String}}}}
    @test TestModA in first.(nested)
    @test TestModA.SubModB in first.(nested)
    @test TestModA.SubModB.TestModA in first.(nested)
    @test TestModA.SubModB.TestModA.TestModC in first.(nested)

    # No logs when `warn_stale=false`
    @test_logs explicit_imports(TestModA, "TestModA.jl"; warn_stale=false)

    # Printing
    # should be no logs
    str = @test_logs sprint(print_explicit_imports, TestModA, "TestModA.jl")
    @test contains(str, "Module Main.TestModA is relying on implicit imports")
    @test contains(str, "using .Exporter: exported_a")
    @test contains(str,
                   "However, Main.TestModA.SubModB.TestModA.TestModC has stale explicit imports for these unused names")

    # test `show_locations=true`
    str = @test_logs sprint(io -> print_explicit_imports(io, TestModA, "TestModA.jl";
                                                         show_locations=true))
    @test contains(str, "using .Exporter3: Exporter3 # used at TestModA.jl:")
    @test contains(str, "(imported at TestModC.jl:")

    # `warn_stale=false` does something (also still no logs)
    str_no_warn = @test_logs sprint(io -> print_explicit_imports(io, TestModA,
                                                                 "TestModA.jl";
                                                                 warn_stale=false))
    @test length(str_no_warn) <= length(str)

    # in particular, this ensures we add `using Foo: Foo` as the first line
    @test using_statement.(explicit_imports_nonrecursive(TestMod4, "test_mods.jl")) ==
          ["using .Exporter4: Exporter4"
           "using .Exporter4: A"
           "using .Exporter4: Z"
           "using .Exporter4: a"
           "using .Exporter4: z"]
end

function exception_string(f)
    str = try
        f()
        false
    catch e
        sprint(showerror, e)
    end
    @test str isa String
    return str
end

@testset "checks" begin
    @test check_no_implicit_imports(TestModEmpty, "test_mods.jl") === nothing
    @test check_no_stale_explicit_imports(TestModEmpty, "test_mods.jl") === nothing
    @test check_no_stale_explicit_imports(TestMod1, "test_mods.jl") === nothing

    @test_throws ImplicitImportsException check_no_implicit_imports(TestMod1,
                                                                    "test_mods.jl")

    # test name ignores
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    ignore=(:print_explicit_imports,)) === nothing

    # test name mod pair ignores
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    ignore=(:print_explicit_imports => ExplicitImports,)) ===
          nothing

    # if you pass the module in the pair, you must get the right one
    @test_throws ImplicitImportsException check_no_implicit_imports(TestMod1,
                                                                    "test_mods.jl";
                                                                    ignore=(:print_explicit_imports => TestModA,)) ===
                                          nothing

    # non-existent names are OK
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    ignore=(:print_explicit_imports => ExplicitImports,
                                            :does_not_exist)) === nothing

    # you can use skip to skip whole modules
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    skip=(Base, Core, ExplicitImports)) === nothing

    @test_throws ImplicitImportsException check_no_implicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                    "TestModC.jl")

    # test submodule ignores
    @test check_no_implicit_imports(TestModA.SubModB.TestModA.TestModC, "TestModC.jl";
                                    ignore=(TestModA.SubModB.TestModA.TestModC,)) ===
          nothing

    @test_throws StaleImportsException check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                       "TestModC.jl")

    # make sure ignored names don't show up in error
    e = try
        check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                        "TestModC.jl";
                                        ignore=(:exported_d,))
        @test false # should error before this
    catch e
        e
    end
    str = sprint(Base.showerror, e)
    @test contains(str, "exported_c")
    @test !contains(str, "exported_d")

    # ignore works:
    @test check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                          "TestModC.jl";
                                          ignore=(:exported_c, :exported_d)) ===
          nothing

    # Test the printing is hitting our formatted errors
    str = exception_string() do
        return check_no_implicit_imports(TestMod1, "test_mods.jl")
    end
    @test contains(str, "is relying on the following implicit imports")

    str = exception_string() do
        return check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                               "TestModC.jl")
    end
    @test contains(str, "has stale (unused) explicit imports for:")

    @testset "Tainted modules" begin
        log = (:warn, r"Dynamic")

        @test_logs log @test drop_location(explicit_imports(DynMod, "DynMod.jl")) ==
                             [DynMod => nothing, DynMod.Hidden => nothing]
        @test_logs log @test drop_location(explicit_imports(DynMod, "DynMod.jl";
                                                            strict=false)) ==
                             [DynMod => [(; name=:print_explicit_imports,
                                          source=ExplicitImports)],
                              # Wrong! Missing explicit export
                              DynMod.Hidden => []]

        @test_logs log @test explicit_imports_nonrecursive(DynMod, "DynMod.jl") === nothing

        @test_logs log @test drop_location(explicit_imports_nonrecursive(DynMod,
                                                                         "DynMod.jl";
                                                                         strict=false)) ==
                             [(; name=:print_explicit_imports, source=ExplicitImports)]
        @test_logs log @test stale_explicit_imports(DynMod, "DynMod.jl") ==
                             [DynMod => nothing,
                              DynMod.Hidden => nothing]

        @test_logs log @test stale_explicit_imports_nonrecursive(DynMod, "DynMod.jl") ===
                             nothing

        @test_logs log @test stale_explicit_imports(DynMod, "DynMod.jl"; strict=false) ==
                             [DynMod => [],
                              # Wrong! Missing stale explicit export
                              DynMod.Hidden => []]

        @test_logs log @test stale_explicit_imports_nonrecursive(DynMod, "DynMod.jl";
                                                                 strict=false) ==
                             []
        @test_logs log str = sprint(print_stale_explicit_imports, DynMod, "DynMod.jl")
        @test contains(str, "DynMod could not be accurately analyzed")

        @test_logs log str = sprint(print_explicit_imports, DynMod, "DynMod.jl")
        @test contains(str, "DynMod could not be accurately analyzed")

        @test_logs log @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                       allow_unanalyzable=(DynMod,
                                                                           DynMod.Hidden)) ===
                             nothing

        # Ignore also works
        @test_logs log @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                       allow_unanalyzable=(DynMod,),
                                                       ignore=(DynMod.Hidden,)) ===
                             nothing

        e = UnanalyzableModuleException
        @test_logs log @test_throws e check_no_implicit_imports(DynMod,
                                                                "DynMod.jl")

        # Missed `Hidden`
        @test_logs log @test_throws e check_no_implicit_imports(DynMod,
                                                                "DynMod.jl";
                                                                allow_unanalyzable=(DynMod,),)

        @test_logs log @test check_no_stale_explicit_imports(DynMod, "DynMod.jl";
                                                             allow_unanalyzable=(DynMod,
                                                                                 DynMod.Hidden)) ===
                             nothing

        @test_logs log @test_throws e check_no_stale_explicit_imports(DynMod,
                                                                      "DynMod.jl")

        str = sprint(Base.showerror, UnanalyzableModuleException(DynMod))
        @test contains(str, "was found to be unanalyzable")
    end
end

@testset "Aqua" begin
    Aqua.test_all(ExplicitImports; ambiguities=false)
end

@testset "`inspect_session`" begin
    # We just want to make sure we are robust enough that this doesn't error
    big_str = with_logger(Logging.NullLogger()) do
        return sprint(inspect_session)
    end
end
