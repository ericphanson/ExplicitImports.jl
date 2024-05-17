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

end # TestMod5

module TestMod6

using LinearAlgebra

function foo(x)
    for (i, I) in pairs(x)
        # this next one is very tricky, since we need to both identify `j`
        # as a for "argument", and note that `I` is a local variable from
        # one scope up.
        for j in I
        end
    end
    for (; k) in x
    end

    for (; k) in x, (; j) in y
    end

    for xi in x, yi in y
    end
end

end # TestMod6

module TestMod7

using LinearAlgebra

# these are all local references to `I`, but you have to go up a scope to know that
function foo(I)
    let
        I + 1
    end
    let k = I
        k + I
    end
    function bar(x)
        return I + 1
    end
    return bar(I)
end

end # TestMod7

module TestMod8
using LinearAlgebra

# https://github.com/ericphanson/ExplicitImports.jl/issues/33
foo(::QR) = ()

end # TestMod8

module TestMod9

using LinearAlgebra

function foo(x)
    [x for (i1, I) in pairs(x)]
    (x for (i2, I) in pairs(x))
    [x for (i3, I) in pairs(x) if I == 1]
    (x for (i4, I) in pairs(x) if I == 1)

    [x for (; i1, I) in pairs(x)]
    (x for (; i2, I) in pairs(x))
    [x for (; i3, I) in pairs(x) if (I, 1) == 1]
    (x for (; i4, I) in pairs(x) if (I, 1) == 1)

    [x for i1 in x, I in x]
    (x for i1 in x, I in x)

    [x for i1 in x, I in x if I == 1]
    (x for i1 in x, I in x if I == 1)

    # Here we want to be sure that `y` does not match!
    return (x for i1 in x, I in x if (y = 1) == 1)
end

end # TestMod9


module TestMod10

using LinearAlgebra

function foo(x)
    while false
        I = 1
    end
    # Here, if our scope detection is wrong, we will think this `I` is local,
    # when in fact it is global. Therefore we must import it explicitly!
    return I
end

end # TestMod10
