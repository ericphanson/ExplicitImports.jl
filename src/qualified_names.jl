# We wish to find qualified usages of a name in which the qualifying module is not the owner of the name
# it is also interesting to know if the name is public in the qualifying module

function analyze_qualified_names(mod::Module, file=pathof(mod))
    check_file(file)
    per_usage_info, _ = analyze_all_names(file)
    # Filter to qualified names
    qualified = [row for row in per_usage_info if row.qualified_by !== nothing]

    # which are in our module
    mod_path = module_path(mod)
    match = module_path -> all(Base.splat(isequal), zip(module_path, mod_path))
    filter!(qualified) do nt
        return match(nt.module_path)
    end

    # Now check:
    table = map(qualified) do row
        current_mod = mod
        for submod in row.qualified_by
            current_mod = something(trygetproperty(current_mod, submod), Some(nothing))
            current_mod isa Module || return nothing
        end
        # OK, now `current_mod` is the module from which we are accessing the name!
        # We could check here if the name is public in `current_mod`, or exported from it, etc.
        value = trygetproperty(current_mod, row.name)
        value === nothing && return nothing
        value = something(value) # unwrap

        # Skip things which do not have a parent module
        parentmod = try
            parentmodule(value)
        catch
            return nothing
        end

        return (; row.name,
                value,
                row.location,
                accessing_from=current_mod,
                which=which(current_mod, row.name),
                parentmodule=parentmod,
                accessing_from_matches_which=current_mod == which(current_mod, row.name),
                accessing_from_matches_parent=current_mod == parentmod,)
    end
    return filter!(!isnothing, table)
end

function trygetproperty(x, y)
    try
        Some(getproperty(x, y))
    catch
        nothing
    end
end

function improper_qualified_names_nonrecursive(mod::Module, file=pathof(mod))
    return improper_qualified_names_nonrecursive(stdout, mod, file)
end
function improper_qualified_names_nonrecursive(io::IO, mod::Module, file=pathof(mod))
    check_file(file)
    qualified = analyze_qualified_names(mod, file)
    problematic = [row for row in qualified if !row.accessing_from_matches_parent]
    if isempty(problematic)
        println(io, "No issues found with qualified names in $mod.")
    else
        # clumsy deduplication
        d = Dict()
        for row in problematic
            d[(; row.name, row.accessing_from)] = row
        end
        println(io, "$(length(d)) issues with qualified names were found:")
        for row in values(problematic)
            println(io,
                    "- `$(row.name)` has parentmodule $(row.parentmodule) but it was accessed from $(row.accessing_from) at $(row.location)")
        end
    end
    ExplicitImports.parent
    return nothing
end
