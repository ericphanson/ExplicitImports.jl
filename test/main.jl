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
    help = replace(readchomp(`$cmd --project=$(dir) -e 'using ExplicitImports: main; main(["--help"])'`),
                   r"\s+" => " ")
    @test contains(help, "SYNOPSIS")
    @test contains(help, "Path to the root directory")
    run1 = replace(readchomp(`$cmd --project=$(dir) -e "using ExplicitImports: main; main([\"$(dir)\"])"`),
                   r"\s+" => " ")
    @test contains(run1, "These could be explicitly imported as follows")
    run2 = replace(readchomp(`$cmd --project=$(dir) -e "using ExplicitImports: main; main([\"$(dir)/Project.toml\"])"`),
                   r"\s+" => " ")
    @test contains(run2, "These could be explicitly imported as follows")
    io = IOBuffer()
    err_run = success(pipeline(`$cmd --project=$(dir) -e "using ExplicitImports: main; main([\"$(dir)/blah.toml\"])"`;
                               stderr=io))
    @test !err_run
    str = replace(String(take!(io)), r"\s+" => " ")
    @test contains(str,
                   "is not a supported flag, directory, or file. See the output of `--help` for usage details")
end
