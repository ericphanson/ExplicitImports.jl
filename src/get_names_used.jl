# In this file, we try to answer the question: what global bindings are being used in a particular module?
# We will do this by parsing, then re-implementing scoping rules on top of the parse tree.
# See `src/parse_utilities.jl` for an overview of the strategy and the utility functions we will use.

@enum AnalysisCode IgnoredNonFirst IgnoredQualified IgnoredImportRHS InternalHigherScope InternalFunctionArg InternalAssignment InternalStruct InternalForLoop InternalGenerator InternalCatchArgument External

Base.@kwdef struct PerUsageInfo
    name::Symbol
    qualified_by::Union{Nothing,Vector{Symbol}}
    import_type::Symbol
    explicitly_imported_by::Union{Nothing,Vector{Symbol}}
    location::String
    function_arg::Bool
    is_assignment::Bool
    module_path::Vector{Symbol}
    scope_path::Vector{JuliaSyntax.SyntaxNode}
    struct_field_or_type_param::Bool
    for_loop_index::Bool
    generator_index::Bool
    catch_arg::Bool
    first_usage_in_scope::Bool
    external_global_name::Union{Missing,Bool}
    analysis_code::AnalysisCode
end

function Base.NamedTuple(r::PerUsageInfo)
    names = fieldnames(typeof(r))
    return NamedTuple{names}(map(x -> getfield(r, x), names))
end

"""
    FileAnalysis

Contains structured analysis results.

## Fields

-  per_usage_info::Vector{PerUsageInfo}
- `needs_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},
    location::String}}`
- `unnecessary_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},
          location::String}}`
- `untainted_modules::Set{Vector{Symbol}}`: those which were analyzed and do not contain an unanalyzable `include`
"""
Base.@kwdef struct FileAnalysis
    per_usage_info::Vector{PerUsageInfo}
    needs_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},
                                           location::String}}
    unnecessary_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},
                                                 location::String}}
    untainted_modules::Set{Vector{Symbol}}
end

# returns `nothing` for no qualifying module, otherwise a symbol
function qualifying_module(leaf)
    # is this name being used in a qualified context, like `X.y`?
    parents_match(leaf, (K"quote", K".")) || return nothing
    # Are we on the right-hand side?
    child_index(parent(leaf)) == 2 || return nothing
    # Ok, now try to retrieve the child on the left-side
    node = first(AbstractTrees.children(get_parent(leaf, 2)))
    path = Symbol[]
    retrieve_module_path!(path, node)
    return path
end

function retrieve_module_path!(path, node)
    kids = AbstractTrees.children(node)
    if kind(node) == K"Identifier"
        push!(path, get_val(node))
    elseif kind(node) == K"."
        k1, k2 = kids
        if kind(k1) === K"Identifier"
            push!(path, get_val(k1))
        end
        return retrieve_module_path!(path, k2)
    elseif kind(node) == K"quote"
        return retrieve_module_path!(path, first(kids))
    end
    return path
end

# figure out if `leaf` is part of an import or using statement
# this seems to trigger for both `X` and `y` in `using X: y`, but that seems alright.
function analyze_import_type(leaf)
    kind(leaf) == K"Identifier" || return :not_import
    has_parent(leaf) || return :not_import
    is_import = parents_match(leaf, (K"importpath",))
    is_import || return :not_import
    if parents_match(leaf, (K"importpath", K":"))
        # we are on the LHS if we are the first child
        if child_index(parent(leaf)) == 1
            return :import_LHS
        else
            return :import_RHS
        end
    elseif parents_match(leaf, (K"importpath", K"as", K":"))
        # this name is either part of an `import X: a as b` statement
        # since we are in an `importpath`, we are the `a` part, not the `b` part, I think
        # do we also want to identify the `b` part as an `import_RHS`?
        # For the purposes of stale explicit imports, we want to know about `b`,
        # since if `b` is unused then it is stale.
        # For the purposes of not suggesting an explicit import that already exists,
        # it is weird since they have renamed it here, so if they are referring to
        # both names in their code (`a` and `b`), that's kind of a different confusing
        # issue.
        # For the purposes of "are they importing a non-public name", we care more about
        # `a`, since that's the name we need to check if it is public or not in the source
        # module (although we could check if `b` is public in the module sourced via `which`?).
        # hm..
        # let's just leave it; for now `b` will be declared `:not_import`
        return :import_RHS
    else
        # Not part of `:` generally means it's a `using X` or `import Y` situation
        # We could be using X.Y.Z, so we will return `plain_import` or `plain_import_member` depending if we are the last one or not
        n_children = length(js_children(parent(leaf)))
        last_child = child_index(leaf) == n_children
        if parents_match(leaf, (K"importpath", K"using"))
            return last_child ? :plain_import : :plain_import_member
        elseif parents_match(leaf, (K"importpath", K"import"))
            return last_child ? :blanket_using : :blanket_using_member
        elseif parents_match(leaf, (K"importpath", K"as", K"import"))
            # import X as Y
            # Here we are `X`, not `Y`
            return last_child ? :plain_import : :plain_import_member
        else
            error("Unhandled case $(js_node(get_parent(leaf, 3)))")
        end
    end
