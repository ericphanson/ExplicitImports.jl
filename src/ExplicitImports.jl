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
"""
function explicit_imports(mod, file=pathof(mod); skips=(Base, Core))
    if isnothing(file)
        throw(ArgumentError("This appears to be a module which is not defined in package. In this case, the file which defines the module must be passed explicitly as the second argument."))
    end
    all_implicit_imports = find_implicit_imports(mod; skips)
    df = get_names_used(file)

    # skip submodules, here we only care about `mod`. It must be the start
    # of the module trail for us to be within the right module (since we go
    # from bottom up).
    subset!(df, :module_path => ByRow(ms -> first(ms) == nameof(mod)))
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

end
