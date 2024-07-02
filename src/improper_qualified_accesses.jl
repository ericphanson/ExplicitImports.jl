# We wish to find qualified usages of a name in which the qualifying module is not the owner of the name
# it is also interesting to know if the name is public in the qualifying module

function analyze_qualified_names(mod::Module, file=pathof(mod);
                                 # private undocumented kwarg for hoisting this analysis
                                 file_analysis=get_names_used(file))
    check_file(file)
    @compat (; per_usage_info, tainted) = filter_to_module(file_analysis, mod)
    # Do we want to do anything with `tainted`? This means there is unanalyzable code here
    # Probably that means we could miss qualified names to report, but not that
    # something there would invalidate the qualified names with issues we did find.
    # For now let's ignore it.

    # Filter to qualified names
    qualified = [row for row in per_usage_info if row.qualified_by !== nothing]

    # which are in our module
    mod_path = module_path(mod)
    match = module_path -> all(Base.splat(isequal), zip(module_path, mod_path))
    filter!(qualified) do nt
        return match(nt.module_path)
    end

    table = @NamedTuple{name::Symbol,
                        location::String,
                        value::Any,
                        accessing_from::Module,
                        whichmodule::Module,
                        public_access::Bool,
                        accessing_from_owns_name::Bool,
                        accessing_from_submodule_owns_name::Bool,
                        internal_access::Bool,
                        self_qualified::Bool}[]
    # Now check:
    for row in qualified
        output = process_qualified_row(row, mod)
        output === nothing && continue
        accessing_from_owns_name = output.whichmodule == output.accessing_from
        accessing_from_submodule_owns_name = has_ancestor(output.whichmodule,
                                                          output.accessing_from)

        internal_access = Base.moduleroot(mod) == Base.moduleroot(output.accessing_from)
        self_qualified = output.accessing_from == mod
        push!(table,
              (; output..., accessing_from_owns_name, accessing_from_submodule_owns_name,
               internal_access, self_qualified))
    end
    # Sort first, so we get the "first" time each is used
    sort!(table; by=nt -> (; nt.name, nt.location))
    unique!(nt -> (; nt.name, nt.accessing_from), table)
    return table
end

function process_qualified_row(row, mod)
    isempty(row.qualified_by) && return nothing
    current_mod = mod
    for submod in row.qualified_by
        current_mod = something(trygetproperty(current_mod, submod), Some(nothing))
        current_mod isa Module || return nothing
    end
    # OK, now `current_mod` is the module from which we are accessing the name!
    # We could check here if the name is public in `current_mod`, or exported from it, etc.
    value = trygetproperty(current_mod, row.name)
    value === nothing && return nothing
    value = something(value) # unwrap

    whichmodule = Base.which(current_mod, row.name)

    return (; row.name,
            row.location,
            value,
            accessing_from=current_mod,
            whichmodule,
            public_access=public_or_exported(current_mod, row.name),)
end

function public_or_exported(mod::Module, name::Symbol)
    return isdefined(Base, :ispublic) ? Base.ispublic(mod, name) :
           Base.isexported(mod, name)
end

# We can't just trust `hasproperty` since e.g. `hasproperty(Base, :Core) == false`:
# (https://github.com/JuliaLang/julia/issues/47150)
function trygetproperty(x::Module, y)
    return isdefined(x, y) ? Some(getproperty(x, y)) : nothing
end

"""
    improper_qualified_accesses_nonrecursive(mod::Module, file=pathof(mod); skip=(Base => Core,
                                                                         Compat => Base,
                                                                         Compat => Core),
                                             allow_internal_accesses=true)


A non-recursive version of [`improper_qualified_accesses`](@ref), meaning it only analyzes the module `mod` itself, not any of its submodules; see that function for details, including important caveats about stability (outputs may grow in future non-breaking releases of ExplicitImports!).

## Example

```jldoctest
julia> using ExplicitImports

julia> example_path = pkgdir(ExplicitImports, "examples", "qualified.jl");

julia> print(read(example_path, String))
module MyMod
using LinearAlgebra
# sum is in `Base`, so we shouldn't access it from LinearAlgebra:
n = LinearAlgebra.sum([1, 2, 3])
end

julia> include(example_path);

julia> row = improper_qualified_accesses_nonrecursive(MyMod, example_path)[1];

julia> (; row.name, row.accessing_from, row.whichmodule)
(name = :sum, accessing_from = LinearAlgebra, whichmodule = Base)
```
"""
function improper_qualified_accesses_nonrecursive(mod::Module, file=pathof(mod);
                                                  skip=(Base => Core,
                                                        Compat => Base,
                                                        Compat => Core),
                                                  allow_internal_accesses=true,
                                                  # deprecated, does nothing
                                                  require_submodule_access=nothing,
                                                  # private undocumented kwarg for hoisting this analysis
                                                  file_analysis=get_names_used(file))
    check_file(file)
    if require_submodule_access !== nothing
        @warn "[improper_qualified_accesses_nonrecursive] `require_submodule_access` is deprecated and unused" _id = :explicit_imports_improper_qualified_accesses_require_submodule_access maxlog = 1
    end
    problematic = analyze_qualified_names(mod, file; file_analysis)

    # Report only non-public accesses or self-qualified ones
    filter!(row -> !row.public_access || row.self_qualified, problematic)

    for (from, parent) in skip
        filter!(problematic) do row
            return !(has_ancestor(row.whichmodule, parent) && row.accessing_from == from)
        end
    end

    # if `allow_internal_accesses=true`, the default, then we strip out any accesses where the accessing module shares a `moduleroot` with the current module,
    # unless it is self-qualified
    if allow_internal_accesses
        filter!(problematic) do row
            return !row.internal_access || row.self_qualified
        end
    end
    return problematic
