
# Here we define a wrapper so we can use AbstractTrees without piracy
# https://github.com/JuliaEcosystem/PackageAnalyzer.jl/blob/293a0836843f8ce476d023e1ca79b7e7354e884f/src/count_loc.jl#L91-L99
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
                    # string literals can only have one child (I think...)
                    c = only(children)
                    # The children of a static include statement is the entire file being included
                    new_file = joinpath(dirname(wrapper.file), c.val)
                    if isfile(new_file)
                        @debug "Recursing into `$new_file`" node wrapper.file
                        new_wrapper = try_parse_wrapper(new_file; wrapper.bad_locations)
                        if new_wrapper !== nothing
                            return [new_wrapper]
                        else
                            push!(wrapper.bad_locations, location)
                            return [SkippedFile(location)]
                        end
                    else
                        @warn "`include` at $location points to missing file; cannot recurse into it."
                        push!(wrapper.bad_locations, location)
                        return [SkippedFile(location)]
                    end
                else
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

js_node(n::SyntaxNodeWrapper) = n.node
js_node(n::TreeCursor) = js_node(nodevalue(n))

kind(n::JuliaSyntax.SyntaxNode) = JuliaSyntax.kind(n)
kind(n::JuliaSyntax.GreenNode) = JuliaSyntax.kind(n)
kind(n::JuliaSyntax.SyntaxHead) = JuliaSyntax.kind(n)
kind(n::Union{TreeCursor,SyntaxNodeWrapper}) = JuliaSyntax.kind(js_node(n))

head(n::JuliaSyntax.SyntaxNode) = JuliaSyntax.head(n)
head(n::JuliaSyntax.GreenNode) = JuliaSyntax.head(n)
head(n::Union{TreeCursor,SyntaxNodeWrapper}) = JuliaSyntax.head(js_node(n))
js_children(n::Union{TreeCursor,SyntaxNodeWrapper}) = JuliaSyntax.children(js_node(n))

# which child are we of our parent
function child_index(n::TreeCursor)
    p = parent(n)
    isnothing(p) && return error("No parent!")
    index = findfirst(==(js_node(n)), js_children(p))
    @assert !isnothing(index)
    return index
end

parents_match(n::TreeCursor, kinds::Tuple{}) = true
function parents_match(n::TreeCursor, kinds::Tuple)
    k = first(kinds)
    p = parent(n)
    isnothing(p) && return false
    kind(p) == k || return false
    return parents_match(p, Base.tail(kinds))
end
