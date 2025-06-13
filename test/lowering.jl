using JuliaLowering, JuliaSyntax
using JuliaLowering: SyntaxTree, ensure_attributes, showprov
using AbstractTrees
# piracy
AbstractTrees.children(t::SyntaxTree) = something(JuliaSyntax.children(t), ())

include("test_mods.jl")

src = read("test_mods.jl", String)
tree = parseall(JuliaLowering.SyntaxTree, src; filename="tests_mods.jl")

testmod1_code = JuliaSyntax.children(JuliaSyntax.children(tree)[2])[2]
func = JuliaSyntax.children(testmod1_code)[end - 1]

leaf = JuliaSyntax.children(func)[2]

ex = testmod1_code
ex = ensure_attributes(ex; var_id=Int)

in_mod = TestMod1
# in_mod=Main
ctx1, ex_macroexpand = JuliaLowering.expand_forms_1(in_mod, ex)
ctx2, ex_desugar = JuliaLowering.expand_forms_2(ctx1, ex_macroexpand)
ctx3, ex_scoped = JuliaLowering.resolve_scopes(ctx2, ex_desugar)

leaf = collect(Leaves(ex_scoped))[end - 3]
showprov(leaf)

binding_info = ctx3.bindings.info[leaf.var_id]
binding_info.kind == :global

global_bindings = filter(ctx3.bindings.info) do binding
    # want globals
    keep = binding_info.kind == :global

    # internal ones seem non-interesting (`#self#` etc)
    keep &= !binding.is_internal

    # I think we want ones that aren't assigned to? otherwise we are _defining_ the global here, not using it
    keep &= binding.n_assigned == 0
    return keep
end


# notes
# global names seem "easy": they show up as BindingID in the source tree and have an info populated in `ctx.binding.info`
# qualified names seem a bit harder, they show up like this:
#
# [call]                                   │
#   top.getproperty    :: top              │
#   #₈/ExplicitImports :: BindingId        │
#   :check_no_implicit_imports :: Symbol   │ scope_layer=1
#
# so here `check_no_implicit_imports` is a qualified name, we can see it as a child of call,
# where we are calling getproperty on ExplicitImports and `check_no_implicit_imports`.
# so if we want to check you are calling it from the "right" module, we need to follow the tree,
# find this pattern, then check the module against the symbol.
# That's what we already do, but now we should have more precision in knowing the module I think
