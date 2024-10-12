module TestMacro
using EnumX: @enumx
using LinearAlgebra
@enumx ApplyStrategy Transpose Inplace

function my_method()
    ApplyStrategy.Transpose
end

end #TestMacro
