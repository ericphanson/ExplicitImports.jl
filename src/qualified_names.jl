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

function improper_qualified_names_nonrecursive(mod::Module, file=pathof(mod);
                                               # private undocumented kwarg for hoisting this analysis
                                               file_analysis=get_names_used(file))
    check_file(file)
    qualified = analyze_qualified_names(mod, file; file_analysis)
    # We allow `Base.x` for names that are owned by Core, like `NamedTuple`
    problematic = [row
                   for row in qualified
                   if !row.accessing_from_matches_parent &&
                      !(row.parentmodule == Core && row.accessing_from == Base)]
    return problematic
end

function improper_qualified_names(mod::Module, file=pathof(mod))
    check_file(file)
    submodules = find_submodules(mod, file)
    file_analysis = Dict{String,FileAnalysis}()
    fill_cache!(file_analysis, last.(submodules))
    return [submodule => improper_qualified_names_nonrecursive(submodule, path;
                                                               file_analysis=file_analysis[path])
            for (submodule, path) in submodules]
end

function print_improper_qualified_names(mod::Module, file=pathof(mod))
    return print_improper_qualified_names(stdout, mod, file)
end

function print_improper_qualified_names(io::IO, mod::Module, file=pathof(mod))
    check_file(file)
    for (i, (mod, problematic)) in enumerate(improper_qualified_names(mod, file))
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
