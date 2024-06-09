struct ImplicitImportsException <: Exception
    mod::Module
    names::Vector{@NamedTuple{name::Symbol,source::Module,exporters::Vector{Module},
                              location::String}}
end

function Base.showerror(io::IO, e::ImplicitImportsException)
    println(io, "ImplicitImportsException")
    println(io, "Module `$(e.mod)` is relying on the following implicit imports:")
    for (; name, source) in e.names
        println(io, "* `$name` which is exported by $(source)")
    end
end

struct UnanalyzableModuleException <: Exception
    mod::Module
end

function Base.showerror(io::IO, e::UnanalyzableModuleException)
    println(io, "UnanalyzableModuleException")
    println(io,
            "Module `$(e.mod)` was found to be unanalyzable. Include this module in the `allow_unanalyzable` keyword argument to allow it to be unanalyzable.")
    return nothing
end

struct QualifiedAccessesFromNonOwnerException <: Exception
    mod::Module
    accesses::Vector{@NamedTuple{name::Symbol,location::String,value::Any,
                                 accessing_from::Module,
                                 whichmodule::Module}}
end

function Base.showerror(io::IO, e::QualifiedAccessesFromNonOwnerException)
    println(io, "QualifiedAccessesFromNonOwnerException")
    println(io,
            "Module `$(e.mod)` has qualified accesses to names via modules other than their owner as determined via `Base.which`:")
    for row in e.accesses
        println(io,
                "- `$(row.name)` has owner $(row.whichmodule) but it was accessed from $(row.accessing_from) at $(row.location)")
    end
end

struct ExplicitImportsFromNonOwnerException <: Exception
    mod::Module
    bad_imports::Vector{@NamedTuple{name::Symbol,location::String,value::Any,
                                    importing_from::Module,
                                    whichmodule::Module}}
end

function Base.showerror(io::IO, e::ExplicitImportsFromNonOwnerException)
    println(io, "ExplicitImportsFromNonOwnerException")
    println(io,
            "Module `$(e.mod)` has explicit imports of names from modules other than their owner as determined via `Base.which`:")
    for row in e.bad_imports
        println(io,
                "- `$(row.name)` has owner $(row.whichmodule) but it was imported from $(row.importing_from) at $(row.location)")
    end
end

struct NonPublicExplicitImportsException <: Exception
    mod::Module
    bad_imports::Vector{@NamedTuple{name::Symbol,location::String,value::Any,
                                    importing_from::Module}}
end

function Base.showerror(io::IO, e::NonPublicExplicitImportsException)
    println(io, "NonPublicExplicitImportsException")
    println(io,
            "Module `$(e.mod)` has explicit imports of names from modules in which they are not public (i.e. exported or declared public in Julia 1.11+):")
    for row in e.bad_imports
        println(io,
                "- `$(row.name)` is not public in $(row.importing_from) but it was imported from $(row.importing_from) at $(row.location)")
    end
end

struct StaleImportsException <: Exception
    mod::Module
    names::Vector{@NamedTuple{name::Symbol,location::String}}
end

function Base.showerror(io::IO, e::StaleImportsException)
    println(io, "StaleImportsException")
    println(io, "Module `$(e.mod)` has stale (unused) explicit imports for:")
    for (; name) in e.names
        println(io, "* `$name`")
    end
end

"""
    check_no_stale_explicit_imports(mod::Module, file=pathof(mod); ignore::Tuple=(), allow_unanalyzable::Tuple=())

Checks that neither `mod` nor any of its submodules has stale (unused) explicit imports, throwing
an `StaleImportsException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.

```julia
@test check_no_stale_explicit_imports(MyPackage) === nothing
```

## Allowing some submodules to be unanalyzable

Pass `allow_unanalyzable` as a tuple of submodules which are allowed to be unanalyzable.
Any other submodules found to be unanalyzable will result in an `UnanalyzableModuleException` being thrown.

## Allowing some stale explicit imports

If `ignore` is supplied, it should be a tuple of `Symbol`s, representing names
that are allowed to be stale explicit imports. For example,

```julia
@test check_no_stale_explicit_imports(MyPackage; ignore=(:DataFrame,)) === nothing
```

would check there were no stale explicit imports besides that of the name `DataFrame`.
"""
function check_no_stale_explicit_imports(mod::Module, file=pathof(mod); ignore::Tuple=(),
                                         allow_unanalyzable::Tuple=())
    check_file(file)
    for (submodule, stale_imports) in improper_explicit_imports(mod, file; strict=true)
        if isnothing(stale_imports)
            submodule in allow_unanalyzable && continue
            throw(UnanalyzableModuleException(submodule))
        end
        filter!(stale_imports) do nt
            return nt.name ∉ ignore && nt.stale
        end
        if !isempty(stale_imports)
            throw(StaleImportsException(submodule,
                                        NamedTuple{(:name, :location)}.(stale_imports)))
        end
    end
    return nothing
