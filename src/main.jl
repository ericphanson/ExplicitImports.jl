const checks = ["all_explicit_imports_are_public",
                "all_qualified_accesses_are_public",
                "all_explicit_imports_via_owners",
                "all_qualified_accesses_via_owners",
                "no_implicit_imports",
                "no_self_qualified_accesses",
                "no_stale_explicit_imports"]
const exclude_prefix = "exclude_"

function err(str)
    printstyled(stderr, "ERROR: "; bold=true, color=:red)
    println(stderr,
            str,
            " See the output of `--help` for usage details.")
    return exit(1)
end

function get_package_name_from_project_toml(path)
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
    return package, project_path
end

function activate_and_load(package, project_path)
    @static if isdefined(Base, :set_active_project)
        Base.set_active_project(project_path)
    else
        @eval Main begin
            using Pkg
            Pkg.activate($project_path)
        end
    end
    @eval Main begin
        using $package: $package
        using ExplicitImports: ExplicitImports
    end
end

function run_checks(package, selected_checks)
    for check in selected_checks
        @info "Checking $check"
        try
            @eval Main ExplicitImports.$(Symbol("check_" * check))($package)
        catch e
            printstyled(stderr, "ERROR: "; bold=true, color=:red)
            Base.showerror(stderr, e)
            exit(1)
        end
    end
end

# Print a typical cli program help message
function print_help()
    io = stdout
    printstyled(io, "NAME\n"; bold=true)
    println(io, "       ExplicitImports.main - analyze a package's namespace")
    println(io)
    printstyled(io, "SYNOPSIS\n"; bold=true)
    println(io, "       julia -m ExplicitImports [OPTIONS] <path>")
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
    println(io, "       --check")
    println(io,
            "           Run checks instead of printing. If --checklist is not specified, all checks are run")
    println(io, "       --checklist <check1,check2>,...")
    println(io,
            """           Run checks specified by <check1>,<check2>,...
                       This will imply --check.

                       Valid values for each check are:
                       - Individual checks:
                             $(join(checks, ",\n\t\t "))
                       - Select all checks: all
                       - Exclude a check: prepend an individual check with '$exclude_prefix'

                       The selection logic is performed in the order given.
                       If you pass only exclusions, it will assume that it starts from a complete list, and then excludes.
                       If you pass any individual checks, it will assume that it starts from an empty list, and then includes.
                       Passing both individual and exclusion checks does not make sense.
            """)
    return
end

function main(args)
    # Argument defaults
    path::String = pwd()
    valid_check_values = [checks; "all"; exclude_prefix .* checks]
    selected_checks = copy(checks)
    should_run_checks = false
    should_print = false
    path = "."

    # Argument parsing
    while length(args) > 0
        x = popfirst!(args)
        if x == "--help"
            # Print help and return (even if other arguments are present)
            print_help()
            return 0
        elseif x == "--check"
            should_run_checks = true
        elseif x == "--print"
            should_print = true
        elseif x == "--checklist"
            should_run_checks = true # Automatically imply --check
            if length(args) == 0
                return err("Argument `--checklist` requires a value")
            end
            values = split(popfirst!(args), ",")
            # If any of passed checks is not an exclude, then starts with an empty list
            if any(.!startswith(exclude_prefix).(values))
                selected_checks = String[]
            end
            for value in values
                unique!(selected_checks)
                if !(value in valid_check_values)
                    return err("Invalid check passed to --checklist: $value")
                end
                if value == "all"
                    selected_checks = copy(checks)
                elseif value in checks
                    push!(selected_checks, value)
                elseif startswith(exclude_prefix)(value)
                    check = value[(1 + length(exclude_prefix)):end]
                    if !(check in checks)
                        return err("Check $check is not part of the valid checks, so it can't be excluded")
                    end
                    i = findfirst(selected_checks .== check)
                    if !isnothing(i)
                        deleteat!(selected_checks, i)
                    end
                end
            end
        else
            # The path might be out of order
            if isdir(abspath(x)) || isfile(abspath(x))
                # If the argument is a directory this is the root directory
                path = abspath(x)
            else
                # Unknown argument
                return err("Argument `$x` is not a supported flag, directory, or file. See the output of `--help` for usage details")
            end
        end
    end

    # Print by default
    if !should_run_checks && !should_print
        should_print = true
    end

    package, project_path = get_package_name_from_project_toml(path)

    if should_print || should_run_checks
        activate_and_load(package, project_path)
    end
    if should_print
        @eval Main ExplicitImports.print_explicit_imports($package)
    end
    if should_run_checks
        if length(selected_checks) == 0
            return err("The passed combination of checks $values made the selection empty")
        end
        run_checks(package, selected_checks)
    end
end

@static if isdefined(Base, Symbol("@main"))
    @main
end
