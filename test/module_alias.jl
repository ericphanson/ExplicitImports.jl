# https://github.com/JuliaTesting/ExplicitImports.jl/issues/106
module ModAlias

module M1
    const g = 9.8
end

const M1′ = M1

using .M1′: g

end # module ModAlias
