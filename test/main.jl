# Here we test the `julia -m ExplicitImports` functionality
cmd = Base.julia_cmd()
dir = pkgdir(ExplicitImports)
help = readchomp(`$cmd --project=$(dir) -m ExplicitImports --help`)
@test contains(help, "SYNOPSIS")
@test contains(help, "Path to the root directory")
run1 = readchomp(`$cmd --project=$(dir) -m ExplicitImports $dir`)
@test contains(run1, "These could be explicitly imported as follows")
run2 = readchomp(`$cmd --project=$(dir) -m ExplicitImports $dir/Project.toml`)
@test contains(run2, "These could be explicitly imported as follows")
io = IOBuffer()
err_run = success(pipeline(`$cmd --project=$(dir) -m ExplicitImports $dir/blah.toml`;
                           stderr=io))
@test !err_run
@test contains(chomp(String(take!(io))),
               "Argument `/Users/eph/ExplicitImports/blah.toml` is not a supported flag, directory, or file. See the output of `--help` for usage details.")
