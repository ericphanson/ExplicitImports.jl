module ExplicitImports

using JuliaSyntax, AbstractTrees
using AbstractTrees: parent
using DataFrames

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
using AbstractTrees, JuliaSyntax

struct SyntaxNodeWrapper
    node::JuliaSyntax.SyntaxNode
    source::JuliaSyntax.SourceFile
end

function AbstractTrees.children(wrapper::SyntaxNodeWrapper)
    return map(n -> SyntaxNodeWrapper(n, wrapper.source), JuliaSyntax.children(wrapper.node))
end

export get_names_used

function get_names_used(file)
    # This is annoying, because at this level we can't work at the module level!
    # Because `pathof` and `pkgdir` only work for packages, not just modules,
    # so we can't find the src code in order to parse it.
    # Here, we need to figure out for each name we find, if it refers to
    # an implicit binding from an `using`'d module, OR, if it refers to something
    # in the local scope we are currently in.
    contents = read(file, String)
    parsed = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, contents)
    tree = SyntaxNodeWrapper(parsed, JuliaSyntax.SourceFile(contents; filename=file))
    # in local scope, a name refers to a global if it is read from before it is assigned to, OR if the global keyword is used
    # a name refers to a local otherwise
    # so we need to traverse the tree, keeping track of state like: which scope are we in, and for each name, in each scope, has it been used

    cursor = TreeCursor(tree)
    df = DataFrame()
    for leaf in Leaves(cursor)
        JuliaSyntax.kind(nodevalue(leaf).node) == K"Identifier" || continue
        # Ok, we have a "name". Let us work our way up and try to figure out if it is in local scope or not
        println("----------")
        ret = analyze_variable(leaf)
        name = nodevalue(leaf).node.val
        println(ret)
        push!(df, (; name, ret...))
    end

    grps = groupby(df, [:name, :scope_path, :global_scope, :module_path])
    ret = combine(grps, :is_assignment => (a -> a[1]) => :assigned_before_used)

    # Ok, which names do we need to explicitly import?
    # first, find all the global names that we might want to explicitly import
    # then check which ones resolve to an external package

    # which global names are there? those are all the ones either used in global scope,
    # or used in local scope but also assigned before they have been used.
    # we want to figure this out on a per-module basis.

    ret = combine(groupby(ret, [:name, :module_path]),
        [:global_scope, :assigned_before_used] => function(g,a)
            any(g) || any(!, a)
        end => :may_want_to_explicitly_import)

    subset!(ret, :may_want_to_explicitly_import)
    select!(ret, :name, :module_path)
    return ret
end

struct NodeSummary
    node::JuliaSyntax.SyntaxNode
end

function analyze_variable(node)
    # Ok, we have a "name". Let us work our way up and try to figure out if it is in local scope or not
    global_scope = true
    module_path = Symbol[]
    scope_path = []
    is_assignment = false
    leaf = node
    idx = 1
    while true
        # update our state
        val = nodevalue(node).node.val
        head = nodevalue(node).node.raw.head
        kind = JuliaSyntax.kind(head)
        args = nodevalue(node).node.raw.args

        println(val, ": ", kind)
        # clear local scope
        if kind in (K"let", K"for", K"function")
            global_scope = false
            push!(scope_path, nodevalue(node).node)
            # try to detect presence in RHS of inline function definition
        elseif idx > 3 && kind == K"=" && !isempty(args) && JuliaSyntax.kind(first(args)) == K"call"
            global_scope = false
            push!(scope_path, nodevalue(node).node)
            # println(JuliaSyntax.kind.(nodevalue(node).node.raw.args))
        end

        # track which modules we are in
        if kind == K"module"
            ids = filter(children(nodevalue(node))) do arg
                JuliaSyntax.kind(arg.node) == K"Identifier"
            end
            if !isempty(ids)
                push!(module_path, first(ids).node.val)
            end
            push!(scope_path, nodevalue(node).node)
        end

        if kind == K"="
            kids = children(nodevalue(node))
            if !isempty(kids)
                c = first(kids)
                is_assignment = c == nodevalue(leaf)
                @show c, nodevalue(leaf)
            end
        end

        node = parent(node)
        node === nothing && return (; global_scope, is_assignment, module_path, scope_path)
        idx += 1
    end
end

export find_implicit_imports
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

export do_it
function do_it(mod, file)
    all_implicit_imports = find_implicit_imports(mod)
    df = get_names_used(file)
    relevant_keys = intersect(df.name, keys(all_implicit_imports))
    return relevant_keys
end

end
#
