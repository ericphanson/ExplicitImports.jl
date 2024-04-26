# In this file, we try to answer the question: what global bindings are being used in a particular module?
# We will do this by parsing, then re-implementing scoping rules on top of the parse tree.
# See `src/parse_utilities.jl` for an overview of the strategy and the utility functions we will use.

Base.@kwdef struct FileAnalysis
    needs_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},
                                           location::String}}
    unnecessary_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},
                                                 location::String}}
    untainted_modules::Set{Vector{Symbol}}
end

function is_qualified(leaf)
    # is this name being used in a qualified context, like `X.y`?
    parents_match(leaf, (K"quote", K".")) || return false
    return child_index(parent(leaf)) == 2
end

# figure out if `leaf` is part of an import or using statement
# this seems to trigger for both `X` and `y` in `using X: y`, but that seems alright.
function analyze_import_type(leaf)
    is_import = parents_match(leaf, (K"importpath",))
    is_import || return :not_import
    is_conditional_import = parents_match(leaf, (K"importpath", K":"))
    if is_conditional_import
        # we are on the LHS if we are the first child
        if child_index(parent(leaf)) == 1
            return :import_LHS
        else
            return :import_RHS
        end
    else
        # Not part of `:` generally means it's a `using X` or `import Y` situation
        return :blanket_import
    end
end

function is_function_definition_arg(leaf)
    return is_anonymous_function_definition_arg(leaf) ||
           is_non_anonymous_function_definition_arg(leaf)
end

function is_anonymous_function_definition_arg(leaf)
    if parents_match(leaf, (K"->",))
        # lhs of a `->`
        return child_index(leaf) == 1
    elseif parents_match(leaf, (K"tuple", K"->"))
        # lhs of a multi-argument `->`
        return child_index(parent(leaf)) == 1
    elseif parents_match(leaf, (K"parameters", K"tuple", K"->"))
        return child_index(get_parent(leaf, 2)) == 1
    elseif parents_match(leaf, (K"function", K"="))
        # `function` is RHS of `=`
        return child_index(parent(leaf)) == 2
    elseif parents_match(leaf, (K"tuple", K"function", K"="))
        # `function` is RHS of `=`
        return child_index(get_parent(leaf, 2)) == 2
    elseif parents_match(leaf, (K"parameters", K"tuple", K"function", K"="))
        # `function` is RHS of `=`
        return child_index(get_parent(leaf, 3)) == 2
    elseif parents_match(leaf, (K"::",))
        # we must be on the LHS, otherwise we're a type
        is_double_colon_LHS(leaf) || return false
        # Ok, let's just step up one level and see again
        return is_anonymous_function_definition_arg(parent(leaf))
    elseif parents_match(leaf, (K"=",))
        # we must be on the LHS, otherwise we're a default value
        child_index(leaf) == 1 || return false
        # Ok, let's just step up one level and see again
        return is_anonymous_function_definition_arg(parent(leaf))
    else
        return false
    end
end

# given a `call`-kind node, is it a function invocation or a function definition?
function call_is_func_def(node)
    kind(node) == K"call" || error("Not a call")
    p = parent(node)
    p === nothing && return false
    # note: macros only support full-form function definitions
    # (not inline)
    kind(p) in (K"function", K"macro") && return true
    if kind(p) == K"="
        # call should be the first arg in an inline function def
        return child_index(node) == 1
    end
    return false
end

function is_struct_field_name(leaf)
    kind(leaf) == K"Identifier" || return false
    if parents_match(leaf, (K"::", K"block", K"struct"))
        # we want to be on the LHS of the `::`
        return is_double_colon_LHS(leaf)
    elseif parents_match(leaf, (K"::", K"=", K"block", K"struct"))
        # if we are in a `Base.@kwdef`, we may be on the LHS of an `=`
        return is_double_colon_LHS(leaf) && child_index(parent(leaf)) == 1
    else
        return false
    end
end

