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

module SubModB

using ..TestModA

h() = f()
end # SubModB

end
