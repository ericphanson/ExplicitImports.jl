struct ImplicitImportsException <: Exception
    mod::Module
    names::Vector{Pair{Symbol,Module}}
end

function Base.showerror(io::IO, e::ImplicitImportsException)
    println(io, "ImplicitImportsException")
    println(io, "Module `$(e.mod)` is relying on the following implicit imports:")
    for (name, source) in e.names
        println(io, "* `$name` which is exported by $(source)")
    end
end

struct StaleImportsException <: Exception
    mod::Module
    names::Vector{Symbol}
end

function Base.showerror(io::IO, e::StaleImportsException)
    println(io, "StaleImportsException")
    println(io, "Module `$(e.mod)` has stale (unused) explicit imports for:")
    for name in e.names
        println(io, "* `$name`")
    end
end

"""
    check_no_implicit_imports(mod, file=pathof(mod); skips=(Base, Core), warn=false)

Checks that neither `mod` nor any of its submodules is relying on implicit imports, throwing
an `ImplicitImportsException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.
```julia
@test check_no_implicit_imports(MyPackage) === nothing
```
"""
function check_no_implicit_imports(mod, file=pathof(mod); skips=(Base, Core), warn=false)
    ee = explicit_imports(mod, file; warn, skips)
    for (mod, names) in ee
        if !isempty(names)
            throw(ImplicitImportsException(mod, names))
        end
    end
    return nothing
end

"""
    check_no_stale_explicit_imports(mod, file=pathof(mod))

Checks that neither `mod` nor any of its submodules has stale (unused) explicit imports, throwing
an `StaleImportsException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.
```julia
@test check_no_stale_explicit_imports(MyPackage) === nothing
```
"""
function check_no_stale_explicit_imports(mod, file=pathof(mod))
    submodules = find_submodules(mod)
    for submodule in submodules
        stale_imports = stale_explicit_imports(submodule, file)
        if !isempty(stale_imports)
            throw(StaleImportsException(submodule, stale_imports))
        end
    end
    return nothing
end
