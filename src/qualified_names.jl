# We wish to find qualified usages of a name in which the qualifying module is not the owner of the name
# it is also interesting to know if the name is public in the qualifying module

function analyze_qualified_names(mod::Module, file=pathof(mod);
                                 # private undocumented kwarg for hoisting this analysis
                                 file_analysis=get_names_used(file))
    check_file(file)
    (; per_usage_info, tainted) = filter_to_module(file_analysis, mod)
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

    table = @NamedTuple{name::Symbol,location::String,value::Any,accessing_from::Module,
                        parentmodule::Module,
                        accessing_from_matches_parent::Bool}[]
    # Now check:
    for row in qualified
        output = process_qualified_row(row, mod)
        output === nothing && continue
        push!(table, output)
    end
    unique!(nt -> (; nt.name, nt.accessing_from), table)
    sort!(table; by=nt -> (; nt.name, nt.location))
    return table
end

function process_qualified_row(row, mod)
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

    # Skip things which do not have a parent module
    applicable(parentmodule, value) || return nothing
    # We still need a try-catch since `applicable` doesn't seem to catch everything, e.g.
    # `MethodError: no method matching parentmodule(::Type{Union{Adjoint{T, S}, Transpose{T, S}}})`
    parentmod = try
        parentmodule(value)
    catch
        return nothing
    end

    return (; row.name,
            row.location,
            value,
            accessing_from=current_mod,
            parentmodule=parentmod,
            accessing_from_matches_parent=current_mod == parentmod,)
end

# We can't just trust `hasproperty` since e.g. `hasproperty(Base, :Core) == false`:
# (https://github.com/JuliaLang/julia/issues/47150)
function trygetproperty(x::Module, y)
    return isdefined(x, y) ? Some(getproperty(x, y)) : nothing
end

"""
    improper_qualified_accesses_nonrecursive(mod::Module, file=pathof(mod); skip=(Base => Core,))


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

julia> (; row.name, row.accessing_from, row.parentmodule)
(name = :sum, accessing_from = LinearAlgebra, parentmodule = Base)
```
"""
function improper_qualified_accesses_nonrecursive(mod::Module, file=pathof(mod);
                                                  skip=(Base => Core,),
                                                  # private undocumented kwarg for hoisting this analysis
                                                  file_analysis=get_names_used(file))
    check_file(file)
    problematic = analyze_qualified_names(mod, file; file_analysis)

    # Currently only care about mismatches between `accessing_from` and `parent`.
    filter!(problematic) do row
        return !row.accessing_from_matches_parent
    end

    for (from, parent) in skip
        filter!(problematic) do row
            return !(row.parentmodule == parent && row.accessing_from == from)
        end
    end

    return problematic
end

"""
    improper_qualified_accesses(mod::Module, file=pathof(mod); skip=(Base => Core,))

Attempts do detect various kinds of "improper" qualified accesses taking place in `mod` and any submodules of `mod`.
Currently, only detects cases in which the name is being accessed from a module which is not it's "owner" (as determined by `Base.parentmodule`).

The keyword argument `skip` is expected to be an iterator of `accessing_from => parent` pairs, where names which are accessed from `accessing_from` but whose parent is `parent` are ignored. By default, accesses from Base to names owned by Core are skipped.

This functionality is still in development, so the exact results may change in future non-breaking releases. Read on for the current outputs, what may change, and what will not change (without a breaking release of ExplicitImports.jl).

Returns a nested structure providing information about improper accesses to names in other modules. This information is structured as a collection of pairs, where the keys are the submodules of `mod` (including `mod` itself). Currently, the values are a `Vector` of `NamedTuple`s with the following keys:

- `name::Symbol`: the name being accessed
- `location::String`: the location the access takes place
- `accessing_from::Module`: the module the name is being accessed from (e.g. `Module.name`)
- `parentmodule::Module`: the `Base.parentmodule` of the object
- `accessing_from_matches_parent::Bool`: whether or not `accessing_from == parentmodule`.

Currently, all rows have `accessing_from_matches_parent=false`.

In non-breaking releases of ExplicitImports:

- more columns may be added to these rows
- rows may be returned for which `accessing_from_matches_parent=true`, but have some other kind of issue (e.g. non-public)

However, the result will be a Tables.jl-compatible row-oriented table (for each module), with at least all of the same columns.

See also [`print_improper_qualified_accesses`](@ref) to easily compute and print these results, [`improper_qualified_accesses_nonrecursive`](@ref) for a non-recursive version which ignores submodules, and  [`check_all_qualified_accesses_via_parents`](@ref) for a version that throws errors, for regression testing.

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

julia> (; row.name, row.accessing_from, row.parentmodule)
(name = :sum, accessing_from = LinearAlgebra, parentmodule = Base)
```
"""
function improper_qualified_accesses(mod::Module, file=pathof(mod); skip=(Base => Core,))
    check_file(file)
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => improper_qualified_accesses_nonrecursive(submodule, path;
                                                                  file_analysis=file_analysis[path],
                                                                  skip)
            for (submodule, path) in submodules]
end

"""
    print_improper_qualified_accesses([io::IO=stdout,] mod::Module, file=pathof(mod))

Runs [`improper_qualified_accesses`](@ref) and prints the results.

Note that the particular printing may change in future non-breaking releases of ExplicitImports.

See also [`print_explicit_imports`](@ref) and [`check_all_qualified_accesses_via_parents`](@ref).
"""
print_improper_qualified_accesses

function print_improper_qualified_accesses(mod::Module, file=pathof(mod))
    return print_improper_qualified_accesses(stdout, mod, file)
end

function print_improper_qualified_accesses(io::IO, mod::Module, file=pathof(mod))
    check_file(file)
    for (i, (mod, problematic)) in enumerate(improper_qualified_accesses(mod, file))
        i == 1 || println(io)
        if isempty(problematic)
            println(io, "Module $mod accesses names only from parent modules.")
        else
            println(io,
                    "Module $mod accesses names from non-parent modules:")
            for row in problematic
                println(io,
                        "- `$(row.name)` has parentmodule $(row.parentmodule) but it was accessed from $(row.accessing_from) at $(row.location)")
            end
        end
    end

    # We leave this so we can have non-trivial printout when running this function on ExplicitImports:
    ExplicitImports.parent
    return nothing
end
