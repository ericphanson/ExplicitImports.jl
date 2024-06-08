function analyze_explicitly_imported_names(mod::Module, file=pathof(mod);
                                           # private undocumented kwarg for hoisting this analysis
                                           file_analysis=get_names_used(file))
    check_file(file)
    (; per_usage_info, unnecessary_explicit_import, tainted) = filter_to_module(file_analysis,
                                                                                mod)
    stale_imports = Set((; nt.name, nt.module_path) for nt in unnecessary_explicit_import)

    _explicit_imports = filter(per_usage_info) do row
        return row.import_type === :import_RHS
    end

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
        output = process_explicitly_imported_row(row, mod)
        output === nothing && continue
        importing_from_owns_name = output.whichmodule == output.importing_from
        importing_from_submodule_owns_name = has_ancestor(output.whichmodule,
                                                          output.importing_from)
        stale = (; row.name, row.module_path) in stale_imports
        push!(table,
              (; output..., importing_from_owns_name, importing_from_submodule_owns_name,
               stale))
    end

    # Sort first, so we get the "first" time each is used
    sort!(table; by=nt -> (; nt.name, nt.location))
    unique!(nt -> (; nt.name, nt.importing_from), table)
    return table, tainted
end

function process_explicitly_imported_row(row, mod)
    current_mod = Base.binding_module(mod, row.name)
    current_mod === mod && return nothing

    isempty(row.explicitly_imported_by) && return nothing

    # Ok, now `current_mod` should contain the actual module we imported the name from
    # This lets us query if the name is public in *that* module, get the value, etc
    value = trygetproperty(current_mod, row.name)
    value === nothing && return nothing
    value = something(value) # unwrap
    whichmodule = try
        which(mod, row.name)
    catch
        return nothing
    end
    return (; row.name,
            row.location,
            value,
            importing_from=current_mod,
            whichmodule,
            public_import=public_or_exported(current_mod, row.name),)
end

"""
    improper_explicit_imports_nonrecursive(mod::Module, file=pathof(mod); strict=true, skip=(Base => Core,))

A non-recursive version of [`improper_explicit_imports`](@ref), meaning it only analyzes the module `mod` itself, not any of its submodules; see that function for details, including important caveats about stability (outputs may grow in future non-breaking releases of ExplicitImports!).

If `strict=true`, then returns `nothing` if `mod` could not be fully analyzed.
"""
function improper_explicit_imports_nonrecursive(mod::Module, file=pathof(mod);
                                                skip=(Base => Core,),
                                                strict=true,
                                                # private undocumented kwarg for hoisting this analysis
                                                file_analysis=get_names_used(file))
    check_file(file)
    problematic, tainted = analyze_explicitly_imported_names(mod, file; file_analysis)

    tainted && strict && return nothing
    # Currently only care about mismatches between `importing_from` and `parent` in which
    # the name is not publicly available in `importing_from`.
    filter!(problematic) do row
        row.stale === true && return true # keep these
        row.public_import && return false # skip these
        return true
    end

    for (from, parent) in skip
        filter!(problematic) do row
            return !(has_ancestor(row.whichmodule, parent) &&
                     row.importing_from == from)
        end
    end

    return problematic
end

"""
    improper_explicit_imports(mod::Module, file=pathof(mod); strict=true, skip=(Base => Core,))

Attempts do detect various kinds of "improper" explicit imports taking place in `mod` and any submodules of `mod`.

Currently, only detects cases in which the name is being imported from a module `mod` for which:

- `name` is not exported from `mod`
- `name` is not declared public in `mod` (requires Julia v1.11+)

The keyword argument `skip` is expected to be an iterator of `importing_from => parent` pairs, where names which are imported from `importing_from` but who have an ancestor which is `parent` are ignored. By default, imports from Base to names owned by Core are skipped.

This functionality is still in development, so the exact results may change in future non-breaking releases. Read on for the current outputs, what may change, and what will not change (without a breaking release of ExplicitImports.jl).

Returns a nested structure providing information about improper explicit imports to names in other modules. This information is structured as a collection of pairs, where the keys are the submodules of `mod` (including `mod` itself). Currently, the values are either `nothing` or a `Vector` of `NamedTuple`s with the following keys:

- `name::Symbol`: the name being imported
- `location::String`: the location the access takes place
- `importing_from::Module`: the module the name is being imported from (e.g. `Module.name`)
- `whichmodule::Module`: the `Base.which` of the object
- `public_import::Bool`: whether or not `name` is public or exported in `importing_from`. Checking if a name is marked `public` requires Julia v1.11+.
- `importing_from_owns_name::Bool` whether or not `importing_from` matches `whichmodule` and therefore is considered to directly "own" the name
- `importing_from_submodule_owns_name::Bool` whether or not `whichmodule` is a submdoule of `importing_from`
- `stale::Bool`: whether or not the explicitly imported name is used

If `strict=true`, then returns `nothing` if `mod` could not be fully analyzed.

In non-breaking releases of ExplicitImports:

- more columns may be added to these rows
- additional rows may be returned which qualify as some other kind of "improper" access

However, the result will be a Tables.jl-compatible row-oriented table (for each module), with at least all of the same columns (or the value will be `nothing` if `strict=true` and the module could not be fully analyzed).

See also [`print_explicit_imports`](@ref) to easily compute and print these results, and [`improper_explicit_imports_nonrecursive`](@ref) for a non-recursive version which ignores submodules.
"""
function improper_explicit_imports(mod::Module, file=pathof(mod); strict=true,
                                   skip=(Base => Core,))
    check_file(file)
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => improper_explicit_imports_nonrecursive(submodule, path; strict,
                                                                file_analysis=file_analysis[path],
                                                                skip)
            for (submodule, path) in submodules]
end
