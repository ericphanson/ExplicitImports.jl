using ExplicitImports
using ExplicitImports: analyze_all_names
using Test

include("Exporter.jl")
include("TestModA.jl")

@testset "ExplicitImports.jl" begin
    @test explicit_imports(TestModA, "TestModA.jl") == ["using .Exporter: exported_a"]

    df = analyze_all_names("TestModA.jl")
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
    @test explicit_imports(TestModA.SubModB, "TestModA.jl") == ["using .Exporter3: exported_b", "using .TestModA: f"]
    sub_df = subset(df, :module_path => ByRow(ms -> first(ms) == nameof(TestModA.SubModB)))

    h = only(subset(sub_df, :name => ByRow(==(:h))))
    @test h.global_scope
    @test !h.assigned_before_used

end
