module ExplicitImports

using JuliaSyntax, AbstractTrees
# suppress warning about Base.parse collision, even though parse is never used
# this avoids a warning when loading the package while creating an unused explicit import
# the former occurs for all users, the latter only for developers of this package
using JuliaSyntax: parse
using AbstractTrees: parent
using TOML: parsefile
using Compat: Compat, @compat
using Markdown: Markdown
using PrecompileTools: @setup_workload, @compile_workload

export print_explicit_imports, explicit_imports, check_no_implicit_imports,
       explicit_imports_nonrecursive
export print_explicit_imports_script
export improper_qualified_accesses,
       improper_qualified_accesses_nonrecursive, check_all_qualified_accesses_via_owners,
       check_all_qualified_accesses_are_public,
       check_no_self_qualified_accesses
export improper_explicit_imports, improper_explicit_imports_nonrecursive,
       check_all_explicit_imports_via_owners, check_all_explicit_imports_are_public
export ImplicitImportsException, UnanalyzableModuleException,
       FileNotFoundException, QualifiedAccessesFromNonOwnerException,
       ExplicitImportsFromNonOwnerException, NonPublicExplicitImportsException,
       NonPublicQualifiedAccessException, SelfQualifiedAccessException
export StaleImportsException, check_no_stale_explicit_imports

# deprecated
export print_stale_explicit_imports, stale_explicit_imports,
       stale_explicit_imports_nonrecursive,
       print_improper_qualified_accesses

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

include("parse_utilities.jl")
include("find_implicit_imports.jl")
include("get_names_used.jl")
include("improper_qualified_accesses.jl")
include("improper_explicit_imports.jl")
include("interactive_usage.jl")
include("checks.jl")
include("deprecated.jl")
include("main.jl")

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
    explicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core), strict=true)

Returns a nested structure providing information about explicit import statements one could make for each submodule of `mod`. This information is structured as a collection of pairs, where the keys are the submodules of `mod` (including `mod` itself), and the values are `NamedTuple`s, with at least the keys `name`, `source`, `exporters`, and `location`, showing which names are being used implicitly, which modules they were defined in, which modules they were exported from, and the location of those usages. Additional keys may be added to the `NamedTuple`'s in the future in non-breaking releases of ExplicitImports.jl.

## Arguments

* `mod::Module`: the module to (recursively) analyze. Often this is a package.
* `file=pathof(mod)`: this should be a path to the source code that contains the module `mod`.
    * if `mod` is the top-level module of a package, `pathof` will be unable to find the code, and a file must be passed which contains `mod` (either directly or indirectly through `include`s)
    * `mod` can be a submodule defined within `file`, but if two modules have the same name (e.g. `X.Y.X` and `X`), results may be inaccurate.

## Keyword arguments

$SKIPS_KWARG
$STRICT_KWARG

!!! note
    If `mod` is a package, we can detect the explicit_imports in the package extensions if those extensions are explicitly loaded before calling this function.

    For example, consider `PackageA` has a weak-dependency on `PackageB` and `PackageC` in the module `PkgBPkgCExt`

    ```julia-repl
    julia> using ExplicitImports, PackageA

    julia> explicit_imports(PackageA) # Only checks for explicit imports in PackageA and its submodules but not in `PkgBPkgCExt`
    ```

    To check for explicit imports in `PkgBPkgCExt`, you can do the following:

    ```julia-repl
    julia> using ExplicitImports, PackageA, PackageB, PackageC

    julia> explicit_imports(PackageA) # Now checks for explicit imports in PackageA and its submodules and also in `PkgBPkgCExt`
    ```

See also [`print_explicit_imports`](@ref) to easily compute and print these results, [`explicit_imports_nonrecursive`](@ref) for a non-recursive version which ignores submodules, and  [`check_no_implicit_imports`](@ref) for a version that throws errors, for regression testing.
"""
function explicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core),
                          strict=true,
                          # deprecated
                          warn_stale=nothing,
                          # private undocumented kwarg for hoisting this analysis
                          file_analysis=Dict())
    check_file(file)
    if warn_stale !== nothing
        @warn "[explicit_imports] keyword argument `warn_stale` is deprecated and does nothing" _id = :explicit_imports_explicit_imports_warn_stale maxlog = 1
    end

    submodules = find_submodules(mod, file)
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => explicit_imports_nonrecursive(submodule, path; skip, warn_stale,
                                                       file_analysis=file_analysis[path],
                                                       strict)
            for (submodule, path) in submodules]
end

# TODO-someday; there may be a better way to make this choice
function choose_exporter(name, exporters)
    by = mod -> reverse(module_path(mod))
    sorted = sort(exporters; by, lt=is_prefix)
    return first(sorted)
end

function using_statements(io::IO, rows; linewidth=80, show_locations=false,
                          separate_lines=false)
    chosen = (choose_exporter(row.name, row.exporters) for row in rows)
    prev_mod = nothing
    cur_line_width = 0
    indent = 0
    first = true
    for (mod, row) in zip(chosen, rows)
        @compat (; name, location) = row
        if show_locations || mod !== prev_mod || separate_lines
            cur_line_width = 0
            loc = show_locations ? " # used at $(location)" : ""
            # skip `Main.X`, just do `.X`
            v = replace(string(mod), "Main" => "")
            use = "using $v: "
            indent = textwidth(use)
            prev_mod = mod
            to_print = string(first ? "" : "\n", use, name, loc)
        elseif cur_line_width + textwidth(", $name") >= linewidth
            to_print = string(",\n", " "^indent, name)
            cur_line_width = 0
        else
            to_print = string(", $name")
        end
        first = false
        cur_line_width += textwidth(to_print)
        print(io, to_print)
    end
    println(io)
    return nothing
end

function is_prefix(x, y)
    return length(x) <= length(y) && all(Base.splat(isequal), zip(x, y))
end

"""
    explicit_imports_nonrecursive(mod::Module, file=pathof(mod); skip=(mod, Base, Core), strict=true)

