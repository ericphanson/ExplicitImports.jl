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

import ..TestModA.SubModB: f # owned by TestModA
end # module
