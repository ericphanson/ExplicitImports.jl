@testset "explicit_imports with `warn_stale`" begin
    # Deprecation log
    @test_logs (:warn, r"deprecated") explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                    "TestModC.jl";
                                                                    warn_stale=true)
    # Deprecation logs when `warn_stale=false`
    @test_logs (:warn, r"deprecated") explicit_imports(TestModA, "TestModA.jl";
                                                       warn_stale=false)

    @test_logs (:warn, r"deprecated") sprint(io -> print_explicit_imports(io, TestModA,
                                                                          "TestModA.jl";
                                                                          warn_stale=false))

    @test_logs (:warn, r"deprecated") sprint(io -> print_explicit_imports(io, TestModA,
                                                                          "TestModA.jl";
                                                                          warn_stale=true))

    @test_throws ArgumentError sprint(io -> print_explicit_imports(io, TestModA,
                                                                   "TestModA.jl";
                                                                   warn_stale=true,
                                                                   warn_improper_explicit_imports=true))
end

@testset "stale_explicit_imports" begin
    # 3 dynamic include statements
    l = (:warn, r"Dynamic")
    logs = (l, l, l)

    @test_logs (:warn, r"deprecated") logs... @test stale_explicit_imports(DynMod,
                                                                           "DynMod.jl") ==
                                                    [DynMod => nothing,
                                                     DynMod.Hidden => nothing]

    @test_logs logs... (:warn, r"deprecated") @test stale_explicit_imports_nonrecursive(DynMod,
                                                                                        "DynMod.jl") ===
                                                    nothing

    @test_logs (:warn, r"deprecated") logs... @test stale_explicit_imports(DynMod,
                                                                           "DynMod.jl";
                                                                           strict=false) ==
                                                    [DynMod => [],
                                                     # Wrong! Missing stale explicit export
                                                     DynMod.Hidden => []]

    @test_logs logs... (:warn, r"deprecated") @test stale_explicit_imports_nonrecursive(DynMod,
                                                                                        "DynMod.jl";
                                                                                        strict=false) ==
                                                    []
    str = @test_logs (:warn, r"deprecated") logs... sprint(print_stale_explicit_imports,
                                                           DynMod,
                                                           "DynMod.jl")
    @test contains(str, "DynMod could not be accurately analyzed")

    # Printing via `print_stale_explicit_imports`
    str = @test_logs (:warn, r"deprecated") sprint(io -> print_stale_explicit_imports(io,
                                                                                      TestModA,
                                                                                      "TestModA.jl";
                                                                                      allow_internal_imports=false))
    @test contains(str, "TestModA has no stale explicit imports")
    @test contains(str, "TestModC has stale explicit imports for these unused names")

    # Printing via `print_improper_qualified_accesses`
    str = @test_logs (:warn, r"deprecated") sprint(io -> print_improper_qualified_accesses(io,
                                                                                           TestQualifiedAccess,
                                                                                           "test_qualified_access.jl";
                                                                                           allow_internal_accesses=false))
    str = replace(str, r"\s+" => " ")
    @test contains(str, "accesses 2 names from non-owner modules")
    @test contains(str, "ABC has owner")

    @test_logs (:warn, r"deprecated") @test only_name_source(stale_explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                                                 "TestModC.jl")) ==
                                            [(; name=:exported_c),
                                             (; name=:exported_d)]

    # Recursive version
    lookup = @test_logs (:warn, r"deprecated") Dict(only_name_source(stale_explicit_imports(TestModA,
                                                                                            "TestModA.jl")))
    @test lookup[TestModA.SubModB.TestModA.TestModC] ==
          [(; name=:exported_c), (; name=:exported_d)]
    @test isempty(lookup[TestModA])
end

@testset "require_submodule_access kwarg" begin
    for val in (true, false)
        @test_logs (:warn, r"deprecated") improper_qualified_accesses(TestQualifiedAccess,
                                                                      "test_qualified_access.jl";
                                                                      require_submodule_access=val)

        @test_logs (:warn, r"deprecated") improper_qualified_accesses_nonrecursive(TestQualifiedAccess,
                                                                                   "test_qualified_access.jl";
                                                                                   require_submodule_access=val)
    end
end