A non-recursive version of [`explicit_imports`](@ref), meaning it only analyzes the module `mod` itself, not any of its submodules; see that function for details.

## Keyword arguments

$SKIPS_KWARG
$STRICT_NONRECURSIVE_KWARG

"""
function explicit_imports_nonrecursive(mod::Module, file=pathof(mod);
                                       skip=(mod, Base, Core),
                                       strict=true,
                                       # deprecated
                                       warn_stale=nothing,
                                       # private undocumented kwarg for hoisting this analysis
                                       file_analysis=get_names_used(file))
    check_file(file)
    if warn_stale !== nothing
        @warn "[explicit_imports_nonrecursive] keyword argument `warn_stale` is deprecated and does nothing" _id = :explicit_imports_explicit_imports_warn_stale maxlog = 1
    end
    all_implicit_imports = find_implicit_imports(mod; skip)

    needs_explicit_import, unnecessary_explicit_import, tainted = filter_to_module(file_analysis,
                                                                                   mod)

    if tainted && strict
        return nothing
    end
    needed_names = Set(nt.name for nt in needs_explicit_import)
    filter!(all_implicit_imports) do (k, v)
        k in needed_names || return false
        any(mod -> should_skip(mod; skip), v.exporters) && return false
        return true
    end

    location_lookup = Dict(nt.name => nt.location for nt in needs_explicit_import)

    to_make_explicit = [(; name=k, v..., location=location_lookup[k])
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

    by = nt -> (nt.name, choose_exporter(nt.name, nt.exporters))
    sort!(to_make_explicit; by, lt)

    return to_make_explicit
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
        (next == mod || nameof(mod) == :Main) && return path
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
    match = module_path -> all(Base.splat(isequal), zip(module_path, mod_path))

    per_usage_info = filter(file_analysis.per_usage_info) do nt
        return match(nt.module_path)
    end
    needs_explicit_import = filter(file_analysis.needs_explicit_import) do nt
        return match(nt.module_path)
    end
    unnecessary_explicit_import = filter(file_analysis.unnecessary_explicit_import) do nt
        return match(nt.module_path)
    end
    mods_found = filter(!isempty, file_analysis.untainted_modules)
    tainted = !any(match, mods_found)
    return (; needs_explicit_import, unnecessary_explicit_import, tainted, per_usage_info)
end

if VERSION < v"1.9-"
    getglobal(mod, name) = getfield(mod, name)
end

# https://github.com/JuliaLang/julia/issues/53574
function _parentmodule(mod)
    mod === Base && return Base
    return parentmodule(mod)
end

# recurse through to find all submodules of `mod`
function _find_submodules(mod)
    sub_modules = Set{Module}([mod])
    for name in names(mod; all=true)
        name == nameof(mod) && continue
        is_submodule = try
            value = getglobal(mod, name)
            value isa Module && _parentmodule(value) == mod
        catch e
            if e isa UndefVarError
                false
            else
                rethrow()
            end
        end
        if is_submodule
            submod = getglobal(mod, name)
            if submod ∉ sub_modules
                union!(sub_modules, _find_submodules(submod))
            end
        end
    end
    # pre-1.9, there are not package extensions
    VERSION < v"1.9-" && return sub_modules

    # Add extensions to the set of submodules if present
    project_file = get_project_file(mod)
    project_file === nothing && return sub_modules
    project_toml = parsefile(project_file)
    if haskey(project_toml, "extensions")
        extensions = project_toml["extensions"]
        for ext in keys(extensions)
            ext_mod = Base.get_extension(mod, Symbol(ext))
            ext_mod === nothing && continue
            if ext_mod ∉ sub_modules
                union!(sub_modules, _find_submodules(ext_mod))
            end
        end
    end
    return sub_modules
end

function get_project_file(mod)
    pkgdir(mod) === nothing && return nothing
    for filename in ("Project.toml", "JuliaProject.toml")
        pfile = joinpath(pkgdir(mod), filename)
        isfile(pfile) && return pfile
    end
    return nothing
end

function find_submodules(mod::Module, file=pathof(mod))
    submodules = sort!(collect(_find_submodules(mod)); by=reverse ∘ module_path,
                       lt=is_prefix)
    paths = find_submodule_path.((file,), submodules)
    return [submod => path for (submod, path) in zip(submodules, paths)]
end

function find_submodule_path(file, submodule)
    path = pathof(submodule)
    path === nothing && return file
    return path
end

function fill_cache!(file_analysis::Dict, files)
    for _file in files
        if !haskey(file_analysis, _file)
            file_analysis[_file] = get_names_used(_file)
        end
    end
    return file_analysis
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

@setup_workload begin
    @compile_workload begin
        sprint(print_explicit_imports, ExplicitImports, @__FILE__)
    end
end

end
