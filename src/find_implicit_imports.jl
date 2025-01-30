# https://discourse.julialang.org/t/how-to-get-all-variable-names-currently-accessible/108839/2
modules_from_using(m::Module) = ccall(:jl_module_usings, Any, (Any,), m)

function get_implicit_names(mod; skip=(mod, Base, Core))
    implicit_names = Dict{Symbol,Vector{Module}}()
    for mod in modules_from_using(mod)
        should_skip(mod; skip) && continue
        for name in names(mod)
            v = get!(Vector{Module}, implicit_names, name)
            push!(v, mod)
        end
    end
    return implicit_names
end

"""
    find_implicit_imports(mod::Module; skip=(mod, Base, Core))

Given a module `mod`, returns a `Dict{Symbol, @NamedTuple{source::Module,exporters::Vector{Module}}}` showing
names exist in `mod`'s namespace which are available due to implicit
exports by other modules. The dict's keys are those names, and the values
are the source module that the name comes from, along with the modules which export the same binding that are available in `mod` due to implicit imports.

In the case of ambiguities (two modules exporting the same name), the name
is unavailable in the module, and hence the name will not be present in the dict.

This is powered by `Base.which`.
"""
function find_implicit_imports(mod::Module; skip=(mod, Base, Core))
    implicit_names = get_implicit_names(mod; skip)

    # Build a dictionary to lookup modules from names
    # we use `which` to figure out what the name resolves to in `mod`
    mod_lookup = Dict{Symbol,@NamedTuple{source::Module,exporters::Vector{Module}}}()
    for (name, exporters) in implicit_names
        source_module = try
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
        # note `source_module` can equal `mod` if both `mod` and some other module
        # define the same name. If it resolves to `mod` though, we don't want to
        # explicitly import anything!
        if !ismissing(source_module) && source_module !== mod
            source = source_module

            es = Module[]
            # Now figure out what names it was exported from
            binding = getglobal(source_module, name)
            # which one to use if more than 1?
            # currently we will use the last one...
            for e in exporters
                exported_binding = try_getglobal(e, name)
                if exported_binding === binding
                    push!(es, e)
                end
            end
            # if there are no matches (empty `es`), we will skip it
            # This seemed to happen for `tryparse` in `Pkg.Types` which resolves to `Base.tryparse`
            # and does not match `TOML.tryparse` which was the only candidate to compare to
            # (since we want to skip `Base.tryparse` as `Base` is in `skip`)
            # If there are no matches, such as in this case, we don't want to count it
            # as an implicit import, since it is probably only from a module in `skip`.
            if !isempty(es)
                mod_lookup[name] = (; source, exporters=es)
            end
        end
    end
    return mod_lookup
end

function try_getglobal(mod, name)
    try
        getglobal(mod, name)
    catch e
        if e isa UndefVarError
            nothing
        else
            rethrow()
        end
    end
end
