module TestModArgs

using ..Exporter4

# `a` is exported, but all these uses are local
function f1(a)
    a
end

function f2(; a)
    a
end

f3(a) = a

f4(; a) = a

# reference global default value
function g1(a=A)
    a
end

function g2(; a=A)
    a
end

g3(a=A) = a

g4(; a=A) = a

# # local default value
function h1(a=1)
    a
end

function h2(; a=1)
    a
end

h3(a=1) = a

h4(; a=1) = a

end # TestModArgs
