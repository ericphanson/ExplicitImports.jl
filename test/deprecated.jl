# Deprecation log
@test_logs (:warn, r"deprecated") explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                "TestModC.jl";
                                                                warn_stale=true)
# Deprecation logs when `warn_stale=false`
@test_logs (:warn, r"deprecated") explicit_imports(TestModA, "TestModA.jl";
                                                   warn_stale=false)

@testset "stale_explicit_imports" begin
    @test_logs match_mode = :any (:warn, r"deprecated") @test stale_explicit_imports(DynMod,
                                                                                     "DynMod.jl") ==
                                                              [DynMod => nothing,
                                                               DynMod.Hidden => nothing]

    @test_logs match_mode = :any (:warn, r"deprecated") @test stale_explicit_imports_nonrecursive(DynMod,
                                                                                                  "DynMod.jl") ===
                                                              nothing

    @test_logs match_mode = :any (:warn, r"deprecated") @test stale_explicit_imports(DynMod,
                                                                                     "DynMod.jl";
                                                                                     strict=false) ==
                                                              [DynMod => [],
                                                               # Wrong! Missing stale explicit export
                                                               DynMod.Hidden => []]

    @test_logs match_mode = :any (:warn, r"deprecated") @test stale_explicit_imports_nonrecursive(DynMod,
                                                                                                  "DynMod.jl";
                                                                                                  strict=false) ==
                                                              []
    @test_logs match_mode = :any (:warn, r"deprecated") str = sprint(print_stale_explicit_imports,
                                                                     DynMod,
                                                                     "DynMod.jl")
    @test contains(str, "DynMod could not be accurately analyzed")
end
