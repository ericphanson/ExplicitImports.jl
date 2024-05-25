function analyze_explicitly_imported_names(mod::Module, file=pathof(Mod);
                                           # private undocumented kwarg for hoisting this analysis
                                           file_analysis=get_names_used(file))
    check_file(file)
    (; per_usage_info) = filter_to_module(file_analysis, mod)

    _explicit_imports = filter(per_usage_info) do row
        return row.import_type === :import_RHS
    end

    # Unlike with qualified names, we can't actually access the modules in question in code in many cases.
    # For example, if you do `module Mod; using LinearAlgebra: svd; end`, then `LinearAlgebra` does not exist
    # inside the `Mod` namespace; only `svd` does. So we can't just do `getproperty(mod, :LinearAlgebra)` to get it.
    # Instead, we will just go by the *names* of the modules and hope there aren't clashes.
    # We will also only support packages, not relative paths, so that we can use `Base.loaded_modules` to inspect
    # the global environment to find the actual module in question.
    filter!(_explicit_imports) do row
        return !(:. in row.explicitly_imported_by)
    end

    # Clashes will get resolved arbitrarily
    # TODO: check for clash and bail
    lookup = Dict(nameof(m) => m for (_, m) in Base.loaded_modules)

    table = @NamedTuple{name::Symbol,location::String,value::Any,importing_from::Module,
                        whichmodule::Module,public_access::Bool}[]
    for row in _explicit_imports
        output = process_explicitly_imported_row(row, mod; lookup)
        output === nothing && continue
        push!(table, output)
    end
    # Sort first, so we get the "first" time each is used
    sort!(table; by=nt -> (; nt.name, nt.location))
    unique!(nt -> (; nt.name, nt.importing_from), table)
    return table
end

function process_explicitly_imported_row(row, mod; lookup)
    isempty(row.explicitly_imported_by) && return nothing
    current_mod = get(lookup, row.explicitly_imported_by[1], nothing)
    for sub in row.explicitly_imported_by[2:end]
        current_mod = trygetproperty(current_mod, sub)
        current_mod isa Module || return nothing
    end

    # Ok, now `current_mod` should contain the actual module we imported the name from
    # This lets us query if the name is public in *that* module, get the value, etc
    value = trygetproperty(current_mod, row.name)
    value === nothing && return nothing
    value = something(value) # unwrap

    # We can also look up the module that created the name. We could use either `current_mod` or `mod` for that.
    # We will in fact use both to try to detect a clash.
    whichmodule = try
        which(mod, row.name)
    catch
        return nothing
    end
    whichmodule2 = try
        which(current_mod, row.name)
    catch
        return nothing
    end
    if whichmodule !== whichmodule2
        #TODO handle somehow?
        @debug "Clash occurred; $(row.name) in mod $mod has `whichmodule=$whichmodule` and `whichmodule2=$whichmodule2`"
        return nothing
    end
    return (; row.name,
            row.location,
            value,
            importing_from=current_mod,
            whichmodule,
            public_access=public_or_exported(current_mod, row.name),)
end

# TODO- this should probably include stale explicit imports, or else it should get a more specific name
function improper_explicit_imports_nonrecursive(mod::Module, file=pathof(mod);
                                                skip=(Base => Core,),
                                                require_submodule_access=false,
                                                # private undocumented kwarg for hoisting this analysis
                                                file_analysis=get_names_used(file))
    check_file(file)
    problematic = analyze_explicitly_imported_names(mod, file; file_analysis)

    # Currently only care about mismatches between `importing_from` and `parent` in which
    # the name is not publicly available in `importing_from`.
    filter!(problematic) do row
        row.public_access && return false # skip these
        if require_submodule_access
            return row.whichmodule != row.importing_from
        else
            return !has_ancestor(row.whichmodule, row.importing_from)
        end
    end

    for (from, parent) in skip
        filter!(problematic) do row
            return !(row.whichmodule == parent && row.importing_from == from)
        end
    end

    return problematic
end
