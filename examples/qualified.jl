module MyMod
using LinearAlgebra
# sum is in `Base`, so we shouldn't access it from LinearAlgebra:
n = LinearAlgebra.sum([1, 2, 3])
end
