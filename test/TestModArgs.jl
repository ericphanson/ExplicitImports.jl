module TestModArgs

using ..Exporter4

# `a` is exported, but all these uses are local
function f1(a)
    return a
end

function f2(; a)
    return a
end

f3(a) = a

f4(; a) = a

# reference global default value
function g1(a=A)
    return a
end

function g2(; a=A)
    return a
end

g3(a=A) = a

g4(; a=A) = a

# # local default value
function h1(a=1)
    return a
end

function h2(; a=1)
    return a
end

h3(a=1) = a

h4(; a=1) = a

function i1(a::Int)
    return a
end

function i2(; a::Int)
    return a
end

i3(a::Int) = a

i4(; a::Int) = a

function j1(a::Int=1)
    return a
end

function j2(; a::Int=1)
    return a
end

j3(a::Int=1) = a

j4(; a::Int=1) = a

function k1(a::Int=j1(A))
    return a
end

function k2(; a::Int=j1(A))
    return a
end

k3(a::Int=j1(A)) = a

k4(; a::Int=j1(A)) = a

end # TestModArgs
