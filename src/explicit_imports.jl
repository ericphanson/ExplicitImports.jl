#####
##### Stale explicit imports
#####

"""
    stale_explicit_imports(mod::Module, file=pathof(mod); strict=true)

Returns a collection of pairs, where the keys are submodules of `mod` (including `mod` itself), and the values are either `nothing` if `strict=true` and the module couldn't analyzed, or else a vector of `NamedTuple`s with at least the keys `name` and `location`, consisting of names that are explicitly imported in that submodule, but which either are not used, or are only used in a qualified fashion, making the explicit import a priori unnecessary.

More keys may be added to the NamedTuples in the future in non-breaking releases of ExplicitImports.jl.

!!! warning
    Note that it is possible for an import from a module (say `X`) into one module (say `A`) to be relied on from another unrelated module (say `B`). For example, if `A` contains the code `using X: x`, but either does not use `x` at all or only uses `x` in the form `X.x`, then `x` will be flagged as a stale explicit import by this function. However, it could be that the code in some unrelated module `B` uses `A.x` or `using A: x`, relying on the fact that `x` has been imported into `A`'s namespace.

    This is an unusual situation (generally `B` should just get `x` directly from `X`, rather than indirectly via `A`), but there are situations in which it arises, so one may need to be careful about naively removing all "stale" explicit imports flagged by this function.

    Running [`improper_qualified_accesses`](@ref) on downstream code can help identify such "improper" accesses to names via modules other than their owner.

## Keyword arguments

$STRICT_KWARG

See [`stale_explicit_imports_nonrecursive`](@ref) for a non-recursive version, and [`check_no_stale_explicit_imports`](@ref) for a version that throws an error when encountering stale explicit imports.

See also [`print_explicit_imports`](@ref) which prints this information.
"""
function stale_explicit_imports(mod::Module, file=pathof(mod); strict=true)
    check_file(file)
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => stale_explicit_imports_nonrecursive(submodule, path;
                                                             file_analysis=file_analysis[path],
                                                             strict)
            for (submodule, path) in submodules]
end

"""
    stale_explicit_imports_nonrecursive(mod::Module, file=pathof(mod); strict=true)

A non-recursive version of [`stale_explicit_imports`](@ref), meaning it only analyzes the module `mod` itself, not any of its submodules.

If `mod` was unanalyzable and `strict=true`, returns `nothing`. Otherwise, returns a collection of `NamedTuple`'s, with at least the keys `name` and `location`, corresponding to the names of stale explicit imports. More keys may be added in the future in non-breaking releases of ExplicitImports.jl.

## Keyword arguments

$STRICT_NONRECURSIVE_KWARG

See also [`print_explicit_imports`](@ref) and [`check_no_stale_explicit_imports`](@ref), both of which do recurse through submodules.
"""
function stale_explicit_imports_nonrecursive(mod::Module, file=pathof(mod);
                                             strict=true,
                                             # private undocumented kwarg for hoisting this analysis
                                             file_analysis=get_names_used(file))
    check_file(file)
    (; unnecessary_explicit_import, tainted) = filter_to_module(file_analysis, mod)
    tainted && strict && return nothing
    ret = [(; nt.name, nt.location) for nt in unnecessary_explicit_import]
    return unique!(nt -> nt.name, sort!(ret))
end

#####
##### Non-public or non-owning explicit imports
#####

function analyze_explicitly_imported_names(mod::Module, file=pathof(Mod);
                                           # private undocumented kwarg for hoisting this analysis
                                           file_analysis=get_names_used(file))
    check_file(file)
    (; per_usage_info, unnecessary_explicit_import) = filter_to_module(file_analysis, mod)
    stale_imports = Set((; nt.name, nt.module_path) for nt in unnecessary_explicit_import)

    _explicit_imports = filter(per_usage_info) do row
        return row.import_type === :import_RHS
    end

    # Unlike with qualified names, we can't actually access the modules in question in code in many cases.
    # For example, if you do `module Mod; using LinearAlgebra: svd; end`, then `LinearAlgebra` does not exist
    # inside the `Mod` namespace; only `svd` does. So we can't just do `getproperty(mod, :LinearAlgebra)` to get it.
    # Instead, we will just go by the *names* of the modules and hope there aren't clashes.
    # For some features also, we will only support packages, not relative paths, so that we can use `Base.loaded_modules` to inspect
    # the global environment to find the actual module in question.

    # Clashes will get resolved arbitrarily
    # TODO: check for clash and bail
    lookup = Dict(nameof(m) => m for (_, m) in Base.loaded_modules)

    table = @NamedTuple{name::Symbol,
                        location::String,
                        value::Any,
                        importing_from::Union{Module,Symbol},
                        whichmodule::Module,
                        public_import::Union{Missing,Bool},
                        importing_from_owns_name::Bool,
                        importing_from_submodule_owns_name::Bool,
                        stale::Bool}[]
    for row in _explicit_imports
        if (:. in row.explicitly_imported_by)
            # Relative module path; we can't figure out somethings, but can others
            output = process_module_explicitly_imported_row(row, mod)
        else
            # Package import: we can lookup the actual module from `Base.loaded_modules`
            # and should have full information, assuming there wasn't a clash
            output = process_explicitly_imported_row(row, mod; lookup)
        end
        output === nothing && continue
        importing_from_owns_name = compare_modules(output.whichmodule,
                                                   output.importing_from)
        importing_from_submodule_owns_name = has_ancestor_name(output.whichmodule,
                                                               output.importing_from)
        stale = (; row.name, row.module_path) in stale_imports
        push!(table,
              (; output..., importing_from_owns_name, importing_from_submodule_owns_name,
               stale))
    end

    # Sort first, so we get the "first" time each is used
    sort!(table; by=nt -> (; nt.name, nt.location))
    unique!(nt -> (; nt.name, nt.importing_from), table)
    return table
end

function process_module_explicitly_imported_row(row, mod)
    # For local modules, we can check if the import is unnecessary,
    # or if the name of the module we are importing from matches the owner.
    value = trygetproperty(mod, row.name)
    value === nothing && return nothing
    value = something(value) # unwrap
    importing_from = row.explicitly_imported_by[end]
    whichmodule = try
        which(mod, row.name)
    catch
        return nothing
    end
    return (; row.name,
            row.location,
            value,
            importing_from,
            whichmodule,
            public_import=missing)
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
            public_import=public_or_exported(current_mod, row.name),)
end

#####
##### All "improper" explicit imports
#####

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
        row.stale === true && return true # keep these

        row.public_import === true && return false # skip these
        if require_submodule_access
            return !row.importing_from_owns_name
        else
            return !row.importing_from_submodule_owns_name
        end
    end

    for (from, parent) in skip
        filter!(problematic) do row
            return !(row.whichmodule == parent && compare_modules(row.importing_from, from))
        end
    end

    return problematic
end
