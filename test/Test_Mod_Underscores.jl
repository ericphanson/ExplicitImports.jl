module Test_Mod_Underscores

using Test # implicit
using LinearAlgebra: map # non-owner
using LinearAlgebra: _svd! # non-public
using LinearAlgebra: svd # unused / stale
export foo

foo() = @test 42 isa Base.Sys.Number # non-owner access
bar() = _svd!() + Test_Mod_Underscores.foo() # self access
qux() = map(Base.__unsafe_string!, 1:2) # non-public access

end