end

function is_function_definition_arg(leaf)
    return is_anonymous_function_definition_arg(leaf) ||
           is_non_anonymous_function_definition_arg(leaf) ||
           is_anonymous_do_function_definition_arg(leaf)
end

function is_anonymous_do_function_definition_arg(leaf)
    if !has_parent(leaf, 2)
        return false
    elseif parents_match(leaf, (K"tuple", K"do"))
        # second argument of `do`-block
        return child_index(parent(leaf)) == 2
    elseif kind(parent(leaf)) in (K"tuple", K"parameters")
        # Ok, let's just step up one level and see again
        return is_anonymous_do_function_definition_arg(parent(leaf))
    else
        return false
    end
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

function get_import_lhs(import_rhs_leaf)
    if parents_match(import_rhs_leaf, (K"importpath", K":"))
        n = first(children(get_parent(import_rhs_leaf, 2)))
        @assert kind(n) == K"importpath"
        return get_val.(children(n))
    elseif parents_match(import_rhs_leaf, (K"importpath", K"as", K":"))
        n = first(children(get_parent(import_rhs_leaf, 3)))
        @assert kind(n) == K"importpath"
        return get_val.(children(n))
    else
        error("does not seem to be an import RHS")
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

# In the future, this may need an update for
# https://github.com/JuliaLang/JuliaSyntax.jl/issues/432
function in_for_argument_position(node)
    # We must be on the LHS of a `for` `equal`.
    if !has_parent(node, 2)
        return false
    elseif parents_match(node, (K"=", K"for"))
        return child_index(node) == 1
    elseif parents_match(node, (K"=", K"cartesian_iterator", K"for"))
        return child_index(node) == 1
    elseif kind(parent(node)) in (K"tuple", K"parameters")
        return in_for_argument_position(get_parent(node))
    else
        return false
    end
end

function is_for_arg(leaf)
    kind(leaf) == K"Identifier" || return false
    return in_for_argument_position(leaf)
end

function is_generator_arg(leaf)
    kind(leaf) == K"Identifier" || return false
    return in_generator_arg_position(leaf)
end

function in_generator_arg_position(node)
    # We must be on the LHS of a `=` inside a generator
    # (possibly inside a filter, possibly inside a `cartesian_iterator`)
    if !has_parent(node, 2)
        return false
    elseif parents_match(node, (K"=", K"generator")) ||
           parents_match(node, (K"=", K"cartesian_iterator", K"generator")) ||
           parents_match(node, (K"=", K"filter")) ||
           parents_match(node, (K"=", K"cartesian_iterator", K"filter"))
        return child_index(node) == 1
    elseif kind(parent(node)) in (K"tuple", K"parameters")
        return in_generator_arg_position(get_parent(node))
    else
        return false
    end
end

function is_catch_arg(leaf)
    kind(leaf) == K"Identifier" || return false
    return in_catch_arg_position(leaf)
end

