module TestModA
# Note: in this file, names containing `"local"` have a particular meaning:
# we test to ensure they are correctly identified as being in local scope.

using ..Exporter
using ..Exporter2
using ..Exporter3

using ..Exporter: un_exported

export f

f() = sqrt(1)

g() = exported_a()

g2() = un_exported()

@mac

x = 1

function func()
    local_var = 1
    for local_z in 1:3
        local_3 = 5
    end
    exported_a()
    x = 2 # local variable, shadowing global name
    return x + 1
end

let local2 = 1
    local3 = 4
end

for local4 in 1:5
    local5 = 1
end

global_a = 1

func2() = (local6 = 1; global_a)

func3() = (; local7=1)

module SubModB
using ..Exporter3
using ..TestModA

export h2
h() = (local8 = 1; f())

h2() = exported_b()

h3() = 1

module TestModA # again

inner_f() = 1

using ..Exporter3

inner_h() = exported_b()

include("TestModC.jl")

end

end # SubModB

# back inside outer TestModA

using .SubModB

h2()

end