function is_struct_type_param(leaf)
    kind(leaf) == K"Identifier" || return false
    if parents_match(leaf, (K"curly", K"struct"))
        # Here we want the non-first argument of `curly`
        return child_index(leaf) > 1
    elseif parents_match(leaf, (K"<:", K"curly", K"struct"))
        # Here we only want the LHS of the <:, AND the not-first argument of curly
        return child_index(leaf) == 1 && child_index(get_parent(leaf)) > 1
    else
        return false
    end
end

function in_for_argument_position(node)
    # We must be on the LHS of a `for` `equal`.
    if !has_parent(node, 2)
        return false
    elseif parents_match(node, (K"=", K"for"))
        return child_index(node) == 1
    else
        return in_for_argument_position(get_parent(node))
    end
end

function is_for_arg(leaf)
    kind(leaf) == K"Identifier" || return false
    return in_for_argument_position(leaf)
end

# check if `leaf` is a function argument (or kwarg), but not a default value etc,
# which is part of a function definition (not just any function call)
function is_non_anonymous_function_definition_arg(leaf)
    # a call who is a child of `function` or `=` is a function def
    # (I think!)
    if parents_match(leaf, (K"call",)) && call_is_func_def(parent(leaf))
        # We are a function arg if we're a child of `call` who is not the function name itself
        return child_index(leaf) != 1
    elseif parents_match(leaf, (K"parameters", K"call")) &&
           call_is_func_def(get_parent(leaf, 2))
        # we're a kwarg without default value in a call
        return true
    elseif parents_match(leaf, (K"=",))
        # we must be on the LHS, otherwise we aren't a function arg
        child_index(leaf) == 1 || return false
        # Ok, let's just step up one level and see again
        return is_non_anonymous_function_definition_arg(parent(leaf))
    elseif parents_match(leaf, (K"::",))
        # we must be on the LHS, otherwise we're a type
        is_double_colon_LHS(leaf) || return false
        # Ok, let's just step up one level and see again
        return is_non_anonymous_function_definition_arg(parent(leaf))
    else
        return false
    end
end

# matches `x` in `x::Y`, but not `Y`, nor `foo(::Y)`
function is_double_colon_LHS(leaf)
    parents_match(leaf, (K"::",)) || return false
    unary = has_flags(get_parent(leaf), JuliaSyntax.PREFIX_OP_FLAG)
    unary && return false
    # OK if not unary, then check we're in position 1 for LHS
    return child_index(leaf) == 1
end

# Here we use the magic of AbstractTrees' `TreeCursor` so we can start at
# a leaf and follow the parents up to see what scopes our leaf is in.
# TODO- cleanup with parsing utilities (?)
function analyze_name(leaf; debug=false)
    # Ok, we have a "name". Let us work our way up and try to figure out if it is in local scope or not
    function_arg = is_function_definition_arg(leaf)
    struct_field_or_type_param = is_struct_type_param(leaf) || is_struct_field_name(leaf)
    for_loop_index = is_for_arg(leaf)
    global_scope = !function_arg && !struct_field_or_type_param && !for_loop_index
    module_path = Symbol[]
    scope_path = JuliaSyntax.SyntaxNode[]
    is_assignment = false
    node = leaf
    idx = 1

    while true
        # update our state
        val = get_val(node)
        k = kind(node)
        args = nodevalue(node).node.raw.args

        debug && println(val, ": ", k)
        if k in (K"let", K"for", K"function", K"struct")
            global_scope = false
            push!(scope_path, nodevalue(node).node)
            # try to detect presence in RHS of inline function definition
        elseif idx > 3 && k == K"=" && !isempty(args) &&
               kind(first(args)) == K"call"
            global_scope = false
            push!(scope_path, nodevalue(node).node)
        end

        # track which modules we are in
        if k == K"module"
            ids = filter(children(nodevalue(node))) do arg
                return kind(arg.node) == K"Identifier"
            end
            if !isempty(ids)
                push!(module_path, first(ids).node.val)
            end
            push!(scope_path, nodevalue(node).node)
        end

        # figure out if our name (`nodevalue(leaf)`) is the LHS of an assignment
        # Note: this doesn't detect assignments to qualified variables (`X.y = rhs`)
        # but that's OK since we don't want to pick them up anyway.
        if k == K"="
            kids = children(nodevalue(node))
            if !isempty(kids)
                c = first(kids)
                is_assignment = c == nodevalue(leaf)
            end
        end

        node = parent(node)

        # finished climbing to the root
        node === nothing &&
            return (; function_arg, global_scope, is_assignment, module_path, scope_path,
                    struct_field_or_type_param, for_loop_index)
        idx += 1
    end