function in_catch_arg_position(node)
    # We must be the first argument of a `catch` block
    if !has_parent(node)
        return false
    elseif parents_match(node, (K"catch",))
        return child_index(node) == 1
    else
        # catch doesn't support destructuring, type annotations, etc, so we're done!
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
# TODO-someday- cleanup. This basically has two jobs: check is function arg etc, and figure out the scope/module path.
# We could do these two things separately for more clarity.
function analyze_name(leaf; debug=false)
    # Ok, we have a "name". Let us work our way up and try to figure out if it is in local scope or not
    function_arg = is_function_definition_arg(leaf)
    struct_field_or_type_param = is_struct_type_param(leaf) || is_struct_field_name(leaf)
    for_loop_index = is_for_arg(leaf)
    generator_index = is_generator_arg(leaf)
    catch_arg = is_catch_arg(leaf)
    module_path = Symbol[]
    scope_path = JuliaSyntax.SyntaxNode[]
    is_assignment = false
    node = leaf
    idx = 1

    prev_node = nothing
    while true
        # update our state
        val = get_val(node)
        k = kind(node)
        args = nodevalue(node).node.raw.args

        debug && println(val, ": ", k)
        # Constructs that start a new local scope. Note `let` & `macro` *arguments* are not explicitly supported/tested yet,
        # but we can at least keep track of scope properly.
        if k in
           (K"let", K"for", K"function", K"struct", K"generator", K"while", K"macro") ||
           # Or do-block when we are considering a path that did not go through the first-arg
           # (which is the function name, and NOT part of the local scope)
           (k == K"do" && child_index(prev_node) > 1) ||
           # any child of `try` gets it's own individual scope (I think)
           (parents_match(node, (K"try",)))
            push!(scope_path, nodevalue(node).node)
            # try to detect presence in RHS of inline function definition
        elseif idx > 3 && k == K"=" && !isempty(args) &&
               kind(first(args)) == K"call"
            push!(scope_path, nodevalue(node).node)
        end

        # track which modules we are in
        if k == K"module" # baremodules?
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
                is_assignment |= c == nodevalue(leaf)
            end
        end

        prev_node = node
        node = parent(node)

        # finished climbing to the root
        node === nothing &&
            return (; function_arg, is_assignment, module_path, scope_path,
                    struct_field_or_type_param, for_loop_index, generator_index, catch_arg)
        idx += 1
    end
end

"""
    analyze_all_names(file)

Returns a tuple of two items:

* `per_usage_info`: a table containing information about each name each time it was used
* `untainted_modules`: a set containing modules found and analyzed successfully
"""
function analyze_all_names(file)
    # we don't use `try_parse_wrapper` here, since there's no recovery possible
    # (no other files we know about to look at)
    tree = SyntaxNodeWrapper(file)
    # in local scope, a name refers to a global if it is read from before it is assigned to, OR if the global keyword is used
    # a name refers to a local otherwise
    # so we need to traverse the tree, keeping track of state like: which scope are we in, and for each name, in each scope, has it been used

    # Here we use a `TreeCursor`; this lets us iterate over the tree, while ensuring
    # we can call `parent` to climb up from a leaf.
    cursor = TreeCursor(tree)

    per_usage_info = @NamedTuple{name::Symbol,
                                 qualified_by::Union{Nothing,Vector{Symbol}},
                                 import_type::Symbol,
                                 explicitly_imported_by::Union{Nothing,Vector{Symbol}},
                                 location::String,
                                 function_arg::Bool,
                                 is_assignment::Bool,
                                 module_path::Vector{Symbol},
                                 scope_path::Vector{JuliaSyntax.SyntaxNode},
                                 struct_field_or_type_param::Bool,
                                 for_loop_index::Bool,
                                 generator_index::Bool,
                                 catch_arg::Bool}[]

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
            mod_path = analyze_name(parent(leaf)).module_path
            push!(tainted_modules, mod_path)
            continue
        end

        # if we don't find any identifiers (or macro names) in a module, I think it's OK to mark it as
        # "not-seen"? Otherwise we need to analyze every leaf, not just the identifiers
        # and that sounds slow. Seems like a very rare edge case to have no identifiers...
        kind(leaf) in (K"Identifier", K"MacroName", K"StringMacroName") || continue

        # Skip quoted identifiers
        # This won't necessarily catch if they are part of a big quoted block,
        # but it will at least catch symbols (however keep qualified names)
        parents_match(leaf, (K"quote",)) && !parents_match(leaf, (K"quote", K".")) &&
            continue

        # Ok, we have a "name". We want to know if:
        # 1. it is being used in global scope
        # or 2. it is being used in local scope, but refers to a global binding
        # To figure out the latter, we check if it has been assigned before it has been used.
        #
        # We want to figure this out on a per-module basis, since each module has a different global namespace.

        location = location_str(nodevalue(leaf))
        name = get_val(leaf)
        qualified_by = qualifying_module(leaf)
        import_type = analyze_import_type(leaf)
        if import_type == :import_RHS
            explicitly_imported_by = get_import_lhs(leaf)
        else
            explicitly_imported_by = nothing
        end
        ret = analyze_name(leaf)
        push!(seen_modules, ret.module_path)
        push!(per_usage_info,
              (; name, qualified_by, import_type, explicitly_imported_by, location, ret...))
    end
    untainted_modules = setdiff!(seen_modules, tainted_modules)
    return analyze_per_usage_info(per_usage_info), untainted_modules
end

