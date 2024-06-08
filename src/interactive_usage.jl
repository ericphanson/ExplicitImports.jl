
function print_explicit_imports(mod::Module, file=pathof(mod); kw...)
    return print_explicit_imports(stdout, mod, file; kw...)
end

"""
    print_explicit_imports([io::IO=stdout,] mod::Module, file=pathof(mod); skip=(mod, Base, Core),
                           warn_implicit_imports=true,
                           warn_improper_explicit_imports=true,
                           warn_improper_qualified_accesses=true,
                           report_non_public=VERSION >= v"1.11-",
                            strict=true)

Runs [`explicit_imports`](@ref) and prints the results, along with those of [`improper_explicit_imports`](@ref) and [`improper_qualified_accesses`](@ref).

Note that the particular printing may change in future non-breaking releases of ExplicitImports.

## Keyword arguments

$SKIPS_KWARG
* `warn_improper_explicit_imports=true`: if set, this function will also print information about any "improper" imports of names from other modules.
* `warn_improper_qualified_accesses=true`: if set, this function will also print information about any "improper" qualified accesses to names from other modules.
$STRICT_PRINTING_KWARG
* `show_locations=false`: whether or not to print locations of where the names are being used.
* `linewidth=80`: format into lines of up to this length. Set to 0 to indicate one name should be printed per line.

See also [`check_no_implicit_imports`](@ref), [`check_no_stale_explicit_imports`](@ref), and [`check_all_qualified_accesses_via_owners`](@ref).
"""
function print_explicit_imports(io::IO, mod::Module, file=pathof(mod);
                                skip=(mod, Base, Core),
                                warn_implicit_imports=true,
                                warn_improper_explicit_imports=nothing, # set to `true` once `warn_stale` is removed
                                warn_improper_qualified_accesses=true,
                                #TODO- document
                                report_non_public=VERSION >= v"1.11-",
                                strict=true,
                                show_locations=false,
                                linewidth=80,
                                # deprecated
                                warn_stale=nothing,
                                # internal kwargs
                                recursive=true,
                                name_fn=mod -> "module $mod")
    if warn_improper_explicit_imports !== nothing && warn_stale !== nothing
        throw(ArgumentError("[print_explicit_imports] Cannot set both `warn_improper_explicit_imports` and `warn_stale`; instead set only `warn_improper_explicit_imports`."))
    elseif warn_stale === nothing && warn_improper_explicit_imports === nothing
        warn_improper_explicit_imports = true
    elseif warn_stale !== nothing
        @warn "[print_explicit_imports] Keyword argument `warn_stale` is deprecated, instead use `warn_improper_explicit_imports`" maxlog = 1
        warn_improper_explicit_imports = warn_stale
    end
    file_analysis = Dict{String,FileAnalysis}()
    ee = explicit_imports(mod, file; skip, strict, file_analysis)
    for (i, (mod, imports)) in enumerate(ee)
        !recursive && i > 1 && break
        i == 1 || println(io)
        if isnothing(imports)
            println(io,
                    "$(uppercasefirst(name_fn(mod))) could not be accurately analyzed, likely due to dynamic `include` statements. You can pass `strict=false` to attempt to get (possibly inaccurate) results anyway.")
        else
            if warn_implicit_imports
                if isempty(imports)
                    println(io,
                            "$(uppercasefirst(name_fn(mod))) is not relying on any implicit imports.")
                else
                    plural1 = length(imports) > 1 ? "s" : ""
                    plural2 = length(imports) > 1 ? "These" : "This"

                    println(io,
                            "$(uppercasefirst(name_fn(mod))) is relying on implicit imports for $(length(imports)) name$(plural1). ",
                            "$(plural2) could be explicitly imported as follows:")
                    println(io)
                    println(io, "```julia")
                    using_statements(io, imports; linewidth, show_locations)
                    println(io, "```")
                end
            end
        end

        if warn_improper_explicit_imports
            problematic_imports = improper_explicit_imports_nonrecursive(mod, file; strict,
                                                                         file_analysis=file_analysis[file])
            if !isnothing(problematic_imports) && !isempty(problematic_imports)
                stale = filter(row -> row.stale, problematic_imports)
                if !isempty(stale)
                    println(io)
                    word = !isnothing(imports) && isempty(imports) ?
                           "However" : "Additionally"

                    plural1 = length(stale) > 1 ? "these" : "this"
                    plural2 = length(stale) > 1 ? "s" : ""
                    println(io,
                            "$word, $(name_fn(mod)) has stale explicit imports for $plural1 $(length(stale)) unused name$(plural2):")
                    for row in stale
                        println(io,
                                "- `$(row.name)` is unused but it was imported from $(row.importing_from) at $(row.location)")
                    end
                end
                non_owner = filter(row -> !row.importing_from_submodule_owns_name,
                                   problematic_imports)
                if !isempty(non_owner)
                    println(io)

                    word = !isnothing(imports) && isempty(imports) && isempty(stale) ?
                           "However" : "Additionally"
                    plural = length(non_owner) > 1 ? "s" : ""
                    println(io,
                            "$word, $(name_fn(mod)) explicitly imports $(length(non_owner)) name$(plural) from non-owner modules:")
                    for row in non_owner
                        println(io,
                                "- `$(row.name)` has owner $(row.whichmodule) but it was imported from $(row.importing_from) at $(row.location)")
                    end
                end
                non_public = report_non_public ?
                             filter(row -> row.importing_from_submodule_owns_name &&
                                        row.public_import === false,
                                    problematic_imports) : []
                if !isempty(non_public)
                    println(io)

                    word = !isnothing(imports) && isempty(imports) && isempty(stale) &&
                           isempty(non_owner) ?
                           "However" : "Additionally"
                    plural = length(non_public) > 1 ? "s" : ""

                    println(io,
                            "$word, $(name_fn(mod)) explicitly imports $(length(non_public)) non-public name$(plural):")
                    for row in non_public
                        println(io,
                                "- `$(row.name)` is not public in $(row.importing_from) but it was imported from $(row.importing_from) at $(row.location)")
                    end
                end
            end
        else
            problematic_imports = ()
        end
        if warn_improper_qualified_accesses
            problematic = improper_qualified_accesses_nonrecursive(mod, file;
                                                                   file_analysis=file_analysis[file])

            non_owner = filter(row -> !row.accessing_from_submodule_owns_name,
                               problematic)

            if !isempty(non_owner)
                println(io)
                word = !isnothing(imports) && isempty(imports) &&
                       isempty(problematic_imports) ?
                       "However" : "Additionally"
                plural = length(non_owner) > 1 ? "s" : ""
                println(io,
                        "$word, $(name_fn(mod)) accesses $(length(non_owner)) name$(plural) from non-owner modules:")
                for row in non_owner
                    println(io,
                            "- `$(row.name)` has owner $(row.whichmodule) but it was accessed from $(row.accessing_from) at $(row.location)")
                end
            end

            non_public = report_non_public ?
                         filter(row -> row.accessing_from_submodule_owns_name &&
                                    row.public_access === false,
                                problematic) : []

            if !isempty(non_public)
                println(io)

                word = !isnothing(imports) && isempty(imports) &&
                       isempty(problematic_imports) && isempty(non_owner) ?
                       "However" : "Additionally"
                plural = length(non_public) > 1 ? "s" : ""
                println(io,
                        "$word, $(name_fn(mod)) accesses $(length(non_public)) non-public name$(plural):")
                for row in non_public
                    println(io,
                            "- `$(row.name)` is not public in $(row.accessing_from) but it was accessed via $(row.accessing_from) at $(row.location)")
                end
            end
        end
    end
end

function print_explicit_imports_script(path; kw...)
    return print_explicit_imports_script(stdout, path; kw...)
end
"""
    print_explicit_imports_script([io::IO=stdout,] path; skip=(Base, Core), warn_improper_explicit_imports=true)

Analyzes the script located at `path` and prints information about reliance on implicit exports as well as any "improper" explicit imports (if `warn_improper_explicit_imports=true`).

Note that the particular printing may change in future non-breaking releases of ExplicitImports.

!!! warning
  The script (or at least, all imports in the script) must be run before this function can give reliable results, since it relies on introspecting what names are present in `Main`.

## Keyword arguments

$SKIPS_KWARG
"""
function print_explicit_imports_script(io::IO, path; skip=(Base, Core), warn_stale=nothing, # deprecated
                                       warn_improper_explicit_imports=nothing, # set to `true` once `warn_stale` is ,removed,
                                       show_locations=false)
    return print_explicit_imports(io, Main, path;
                                  skip, warn_stale, warn_improper_explicit_imports,
                                  show_locations,
                                  strict=false,
                                  recursive=false,
                                  name_fn=_ -> "script `$path`")
end
