
# using JuliaInterpreter
# function def(mod)
#     path = pathof(mod)
#     ret = []
#     frames = []
#     expr = Base.parse_input_line(String(read(path)); filename=path)
#     for (mod, ex) in ExprSplitter(mod, expr)
#         if ex.head === :global
#             # global declarations can't be lowered to a CodeInfo.
#             # In this demo we choose to evaluate them, but you can do something else.
#             # Core.eval(mod, ex)
#             continue
#         end
#         frame = Frame(mod, ex)
#         code = frame.framecode.src
#         append!(ret, global_refs_with_locations(code))
#         global FRAME = frame
#         push!(frames, frame)
#     end
#     return ret, frames
# end

function analyze_toplevel(mod, path=pathof(mod))
    expr = Base.parse_input_line(String(read(path)); filename=path)
    return lowered = Meta.lower(mod, expr)
end

using MethodAnalysis

# strategy:
# we can find lowered code for methods, and those have juicy global refs
# that may be implicit
# to find the lowered code for methods, we first look at ALL methods
# then look for ones defined in our module of interest
# then look for their global refs
# We need to look everywhere (not sure why)
function analyze_locals_nonrecursive(mod; debug=false)
    methods = Set{Core.Method}()
    # look for methods defined in our module
    f = item -> begin
        debug && println(typeof(item), ": ", try
                             nameof(item)
                         catch
                             try
                                 item.name
                             catch
                                 nothing
                             end
                         end)

        if item isa Core.Method && item.module == mod
            push!(methods, item)
        end
        return true
    end

    visit(f, mod)
    # traverse all loaded modules
    visit(f)

    # Also support kwargs on 1.9+
    for m in Base.methods(Core.kwcall)
        if m.module == mod
            push!(methods, m)
        end
    end

    ret = @NamedTuple{line_info::Union{Core.LineInfoNode,Nothing},ref::Core.GlobalRef}[]
    for m in methods
        append!(ret, global_refs_with_locations(m; debug))
    end
    # Ignore references within our own module
    # filter!(ret) do r
    # r.ref.mod != mod
    # end

    return ret
end

function global_names(m; debug)
    code = Base.uncompressed_ast(m)
    return global_refs_with_locations(code::Core.CodeInfo; debug)
end

function global_refs_with_locations(m::Core.Method; debug)
    code = Base.uncompressed_ast(m)
    return global_refs_with_locations(code; debug)
end

function global_refs_with_locations(code::Core.CodeInfo; debug)
    debug && println(code)
    ret = @NamedTuple{line_info::Union{Core.LineInfoNode,Nothing},ref::Core.GlobalRef}[]
    for (i, stmt) in enumerate(code.code)
        loc = code.codelocs[i]
        if loc == 0
            if !isempty(code.linetable)
                line_info = code.linetable[1]

            else
                line_info = nothing
            end
        else
            line_info = code.linetable[loc]
        end
        debug && println(typeof(stmt), ": ", stmt)
        debug && if stmt isa Expr
            println(typeof(stmt.args[2]))
            println(dump(stmt.args[2]))
        end
        if stmt isa Core.GlobalRef
            push!(ret, (; line_info, ref=stmt))
        else
            refs = Core.GlobalRef[]
            find_global_refs!(refs, stmt)
            for x in refs
                push!(ret, (; line_info, ref=x))
            end
        end
    end
    return ret
end

function find_global_refs!(refs, expr::Expr)
    if Meta.isexpr(expr, (:isdefined, :thunk, :toplevel, :method, :global, :const))
        return nothing
    end
    for ex in expr.args
        find_global_refs!(refs, ex)
    end
    return nothing
end
find_global_refs!(refs, ::Core.SlotNumber) = nothing
find_global_refs!(refs, ::Core.Argument) = nothing
function find_global_refs!(refs, code::Core.CodeInfo)
    return error("TODO")
end

function find_global_refs!(refs, node::Core.GotoNode)
    find_global_refs!(refs, node.label)
    return nothing
end

function find_global_refs!(refs, node::Core.ReturnNode)
    find_global_refs!(refs, node.val)
    return nothing
end

function find_global_refs!(refs, node::Core.QuoteNode)
    find_global_refs!(refs, node.value)
    return nothing
end

function find_global_refs!(refs, ref::Core.GlobalRef)
    push!(refs, ref)
    return nothing
end
function find_global_refs!(refs, node::Core.GotoIfNot)
    find_global_refs!(refs, node.cond)
    find_global_refs!(refs, node.dest)
    return nothing
end
find_global_refs!(refs, ::Core.SSAValue) = nothing
find_global_refs!(refs, ::Core.NewvarNode) = nothing
find_global_refs!(refs, ::Any) = nothing
