"""
    get_names_used(file) -> DataFrame

Figures out which global names are used in `file`, and what modules they are used within.

Traverses static `include` statements.

Returns a `DataFrame` with two columns, one for the `name`, and one for the path of modules,
where the first module in the path is the innermost.
"""
function get_names_used(file)
    df = analyze_all_names(file)

    # further processing...
    ret = combine(groupby(df, [:name, :module_path]),
                  [:global_scope, :assigned_before_used] => function (g, a)
                      return any(g) || any(!, a)
                  end => :may_want_to_explicitly_import)

    subset!(ret, :may_want_to_explicitly_import)
    select!(ret, :name, :module_path)
    return ret
end

"""
    analyze_all_names(file) -> DataFrame

Returns a DataFrame with one row per name per scope, with information about whether or not
it is within global scope, what modules it is in, and whether or not it was assigned before
ever being used in that scope.
"""
function analyze_all_names(file)
    # This is annoying, because at this level we can't work at the module level!
    # Because `pathof` and `pkgdir` only work for packages, not just modules,
    # so we can't find the src code in order to parse it.
    # Here, we need to figure out for each name we find, if it refers to
    # an implicit binding from an `using`'d module, OR, if it refers to something
    # in the local scope we are currently in.
    tree = SyntaxNodeWrapper(file)
    # in local scope, a name refers to a global if it is read from before it is assigned to, OR if the global keyword is used
    # a name refers to a local otherwise
    # so we need to traverse the tree, keeping track of state like: which scope are we in, and for each name, in each scope, has it been used

    cursor = TreeCursor(tree)
    df = DataFrame()
    for leaf in Leaves(cursor)
        JuliaSyntax.kind(nodevalue(leaf).node) == K"Identifier" || continue
        # Ok, we have a "name". We want to know if:
        # 1. it is being used in global scope
        # or 2. it is being used in local scope, but refers to a global binding
        # To figure out the latter, we check if it has been assigned before it has been used.
        #
        # We want to figure this out on a per-module basis, since each module has a different global namespace.

        # println("----------")
        ret = analyze_name(leaf)
        name = nodevalue(leaf).node.val
        # println(ret)
        push!(df, (; name, ret...))
    end

    grps = groupby(df, [:name, :scope_path, :global_scope, :module_path])
    return combine(grps, :is_assignment => (a -> a[1]) => :assigned_before_used)
end
# Here we define a wrapper so we can use AbstractTrees without piracy
# https://github.com/JuliaEcosystem/PackageAnalyzer.jl/blob/293a0836843f8ce476d023e1ca79b7e7354e884f/src/count_loc.jl#L91-L99
struct SyntaxNodeWrapper
    node::JuliaSyntax.SyntaxNode
    file::String
end

function SyntaxNodeWrapper(file::AbstractString)
    contents = read(file, String)
    parsed = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, contents)
    return SyntaxNodeWrapper(parsed, file)
end

function AbstractTrees.children(wrapper::SyntaxNodeWrapper)
    node = wrapper.node
    if JuliaSyntax.kind(node) == K"call"
        children = JuliaSyntax.children(node)
        if length(children) == 2
            f, arg = children
            if f.val === :include
                if JuliaSyntax.kind(arg) == K"string"
                    children = JuliaSyntax.children(arg)
                    c = only(children)
                    # The children of a static include statement is the entire file being included...
                    new_file = joinpath(dirname(wrapper.file), c.val)
                    @debug "Recursing into `$new_file`" node wrapper.file
                    return [SyntaxNodeWrapper(new_file)]
                else
                    error("Dynamic `include` found; aborting")
                end
            end
        end
    end
    return map(n -> SyntaxNodeWrapper(n, wrapper.file), JuliaSyntax.children(node))
end

# Here we use the magic of AbstractTrees' `TreeCursor` so we can start at
# a leaf and follow the parents up to see what scopes our leaf is in.
function analyze_name(leaf)
    # Ok, we have a "name". Let us work our way up and try to figure out if it is in local scope or not
    global_scope = true
    module_path = Symbol[]
    scope_path = []
    is_assignment = false
    node = leaf
    idx = 1
    while true
        # update our state
        val = nodevalue(node).node.val
        head = nodevalue(node).node.raw.head
        kind = JuliaSyntax.kind(head)
        args = nodevalue(node).node.raw.args

        # println(val, ": ", kind)
        if kind in (K"let", K"for", K"function")
            global_scope = false
            push!(scope_path, nodevalue(node).node)
            # try to detect presence in RHS of inline function definition
        elseif idx > 3 && kind == K"=" && !isempty(args) &&
               JuliaSyntax.kind(first(args)) == K"call"
            global_scope = false
            push!(scope_path, nodevalue(node).node)
        end

        # track which modules we are in
        if kind == K"module"
            ids = filter(children(nodevalue(node))) do arg
                return JuliaSyntax.kind(arg.node) == K"Identifier"
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
            end
        end

        node = parent(node)
        node === nothing && return (; global_scope, is_assignment, module_path, scope_path)
        idx += 1
    end
end
