module ExplicitImports

using JuliaSyntax, AbstractTrees
using AbstractTrees: parent

export print_explicit_imports, explicit_imports, check_no_implicit_imports,
       explicit_imports_nonrecursive
export print_stale_explicit_imports, stale_explicit_imports,
       check_no_stale_explicit_imports, stale_explicit_imports_nonrecursive
export StaleImportsException, ImplicitImportsException, UnanalyzableModuleException,
       FileNotFoundException

include("parse_utilities.jl")
include("find_implicit_imports.jl")
include("get_names_used.jl")
include("checks.jl")

const SKIPS_KWARG = """
    * `skip=(mod, Base, Core)`: any names coming from the listed modules (or any submodules thereof) will be skipped. Since `mod` is included by default, implicit imports of names exported from its own submodules will not count by default.
    """

const STRICT_KWARG = """
    * `strict=true`: when `strict` is set, results for a module will be `nothing` in the case that the analysis could not be performed accurately, due to e.g. dynamic `include` statements. When `strict=false`, results are returned in all cases, but may be inaccurate."""

const STRICT_PRINTING_KWARG = """
    * `strict=true`: when `strict` is set, a module will be noted as unanalyzable in the case that the analysis could not be performed accurately, due to e.g. dynamic `include` statements. When `strict=false`, results are returned in all cases, but may be inaccurate.
    """

const STRICT_NONRECURSIVE_KWARG = """
    * `strict=true`: when `strict=true`, results will be `nothing` in the case that the analysis could not be performed accurately, due to e.g. dynamic `include` statements. When `strict=false`, results are returned in all cases, but may be inaccurate."""

const WARN_STALE_KWARG = """
    * `warn_stale=true`: whether or not to warn about stale explicit imports.
    """

struct FileNotFoundException <: Exception end

function Base.showerror(io::IO, ::FileNotFoundException)
    println(io,
            """
            FileNotFoundException:
            This appears to be a module which is not top-level in a package. In this case, a file which defines the module (or includes files which do) must be passed explicitly as the second argument.
            """)
    print(io,
          """
          For example, if you've passed a submodule of a package, you can pass `pkgdir(MyPackage)` as the second argument. Or if you've passed a module which is not part of a package, pass the filepath to the code that defines the module.""")
    return nothing
end

function check_file(file)
    isnothing(file) && throw(FileNotFoundException())
    return nothing
end

"""
    explicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core), warn_stale=true, strict=true)

Returns a nested structure providing information about explicit import statements one could make for each submodule of `mod`. This information is structured as a collection of pairs, where the keys are the submodules of `mod` (including `mod` itself), and the values are `NamedTuple`s, with at least the keys `name`, `source`, and `location`, showing which names are being used implicitly, which modules they came from, and the location of those usages. Additional keys may be added to the `NamedTuple`'s in the future in non-breaking releases of ExplicitImports.jl.

## Arguments

* `mod::Module`: the module to (recursively) analyze. Often this is a package.
* `file=pathof(mod)`: this should be a path to the source code that contains the module `mod`.
    * if `mod` is the top-level module of a package, `pathof` will be unable to find the code, and a file must be passed which contains `mod` (either directly or indirectly through `include`s)
    * `mod` can be a submodule defined within `file`, but if two modules have the same name (e.g. `X.Y.X` and `X`), results may be inaccurate.

## Keyword arguments

$SKIPS_KWARG
$WARN_STALE_KWARG
$STRICT_KWARG

See also [`print_explicit_imports`](@ref) to easily compute and print these results, [`explicit_imports_nonrecursive`](@ref) for a non-recursive version which ignores submodules, and  [`check_no_implicit_imports`](@ref) for a version that throws errors, for regression testing.
"""
function explicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core),
                          warn_stale=true, strict=true,
                          # private undocumented kwarg for hoisting this analysis
                          file_analysis=get_names_used(file))
    check_file(file)
    submodules = find_submodules(mod)
    return [submodule => explicit_imports_nonrecursive(submodule, file; skip, warn_stale,
                                                       file_analysis, strict)
            for submodule in submodules]
end

function print_explicit_imports(mod::Module, file=pathof(mod); kw...)
    return print_explicit_imports(stdout, mod, file; kw...)
end

