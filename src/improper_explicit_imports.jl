function analyze_explicitly_imported_names(mod::Module, file=pathof(mod);
                                           # private undocumented kwarg for hoisting this analysis
                                           file_analysis=get_names_used(file))
    check_file(file)
    @compat (; per_usage_info, unnecessary_explicit_import, tainted) = filter_to_module(file_analysis,
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
                        stale::Bool,
                        internal_import::Bool}[]
    for row in _explicit_imports
        output = process_explicitly_imported_row(row, mod)
        output === nothing && continue
        importing_from_owns_name = output.whichmodule == output.importing_from
        importing_from_submodule_owns_name = has_ancestor(output.whichmodule,
                                                          output.importing_from)
        internal_import = Base.moduleroot(mod) == Base.moduleroot(output.importing_from)
        stale = (; row.name, row.module_path) in stale_imports
        # Cannot be stale if public or exported in the module `mod`
        # https://github.com/ericphanson/ExplicitImports.jl/issues/69
        if public_or_exported(mod, row.name)
            stale = false
        end
        push!(table,
              (; output..., importing_from_owns_name, importing_from_submodule_owns_name,
               stale, internal_import))
    end

    # Sort first, so we get the "first" time each is used
    sort!(table; by=nt -> (; nt.name, nt.location))
    unique!(nt -> (; nt.name, nt.importing_from), table)
    return table, tainted
end

if !isdefined(Base, :require_lock)
    # 1.7 support
    maybe_root_module(key::Base.PkgId) = get(Base.loaded_modules, key, nothing)
else
    # if `require_lock` exists (so newer Julia versions)
    # but `maybe_root_module` does not anymore, this will error,
    # which will be our sign to update this code.
    maybe_root_module(key::Base.PkgId) = Base.maybe_root_module(key)
end

# Like `Base.require` (as invoked by `eval_import_path`), but
# assumes the package is already loaded (so importantly, doesn't try to actually load new modules).
# Returns `nothing` if something goes wrong.
function __require(into, mod)
    pkgid = Base.identify_package(into, String(mod))
    pkgid === nothing && return nothing
    return maybe_root_module(pkgid)
end

# partial reimplementation of `eval_import_path`
# https://github.com/JuliaLang/julia/blob/94a0ee8637b66ab67445aecc5895d79c960ab50d/src/toplevel.c#L498-L559
function parse_module_path(w, mod_path)
    # println("-----$w:$(mod_path)----")
    isempty(mod_path) && return w
    var = mod_path[1]
    i = 2
    if var != Symbol(".")
        if var == :Core
            mod = Core
        elseif var == :Base
            mod = Base
        else
            mod = __require(w, var)
            # This can happen with `using X` behind a version-check
            mod === nothing && return nothing
        end
        if i > length(mod_path)
            return mod
        end
    else
        mod = w
        while true
            var = mod_path[i]
            if var != Symbol(".")
                break
            end
            i += 1
            mod = parentmodule(mod)
        end
    end

    while true
        # @show (i, length(mod_path), mod)
        if i > length(mod_path)
            break
        end
        var = mod_path[i]
        # @show w mod var
        mod = try_getglobal(mod, var)
        mod === nothing && return nothing
        i += 1
    end
    return mod
end

function process_explicitly_imported_row(row, mod)
    current_mod = parse_module_path(mod, row.explicitly_imported_by)

    # this can happen for modules like `X.Y.X` if `filter_to_module`
    # got confused about which `X` we are in and this row is actually invalid
    # or if the import was conditional, but it hasn't actually happened in this session
    current_mod === nothing && return nothing

    # doesn't seem to be an import
    current_mod === mod && return nothing

    isempty(row.explicitly_imported_by) && return nothing

    if row.explicitly_imported_by[end] != nameof(current_mod)
        error("""
        Encountered implementation bug in `process_explicitly_imported_row`.
        Please file an issue on ExplicitImports.jl (https://github.com/ericphanson/ExplicitImports.jl/issues/new).

        Info:

        `row.explicitly_imported_by`=$(row.explicitly_imported_by)
        `nameof(current_mod)`=$(nameof(current_mod))
        """)
    end

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
    improper_explicit_imports_nonrecursive(mod::Module, file=pathof(mod); strict=true, skip=(Base => Core,
                                                                         Compat => Base,
                                                                         Compat => Core),
                                           allow_internal_imports=true)

