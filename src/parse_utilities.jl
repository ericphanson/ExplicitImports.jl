# Since we mostly care about identifiers, our parsing strategy will be:
# 1. Parse into `SyntaxNode` with JuliaSyntax
# 2. use an `AbstractTrees.TreeCursor` so we can navigate up (i.e. from leaf to root), not just down, the parse tree
# 3. Use `AbstractTrees.Leaves` to find all the leaves (which is where the identifiers are)
# 4. Find the identifiers, then traverse up (via `AbstractTrees.parent`) to check what is true about the identifier
#    such as if it's a local variable, function argument, if it is qualified, etc.

# We define a new tree that wraps a `SyntaxNode`.
# For this tree, we we add an `AbstractTrees` `children` method to traverse `include` statements to span our tree across files.
struct SyntaxNodeWrapper
    node::JuliaSyntax.SyntaxNode
    file::String
    bad_locations::Set{String}
end

function SyntaxNodeWrapper(file::AbstractString; bad_locations=Set{String}())
    contents = read(file, String)
    parsed = JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, contents; ignore_warnings=true)
    return SyntaxNodeWrapper(parsed, file, bad_locations)
end

function try_parse_wrapper(file::AbstractString; bad_locations)
    return try
        SyntaxNodeWrapper(file; bad_locations)
    catch e
        msg = "Error when parsing file. Skipping this file."
        @error msg file exception = (e, catch_backtrace())
        nothing
    end
end

# string representation of the location of the node
# this prints in a format where if it shows up in the VSCode terminal, you can click it
# to jump to the file
function location_str(wrapper::SyntaxNodeWrapper)
    line, col = JuliaSyntax.source_location(wrapper.node)
    return "$(wrapper.file):$line:$col"
end

struct SkippedFile
    # location of the file being skipped
    # (we don't include the file itself, since we may not know what it is)
    location::Union{String}
end

AbstractTrees.children(::SkippedFile) = ()

# Here we define children such that if we get to a static `include`, we just recurse
# into the parse tree of that file.
# This function has become increasingly horrible in the name of robustness
function AbstractTrees.children(wrapper::SyntaxNodeWrapper)
    node = wrapper.node
    if JuliaSyntax.kind(node) == K"call"
        children = JuliaSyntax.children(node)
        if length(children) == 2
            f, arg = children::Vector{JuliaSyntax.SyntaxNode} # make JET happy
            if f.val === :include
                location = location_str(wrapper)
                if location in wrapper.bad_locations
                    return [SkippedFile(location)]
                end
                if JuliaSyntax.kind(arg) == K"string"
                    children = JuliaSyntax.children(arg)
                    # if we have interpolation, there may be >1 child
                    length(children) == 1 || @goto dynamic
                    c = only(children)
                    # if we have interpolation, this might not be a string
                    kind(c) == K"String" || @goto dynamic
                    # The children of a static include statement is the entire file being included
                    new_file = joinpath(dirname(wrapper.file), c.val)
                    if isfile(new_file)
                        # @debug "Recursing into `$new_file`" node wrapper.file
                        new_wrapper = try_parse_wrapper(new_file; wrapper.bad_locations)
                        if new_wrapper === nothing
                            push!(wrapper.bad_locations, location)
                            return [SkippedFile(location)]
                        else
                            return [new_wrapper]
                        end
                    else
                        @warn "`include` at $location points to missing file; cannot recurse into it."
                        push!(wrapper.bad_locations, location)
                        return [SkippedFile(location)]
                    end
                else
                    @label dynamic
                    @warn "Dynamic `include` found at $location; not recursing"
                    push!(wrapper.bad_locations, location)
                    return [SkippedFile(location)]
                end
            end
        end
    end
    return map(n -> SyntaxNodeWrapper(n, wrapper.file, wrapper.bad_locations),
               JuliaSyntax.children(node))
end

js_children(n::Union{TreeCursor,SyntaxNodeWrapper}) = JuliaSyntax.children(js_node(n))
js_node(n::SyntaxNodeWrapper) = n.node
js_node(n::TreeCursor) = js_node(nodevalue(n))

function kind(n::Union{JuliaSyntax.SyntaxNode,JuliaSyntax.GreenNode,JuliaSyntax.SyntaxHead})
    return JuliaSyntax.kind(n)
end
kind(n::Union{TreeCursor,SyntaxNodeWrapper}) = kind(js_node(n))

head(n::Union{JuliaSyntax.SyntaxNode,JuliaSyntax.GreenNode}) = JuliaSyntax.head(n)
head(n::Union{TreeCursor,SyntaxNodeWrapper}) = head(js_node(n))

get_val(n::JuliaSyntax.SyntaxNode) = n.val
get_val(n::Union{TreeCursor,SyntaxNodeWrapper}) = get_val(js_node(n))

function has_flags(n::Union{JuliaSyntax.SyntaxNode,JuliaSyntax.GreenNode}, args...)
    return JuliaSyntax.has_flags(n, args...)
end
has_flags(n::Union{TreeCursor,SyntaxNodeWrapper}, args...) = has_flags(js_node(n), args...)

# which child are we of our parent
function child_index(n::TreeCursor)
    p = parent(n)
    isnothing(p) && return error("No parent!")
    index = findfirst(==(js_node(n)), js_children(p))
    @assert !isnothing(index)
    return index
end

kind_match(k1::JuliaSyntax.Kind, k2::JuliaSyntax.Kind) = k1 == k2

parents_match(n::TreeCursor, kinds::Tuple{}) = true
function parents_match(n::TreeCursor, kinds::Tuple)
    k = first(kinds)
    p = parent(n)
    isnothing(p) && return false
    kind_match(kind(p), k) || return false
    return parents_match(p, Base.tail(kinds))
end

function get_parent(n, i=1)
    for _ in i:-1:1
        n = parent(n)
        n === nothing && error("No parent")
    end
    return n
end

function has_parent(n, i=1)
    for _ in i:-1:1
        n = parent(n)
        n === nothing && return false
    end
    return true
end
