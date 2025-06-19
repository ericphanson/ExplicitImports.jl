const CHECKS = ["all_explicit_imports_are_public",
                "all_qualified_accesses_are_public",
                "all_explicit_imports_via_owners",
                "all_qualified_accesses_via_owners",
                "no_implicit_imports",
                "no_self_qualified_accesses",
                "no_stale_explicit_imports"]
const EXCLUDE_PREFIX = "exclude_"

function err(str)
    printstyled(stderr, "ERROR: "; bold=true, color=:red)
    println(stderr,
            str,
            " See the output of `--help` for usage details.")
    return 1
end

function get_package_name_from_project_toml(path)
    if endswith(path, "Project.toml")
        project_path = path
    elseif isfile(joinpath(path, "Project.toml"))
        project_path = joinpath(path, "Project.toml")
    else
        return err("No `Project.toml` file found at $path or $(joinpath(path, "Project.toml")).")
    end
    project = parsefile(project_path)
    if !haskey(project, "name")
        return err("`Project.toml` does not have `name` entry; does not correspond to valid Julia package.")
    end
    package = Symbol(project["name"])
    return package, project_path
end

function get_manifest_julia_version(manifest_path)
    isfile(manifest_path) || return nothing
    manifest = TOML.tryparsefile(manifest_path)
    isnothing(manifest) && return nothing
    v_str = get(manifest, "julia_version", nothing)
    isnothing(v_str) && return nothing
    return tryparse(VersionNumber, v_str)
end

function julia_has_color()
    if isdefined(Base, :ioproperties)
        return get(Base.ioproperties(stderr), :color, false)
    else
        # safe fallback
        return false
    end
end

function activate_and_load(package, project_path)
    @info "Loading package at $(abspath(project_path))"
    manifest_path = Pkg.Types.manifestfile_path(dirname(project_path))
    v = get_manifest_julia_version(manifest_path)
    pkg_io = IOContext(Base.BufferStream(), :color => julia_has_color())
    try # we will dump `pkg_io` to stderr if there is an error
        if !isnothing(v) && v.major == VERSION.major && v.minor == VERSION.minor
            # unless we already have a manifest that should work, we will use a temp env
            # we don't want to:
            # 1. error because the user has a manifest with a different julia version
            # 2. create a new manifest with `Pkg.instantiate` when one does not exist
            @info "Using existing manifest at $manifest_path"
            @debug "Manifest version: $v. Current version: $VERSION"
            @static if isdefined(Base, :set_active_project)
                Base.set_active_project(project_path)
            else
                Pkg.activate(project_path; io=pkg_io)
                Pkg.instantiate(; io=pkg_io)
            end
        else
            # safe fallback: temp env
            @info "Creating new manifest in temporary environment"
            Pkg.activate(; temp=true, io=pkg_io)
            Pkg.develop(; path=dirname(project_path), io=pkg_io)
        end
    catch
        # Dump pkg io
        close(pkg_io)
        write(stderr, read(pkg_io))
        rethrow()
    end

    # In an apps context, our `LOAD_PATH` may not include the active project!
    # We have just set an active project we do want to load from, so let's push
    # it into our `LOAD_PATH`
    load_path_project = Base.active_project()
    pushfirst!(LOAD_PATH, load_path_project)
    try
        @eval Main begin
            using $package: $package
        end
    finally
        # let us try to be good citizens and undo the `LOAD_PATH` modification
        # we have made, if no one has messed with since.
        if !isempty(LOAD_PATH) && first(LOAD_PATH) == load_path_project
            popfirst!(LOAD_PATH)
        end
    end
end

function run_checks(package, selected_checks; fail_fast::Bool = false)
    errs = []
    for check in selected_checks
        @info "Checking $check"
        try
            @eval Main $ExplicitImports.$(Symbol("check_" * check))($package)
        catch e
            push!(errs, e)
            fail_fast && break
        end
    end
    if !isempty(errs)
        for err in errs
            printstyled(stderr, "ERROR: "; bold=true, color=:red)
            Base.showerror(stderr, err)
        end
        return 1
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
    println(io, "       --fail-fast")
    println(io, "           Exit on first --check error and skip remaining ones")
    println(io, "       --check")
    println(io,
            "           Run checks instead of printing. If --checklist is not specified, all checks are run")
    println(io, "       --checklist <check1,check2>,...")
    println(io,
            """           Run checks specified by <check1>,<check2>,...
                       This will imply --check.

                       Valid values for each check are:
                       - Individual checks:
                             $(join(CHECKS, ",\n\t\t "))
                       - Select all checks: all
                       - Exclude a check: prepend an individual check with '$EXCLUDE_PREFIX'

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
    valid_check_values = [CHECKS; "all"; EXCLUDE_PREFIX .* CHECKS]
    selected_checks = copy(CHECKS)
    should_run_checks = false
    should_print = false
    fail_fast = false
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
        elseif x == "--fail-fast"
            fail_fast = true
        elseif x == "--print"
            should_print = true
        elseif x == "--checklist"
            should_run_checks = true # Automatically imply --check
            if length(args) == 0
                return err("Argument `--checklist` requires a value.")
            end
            values = split(popfirst!(args), ",")
            # If any of passed checks is not an exclude, then starts with an empty list
            if any(.!startswith(EXCLUDE_PREFIX).(values))
                selected_checks = String[]
            end
            for value in values
                unique!(selected_checks)
                if !(value in valid_check_values)
                    return err("Invalid check passed to --checklist: $value.")
                end
                if value == "all"
                    selected_checks = copy(CHECKS)
                elseif value in CHECKS
                    push!(selected_checks, value)
                elseif startswith(EXCLUDE_PREFIX)(value)
                    check = value[(1 + length(EXCLUDE_PREFIX)):end]
                    if !(check in CHECKS)
                        return err("Check $check is not part of the valid checks, so it can't be excluded.")
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
                return err("Argument `$x` is not a supported flag, directory, or file.")
            end
        end
    end

    # Print by default
    if !should_run_checks && !should_print
        should_print = true
    end

    ret = get_package_name_from_project_toml(path)
    if ret isa Integer # handle errors
        return ret
    end
    package, project_path = ret

    activate_and_load(package, project_path)
    if should_print
        try
            @eval Main $ExplicitImports.print_explicit_imports($package)
        catch e
            printstyled(stderr, "ERROR: "; bold=true, color=:red)
            Base.showerror(stderr, e)
            return 1
        end
    end
    if should_run_checks
        if length(selected_checks) == 0
            return err("The passed combination of checks $values made the selection empty.")
        end
        return run_checks(package, selected_checks; fail_fast)
    end
    return 0
end

@static if isdefined(Base, Symbol("@main"))
    @main
end
