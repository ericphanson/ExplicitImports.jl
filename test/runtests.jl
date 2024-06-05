using Pkg
Pkg.develop(; path=joinpath(@__DIR__, "TestPkg"))
Pkg.precompile()
using ExplicitImports
using ExplicitImports: analyze_all_names, has_ancestor, should_skip,
                       module_path, explicit_imports_nonrecursive,
                       inspect_session, get_parent, choose_exporter,
                       get_import_lhs, analyze_import_type
using Test
using DataFrames
using Aqua
using Logging, UUIDs
using AbstractTrees
using ExplicitImports: is_function_definition_arg, SyntaxNodeWrapper, get_val
using ExplicitImports: is_struct_type_param, is_struct_field_name, is_for_arg,
                       is_generator_arg, analyze_qualified_names
using TestPkg, Markdown

# DataFrames version of `filter_to_module`
function restrict_to_module(df, mod)
    mod_path = module_path(mod)
    return subset(df,
                  :module_path => ByRow(ms -> all(Base.splat(isequal), zip(ms, mod_path))))
end

# old definition for simple 1-line using statement
# (now we do linelength aware printing)
function using_statement((; name, exporters))
    # skip `Main.X`, just do `.X`
    e = choose_exporter(name, exporters)
    v = replace(string(e), "Main" => "")
    return "using $v: $name"
end

function only_name_source(nt::@NamedTuple{name::Symbol,source::Module,
                                          exporters::Vector{Module},location::String})
    @test !isempty(nt.exporters)
    return (; nt.name, nt.source)
end

function only_name_source(nt::@NamedTuple{name::Symbol,location::String})
    return (; nt.name)
end
only_name_source(::Nothing) = nothing
only_name_source(v::Vector) = only_name_source.(v)
only_name_source(p::Pair) = first(p) => only_name_source(last(p))

include("public_compat.jl")
include("Exporter.jl")
include("TestModA.jl")
include("test_mods.jl")
include("DynMod.jl")
include("TestModArgs.jl")
include("examples.jl")
include("script.jl")
include("test_qualified_access.jl")

# package extension support needs Julia 1.9+
if VERSION > v"1.9-"
    @testset "Extensions" begin
        submods = ExplicitImports.find_submodules(TestPkg)
        @test length(submods) == 2
        DataFramesExt = Base.get_extension(TestPkg, :DataFramesExt)
        @test haskey(Dict(submods), DataFramesExt)

        ext_imports = Dict(only_name_source(explicit_imports(TestPkg)))[DataFramesExt]
        @test ext_imports == [(; name=:DataFrames, source=DataFrames),
                              (; name=:DataFrame, source=DataFrames),
                              (; name=:groupby, source=DataFrames)]
    end
end

@testset "imports" begin
    cursor = TreeCursor(SyntaxNodeWrapper("imports.jl"))
    leaves = collect(Leaves(cursor))
    import_type_pairs = get_val.(leaves) .=> analyze_import_type.(leaves)
    filter!(import_type_pairs) do (k, v)
        return v !== :not_import
    end
    @test import_type_pairs ==
          [:Exporter => :import_LHS,
           :exported_a => :import_RHS,
           :exported_c => :import_RHS,
           :Exporter => :import_LHS,
           :exported_c => :import_RHS,
           :TestModA => :blanket_using_member,
           :SubModB => :blanket_using,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :h2 => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :h3 => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :h => :import_RHS,
           :Exporter => :blanket_using,
           :Exporter => :plain_import,
           :LinearAlgebra => :import_LHS,
           :map => :import_RHS,
           :_svd! => :import_RHS,
           :LinearAlgebra => :import_LHS,
           :svd => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS, :exported_b => :import_RHS]

    inds = findall(==(:import_RHS), analyze_import_type.(leaves))
    lhs_rhs_pairs = get_import_lhs.(leaves[inds]) .=> get_val.(leaves[inds])
    @test lhs_rhs_pairs == [[:., :., :Exporter] => :exported_a,
                            [:., :., :Exporter] => :exported_c,
                            [:., :., :Exporter] => :exported_c,
                            [:., :., :TestModA, :SubModB] => :h2,
                            [:., :., :TestModA, :SubModB] => :h3,
                            [:., :., :TestModA, :SubModB] => :h,
                            [:LinearAlgebra] => :map,
                            [:LinearAlgebra] => :_svd!,
                            [:LinearAlgebra] => :svd,
                            [:., :., :TestModA, :SubModB] => :exported_b]
