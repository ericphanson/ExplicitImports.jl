module Exporter123
export exported_a
exported_a() = "hi"
end # Exporter123

module TestInterpolation

using ..Exporter123
function register_steelProfile()
    function file()
        return print(`$(exported_a())`)
    end
end

end # TestInterpolation