end

"""
    check_no_implicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core), ignore::Tuple=(), allow_unanalyzable::Tuple=())

Checks that neither `mod` nor any of its submodules is relying on implicit imports, throwing
an `ImplicitImportsException` if so, and returning `nothing` otherwise.

This function can be used in a package's tests, e.g.

```julia
@test check_no_implicit_imports(MyPackage) === nothing
```

## Allowing some submodules to be unanalyzable

Pass `allow_unanalyzable` as a tuple of submodules which are allowed to be unanalyzable.
Any other submodules found to be unanalyzable will result in an `UnanalyzableModuleException` being thrown.

These unanalyzable submodules can alternatively be included in `ignore`.

## Allowing some implicit imports

The `skip` keyword argument can be passed to allow implicit imports from some modules (and their submodules). By default, `skip` is set to `(Base, Core)`. For example:

```julia
@test check_no_implicit_imports(MyPackage; skip=(Base, Core, DataFrames)) === nothing
```

would verify there are no implicit imports from modules other than Base, Core, and DataFrames.

Additionally, the keyword `ignore` can be passed to represent a tuple of items to ignore. These can be:

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
function check_no_implicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core),
                                   ignore::Tuple=(), allow_unanalyzable::Tuple=())
    check_file(file)
    ee = explicit_imports(mod, file; skip)
    for (submodule, names) in ee
        if isnothing(names) && submodule in allow_unanalyzable
            continue
        end
        should_ignore!(names, submodule; ignore)
        if !isnothing(names) && !isempty(names)
            throw(ImplicitImportsException(submodule, names))
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

function should_ignore!(::Nothing, mod; ignore)
    for elt in ignore
        # we're ignoring this whole module
        if elt == mod
            return
        end
    end
    # Not ignored, and unanalyzable
    throw(UnanalyzableModuleException(mod))
end

"""
    check_all_qualified_accesses_via_owners(mod::Module, file=pathof(mod); ignore::Tuple=(), require_submodule_access=false)

Checks that neither `mod` nor any of its submodules has accesses to names via modules other than their owner as determined by `Base.which` (unless the name is public or exported in that module),
throwing an `QualifiedAccessesFromNonOwnerException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.

```julia
@test check_all_qualified_accesses_via_owners(MyPackage) === nothing
```

## Allowing some qualified accesses via non-owner modules

If `ignore` is supplied, it should be a tuple of `Symbol`s, representing names
that are allowed to be accessed from non-owner modules. For example,

```julia
@test check_all_qualified_accesses_via_owners(MyPackage; ignore=(:DataFrame,)) === nothing
```

would check there were no qualified accesses from non-owner modules besides that of the name `DataFrame`.

If `require_submodule_access=true`, then an error will be thrown if the name is accessed by a non-owner module even if it is accessed by a parent module of the owner module. For example, in June 2024, `JSON.parse` is actually defined in the submodule `JSON.Parser` and is not declared public inside `JSON`, but the name is present within the module `JSON`. If `require_submodule_access=false`, the default, in this scenario the access `JSON.parse` will not trigger an error, since the name is being accessed by a parent of the owner. If `require_submodule_access=false`, then accessing the function as `JSON.Parser.parse` will be required to avoid an error.

See also: [`improper_qualified_accesses`](@ref). Note that while that function may increase in scope and report other kinds of improper accesses, `check_all_qualified_accesses_via_owners` will not.
"""
function check_all_qualified_accesses_via_owners(mod::Module, file=pathof(mod);
                                                 ignore::Tuple=(),
                                                 require_submodule_access=false)
    check_file(file)
    for (submodule, problematic) in
        improper_qualified_accesses(mod, file; skip=ignore)
        filter!(problematic) do nt
            return nt.name ∉ ignore
        end
        filter!(problematic) do row
            if require_submodule_access
                !row.accessing_from_owns_name
            else
                !row.accessing_from_submodule_owns_name
            end
        end

        # drop unnecessary columns
        problematic = NamedTuple{(:name, :location, :value, :accessing_from, :whichmodule)}.(problematic)
        if !isempty(problematic)
            throw(QualifiedAccessesFromNonOwnerException(submodule, problematic))
        end
    end
    return nothing
end

"""
    check_all_explicit_imports_via_owners(mod::Module, file=pathof(mod); ignore::Tuple=(), require_submodule_import=false)

Checks that neither `mod` nor any of its submodules has imports to names via modules other than their owner as determined by `Base.which` (unless the name is public or exported in that module),
throwing an `ExplicitImportsFromNonOwnerException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.

```julia
@test check_all_explicit_imports_via_owners(MyPackage) === nothing
```

## Allowing some explicit imports via non-owner modules

