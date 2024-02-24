# In this file, we try to answer the question: what global bindings are being used in a particular module?
# We will do this by parsing, then re-implementing scoping rules on top of the parse tree.

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

# Here we define children such that if we get to a static `include`, we just recurse
# into the parse tree of that file.
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
                    line, col = JuliaSyntax.source_location(wrapper.node)
                    location = "$(wrapper.file):$line:$col"
                    # We choose our `id` so maxlog will work the way we want
                    # (don't log the same message multiple times, but do log each separate location)
                    id = Symbol("dynamic_include_", location)
                    @warn("Dynamic `include` found at $location; not recursing", _id = id,
                          maxlog = 1)
                end
            end
        end
    end
    return map(n -> SyntaxNodeWrapper(n, wrapper.file), JuliaSyntax.children(node))
end

function is_qualified(leaf)
    # is this name being used in a qualified context, like `X.y`?
    if !isnothing(parent(leaf)) && !isnothing(parent(parent(leaf)))
        p = nodevalue(parent(leaf)).node
        p2 = nodevalue(parent(parent(leaf))).node
        if JuliaSyntax.kind(p) == K"quote" && JuliaSyntax.kind(p2) == K"."
            # ok but is the quote we are in the 2nd argument, not the first?
            dot_kids = JuliaSyntax.children(p2)
            if length(dot_kids) == 2 && dot_kids[2] == p
                return true
            end
        end
    end
    return false
end

# figure out if `leaf` is part of an import or using statement
# this seems to trigger for both `X` and `y` in `using X: y`, but that seems alright.
function analyze_import_type(leaf)
    isnothing(parent(leaf)) && return false
    p = nodevalue(parent(leaf)).node
    is_import = JuliaSyntax.kind(p) == K"importpath"
    if is_import && !isnothing(parent(parent(leaf)))
        p2 = nodevalue(parent(parent(leaf))).node
        if JuliaSyntax.kind(p2) == K":"
            kids = JuliaSyntax.children(p2)
            if !isempty(kids)
                if first(kids) != p
                    # We aren't the first child, therefore we are on the RHS
                    return :import_RHS
                else
                    return :import_LHS
                end
            end
        end
    end
    # Not part of `:` generally means it's a `using X` or `import Y` situation
    is_import && return :blanket_import
    return :not_import
end

# Here we use the magic of AbstractTrees' `TreeCursor` so we can start at
# a leaf and follow the parents up to see what scopes our leaf is in.
function analyze_name(leaf; debug=false)
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

        debug && println(val, ": ", kind)
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

        # figure out if our name (`nodevalue(leaf)`) is the LHS of an assignment
        # Note: this doesn't detect assignments to qualified variables (`X.y = rhs`)
        # but that's OK since we don't want to pick them up anyway.
        if kind == K"="
            kids = children(nodevalue(node))
            if !isempty(kids)
                c = first(kids)
                is_assignment = c == nodevalue(leaf)
            end
        end

        node = parent(node)

        # finished climbing to the root
        node === nothing &&
            return (; global_scope, is_assignment, is_qualified, module_path, scope_path)
        idx += 1
    end
end

"""
    analyze_all_names(file) -> Tuple{DataFrame, DataFrame}

Returns:
* a DataFrame with one row per name per scope, with information about whether or not
it is within global scope, what modules it is in, and whether or not it was assigned before
ever being used in that scope.
* a DataFrame with one row per name per module path, consisting of names that have been explicitly imported in that module.
"""
function analyze_all_names(file; debug=false)
    tree = SyntaxNodeWrapper(file)
    # in local scope, a name refers to a global if it is read from before it is assigned to, OR if the global keyword is used
    # a name refers to a local otherwise
    # so we need to traverse the tree, keeping track of state like: which scope are we in, and for each name, in each scope, has it been used

    # Here we use a `TreeCursor`; this lets us iterate over the tree, while ensuring
    # we can call `parent` to climb up from a leaf.
    cursor = TreeCursor(tree)
    df = DataFrame()
    explicit_imports = DataFrame([:name => Symbol[], :location => String[],
                                  :import_type => Symbol[],
                                  :module_path => Vector{Symbol}[]])
    for leaf in Leaves(cursor)
        JuliaSyntax.kind(nodevalue(leaf).node) == K"Identifier" || continue
        # Ok, we have a "name". We want to know if:
        # 1. it is being used in global scope
        # or 2. it is being used in local scope, but refers to a global binding
        # To figure out the latter, we check if it has been assigned before it has been used.
        #
        # We want to figure this out on a per-module basis, since each module has a different global namespace.

        debug && println("-"^80)
        file = nodevalue(leaf).file
        line, col = JuliaSyntax.source_location(nodevalue(leaf).node)
        location = "$file:$line:$col"
        debug && println("Leaf position: $location")
        name = nodevalue(leaf).node.val
        debug && println("Leaf name: ", name)
        qualified = is_qualified(leaf)

        debug && qualified && println("$name's usage here is qualified; skipping")
        qualified && continue

        import_type = analyze_import_type(leaf)
        debug && println("Import type: ", import_type)
        debug && println("--")
        debug && println("val : kind")
        ret = analyze_name(leaf; debug)
        debug && println(ret)

        if import_type == :import_RHS
            push!(explicit_imports, (; name, location, import_type, ret.module_path))
        elseif import_type == :not_import
            push!(df, (; name, location, ret...))
        end
    end

    grps = groupby(df, [:name, :scope_path, :global_scope, :module_path])
    names = combine(grps, :is_assignment => (a -> a[1]) => :assigned_before_used)
    select!(explicit_imports, [:name, :module_path])
    unique!(explicit_imports)
    return names, explicit_imports
end

"""
    get_names_used(file) -> DataFrame

Figures out which global names are used in `file`, and what modules they are used within.

Traverses static `include` statements.

Returns a `DataFrame` with four columns:
* `name`: the name in question
* `module_path`: the path of modules to access the name, where the first module in the path is the innermost.
* `needs_explicit_import::Bool`
* `unnecessary_explicit_import::Bool`
"""
function get_names_used(file)
    # Here we get 1 row per name per scope
    df, explicit_imports = analyze_all_names(file)
    explicit_imports.explicitly_imported .= true

    # further processing...
    # we want one row per name per module path, not per scope,
    # so combine over scopes-within-a-module and decide if this name
    # is being used to refer to a global binding within this module
    ret = combine(groupby(df, [:name, :module_path]),
                  [:global_scope, :assigned_before_used] => function (g, a)
                      return any(g) || any(!, a)
                  end => :may_want_to_explicitly_import)

    ret = outerjoin(ret, explicit_imports; on=[:name, :module_path])
    ret.explicitly_imported = coalesce.(ret.explicitly_imported, false)
    ret.may_want_to_explicitly_import = coalesce.(ret.may_want_to_explicitly_import, false)

    select!(ret, :name, :module_path,
            [:may_want_to_explicitly_import, :explicitly_imported] => ByRow() do want, is
                needs_explicit_import = want && !is
                unnecessary_explicit_import = !want && is
                return (; needs_explicit_import, unnecessary_explicit_import)
            end => AsTable)

    subset!(ret, [:needs_explicit_import, :unnecessary_explicit_import] => ByRow(|))
    return ret
end