end

"""
    analyze_all_names(file)

Returns a tuple of two items:

* `per_usage_info`: a table containing information about each name each time it was used
* `untainted_modules`: a set containing modules found and analyzed successfully
"""
function analyze_all_names(file; debug=false)
    # we don't use `try_parse_wrapper` here, since there's no recovery possible
    # (no other files we know about to look at)
    tree = SyntaxNodeWrapper(file)
    # in local scope, a name refers to a global if it is read from before it is assigned to, OR if the global keyword is used
    # a name refers to a local otherwise
    # so we need to traverse the tree, keeping track of state like: which scope are we in, and for each name, in each scope, has it been used

    # Here we use a `TreeCursor`; this lets us iterate over the tree, while ensuring
    # we can call `parent` to climb up from a leaf.
    cursor = TreeCursor(tree)

    per_usage_info = @NamedTuple{name::Symbol,qualified::Bool,import_type::Symbol,
                                 location::String,
                                 function_arg::Bool,global_scope::Bool,is_assignment::Bool,
                                 module_path::Vector{Symbol},
                                 scope_path::Vector{JuliaSyntax.SyntaxNode},
                                 struct_field_or_type_param::Bool,for_loop_index::Bool}[]

    # we need to keep track of all names that we see, because we could
    # miss entire modules if it is an `include` we cannot follow.
    # Therefore, the "untainted" modules will be all the seen ones
    # minus all the explicitly tainted ones, and those will be the ones
    # safe to analyze.
    seen_modules = Set{Vector{Symbol}}()
    tainted_modules = Set{Vector{Symbol}}()

    for leaf in Leaves(cursor)
        if nodevalue(leaf) isa SkippedFile
            # we start from the parent
            mod_path = analyze_name(parent(leaf); debug).module_path
            push!(tainted_modules, mod_path)
            continue
        end

        # if we don't find any identifiers (or macro names) in a module, I think it's OK to mark it as
        # "not-seen"? Otherwise we need to analyze every leaf, not just the identifiers
        # and that sounds slow. Seems like a very rare edge case to have no identifiers...
        kind(leaf) in (K"Identifier", K"MacroName", K"StringMacroName") || continue

        # Skip quoted identifiers
        # This won't necessarily catch if they are part of a big quoted block,
        # but it will at least catch symbols
        parents_match(leaf, (K"quote",)) && continue

        # Ok, we have a "name". We want to know if:
        # 1. it is being used in global scope
        # or 2. it is being used in local scope, but refers to a global binding
        # To figure out the latter, we check if it has been assigned before it has been used.
        #
        # We want to figure this out on a per-module basis, since each module has a different global namespace.

        debug && println("-"^80)
        location = location_str(nodevalue(leaf))
        debug && println("Leaf position: $(location)")
        name = get_val(leaf)
        debug && println("Leaf name: ", name)
        qualified = is_qualified(leaf)
        import_type = analyze_import_type(leaf)
        debug && println("Import type: ", import_type)
        debug && println("--")
        debug && println("val : kind")
        ret = analyze_name(leaf; debug)
        debug && println(ret)
        push!(seen_modules, ret.module_path)
        push!(per_usage_info,
              (; name, qualified, import_type, location, ret...,))
    end
    untainted_modules = setdiff!(seen_modules, tainted_modules)
    return per_usage_info, untainted_modules
end

