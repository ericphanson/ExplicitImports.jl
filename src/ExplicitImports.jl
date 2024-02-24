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
    explicit_imports(mod, file; skips=(Base, Core)) -> Vector{String}

Returns a list of explicit import statements one could make.

Currently:

* requires both a module and a file that defines that module.
* does not traverse `include` statements
* does not handle submodules properly
"""
function explicit_imports(mod, file; skips=(Base, Core))
    all_implicit_imports = find_implicit_imports(mod; skips)
    df = get_names_used(file)
    relevant_keys = intersect(df.name, keys(all_implicit_imports))
    usings = []
    for k in relevant_keys
        v_mod = all_implicit_imports[k]
        v_mod in skips && continue
        # skip `Main.X`, just do `.X`
        v = replace(string(v_mod), "Main" => "")

        # skip `using X: X`
        v == string(k) && continue
        push!(usings, "using $v: $k")
    end
    sort!(usings)
    return usings
end

end
