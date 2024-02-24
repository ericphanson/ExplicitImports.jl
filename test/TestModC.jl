module TestModC

# go wayy up to get the top-level `TestModA` which exports `f`
using ....TestModA

func_c() = (local9 = 1; f())

end # module