end

#####
##### To analyze a test case
#####
# using ExplicitImports: js_node, get_parent, kind, parents_match
# using JuliaSyntax: @K_str

# cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"));
# leaves = collect(Leaves(cursor))
# leaf = leaves[end - 2] # select a leaf
# js_node(leaf) # inspect it
# p = js_node(get_parent(leaf, 3)) # see the tree, etc
# kind(p)

@testset "qualified access" begin
    # analyze_qualified_names
    qualified = analyze_qualified_names(TestQualifiedAccess, "test_qualified_access.jl")
    @test length(qualified) == 4
    ABC, DEF, HIJ, X = qualified
    @test ABC.name == :ABC
    @test DEF.public_access
    @test HIJ.public_access
    @test DEF.name == :DEF
    @test HIJ.name == :HIJ
    @test X.name == :X

    # improper_qualified_accesses
    ret = Dict(improper_qualified_accesses(TestQualifiedAccess,
                                           "test_qualified_access.jl")...)
    @test isempty(ret[TestQualifiedAccess.Bar])
    @test isempty(ret[TestQualifiedAccess.FooModule])
    @test !isempty(ret[TestQualifiedAccess])
    row = only(ret[TestQualifiedAccess])
    @test row.name == :ABC
    @test row.whichmodule == TestQualifiedAccess.Bar
    @test row.accessing_from == TestQualifiedAccess.FooModule

    # test require_submodule_access=true
    ret = improper_qualified_accesses_nonrecursive(TestQualifiedAccess,
                                                   "test_qualified_access.jl";
                                                   require_submodule_access=true)
    @test length(ret) == 2
    ABC, X = ret
    @test ABC.name == :ABC
    @test X.name == :X
    @test X.whichmodule == TestQualifiedAccess.FooModule.FooSub

    # check_all_qualified_accesses_via_owners
    ex = QualifiedAccessesFromNonOwnerException
    @test_throws ex check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                            "test_qualified_access.jl")

    ignore = (TestQualifiedAccess.FooModule => TestQualifiedAccess.Bar,)
    @test check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  ignore) === nothing

    @test_throws ex check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                            "test_qualified_access.jl";
                                                            ignore,
                                                            require_submodule_access=true)

    ignore = (TestQualifiedAccess.FooModule => TestQualifiedAccess.Bar,
              TestQualifiedAccess.FooModule => TestQualifiedAccess.FooModule.FooSub)
    @test check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  ignore,
                                                  require_submodule_access=true) === nothing

    # Printing via `print_improper_qualified_accesses`
    str = sprint(print_improper_qualified_accesses, TestQualifiedAccess,
                 "test_qualified_access.jl")
    @test contains(str, "accesses names from non-owner modules")
    @test contains(str, "`ABC` has owner")

    # Printing via `print_explicit_imports`
    str = sprint(print_explicit_imports, TestQualifiedAccess, "test_qualified_access.jl")
    @test contains(str, "accesses names from non-owner modules")
    @test contains(str, "`ABC` has owner")
end

