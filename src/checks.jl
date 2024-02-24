struct ImplicitImportsException <: Exception
    mod::Module
    names::Vector{Pair{Symbol,Module}}
end

struct StaleImportsException <: Exception
    mod::Module
    names::Vector{Symbol}
end

# TODO- write `Base.showerror` for these exceptions
# TODO- write docs for these functions
# TODO- write tests for these functions

function check_no_implicit_imports(mod, file=pathof(mod); skips=(Base, Core), warn=false)
    ee = explicit_imports(mod, file; warn, skips)
    for (mod, names) in ee
        if !isempty(names)
            throw(ImplicitImportsException(mod, names))
        end
    end
    return nothing
end

function check_no_stale_explicit_imports(mod, file=pathof(mod); warn=false)
    submodules = find_submodules(mod)
    for submodule in submodules
        stale_imports = stale_explicit_imports(submodule, file)
        if !isempty(names)
            throw(StaleImportsException(submodule, stale_imports))
        end
    end
    return nothing
end
