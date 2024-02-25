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
            f, arg = children::Vector{JuliaSyntax.SyntaxNode} # make JET happy
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
            return (; global_scope, is_assignment, module_path, scope_path)
        idx += 1
    end
end

"""
    analyze_all_names(file)

Returns a tuple of two tables:

* a table with one row per name per scope, with information about whether or not it is within global scope, what modules it is in, and whether or not it was assigned before ever being used in that scope.
* a table with one row per name per module path, consisting of names that have been explicitly imported in that module.
"""
function analyze_all_names(file; debug=false)
    tree = SyntaxNodeWrapper(file)
    # in local scope, a name refers to a global if it is read from before it is assigned to, OR if the global keyword is used
    # a name refers to a local otherwise
    # so we need to traverse the tree, keeping track of state like: which scope are we in, and for each name, in each scope, has it been used

    # Here we use a `TreeCursor`; this lets us iterate over the tree, while ensuring
    # we can call `parent` to climb up from a leaf.
    cursor = TreeCursor(tree)
    per_scope_info = @NamedTuple{name::Symbol,global_scope::Bool,assigned_first::Bool,
                                 module_path::Vector{Symbol},
                                 scope_path::Vector{JuliaSyntax.SyntaxNode}}[]

    # We actually only care about the first instance of a name in any given scope,
    # since that tells us about assignment
    seen = Set{@NamedTuple{name::Symbol,scope_path::Vector{JuliaSyntax.SyntaxNode}}}()

    explicit_imports = Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol}}}()

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
            push!(explicit_imports, (; name, ret.module_path))
        elseif import_type == :not_import
            # Only add it the first time
            if (; name, ret.scope_path) ∉ seen
                push!(per_scope_info,
                      (; name, ret.global_scope, assigned_first=ret.is_assignment,
                       ret.module_path, ret.scope_path))
                push!(seen, (; name, ret.scope_path))
            end
        end
    end

    return per_scope_info, explicit_imports
end

"""
    get_names_used(file) -> DataFrame

Figures out which global names are used in `file`, and what modules they are used within.

Traverses static `include` statements.

Returns two `Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol}}}`, namely

* `needs_explicit_import`
* `unnecessary_explicit_import`
"""
function get_names_used(file)
    # Here we get 1 row per name per scope
    per_scope_info, explicit_imports = analyze_all_names(file)

    # if a name is used to refer to a global in any scope within a module,
    # then we may want to explicitly import it.
    # So we iterate through our scopes and see.
    names_used_for_global_bindings = Set{@NamedTuple{name::Symbol,
                                                     module_path::Vector{Symbol}}}()
    for nt in per_scope_info
        if nt.global_scope || !nt.assigned_first
            push!(names_used_for_global_bindings, (; nt.name, nt.module_path))
        end
    end
    # name used to point to a global which was not explicitly imported
    needs_explicit_import = setdiff(names_used_for_global_bindings, explicit_imports)
    unnecessary_explicit_import = setdiff(explicit_imports, names_used_for_global_bindings)
    return (; needs_explicit_import, unnecessary_explicit_import)
end
