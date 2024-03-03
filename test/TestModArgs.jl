module TestModArgs

using ..Exporter4

# This module is all about testing whether we are detecting
# arguments of function definitions correctly.
# Here, `a` is always the argument in question, and
# A and Z are globals from `exporter4`.
# We define all 4 forms of function definition,
# with various choices of default values, type annotations, etc.

# `a` is exported, but all these uses are local
function f1(a)
    return Z
end

function f2(; a)
    return Z
end

f3(a) = Z

f4(; a) = Z

# reference global default value
function g1(a=A)
    return Z
end

function g2(; a=A)
    return Z
end

g3(a=A) = Z

g4(; a=A) = Z

# # local default value
function h1(a=1)
    return Z
end

function h2(; a=1)
    return Z
end

h3(a=1) = Z

h4(; a=1) = Z

function i1(a::Int)
    return Z
end

function i2(; a::Int)
    return Z
end

i3(a::Int) = Z

i4(; a::Int) = Z

function j1(a::Int=1)
    return Z
end

function j2(; a::Int=1)
    return Z
end

j3(a::Int=1) = Z

j4(; a::Int=1) = Z

function k1(a::Int=j1(A))
    return Z
end

function k2(; a::Int=j1(A))
    return Z
end

k3(a::Int=j1(A)) = Z

k4(; a::Int=j1(A)) = Z

l1 = function (a::Int=j1(A))
    return Z
end

l2 = function (; a::Int=j1(A))
    return Z
end

l3 = (a::Int = j1(A)) -> Z

l4 = (; a::Int=j1(A)) -> Z

m1 = function (a::Int)
    return Z
end

m2 = function (; a::Int)
    return Z
end

m3 = (a::Int) -> Z

m4 = (; a::Int) -> Z

n1 = function (a)
    return Z
end

n3 = a -> Z

n4 = (; a) -> Z

n2 = function (; a)
    return Z
end

macro o1(a)
    return Z
end

macro o1_str(a)
    return Z
end

end # TestModArgs
