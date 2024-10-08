# We need both `@main` and `julia -m` to be supported:
if isdefined(Base, Symbol("@main")) && VERSION >= v"1.12.0-DEV.102"
    @testset "Test `julia -m ExplicitImports` functionality" begin
        cmd = Base.julia_cmd()
        dir = pkgdir(ExplicitImports)
        help = replace(readchomp(`$cmd --project=$(dir) -m ExplicitImports --help`),
                       r"\s+" => " ")
        @test contains(help, "SYNOPSIS")
        @test contains(help, "Path to the root directory")
        run1 = replace(readchomp(`$cmd --project=$(dir) -m ExplicitImports $dir`),
                       r"\s+" => " ")
        @test contains(run1, "These could be explicitly imported as follows")
        run2 = replace(readchomp(`$cmd --project=$(dir) -m ExplicitImports $dir/Project.toml`),
                       r"\s+" => " ")
        @test contains(run2, "These could be explicitly imported as follows")
        io = IOBuffer()
        err_run = success(pipeline(`$cmd --project=$(dir) -m ExplicitImports $dir/blah.toml`;
                                   stderr=io))
        @test !err_run
        str = replace(String(take!(io)), r"\s+" => " ")
        @test contains(str,
                       "is not a supported flag, directory, or file. See the output of `--help` for usage details")
    end
end

@testset "Test main functionality" begin
    cmd = Base.julia_cmd()
    dir = pkgdir(ExplicitImports)
    help = replace(readchomp(`$cmd --project=$(dir) -e 'using ExplicitImports: main; exit(main(["--help"]))'`),
                   r"\s+" => " ")
    @test contains(help, "SYNOPSIS")
    @test contains(help, "Path to the root directory")
    run1 = replace(readchomp(`$cmd --project=$(dir) -e "using ExplicitImports: main; exit(main([\"$(dir)\"]))"`),
                   r"\s+" => " ")
    @test contains(run1, "These could be explicitly imported as follows")
    run2 = replace(readchomp(`$cmd --project=$(dir) -e "using ExplicitImports: main; exit(main([\"$(dir)/Project.toml\"]))"`),
                   r"\s+" => " ")
    @test contains(run2, "These could be explicitly imported as follows")
    io = IOBuffer()
    err_run = success(pipeline(`$cmd --project=$(dir) -e "using ExplicitImports: main; exit(main([\"$(dir)/blah.toml\"]))"`;
                               stderr=io))
    @test !err_run
    str = replace(String(take!(io)), r"\s+" => " ")
    @test contains(str,
                   "is not a supported flag, directory, or file. See the output of `--help` for usage details")
end

if VERSION >= v"1.9-" # test only when we have package extensions, for simplicity
    @testset "Test checks" begin
        # Expected failure on no_implicit_imports due to DataFramesExt
        dir = joinpath(@__DIR__, "TestPkg")
        expected_failure = ["no_implicit_imports"]

        @testset "Specific check $check" for check in ExplicitImports.CHECKS
            expected = check in expected_failure ? 1 : 0
            @test ExplicitImports.main([dir, "--check", "--checklist", check]) == expected
        end
        @testset "All checks" begin
            @test ExplicitImports.main([dir, "--check", "--checklist", "all"]) == 1
        end
        @testset "Exclude check" begin
            checks = join("exclude_" .* expected_failure, ",")
            @test ExplicitImports.main([dir, "--check", "--checklist", checks]) == 0
        end
    end
end