function is_name_internal_in_higher_local_scope(name, scope_path, seen)
    # We will recurse up the `scope_path`. Note the order is "reversed",
    # so the first entry of `scope_path` is deepest.

    while !isempty(scope_path)
        # First, if we are directly in a module, then we don't want to recurse further.
        # We will just end up in a different module.
        if kind(first(scope_path)) == K"module"
            return false
        end
        # Ok, now pop off the first scope and check.
        scope_path = scope_path[2:end]
        ret = get(seen, (; name, scope_path), nothing)
        if ret === nothing
            # Not introduced here yet, trying recursing further
            continue
        else
            # return value is `is_global`, so negate it
            return !ret
        end
    end
    # Did not find a local introduction
    return false
end

function analyze_per_usage_info(per_usage_info)
    # For each scope, we want to understand if there are any global usages of the name in that scope
    # First, throw away all qualified usages, they are irrelevant
    # Next, if a name is on the RHS of an import, we don't care, so throw away
    # Next, if the name is beign used at global scope, obviously it is a global
    # Otherwise, we are in local scope:
    #   1. Next, if the name is a function arg, then this is not a global name (essentially first usage is assignment)
    #   2. Otherwise, if first usage is assignment, then it is local, otherwise it is global
    seen = Dict{@NamedTuple{name::Symbol,scope_path::Vector{JuliaSyntax.SyntaxNode}},Bool}()
    return map(per_usage_info) do nt
        @compat if (; nt.name, nt.scope_path) in keys(seen)
            return PerUsageInfo(; nt..., first_usage_in_scope=false,
                                external_global_name=missing,
                                analysis_code=IgnoredNonFirst)
        end
        if nt.qualified_by !== nothing
            return PerUsageInfo(; nt..., first_usage_in_scope=true,
                                external_global_name=missing,
                                analysis_code=IgnoredQualified)
        end
        if nt.import_type == :import_RHS
            return PerUsageInfo(; nt..., first_usage_in_scope=true,
                                external_global_name=missing,
                                analysis_code=IgnoredImportRHS)
        end

        # At this point, we have an unqualified name, which is not the RHS of an import, and it is the first time we have seen this name in this scope.
        # Is it global or local?
        # We will check a bunch of things:
        # * this name could be local due to syntax: due to it being a function argument, LHS of an assignment, a struct field or type param, or due to a loop index.
        for (is_local, reason) in
            ((nt.function_arg, InternalFunctionArg),
             (nt.struct_field_or_type_param, InternalStruct),
             (nt.for_loop_index, InternalForLoop),
             (nt.generator_index, InternalGenerator),
             (nt.catch_arg, InternalCatchArgument),
             # We check this last, since it is less specific
             # than e.g. `InternalForLoop` but can trigger in
             # some of the same cases
             (nt.is_assignment, InternalAssignment))
            if is_local
                external_global_name = false
                push!(seen, (; nt.name, nt.scope_path) => external_global_name)
                return PerUsageInfo(; nt..., first_usage_in_scope=true,
                                    external_global_name,
                                    analysis_code=reason)
            end
        end
        # * this was the first usage in this scope, but it could already be used in a "higher" local scope. It is possible we have not yet processed that scope fully but we will assume we have (TODO-someday). So we will recurse up and check if it is a local name there.
        if is_name_internal_in_higher_local_scope(nt.name,
                                                  nt.scope_path,
                                                  seen)
            external_global_name = false
            push!(seen, (; nt.name, nt.scope_path) => external_global_name)
            return PerUsageInfo(; nt..., first_usage_in_scope=true, external_global_name,
                                analysis_code=InternalHigherScope)
        end

        external_global_name = true
        push!(seen, (; nt.name, nt.scope_path) => external_global_name)
        return PerUsageInfo(; nt..., first_usage_in_scope=true, external_global_name,
                            analysis_code=External)
    end
end

function get_global_names(per_usage_info)
    names_used_for_global_bindings = Set{@NamedTuple{name::Symbol,
                                                     module_path::Vector{Symbol},
                                                     location::String}}()

    for nt in per_usage_info
        if nt.external_global_name === true
            push!(names_used_for_global_bindings, (; nt.name, nt.module_path, nt.location))
        end
    end
    return names_used_for_global_bindings
end

function get_explicit_imports(per_usage_info)
    explicit_imports = Set{@NamedTuple{name::Symbol,
                                       module_path::Vector{Symbol},
                                       location::String}}()
    for nt in per_usage_info
        # skip qualified names
        (nt.qualified_by === nothing) || continue
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

Returns a `FileAnalysis` object.
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

    return FileAnalysis(; per_usage_info, needs_explicit_import,
                        unnecessary_explicit_import,
                        untainted_modules)
end