"""
    print_explicit_imports([io::IO=stdout,] mod::Module, file=pathof(mod); skip=(mod, Base, Core), warn_stale=true, strict=true)

Runs [`explicit_imports`](@ref) and prints the results, along with those of [`stale_explicit_imports`](@ref).

## Keyword arguments

$SKIPS_KWARG
* `warn_stale=true`: if set, this function will also print information about stale explicit imports.
$STRICT_PRINTING_KWARG

See also [`check_no_implicit_imports`](@ref) and [`check_no_stale_explicit_imports`](@ref).
"""
function print_explicit_imports(io::IO, mod::Module, file=pathof(mod);
                                skip=(mod, Base, Core), warn_stale=true, strict=true)
    file_analysis = get_names_used(file)
    ee = explicit_imports(mod, file; warn_stale=false, skip, strict, file_analysis)
    for (i, (mod, imports)) in enumerate(ee)
        i == 1 || println(io)
        if isnothing(imports)
            println(io,
                    "Module $mod could not be accurately analyzed, likely due to dynamic `include` statements. You can pass `strict=false` to attempt to get (possibly inaccurate) results anyway.")
        elseif isempty(imports)
            println(io, "Module $mod is not relying on any implicit imports.")
        else
            println(io,
                    "Module $mod is relying on implicit imports for $(length(imports)) names. ",
                    "These could be explicitly imported as follows:")
            println(io)
            println(io, "```julia")
            for nt in imports
                println(io, using_statement(nt))
            end
            println(io, "```")
        end
        if warn_stale
            stale = stale_explicit_imports_nonrecursive(mod, file; strict, file_analysis)
            if !isnothing(stale) && !isempty(stale)
                word = isempty(imports) ? "However" : "Additionally"
                println(io)
                println(io,
                        "$word, $mod has stale explicit imports for these unused names:")
                for (; name) in stale
                    println(io, "- $name")
                end
            end
        end
    end
end

function using_statement((; name, source))
    # skip `Main.X`, just do `.X`
    v = replace(string(source), "Main" => "")
    return "using $v: $name"
end

function is_prefix(x, y)
    return length(x) <= length(y) && all(Base.splat(isequal), zip(x, y))
end

"""
    explicit_imports_nonrecursive(mod::Module, file=pathof(mod); skip=(mod, Base, Core), warn_stale=true, strict=true)

A non-recursive version of [`explicit_imports`](@ref), meaning it only analyzes the module `mod` itself, not any of its submodules; see that function for details.

## Keyword arguments

$SKIPS_KWARG
$WARN_STALE_KWARG
$STRICT_NONRECURSIVE_KWARG

"""
function explicit_imports_nonrecursive(mod::Module, file=pathof(mod);
                                       skip=(mod, Base, Core),
                                       warn_stale=true,
                                       strict=true,
                                       # private undocumented kwarg for hoisting this analysis
                                       file_analysis=get_names_used(file))
    check_file(file)
    all_implicit_imports = find_implicit_imports(mod; skip)

    needs_explicit_import, unnecessary_explicit_import, tainted = filter_to_module(file_analysis,
                                                                                   mod)

    if tainted && strict
        return nothing
    end
    needed_names = Set(nt.name for nt in needs_explicit_import)
    filter!(all_implicit_imports) do (k, v)
        k in needed_names || return false
        should_skip(v; skip) && return false
        return true
    end

    location_lookup = Dict(nt.name => nt.location for nt in needs_explicit_import)

    to_make_explicit = [(; name=k, source=v, location=location_lookup[k])
                        for (k, v) in all_implicit_imports]

    function lt((k1, v1), (k2, v2))
        p1 = reverse(module_path(v1))
        p2 = reverse(module_path(v2))
        is_lt = if p1 == p2
            if nameof(v1) == k1
                true
            elseif nameof(v1) == k2
                false
            else
                isless(k1, k2)
            end
        elseif is_prefix(p1, p2)
            true
        else
            tuple(p1) <= tuple(p2)
        end
        return is_lt
    end

    sort!(to_make_explicit; lt)

    if warn_stale
        unnecessary = unique!(sort!([nt.name for nt in unnecessary_explicit_import]))
        if !isempty(unnecessary)
            @warn "Found stale explicit imports in $mod for these names: $unnecessary. To get this list programmatically, call `stale_explicit_imports`. To silence this warning, pass `warn_stale=false`."
        end
    end

    return to_make_explicit
end

"""
    print_stale_explicit_imports([io::IO=stdout,] mod::Module, file=pathof(mod); strict=true)

Runs [`stale_explicit_imports`](@ref) and prints the results.

## Keyword arguments

$STRICT_PRINTING_KWARG

See also [`print_explicit_imports`](@ref) and [`check_no_stale_explicit_imports`](@ref).
"""
print_stale_explicit_imports

function print_stale_explicit_imports(mod::Module, file=pathof(mod); kw...)
    return print_stale_explicit_imports(stdout, mod, file; kw...)
