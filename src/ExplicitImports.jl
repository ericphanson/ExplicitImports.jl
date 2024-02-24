module ExplicitImports

using JuliaSyntax, AbstractTrees
using AbstractTrees: parent
using DataFrames

export explicit_imports, stale_explicit_imports, print_explicit_imports,
       explicit_imports_single, check_no_implicit_imports, check_no_stale_explicit_imports
export StaleImportsException, ImplicitImportsException

include("find_implicit_imports.jl")
include("get_names_used.jl")
include("checks.jl")

"""
    explicit_imports(mod, file=pathof(mod); skips=(Base, Core), warn=true)

Returns a nested structure providing information about explicit import statements one could make for each submodule of `mod`.

* `file=pathof(mod)`: this should be a path to the source code that contains the module `mod`.
    * if `mod` is not from a package, `pathof` will be unable to find the code, and a file must be passed which contains `mod` (either directly or indirectly through `include`s)
    * `mod` can be a submodule defined within `file`, but if two modules have the same name (e.g. `X.Y.X` and `X`), results may be inaccurate.
* `skips=(Base, Core)`: any names coming from the listed modules (or any submodules thereof) will be skipped.
* `warn=true`: whether or not to warn about stale explicit imports.

See also [`print_explicit_imports`](@ref) to easily compute and print these results, and [`explicit_imports_single`](@ref) for a non-recursive version which ignores submodules.
"""
function explicit_imports(mod, file=pathof(mod); skips=(Base, Core), warn=true)
    submodules = find_submodules(mod)
    return [submodule => explicit_imports_single(submodule, file; skips, warn)
            for submodule in submodules]
end

function print_explicit_imports(mod, file=pathof(mod); kw...)
    return print_explicit_imports(stdout, mod, file; kw...)
end

"""
    print_explicit_imports([io::IO=stdout,] mod, file=pathof(mod); kw...)

Runs [`explicit_imports`](@ref) and prints the results, along with those of [`stale_explicit_imports`](@ref). Accepts the same keyword arguments as that function.
"""
function print_explicit_imports(io::IO, mod, file=pathof(mod); kw...)
    ee = explicit_imports(mod, file; warn=false, kw...)
    for (mod, imports) in ee
        if isempty(imports)
            println(io, "Module $mod is not relying on any implicit imports.")
        else
            println(io,
                    "Module $mod is relying on implicit imports for $(length(imports)) names. These could be explicitly imported as follows:")
            println(io)
            println(io, "```julia")
            for pair in imports
                println(io, using_statement(pair))
            end
            println(io, "```")
        end
        stale = stale_explicit_imports(mod, file)
        if !isempty(stale)
            println(io)
            println(io,
                    "Additionally $mod has stale explicit imports for these unused names:")
            foreach(line -> println(io, line), stale)
        end
    end
end

function using_statement((k, v_mod))
    # skip `Main.X`, just do `.X`
    v = replace(string(v_mod), "Main" => "")
    return "using $v: $k"
end

function is_prefix(x, y)
    return length(x) <= length(y) && all(Base.splat(isequal), zip(x, y))
end

"""
    explicit_imports_single(mod, file=pathof(mod); skips=(Base, Core), warn=true)

A non-recursive version of [`explicit_imports`](@ref); see that function for details.
"""
function explicit_imports_single(mod, file=pathof(mod); skips=(Base, Core), warn=true)
    if isnothing(file)
        throw(ArgumentError("This appears to be a module which is not defined in package. In this case, the file which defines the module must be passed explicitly as the second argument."))
    end
    all_implicit_imports = find_implicit_imports(mod; skips)
    df = get_names_used(file)
    df = restrict_to_module(df, mod)

    needs = subset(df, :needs_explicit_import)
    needed_names = Set(needs.name)
    filter!(all_implicit_imports) do (k, v)
        k in needed_names || return false
        should_skip(v; skips) && return false
        # skip `using X: X`
        nameof(v) == k && return false
        return true
    end

    to_make_explicit = [k => v for (k, v) in all_implicit_imports]

    function lt((k1, v1), (k2, v2))
        p1 = reverse(module_path(v1))
        p2 = reverse(module_path(v2))
        is_lt = if p1 == p2
            isless(k1, k2)
        elseif is_prefix(p1, p2)
            true
        else
            tuple(p1) <= tuple(p2)
        end
        return is_lt
    end

    sort!(to_make_explicit; lt)

    if warn
        unnecessary = unique(sort(subset(df, :unnecessary_explicit_import).name))
        if !isempty(unnecessary)
            @warn "Found stale explicit imports in $mod for these names: $unnecessary. To get this list programmatically, call `stale_explicit_imports`. To silence this warning, pass `warn=false`."
        end
    end

    return to_make_explicit
end

"""
    stale_explicit_imports(mod, file=pathof(mod)) -> Vector{Symbol}

Returns a list of names that are not used in `mod`, but are still explicitly imported.
"""
function stale_explicit_imports(mod, file=pathof(mod))
    if isnothing(file)
        throw(ArgumentError("This appears to be a module which is not defined in package. In this case, the file which defines the module must be passed explicitly as the second argument."))
    end
    df = get_names_used(file)
    df = restrict_to_module(df, mod)
    unnecessary = unique(sort(subset(df, :unnecessary_explicit_import).name))
    return unnecessary
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

function find_submodules(mod)
    return sort!(collect(_find_submodules(mod)); by=reverse ∘ module_path,
                 lt=is_prefix)
end

end