If `ignore` is supplied, it should be a tuple of `Symbol`s, representing names
that are allowed to be accessed from non-owner modules. For example,

```julia
@test check_all_explicit_imports_via_owners(MyPackage; ignore=(:DataFrame,)) === nothing
```

would check there were no explicit imports from non-owner modules besides that of the name `DataFrame`.

## `require_submodule_import`

If `require_submodule_import=true`, then an error will be thrown if the name is imported from a non-owner module even if it is imported from a parent module of the owner module. For example, in June 2024, `JSON.parse` is actually defined in the submodule `JSON.Parser` and is not declared public inside `JSON`, but the name is present within the module `JSON`. If `require_submodule_import=false`, the default, in this scenario the access `using JSON: parse` will not trigger an error, since the name is being accessed by a parent of the owner. If `require_submodule_import=false`, then accessing the function as `using JSON.Parser: parse` will be required to avoid an error.

## non-fully-analyzable modules do not cause exceptions

Note that if a module is not fully analyzable (e.g. it has dynamic `include` calls), explicit imports of non-public names which could not be analyzed will be missed. Unlike [`check_no_stale_explicit_imports`](@ref) and [`check_no_implicit_imports`](@ref), this function will *not* throw an `UnanalyzableModuleException` in such cases.

See also: [`improper_explicit_imports`](@ref). Note that while that function may increase in scope and report other kinds of improper accesses, `check_all_explicit_imports_via_owners` will not.
"""
function check_all_explicit_imports_via_owners(mod::Module, file=pathof(mod);
                                               ignore::Tuple=(),
                                               require_submodule_import=false)
    check_file(file)
    # `strict=false` because unanalyzability doesn't compromise our analysis
    # that much, unlike in the stale case (in which we might miss usages of the
    # "stale" name, making it not-stale). Here we might just miss bad imports
    # hidden behind a dynamic include or such. IMO it's sufficient to have
    # `check_no_stale_explicit_imports` or `check_no_implicit_imports`
    # throw by default there and not require this function to also throw
    # in the exact same cases.
    for (submodule, problematic) in
        improper_explicit_imports(mod, file; strict=false)
        filter!(problematic) do nt
            return nt.name ∉ ignore
        end

        # Discard imports from names that are public in their module; that's OK
        filter!(problematic) do nt
            return !nt.public_import
        end

        filter!(problematic) do row
            if require_submodule_import
                !row.importing_from_owns_name
            else
                !row.importing_from_submodule_owns_name
            end
        end

        # drop unnecessary columns
        problematic = NamedTuple{(:name, :location, :value, :importing_from, :whichmodule)}.(problematic)
        if !isempty(problematic)
            throw(ExplicitImportsFromNonOwnerException(submodule, problematic))
        end
    end
    return nothing
end

"""
    check_all_explicit_imports_are_public(mod::Module, file=pathof(mod);
                                          ignore::Tuple=())

Checks that neither `mod` nor any of its submodules has imports to names which are non-public (i.e. not exported, nor declared public on Julia 1.11+)
throwing an `NonPublicExplicitImportsException` if so, and returning `nothing` otherwise.

This can be used in a package's tests, e.g.

```julia
@test check_all_explicit_imports_are_public(MyPackage) === nothing
```

## Allowing some non-public explicit imports

If `ignore` is supplied, it should be a tuple of `Symbol`s, representing names
that are allowed to be imported from modules in which they are not public. For example,

```julia
@test check_all_explicit_imports_are_public(MyPackage; ignore=(:DataFrame,)) === nothing
```

would check there were no non-public explicit imports besides that of the name `DataFrame`.

## non-fully-analyzable modules do not cause exceptions

Note that if a module is not fully analyzable (e.g. it has dynamic `include` calls), explicit imports of non-public names which could not be analyzed will be missed. Unlike [`check_no_stale_explicit_imports`](@ref) and [`check_no_implicit_imports`](@ref), this function will *not* throw an `UnanalyzableModuleException` in such cases.

See also: [`improper_explicit_imports`](@ref) and [`check_all_explicit_imports_via_owners`]. Note that while `improper_explicit_imports` may increase in scope and report other kinds of improper accesses, `check_all_explicit_imports_are_public` will not.
"""
function check_all_explicit_imports_are_public(mod::Module, file=pathof(mod);
                                               ignore::Tuple=())
    check_file(file)
    for (submodule, problematic) in
        improper_explicit_imports(mod, file; strict=false)
        filter!(problematic) do nt
            return nt.name ∉ ignore
        end

        # Discard imports from names that are public in their module; that's OK
        filter!(problematic) do nt
            return !nt.public_import
        end

        # drop unnecessary columns
        problematic = NamedTuple{(:name, :location, :value, :importing_from)}.(problematic)
        if !isempty(problematic)
            throw(NonPublicExplicitImportsException(submodule, problematic))
        end
    end
    return nothing
end