end

"""
    improper_qualified_accesses(mod::Module, file=pathof(mod); skip=(Base => Core,
                                                                         Compat => Base,
                                                                         Compat => Core),
                                allow_internal_accesses=true)

Attempts do detect various kinds of "improper" qualified accesses taking place in `mod` and any submodules of `mod`.

Currently, only detects cases in which the name is being accessed from a module `mod` for which:

- `name` is not exported from `mod`
- or `name` is not declared public in `mod` (requires Julia v1.11+)
- or `name` is "self-qualified": i.e. in the module `Foo`, `Foo.name` is being accessed.

The keyword argument `allow_internal_accesses` determines whether or not "internal" qualified accesses to other modules in the same package (or more generally, sharing the same `Base.moduleroot`) are reported here. If `allow_internal_accesses=false`, then even such "internal" qualified accesses will be returned. Note self-qualified accesses are reported regardless of the setting of `allow_internal_accesses`.

The keyword argument `skip` is expected to be an iterator of `accessing_from => parent` pairs, where names which are accessed from `accessing_from` but who have an ancestor `parent` are ignored. By default, accesses from Base to names owned by Core are skipped.

This functionality is still in development, so the exact results may change in future non-breaking releases. Read on for the current outputs, what may change, and what will not change (without a breaking release of ExplicitImports.jl).

Returns a nested structure providing information about improper accesses to names in other modules. This information is structured as a collection of pairs, where the keys are the submodules of `mod` (including `mod` itself). Currently, the values are a `Vector` of `NamedTuple`s with the following keys:

- `name::Symbol`: the name being accessed
- `location::String`: the location the access takes place
- `value::Any`: the which `name` points to in `mod`
- `accessing_from::Module`: the module the name is being accessed from (e.g. `Module.name`)
- `whichmodule::Module`: the `Base.which` of the object
- `public_access::Bool`: whether or not `name` is public or exported in `accessing_from`. Checking if a name is marked `public` requires Julia v1.11+.
- `accessing_from_owns_name::Bool`: whether or not `accessing_from` matches `whichmodule` and therefore is considered to directly "own" the name
- `accessing_from_submodule_owns_name::Bool`: whether or not `whichmodule` is a submodule of `accessing_from`
- `internal_access::Bool`: whether or not the access is "internal", meaning the module it was accessed in and the module it was accessed from share the same `Base.moduleroot`.
- `self_qualified::Bool`: whether or not the access is "self-qualified", meaning the module it was accessed in and the module it is accessed from are the same module.

In non-breaking releases of ExplicitImports:

- more columns may be added to these rows
- additional rows may be returned which qualify as some other kind of "improper" access

However, the result will be a Tables.jl-compatible row-oriented table (for each module), with at least all of the same columns.

See also [`print_explicit_imports`](@ref) to easily compute and print these results, [`improper_qualified_accesses_nonrecursive`](@ref) for a non-recursive version which ignores submodules, and the `check_` functions  [`check_all_qualified_accesses_via_owners`](@ref) and [`check_all_explicit_imports_are_public`](@ref) for versions that throws errors, for regression testing.

## Example

```jldoctest
julia> using ExplicitImports

julia> example_path = pkgdir(ExplicitImports, "examples", "qualified.jl");

julia> print(read(example_path, String))
module MyMod
using LinearAlgebra
# sum is in `Base`, so we shouldn't access it from LinearAlgebra:
n = LinearAlgebra.sum([1, 2, 3])
end

julia> include(example_path);

julia> row = improper_qualified_accesses(MyMod, example_path)[1][2][1];

julia> (; row.name, row.accessing_from, row.whichmodule)
(name = :sum, accessing_from = LinearAlgebra, whichmodule = Base)
```
"""
function improper_qualified_accesses(mod::Module, file=pathof(mod);
                                     skip=(Base => Core,
                                           Compat => Base,
                                           Compat => Core),
                                     allow_internal_accesses=true,
                                     # deprecated
                                     require_submodule_access=nothing)
    check_file(file)
    if require_submodule_access !== nothing
        @warn "[improper_qualified_accesses] `require_submodule_access` is deprecated and unused" _id = :explicit_imports_improper_qualified_accesses_require_submodule_access maxlog = 1
    end
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => improper_qualified_accesses_nonrecursive(submodule, path;
                                                                  file_analysis=file_analysis[path],
                                                                  skip,
                                                                  require_submodule_access,
                                                                  allow_internal_accesses)
            for (submodule, path) in submodules]
end
