module TestModEmpty end

module TestMod1

using ExplicitImports: ExplicitImports
using ExplicitImports

f() = print_explicit_imports

g() = ExplicitImports.check_no_implicit_imports

end # TestMod1

# many implicit imports to test sorting
module TestMod4

using ..Exporter4

fA() = A()
fZ() = Z()
fa() = a()
fz() = z()
fA2() = Exporter4.A()
fZ2() = Exporter4.Z()
fa2() = Exporter4.a()
fz2() = Exporter4.z()

end # TestMod4

# https://github.com/ericphanson/ExplicitImports.jl/issues/34
module TestMod5

using LinearAlgebra

struct Bar{QR}
    x::QR
end

end # TestMOd5