end
function print_stale_explicit_imports(io::IO, mod::Module, file=pathof(mod); strict=true)
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
            for name in stale_imports
                println(io, "- $name")
            end
        end
    end
end

"""
    stale_explicit_imports(mod::Module, file=pathof(mod); strict=true)

Returns a collection of pairs, where the keys are submodules of `mod` (including `mod` itself), and the values are either `nothing` if `strict=true` and the module couldn't analyzed, or else a vector of `NamedTuple`s with at least the keys `name` and `location`, consisting of names that are explicitly imported in that submodule, but which either are not used, or are only used in a qualified fashion, making the explicit import a priori unnecessary.

More keys may be added to the NamedTuples in the future in non-breaking releases of ExplicitImports.jl.

!!! warning
    Note that it is possible for an import from a module (say `X`) into one module (say `A`) to be relied on from another unrelated module (say `B`). For example, if `A` contains the code `using X: x`, but either does not use `x` at all or only uses `x` in the form `X.x`, then `x` will be flagged as a stale explicit import by this function. However, it could be that the code in some unrelated module `B` uses `A.x` or `using A: x`, relying on the fact that `x` has been imported into `A`'s namespace.

    This is an unusual situation (generally `B` should just get `x` directly from `X`, rather than indirectly via `A`), but there are situations in which it arises, so one may need to be careful about naively removing all "stale" explicit imports flagged by this function.

## Keyword arguments

$STRICT_KWARG

See [`stale_explicit_imports_nonrecursive`](@ref) for a non-recursive version, and [`check_no_stale_explicit_imports`](@ref) for a version that throws an error when encountering stale explicit imports.

See also [`print_explicit_imports`](@ref) which prints this information.
"""
function stale_explicit_imports(mod::Module, file=pathof(mod); strict=true)
    check_file(file)
    submodules = find_submodules(mod)
    file_analysis = get_names_used(file) # only do this once
    return [submodule => stale_explicit_imports_nonrecursive(submodule, file; file_analysis,
                                                             strict)
            for submodule in submodules]
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

function has_ancestor(query, target)
    query == target && return true
    while true
        next = parentmodule(query)
        next == target && return true
        next == query && return false
        query = next
    end
end

function should_skip(target; skip)
    for m in skip
        has_ancestor(target, m) && return true
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

function filter_to_module(file_analysis::FileAnalysis, mod::Module)
    mod_path = module_path(mod)
    # Limit to only the module of interest. We make some attempt to avoid name collisions
    # (where two nested modules have the same name) by matching on the full path - to some extent.
    # We can't really assume we were given the "top-level" file (I think), so we might not be
    # aware of all the parent modules in the names we obtained by parsing.
    # Therefore, we use `zip` for its early termination, to just match the module paths
    # to the extent they agree (starting at the earliest point).
    # This means we cannot distinguish X.Y.X from X in some cases.
    # Don't do that!
    match = module_path -> all(Base.splat(isequal), zip(module_path, mod_path))

    needs_explicit_import = filter(file_analysis.needs_explicit_import) do nt
        return match(nt.module_path)
    end
    unnecessary_explicit_import = filter(file_analysis.unnecessary_explicit_import) do nt
        return match(nt.module_path)
    end
    tainted = !any(match, file_analysis.untainted_modules)
    return (; needs_explicit_import, unnecessary_explicit_import, tainted)
end

# recurse through to find all submodules of `mod`
function _find_submodules(mod)
    sub_modules = Set{Module}([mod])
    for name in names(mod; all=true)
        name == nameof(mod) && continue
        is_submodule = try
            value = getglobal(mod, name)
            value isa Module && parentmodule(value) == mod
        catch
            false
        end
        if is_submodule
            submod = getglobal(mod, name)
            if submod ∉ sub_modules
                union!(sub_modules, _find_submodules(submod))
            end
        end
    end
    return sub_modules
end

function find_submodules(mod::Module)
    return sort!(collect(_find_submodules(mod)); by=reverse ∘ module_path,
                 lt=is_prefix)
end

inspect_session(; kw...) = inspect_session(stdout; kw...)

"""
    ExplicitImports.inspect_session([io::IO=stdout,]; skip=(Base, Core), inner=print_explicit_imports)

Experimental functionality to call `inner` (defaulting to `print_explicit_imports`) on each loaded package in the Julia session.
"""
function inspect_session(io::IO; skip=(Base, Core), inner=print_explicit_imports)
    for mod in Base.loaded_modules_array()
        should_skip(mod; skip) && continue
        pathof(mod) === nothing && continue
        isfile(pathof(mod)) || continue
        inner(io, mod)
        println(io)
    end
end

end