function get_global_names(per_usage_info)
    # For each scope, we want to understand if there are any global usages of the name in that scope
    # First, throw away all qualified usages, they are irrelevant
    # Next, if a name is on the RHS of an import, we don't care, so throw away
    # Next, if the name is beign used at global scope, obviously it is a global
    # Otherwise, we are in local scope:
    #   1. Next, if the name is a function arg, then this is not a global name (essentially first usage is assignment)
    #   2. Otherwise, if first usage is assignment, then it is local, otherwise it is global

    names_used_for_global_bindings = Set{@NamedTuple{name::Symbol,
                                                     module_path::Vector{Symbol},
                                                     location::String}}()
    seen = Dict{@NamedTuple{name::Symbol,scope_path::Vector{JuliaSyntax.SyntaxNode}},Bool}()

    for nt in per_usage_info
        (; nt.name, nt.scope_path) in keys(seen) && continue
        nt.qualified && continue
        nt.import_type == :import_RHS && continue

        # Ok, at this point it counts!
        push!(seen, (; nt.name, nt.scope_path) => nt.global_scope)

        if nt.global_scope
            push!(names_used_for_global_bindings, (; nt.name, nt.module_path, nt.location))
        else
            # we are in local scope.
            # If we were e.g. an assignment in a higher local scope though, it could still be a local name, as opposed to a global one.
            # We will recurse up the `scope_path`. Note the order is "reversed",
            # so the first entry of `scope_path` is deepest.
            scope_path = nt.scope_path
            while !isempty(scope_path)
                # First, if we are directly in a module, then we don't want to recurse further.
                # We will just end up in a different module.
                if kind(first(scope_path)) == K"module"
                    @goto inner
                end
                # Ok, now pop off the first scope and check.
                scope_path = scope_path[2:end]
                ret = get(seen, (; nt.name, scope_path), nothing)
                if ret === false # local usage found earlier
                    @goto outer
                elseif ret === true
                    # We hit global scope, time to bail
                    @goto inner
                end
                # else, continue recursing
            end
            @label inner
            if !(nt.function_arg || nt.is_assignment || nt.struct_field_or_type_param || nt.for_loop_index)
                push!(names_used_for_global_bindings,
                      (; nt.name, nt.module_path, nt.location))
            end
        end
        @label outer
    end
    return names_used_for_global_bindings
end

function get_explicit_imports(per_usage_info)
    explicit_imports = Set{@NamedTuple{name::Symbol,
                                       module_path::Vector{Symbol},
                                       location::String}}()
    for nt in per_usage_info
        nt.qualified && continue
        if nt.import_type == :import_RHS
            push!(explicit_imports, (; nt.name, nt.module_path, nt.location))
        end
    end
    return explicit_imports
end

drop_metadata(nt) = (; nt.name, nt.module_path)
function setdiff_no_metadata(set1, set2)
    remove = Set(drop_metadata(nt) for nt in set2)
    return Set(nt for nt in set1 if drop_metadata(nt) ∉ remove)
end

"""
    get_names_used(file) -> FileAnalysis

Figures out which global names are used in `file`, and what modules they are used within.

Traverses static `include` statements.

Returns two `Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol}}}`, namely

* `needs_explicit_import`
* `unnecessary_explicit_import`

and a `Set{Vector{Symbol}}` of "untainted module paths", i.e. those which were analyzed and do not contain an unanalyzable `include`:

* `untainted_modules`
"""
function get_names_used(file)
    check_file(file)
    # Here we get 1 row per name per usage
    per_usage_info, untainted_modules = analyze_all_names(file)

    names_used_for_global_bindings = get_global_names(per_usage_info)
    explicit_imports = get_explicit_imports(per_usage_info)

    # name used to point to a global which was not explicitly imported
    needs_explicit_import = setdiff_no_metadata(names_used_for_global_bindings,
                                                explicit_imports)
    unnecessary_explicit_import = setdiff_no_metadata(explicit_imports,
                                                      names_used_for_global_bindings)

    return FileAnalysis(; needs_explicit_import, unnecessary_explicit_import,
                        untainted_modules)
end