A non-recursive version of [`improper_explicit_imports`](@ref), meaning it only analyzes the module `mod` itself, not any of its submodules; see that function for details, including important caveats about stability (outputs may grow in future non-breaking releases of ExplicitImports!).

If `strict=true`, then returns `nothing` if `mod` could not be fully analyzed.
"""
function improper_explicit_imports_nonrecursive(mod::Module, file=pathof(mod);
                                                skip=(Base => Core,
                                                      Compat => Base,
                                                      Compat => Core),
                                                strict=true,
                                                allow_internal_imports=true,
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

    # if `allow_internal_imports=true`, the default, then we strip out any imports where the importing module shares a `moduleroot` with the current module
    if allow_internal_imports
        filter!(problematic) do row
            return !row.internal_import
        end
    end

    return problematic
end

"""
    improper_explicit_imports(mod::Module, file=pathof(mod); strict=true, skip=(Base => Core,
                                                                         Compat => Base,
                                                                         Compat => Core),
                              allow_internal_imports=true)

Attempts do detect various kinds of "improper" explicit imports taking place in `mod` and any submodules of `mod`.

Currently detects two classes of issues:

- names which are explicitly imported but unused (stale)
- names which are not public in `mod`
    - here, public means either exported or declared with the `public` keyword (requires Julia v1.11+)
    - one particularly egregious type of non-public import is when a name is imported from a module which does not even "own" that name. See the returned fields `importing_from_owns_name` and `importing_from_submodule_owns_name` for two variations on this.

The keyword argument `allow_internal_imports` determines whether or not "internal" explicit imports to other modules in the same package (or more generally, sharing the same `Base.moduleroot`) are reported here. If `allow_internal_imports=false`, then even such "internal" explicit imports will be returned.

The keyword argument `skip` is expected to be an iterator of `importing_from => parent` pairs, where names which are imported from `importing_from` but who have an ancestor which is `parent` are ignored. By default, imports from Base to names owned by Core are skipped.

This functionality is still in development, so the exact results may change in future non-breaking releases. Read on for the current outputs, what may change, and what will not change (without a breaking release of ExplicitImports.jl).

Returns a nested structure providing information about improper explicit imports to names in other modules. This information is structured as a collection of pairs, where the keys are the submodules of `mod` (including `mod` itself). Currently, the values are either `nothing` or a `Vector` of `NamedTuple`s with the following keys:

- `name::Symbol`: the name being imported
- `location::String`: the location the import takes place
- `value::Any`: the which `name` points to in `mod`
- `importing_from::Module`: the module the name is being imported from (e.g. in the example `using Foo.X: bar`, this would be `X`)
- `whichmodule::Module`: the `Base.which` of the object
- `public_import::Bool`: whether or not `name` is public or exported in `importing_from`. Checking if a name is marked `public` requires Julia v1.11+.
- `importing_from_owns_name::Bool`: whether or not `importing_from` matches `whichmodule` and therefore is considered to directly "own" the name
- `importing_from_submodule_owns_name::Bool`: whether or not `whichmodule` is a submodule of `importing_from`
- `stale::Bool`: whether or not the explicitly imported name is used
- `internal_import::Bool`: whether or not the import is "internal", meaning the module it was imported into and the module it was imported from share the same `Base.moduleroot`.

If `strict=true`, then returns `nothing` if `mod` could not be fully analyzed.

In non-breaking releases of ExplicitImports:

- more columns may be added to these rows
- additional rows may be returned which qualify as some other kind of "improper" access

However, the result will be a Tables.jl-compatible row-oriented table (for each module), with at least all of the same columns (or the value will be `nothing` if `strict=true` and the module could not be fully analyzed).

See also [`print_explicit_imports`](@ref) to easily compute and print these results, [`improper_explicit_imports_nonrecursive`](@ref) for a non-recursive version which ignores submodules, as well as [`check_no_stale_explicit_imports`](@ref), [`check_all_explicit_imports_via_owners`](@ref), and [`check_all_explicit_imports_are_public`](@ref) for specific regression-testing helpers.
"""
function improper_explicit_imports(mod::Module, file=pathof(mod); strict=true,
                                   skip=(Base => Core,
                                         Compat => Base,
                                         Compat => Core),
                                   allow_internal_imports=true)
    check_file(file)
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => improper_explicit_imports_nonrecursive(submodule, path; strict,
                                                                file_analysis=file_analysis[path],
                                                                skip,
                                                                allow_internal_imports)
            for (submodule, path) in submodules]
end
