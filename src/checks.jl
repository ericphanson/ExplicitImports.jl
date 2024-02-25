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
    check_no_implicit_imports(mod::Module, file=pathof(mod); skips=(mod, Base, Core), ignore = ())

Checks that neither `mod` nor any of its submodules is relying on implicit imports, throwing
an `ImplicitImportsException` if so, and returning `nothing` otherwise.

This function can be used in a package's tests, e.g.

```julia
@test check_no_implicit_imports(MyPackage) === nothing
```

## Allowing some implicit imports

The `skips` keyword argument can be passed to allow implicit imports from some modules (and their submodules). By default, `skips` is set to `(Base, Core)`. For example:

```julia
@test check_no_implicit_imports(MyPackage; skips=(Base, Core, DataFrames)) === nothing
```

would verify there are no implicit imports from modules other than Base, Core, and DataFrames.

Additionally, the keyword `ignore` can be passed to represent a collection of items to ignore. These can be:

* modules. Any submodule of `mod` matching an element of `ignore` is skipped. This can be used to allow the usage of implicit imports in some submodule of your package.
* symbols: any implicit import of a name matching an element of `ignore` is ignored (does not throw)
* `symbol => module` pairs. Any implicit import of a name matching that symbol from a module matching the module is ignored.

One can mix and match between these type of ignored elements. For example:

```julia
@test check_no_implicit_imports(MyPackage; ignore=(:DataFrame => DataFrames, :ByRow, MySubModule)) === nothing
```

This would:

1. Ignore any implicit import of `DataFrame` from DataFrames
2. Ignore any implicit import of the name `ByRow` from any module.
3. Ignore any implicit imports present in `MyPackage`'s submodule `MySubModule`

but verify there are no other implicit imports.
"""
function check_no_implicit_imports(mod::Module, file=pathof(mod); skips=(mod, Base, Core),
                                   ignore=())
    ee = explicit_imports(mod, file; warn_stale=false, skips)
    for (mod, names) in ee
        should_ignore!(names, mod; ignore)
        if !isempty(names)
            throw(ImplicitImportsException(mod, names))
        end
    end
    return nothing
end

function should_ignore!(names, mod; ignore)
    for elt in ignore
        # we're ignoring this whole module
        if elt == mod
            empty!(names)
            return
        end
        filter!(names) do (k, v)
            return !(elt == k || elt == (k => v))
        end
    end
end

"""
    check_no_stale_explicit_imports(mod::Module, file=pathof(mod); ignore=())

Checks that neither `mod` nor any of its submodules has stale (unused) explicit imports, throwing
an `StaleImportsException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.

```julia
@test check_no_stale_explicit_imports(MyPackage) === nothing
```

## Allowing some stale explicit imports

If `ignore` is supplied, it should be a collection of `Symbol`s, representing names
that are allowed to be stale explicit imports. For example,

```julia
@test check_no_stale_explicit_imports(MyPackage; ignore=(:DataFrame,)) === nothing
```

would check there were no stale explicit imports besides that of the name `DataFrame`.
"""
function check_no_stale_explicit_imports(mod::Module, file=pathof(mod); ignore=())
    for (submodule, stale_imports) in stale_explicit_imports(mod, file)
        setdiff!(stale_imports, ignore)
        if !isempty(stale_imports)
            throw(StaleImportsException(submodule, stale_imports))
        end
    end
    return nothing
end
