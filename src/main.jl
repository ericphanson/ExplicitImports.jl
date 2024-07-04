function err(str)
    printstyled(stderr, "ERROR: "; bold=true, color=:red)
    println(stderr,
            str,
            " See the output of `--help` for usage details.")
    return 1
end

function auto_print_explicit_imports(path)
    if endswith(path, "Project.toml")
        project_path = path
    elseif isfile(joinpath(path, "Project.toml"))
        project_path = joinpath(path, "Project.toml")
    else
        return err("No `Project.toml` file found at $path or $(joinpath(path, "Project.toml"))")
    end
    project = parsefile(project_path)
    if !haskey(project, "name")
        return err("`Project.toml` does not have `name` entry; does not correspond to valid Julia package")
    end
    package = Symbol(project["name"])
    Base.set_active_project(project_path)
    @eval Main begin
        using $package: $package
    end
    @eval begin
        print_explicit_imports($package)
    end
    return 0
end

# Print a typical cli program help message
function print_help()
    io = stdout
    printstyled(io, "NAME\n"; bold=true)
    println(io, "       ExplicitImports.main - analyze a package's namespace")
    println(io)
    printstyled(io, "SYNOPSIS\n"; bold=true)
    println(io, "       julia -m ExplicitImports <path>")
    println(io)
    printstyled(io, "DESCRIPTION\n"; bold=true)
    println(io,
            """       `ExplicitImports.main` (typically invoked as `julia -m ExplicitImports`)
                      analyzes a package's imports and qualified accesses, and prints the results.
               """)
    printstyled(io, "OPTIONS\n"; bold=true)
    println(io, "       <path>")
    println(io, "           Path to the root directory of the package (default: pwd)")
    println(io, "       --help")
    println(io, "           Show this message")
    return
end

function (@main)(ARGS)
    # Argument defaults
    path::String = pwd()
    # Argument parsing
    while length(ARGS) > 0
        x = popfirst!(ARGS)
        if x == "--help"
            # Print help and return (even if other arguments are present)
            print_help()
            return 0
        elseif length(ARGS) == 0 && isdir(abspath(x)) || isfile(abspath(x))
            # If ARGS is empty and the argument is a directory this is the root directory
            path = abspath(x)
        else
            # Unknown argument
            return err("Argument `$x` is not a supported flag, directory, or file.")
        end
    end
    return ExplicitImports.auto_print_explicit_imports(path)
end
