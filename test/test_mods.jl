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

module TestMod5

using LinearAlgebra

struct Unrelated{X<:AbstractArray}
    x::Union{X,Vector}
end

struct Unrelated2{Y<:AbstractArray}
    x::Y
end

# https://github.com/ericphanson/ExplicitImports.jl/issues/34
struct Bar{QR}
    x::QR
end

# https://github.com/ericphanson/ExplicitImports.jl/issues/36
struct Foo
    qr::Int
end

Base.@kwdef struct Foo2
    qr::Int = 1
end

end # TestMOd5

module TestMod6

using LinearAlgebra

function foo(x)
    for (i, I) in pairs(x)
    end
end

end # module
