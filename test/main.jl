# Here we test the `julia -m ExplicitImports` functionality
cmd = Base.julia_cmd()
dir = pkgdir(ExplicitImports)
help = replace(readchomp(`$cmd --project=$(dir) -m ExplicitImports --help`), r"\s+" => " ")
@test contains(help, "SYNOPSIS")
@test contains(help, "Path to the root directory")
run1 = replace(readchomp(`$cmd --project=$(dir) -m ExplicitImports $dir`), r"\s+" => " ")
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
               "Argument `/Users/eph/ExplicitImports/blah.toml` is not a supported flag, directory, or file. See the output of `--help` for usage details.")