@testset "structs" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))
    @test map(get_val, filter(is_struct_type_param, leaves)) == [:X, :Y, :QR]

    @test map(get_val, filter(is_struct_field_name, leaves)) == [:x, :x, :x, :qr, :qr]

    # Tests #34 and #36
    @test using_statement.(explicit_imports_nonrecursive(TestMod5, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra"]
end

@testset "loops" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))
    @test map(get_val, filter(is_for_arg, leaves)) == [:i, :I, :j, :k, :k, :j, :xi, :yi]

    # Tests #35
    @test using_statement.(explicit_imports_nonrecursive(TestMod6, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra"]
end

@testset "nested local scope" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))
    # Test nested local scope
    @test using_statement.(explicit_imports_nonrecursive(TestMod7, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra"]
end

@testset "types without values in function signatures" begin
    # https://github.com/ericphanson/ExplicitImports.jl/issues/33
    @test using_statement.(explicit_imports_nonrecursive(TestMod8, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra", "using LinearAlgebra: QR"]
end

@testset "generators" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))

    v = [:i1, :I, :i2, :I, :i3, :I, :i4, :I]
    w = [:i1, :I]
    @test map(get_val, filter(is_generator_arg, leaves)) ==
          [v; v; w; w; w; w; w]

    @test using_statement.(explicit_imports_nonrecursive(TestMod9, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra"]

    per_usage_info, _ = analyze_all_names("test_mods.jl")
    df = DataFrame(per_usage_info)
    subset!(df, :module_path => ByRow(==([:TestMod9])), :name => ByRow(==(:i1)))
    @test all(==(ExplicitImports.InternalGenerator), df.analysis_code)
end

@testset "while loops" begin
    @test using_statement.(explicit_imports_nonrecursive(TestMod10, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra", "using LinearAlgebra: I"]

    per_usage_info, _ = analyze_all_names("test_mods.jl")
    df = DataFrame(per_usage_info)
    subset!(df, :module_path => ByRow(==([:TestMod10])), :name => ByRow(==(:I)))
    # First one is internal, second one external
    @test df.analysis_code == [ExplicitImports.InternalAssignment, ExplicitImports.External]
end

@testset "do- syntax" begin
    @test using_statement.(explicit_imports_nonrecursive(TestMod11, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra",
           "using LinearAlgebra: Hermitian",
           "using LinearAlgebra: svd"]

    per_usage_info, _ = analyze_all_names("test_mods.jl")
    df = DataFrame(per_usage_info)
    subset!(df, :module_path => ByRow(==([:TestMod11])))

    I_codes = subset(df, :name => ByRow(==(:I))).analysis_code
    @test I_codes == [ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst,
                      ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst,
                      ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst,
                      ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst]
    svd_codes = subset(df, :name => ByRow(==(:svd))).analysis_code
    @test svd_codes == [ExplicitImports.InternalFunctionArg, ExplicitImports.External]
    Hermitian_codes = subset(df, :name => ByRow(==(:Hermitian))).analysis_code
    @test Hermitian_codes == [ExplicitImports.External, ExplicitImports.IgnoredNonFirst]
end

@testset "try-catch" begin
    @test using_statement.(explicit_imports_nonrecursive(TestMod12, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra",
           "using LinearAlgebra: I",
           "using LinearAlgebra: svd"]

    per_usage_info, _ = analyze_all_names("test_mods.jl")
    df = DataFrame(per_usage_info)
    subset!(df, :module_path => ByRow(==([:TestMod12])))

    I_codes = subset(df, :name => ByRow(==(:I))).analysis_code
    @test I_codes == [ExplicitImports.InternalAssignment,
                      ExplicitImports.External,
                      ExplicitImports.External,
                      ExplicitImports.InternalAssignment,
                      ExplicitImports.InternalCatchArgument,
                      ExplicitImports.IgnoredNonFirst,
                      ExplicitImports.External]
    svd_codes = subset(df, :name => ByRow(==(:svd))).analysis_code
    @test svd_codes == [ExplicitImports.InternalAssignment,
                        ExplicitImports.External,
                        ExplicitImports.InternalAssignment,
                        ExplicitImports.External]
end

@testset "scripts" begin
    str = sprint(print_explicit_imports_script, "script.jl")
    @test contains(str, "Script `script.jl`")
    @test contains(str, "relying on implicit imports for 1 name")
    @test contains(str, "using LinearAlgebra: norm")
    @test contains(str, "stale explicit imports for these unused names")
    @test contains(str, "- qr")
end

@testset "Don't skip source modules (#29)" begin
    # In this case `UUID` is defined in Base but exported in UUIDs
    ret = ExplicitImports.find_implicit_imports(Mod29)[:UUID]
    @test ret.source == Base
    @test ret.exporters == [UUIDs]
    # We should NOT skip it, even though `skip` includes `Base`, since the exporters
    # are not skipped.
    statements = using_statement.(explicit_imports_nonrecursive(Mod29, "examples.jl"))
    @test statements == ["using UUIDs: UUIDs", "using UUIDs: UUID"]
end

@testset "Exported module (#24)" begin
    statements = using_statement.(explicit_imports_nonrecursive(Mod24, "examples.jl"))
    # The key thing here is we do not have `using .Exporter: exported_a`,
    # since we haven't done `using .Exporter` in `Mod24`, only `using .Exporter2`
    @test statements == ["using .Exporter2: Exporter2", "using .Exporter2: exported_a"]
end

@testset "string macros (#20)" begin
    foo = only_name_source(explicit_imports_nonrecursive(Foo20, "examples.jl"))
    @test foo == [(; name=:Markdown, source=Markdown),
                  (; name=Symbol("@doc_str"), source=Markdown)]
    bar = explicit_imports_nonrecursive(Bar20, "examples.jl")
    @test isempty(bar)
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

    # written this way to get clearer test failure messages
    vals = unique(get_val.(purported_function_args))
    @test vals == [:a]

    # we have 9*4  functions with one argument `a`, plus 2 macros
    @test length(purported_function_args) == 9 * 4 + 2
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
    dropmissing!(per_usage_df, :external_global_name)
    return per_usage_df
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
          ["using .Exporter: Exporter", "using .Exporter: @mac",
           "using .Exporter2: Exporter2",
           "using .Exporter2: exported_a", "using .Exporter3: Exporter3"]

    per_usage_info, _ = analyze_all_names("TestModA.jl")
    df = get_per_scope(per_usage_info)
    locals = contains.(string.(df.name), Ref("local"))
    @test all(!, df.external_global_name[locals])

    # we use `x` in two scopes
    xs = subset(df, :name => ByRow(==(:x)))
    @test !xs[1, :external_global_name]
    @test !xs[2, :external_global_name]
    @test xs[2, :analysis_code] == ExplicitImports.InternalAssignment

    # we use `exported_a` in two scopes; both times refer to the global name
    exported_as = subset(df, :name => ByRow(==(:exported_a)))
    @test exported_as[1, :external_global_name]
    @test exported_as[2, :external_global_name]
    @test !exported_as[2, :is_assignment]

    # Test submodules
    @test using_statement.(explicit_imports_nonrecursive(TestModA.SubModB, "TestModA.jl")) ==
          ["using .Exporter3: Exporter3", "using .Exporter3: exported_b",
           "using .TestModA: f"]

    mod_path = module_path(TestModA.SubModB)
    @test mod_path == [:SubModB, :TestModA, :Main]
    sub_df = restrict_to_module(df, TestModA.SubModB)

    h = only(subset(sub_df, :name => ByRow(==(:h))))
    @test h.external_global_name
    @test !h.is_assignment

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
          [:TestModC, :TestModA, :SubModB, :TestModA, :Main]

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

    @test only_name_source(stale_explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                               "TestModC.jl")) ==
          [(; name=:exported_c), (; name=:exported_d)]

    # Recursive version
    lookup = Dict(only_name_source(stale_explicit_imports(TestModA, "TestModA.jl")))
    @test lookup[TestModA.SubModB.TestModA.TestModC] ==
          [(; name=:exported_c), (; name=:exported_d)]
    @test isempty(lookup[TestModA])

    per_usage_info, _ = analyze_all_names("TestModC.jl")
    testmodc = DataFrame(per_usage_info)
    qualified_row = only(subset(testmodc, :name => ByRow(==(:exported_a))))
    @test qualified_row.analysis_code == ExplicitImports.IgnoredQualified
    @test qualified_row.qualified_by == [:Exporter]

    qualified_row2 = only(subset(testmodc, :name => ByRow(==(:h))))
    @test qualified_row2.qualified_by == [:TestModA, :SubModB]

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
                                 Vector{@NamedTuple{name::Symbol,source::Module,
                                                    exporters::Vector{Module},location::String}}}}
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
    @test contains(str, "using .Exporter2: Exporter2, exported_a")
    @test contains(str,
                   "However, module Main.TestModA.SubModB.TestModA.TestModC has stale explicit imports for these unused names")

    # should be no logs
    # try with linewidth tiny - should put one name per line
    str = @test_logs sprint(io -> print_explicit_imports(io, TestModA, "TestModA.jl";
                                                         linewidth=0))
    @test contains(str,
                   """
                   using .Exporter2: Exporter2,
                                     exported_a""")

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
        # 3 dynamic include statements
        l = (:warn, r"Dynamic")
        log = (l, l, l)

        @test_logs log... @test only_name_source(explicit_imports(DynMod, "DynMod.jl")) ==
                                [DynMod => nothing, DynMod.Hidden => nothing]
        @test_logs log... @test only_name_source(explicit_imports(DynMod, "DynMod.jl";
                                                                  strict=false)) ==
                                [DynMod => [(; name=:print_explicit_imports,
                                             source=ExplicitImports)],
                                 # Wrong! Missing explicit export
                                 DynMod.Hidden => []]

        @test_logs log... @test explicit_imports_nonrecursive(DynMod, "DynMod.jl") ===
                                nothing

        @test_logs log... @test only_name_source(explicit_imports_nonrecursive(DynMod,
                                                                               "DynMod.jl";
                                                                               strict=false)) ==
                                [(; name=:print_explicit_imports, source=ExplicitImports)]
        @test_logs log... @test stale_explicit_imports(DynMod, "DynMod.jl") ==
                                [DynMod => nothing,
                                 DynMod.Hidden => nothing]

        @test_logs log... @test stale_explicit_imports_nonrecursive(DynMod, "DynMod.jl") ===
                                nothing

        @test_logs log... @test stale_explicit_imports(DynMod, "DynMod.jl"; strict=false) ==
                                [DynMod => [],
                                 # Wrong! Missing stale explicit export
                                 DynMod.Hidden => []]

        @test_logs log... @test stale_explicit_imports_nonrecursive(DynMod, "DynMod.jl";
                                                                    strict=false) ==
                                []
        @test_logs log... str = sprint(print_stale_explicit_imports, DynMod, "DynMod.jl")
        @test contains(str, "DynMod could not be accurately analyzed")

        @test_logs log... str = sprint(print_explicit_imports, DynMod, "DynMod.jl")
        @test contains(str, "DynMod could not be accurately analyzed")

        @test_logs log... @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                          allow_unanalyzable=(DynMod,
                                                                              DynMod.Hidden)) ===
                                nothing

        # Ignore also works
        @test_logs log... @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                          allow_unanalyzable=(DynMod,),
                                                          ignore=(DynMod.Hidden,)) ===
                                nothing

        e = UnanalyzableModuleException
        @test_logs log... @test_throws e check_no_implicit_imports(DynMod,
                                                                   "DynMod.jl")

        # Missed `Hidden`
        @test_logs log... @test_throws e check_no_implicit_imports(DynMod,
                                                                   "DynMod.jl";
                                                                   allow_unanalyzable=(DynMod,),)

        @test_logs log... @test check_no_stale_explicit_imports(DynMod, "DynMod.jl";
                                                                allow_unanalyzable=(DynMod,
                                                                                    DynMod.Hidden)) ===
                                nothing

        @test_logs log... @test_throws e check_no_stale_explicit_imports(DynMod,
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
