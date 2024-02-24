module ExplicitImports

using JuliaSyntax, AbstractTrees
using AbstractTrees: parent
using DataFrames

export find_implicit_imports
include("find_implicit_imports.jl")

export get_names_used
include("get_names_used.jl")

export explicit_imports

"""
    explicit_imports(mod, file=pathof(mod); skips=(Base, Core)) -> Vector{String}

Returns a list of explicit import statements one could make for the module `mod`.

Notes:
* Currently, this does not filter to only new explicit imports (these may be redundant with already existing explicit imports).
* if `mod` is not from a package, `pathof` will be unable to find the code, and a file must be passed which contains `mod` (either directly or indirectly through `include`s)
* `mod` can be a submodule defined within `file`, but if two modules have the same name (e.g. `X.Y.X` and `X`), results may be inaccurate.
* `skips` will skip names coming from the listed modules, or any submodules thereof.
"""
function explicit_imports(mod, file=pathof(mod); skips=(Base, Core))
    if isnothing(file)
        throw(ArgumentError("This appears to be a module which is not defined in package. In this case, the file which defines the module must be passed explicitly as the second argument."))
    end
    all_implicit_imports = find_implicit_imports(mod; skips)
    df = get_names_used(file)

    df = restrict_to_module(df, mod)
    relevant_keys = intersect(df.name, keys(all_implicit_imports))
    usings = String[]
    for k in relevant_keys
        v_mod = all_implicit_imports[k]
        should_skip(v_mod; skips) && continue

        # hacky stuff...

        # skip `Main.X`, just do `.X`
        v = replace(string(v_mod), "Main" => "")

        # skip `using X: X`
        v == string(k) && continue

        # skip `using .X: X`
        v == string(".", k) && continue
        push!(usings, "using $v: $k")
    end
    sort!(usings)
    return usings
end

function has_ancestor(query, target)
    query == target && return true
    while true
        next = parentmodule(query)
        next == target && return true
        next == query && return false
        query = next
    end
end

function should_skip(target; skips)
    for skip in skips
        has_ancestor(target, skip) && return true
    end
    return false
end

function module_path(mod)
    path = Symbol[nameof(mod)]
    while true
        next = parentmodule(mod)
        (next == mod || nameof(next) == :Main) && return path
        push!(path, nameof(next))
        mod = next
    end
end

function restrict_to_module(df, mod)
    # Limit to only the module of interest. We make some attempt to avoid name collisions
    # (where two nested modules have the same name) by matching on the full path - to some extent.
    # We can't really assume we were given the "top-level" file (I think), so we might not be
    # aware of all the parent modules in the names we obtained by parsing.
    # Therefore, we use `zip` for its early termination, to just match the module paths
    # to the extent they agree (starting at the earliest point).
    # This means we cannot distinguish X.Y.X from X in some cases.
    # Don't do that!
    mod_path = module_path(mod)
    return subset(df,
                  :module_path => ByRow(ms -> all(Base.splat(isequal), zip(ms, mod_path))))
end

end
