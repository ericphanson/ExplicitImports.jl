using ExplicitImports
using ExplicitImports: analyze_all_names, has_ancestor, should_skip, restrict_to_module,
                       module_path, explicit_imports_single, using_statement
using Test
using DataFrames

include("Exporter.jl")
include("TestModA.jl")
include("test_mods.jl")

@testset "has_ancestor" begin
    @test has_ancestor(TestModA.SubModB, TestModA)
    @test !has_ancestor(TestModA, TestModA.SubModB)

    @test should_skip(Base.Iterators; skips=(Base, Core))
end

# TODO- unit tests for `analyze_import_type`, `is_qualified`, `analyze_name`, etc.
# TODO- tests for dynamic imports (e.g. that the warning is thrown correctly, once per path)

@testset "ExplicitImports.jl" begin
    @test using_statement.(explicit_imports_single(TestModA, "TestModA.jl")) ==
          ["using .Exporter: exported_a"]

    df, imports = analyze_all_names("TestModA.jl")
    locals = contains.(string.(df.name), Ref("local"))
    @test all(!, df.global_scope[locals])

    # we use `x` in two scopes; first time is global scope, second time is local
    xs = subset(df, :name => ByRow(==(:x)))
    @test xs[1, :global_scope]
    @test !xs[2, :global_scope]
    @test xs[2, :assigned_before_used]

    # we use `exported_a` in two scopes; both times refer to the global name
    exported_as = subset(df, :name => ByRow(==(:exported_a)))
    @test exported_as[1, :global_scope]
    @test !exported_as[2, :global_scope]
    @test !exported_as[2, :assigned_before_used]

    # Test submodules
    @test using_statement.(explicit_imports_single(TestModA.SubModB, "TestModA.jl")) ==
          ["using .Exporter3: exported_b", "using .TestModA: f"]

    mod_path = module_path(TestModA.SubModB)
    @test mod_path == [:SubModB, :TestModA]
    sub_df = restrict_to_module(df, TestModA.SubModB)

    h = only(subset(sub_df, :name => ByRow(==(:h))))
    @test h.global_scope
    @test !h.assigned_before_used

    # Nested submodule with same name as outer module...
    @test using_statement.(explicit_imports_single(TestModA.SubModB.TestModA,
                                                   "TestModA.jl")) ==
          ["using .Exporter3: exported_b"]

    # Check we are getting innermost names and not outer ones
    subsub_df = restrict_to_module(df, TestModA.SubModB.TestModA)
    @test :inner_h in subsub_df.name
    @test :h ∉ subsub_df.name
    # ...we do currently get the outer ones when the module path prefixes collide
    @test_broken :f ∉ subsub_df.name
    @test_broken :func ∉ subsub_df.name

    df, imports = analyze_all_names("TestModC.jl")

    # starts from innermost
    @test module_path(TestModA.SubModB.TestModA.TestModC) ==
          [:TestModC, :TestModA, :SubModB, :TestModA]

    from_outer_file = @test_logs (:warn, r"stale") using_statement.(explicit_imports_single(TestModA.SubModB.TestModA.TestModC,
                                                                                            "TestModA.jl"))
    from_inner_file = @test_logs (:warn, r"stale") using_statement.(explicit_imports_single(TestModA.SubModB.TestModA.TestModC,
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

    @test from_inner_file == ["using .TestModA: f"]

    @test stale_explicit_imports(TestModA.SubModB.TestModA.TestModC, "TestModC.jl") ==
          [:exported_c, :exported_d]

    # in particular, this ensures we don't add `using ExplicitImports: ExplicitImports`
    # (maybe eventually we will want to though)
    @test using_statement.(explicit_imports_single(TestMod1,
                                                   "test_mods.jl")) ==
          ["using ExplicitImports: print_explicit_imports"]

    # Recursion
    nested = @test_logs (:warn, r"stale") explicit_imports(TestModA, "TestModA.jl")
    @test nested isa Vector{Pair{Module,Vector{Pair{Symbol,Module}}}}
    @test TestModA in first.(nested)
    @test TestModA.SubModB in first.(nested)
    @test TestModA.SubModB.TestModA in first.(nested)
    @test TestModA.SubModB.TestModA.TestModC in first.(nested)

    # Printing
    str = sprint(print_explicit_imports, TestModA, "TestModA.jl")
    @test contains(str, "Module Main.TestModA is relying on implicit imports")
    @test contains(str, "using .Exporter: exported_a")
    @test contains(str,
                   "Additionally Main.TestModA.SubModB.TestModA.TestModC has stale explicit imports for these unused names")
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

    # you can use skips to skip whole modules
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    skips=(Base, Core, ExplicitImports)) === nothing

    @test_throws ImplicitImportsException check_no_implicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                    "TestModC.jl")

    # test submodule ignores
    @test check_no_implicit_imports(TestModA.SubModB.TestModA, "TestModC.jl";
                                    ignore=(TestModA.SubModB.TestModA.TestModC,)) ===
          nothing

    @test_throws StaleImportsException check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                       "TestModC.jl")

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
end
