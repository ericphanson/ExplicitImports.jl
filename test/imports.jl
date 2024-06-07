module ModImports
using ..Exporter: exported_a, exported_c
import ..Exporter: exported_c
import ..TestModA.SubModB
import ..TestModA.SubModB: h2
import ..TestModA.SubModB: h3 as h2a
using ..TestModA.SubModB: h
import ..Exporter
using ..Exporter
using LinearAlgebra: map, _svd!
using LinearAlgebra: svd

import ..TestModA.SubModB: exported_b

end # module

# scope = JSON
# var = :parse
# bnd = ccall(:jl_get_module_binding, Any, (Any, Any, Cint), scope, var, true)::Core.Binding

# @ccall jl_binding_dbgmodule(bnd::Any, scope::Module, var::Symbol)::Module
# ccall(:jl_binding_dbgmodule, Module, (Any, Module, Symbol), bnd, scope, var)::Module

# jl_get_binding_for_method_def
# bnd = ccall(:jl_get_binding_for_method_def, Any, (Any, Any), scope, var)::Core.Binding

function jl_binding_dbgmodule(b::Core.Binding, m::Module, var::Symbol)
    b2 = b.owner

    if (b2 != b && !b.imported)

        # // for implicitly imported globals, try to re-resolve it to find the module we got it from most directly
        from = nothing
        # b = using_resolve_binding(m, var, &from, NULL, 0);

        if b !== nothing
            if b2 === nothing || b.owner == b2.owner
                return from
            end
        end
    end

    return m
end
