# https://discourse.julialang.org/t/how-to-get-all-variable-names-currently-accessible/108839/2
modules_from_using(m::Module) = ccall(:jl_module_usings, Any, (Any,), m)

function get_implicit_names(mod; skip=(mod, Base, Core))
    implicit_names = Symbol[]
    for mod in modules_from_using(mod)
        should_skip(mod; skip) && continue
        append!(implicit_names, names(mod))
    end
    return unique!(implicit_names)
end

"""
    find_implicit_imports(mod::Module; skip=(mod, Base, Core))

Given a module `mod`, returns a `Dict{Symbol, Module}` showing
names exist in `mod`'s namespace which are available due to implicit
exports by other modules. The dict's keys are those names, and the values
are the module that the name comes from.

In the case of ambiguities (two modules exporting the same name), the name
is unavailable in the module, and hence the name will not be present in the dict.

This is powered by `Base.which`.
"""
function find_implicit_imports(mod::Module; skip=(mod, Base, Core))
    implicit_names = get_implicit_names(mod; skip)

    # Build a dictionary to lookup modules from names
    # we use `which` to figure out what the name resolves to in `mod`
    mod_lookup = Dict{Symbol,Module}()
    for name in implicit_names
        resolved_module = try
            # I would like to suppress this warning:
            # WARNING: both X and Y export "parse"; uses of it in module Z must be qualified
            # However, `redirect_stdio` does not help!
            # redirect_stdio(; stderr=devnull, stdout=devnull) do
            which(mod, name)
            # end
        catch err
            # This happens when you get stuff like
            # `WARNING: both Exporter3 and Exporter2 export "exported_a"; uses of it in module TestModA must be qualified`
            # and there is an ambiguity, and the name is in fact not resolved in `mod`
            clash = err == ErrorException("\"$name\" is not defined in module $mod")
            # if it is something else, rethrow
            clash || rethrow()
            missing
        end
        # for unambiguous names, we can figure them out
        # note `resolved_module` can equal `mod` if both `mod` and some other module
        # define the same name. If it resolves to `mod` though, we don't want to
        # explicitly import anything!
        if !ismissing(resolved_module) && resolved_module !== mod
            mod_lookup[name] = resolved_module
        end
    end
    return mod_lookup
end
