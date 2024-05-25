module ModImports
using ..Exporter: exported_a, exported_b
import ..Exporter: exported_c
import ..TestModA.SubModB
import ..TestModA.SubModB: h2
import ..TestModA.SubModB: h3 as h2a
using ..TestModA.SubModB: h
import ..Exporter
using ..Exporter
using LinearAlgebra: map
using LinearAlgebra: svd

end # module
