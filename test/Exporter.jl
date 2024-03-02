module Exporter

export exported_a, exported_b, exported_c, x, exported_d, @mac

exported_a() = "hi"
exported_b() = "hi-b"
exported_c() = "hi-c"
exported_d() = "hi-d"

un_exported() = "bye"

x = 2

macro mac(args...)
end

end # Exporter

# a duplicate
module Exporter2
using ..Exporter

# re-export the same name
export exported_a

end # Exporter2

# a clash
module Exporter3

export exported_b

exported_b() = "hi-b-clash"

end # Exporter3

# many exports to test sorting
module Exporter4

export A, Z, a, z

A() = "A"
Z() = "Z"
a() = "a"
z() = "z"

end # Exporter4
