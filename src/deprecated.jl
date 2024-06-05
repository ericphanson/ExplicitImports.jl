# TODO- add deprecation warnings

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

"""
    print_stale_explicit_imports([io::IO=stdout,] mod::Module, file=pathof(mod); strict=true, show_locations=false)

Runs [`stale_explicit_imports`](@ref) and prints the results.

Note that the particular printing may change in future non-breaking releases of ExplicitImports.

## Keyword arguments

$STRICT_PRINTING_KWARG
* `show_locations=false`: whether or not to print where the explicit imports were made. If the same name was explicitly imported more than once, it will only show one such import.

See also [`print_explicit_imports`](@ref) and [`check_no_stale_explicit_imports`](@ref).
"""
print_stale_explicit_imports

function print_stale_explicit_imports(mod::Module, file=pathof(mod); kw...)
    return print_stale_explicit_imports(stdout, mod, file; kw...)
end
function print_stale_explicit_imports(io::IO, mod::Module, file=pathof(mod); strict=true,
                                      show_locations=false)
    check_file(file)
    for (i, (mod, stale_imports)) in enumerate(stale_explicit_imports(mod, file; strict))
        i == 1 || println(io)
        if isnothing(stale_imports)
            println(io,
                    "Module $mod could not be accurately analyzed, likely due to dynamic `include` statements. You can pass `strict=false` to attempt to get (possibly inaccurate) results anyway.")
        elseif isempty(stale_imports)
            println(io, "Module $mod has no stale explicit imports.")
        else
            println(io,
                    "Module $mod has stale explicit imports for these unused names:")
            for (; name, location) in stale_imports
                if show_locations
                    proof = " (imported at $(location))"
                else
                    proof = ""
                end
                println(io, "- $name", proof)
            end
        end
    end
end

# TODO- deprecate for `print_explicit_imports` with kwargs
"""
    print_improper_qualified_accesses([io::IO=stdout,] mod::Module, file=pathof(mod))

Runs [`improper_qualified_accesses`](@ref) and prints the results.

Note that the particular printing may change in future non-breaking releases of ExplicitImports.

See also [`print_explicit_imports`](@ref) and [`check_all_qualified_accesses_via_owners`](@ref).
"""
print_improper_qualified_accesses

function print_improper_qualified_accesses(mod::Module, file=pathof(mod))
    return print_improper_qualified_accesses(stdout, mod, file)
end

function print_improper_qualified_accesses(io::IO, mod::Module, file=pathof(mod))
    print_explicit_imports(io, mod, file;
                           warn_improper_qualified_accesses=true,
                           warn_improper_explicit_imports=false,
                           warn_implicit_imports=false,
                           #TODO- document
                           report_non_public=VERSION >= v"1.11-")
    # We leave this so we can have non-trivial printout when running this function on ExplicitImports:
    ExplicitImports.parent
    return nothing
end
