module TestModA

using ..Exporter
using ..Exporter2
using ..Exporter3

using ..Exporter: un_exported

export f

f() = sqrt(1)

g() = exported_a()

g2() = un_exported()

x = 1

function func()
    local_var = 1
    for local_z = 1:3
        local_3 = 5
    end
    exported_a()
    x = 2 # local variable, shadowing global name
    x + 1
end


let local2 = 1
    local3 = 4
end

for local4 = 1:5
    local5 = 1
end

global_a = 1

func2() = (local6=1; global_a)

func3() = (; local7=1)

module SubModB

using ..TestModA

h() = f()
end # SubModB

end
