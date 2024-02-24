using ExplicitImports
using ExplicitImports: analyze_all_names, has_ancestor, should_skip, restrict_to_module,
                       module_path
using Test
using DataFrames

include("Exporter.jl")
include("TestModA.jl")

@testset "has_ancestor" begin
    @test has_ancestor(TestModA.SubModB, TestModA)
    @test !has_ancestor(TestModA, TestModA.SubModB)

    @test should_skip(Base.Iterators; skips=(Base, Core))
end

@testset "ExplicitImports.jl" begin
    @test explicit_imports(TestModA, "TestModA.jl") == ["using .Exporter: exported_a"]

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
    @test explicit_imports(TestModA.SubModB, "TestModA.jl") ==
          ["using .Exporter3: exported_b", "using .TestModA: f"]

    mod_path = module_path(TestModA.SubModB)
    @test mod_path == [:SubModB, :TestModA]
    sub_df = restrict_to_module(df, TestModA.SubModB)

    h = only(subset(sub_df, :name => ByRow(==(:h))))
    @test h.global_scope
    @test !h.assigned_before_used

    # Nested submodule with same name as outer module...
    @test explicit_imports(TestModA.SubModB.TestModA, "TestModA.jl") ==
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

    from_outer_file = @test_logs (:warn, r"stale") explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                    "TestModA.jl")
    from_inner_file = @test_logs (:warn, r"stale") explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                    "TestModC.jl")
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
end
