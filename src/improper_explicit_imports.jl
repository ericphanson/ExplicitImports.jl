function analyze_explicitly_imported_names(mod::Module, file=pathof(mod);
                                           # private undocumented kwarg for hoisting this analysis
                                           file_analysis=get_names_used(file))
    check_file(file)
    (; per_usage_info, unnecessary_explicit_import) = filter_to_module(file_analysis, mod)
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

# TODO-docs, tests
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
        row.public_import === false && return true # keep these
        # OK, if we are down to `missing`, then it's a local module.
        # We will report only if there is an ownership issue.
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

# TODO-docs, tests
function improper_explicit_imports(mod::Module, file=pathof(mod); skip=(Base => Core,))
    check_file(file)
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => improper_explicit_imports_nonrecursive(submodule, path;
                                                                file_analysis=file_analysis[path],
                                                                skip)
            for (submodule, path) in submodules]
end
