module ExplicitImports

using JuliaSyntax

# https://discourse.julialang.org/t/how-to-get-all-variable-names-currently-accessible/108839/2
modules_from_using(m::Module) = ccall(:jl_module_usings, Any, (Any,), m)

function get_implicit_names(mod)
    implicit_names = Symbol[]
    for mod in modules_from_using(mod)
        mod in (Base, Core) && continue
        append!(implicit_names, names(mod))
    end
    return unique!(implicit_names)
end

function get_names_used(file)
    # This is annoying, because at this level we can't work at the module level!
    # Because `pathof` and `pkgdir` only work for packages, not just modules,
    # so we can't find the src code in order to parse it.
    # Here, we need to figure out for each name we find, if it refers to
    # an implicit binding from an `using`'d module, OR, if it refers to something
    # in the local scope we are currently in.
    tree = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, read(file, String))
end

function find_implicit_imports(mod)
    implicit_names = get_implicit_names(mod)

    # Build a dictionary to lookup modules from names
    # we use `which` to figure out what the name resolves to in `mod`
    mod_lookup = Dict{Symbol,Module}()
    ambiguous_names = Symbol[]
    for name in implicit_names
        resolved_module = try
            which(mod, name)
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
        if ismissing(resolved_module)
            push!(ambiguous_names, name)
            # note `resolved_module` can equal `mod` if both `mod` and some other module
            # define the same name. If it resolves to `mod` though, we don't want to
            # explicitly import anything!
        elseif resolved_module !== mod
            mod_lookup[name] = resolved_module
        end
    end

    # Now, we need to figure out:
    # 1. Which of these names are actually used within `mod` (ignore the rest)
    #   For this, I think we do have to parse the code.
    # 2. Which of these names are not *already* explicitly imported/using'd
    #   * for imported, we can just look at `names(TestModA; imported=true, all=true)`
    #   * for using'd, we need https://github.com/JuliaLang/julia/issues/36529
    #   Maybe in the meantime we can parse the code ourselves and try to figure it out...

    return mod_lookup

end

end
