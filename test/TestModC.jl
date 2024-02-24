module TestModC

# go wayy up to get the top-level `TestModA` which exports `f`
using ....TestModA
using ....Exporter
using ....Exporter: exported_b

# unnecessary explicit imports
# TODO: write functionality to detect this...
using ....Exporter: exported_c
import ....Exporter: exported_c

func_c() = (local9 = 1; f())

# fully qualified usage of implicitly available exported name
y = Exporter.exported_a()

# explicitly imported name, which is also available implicitly
z = exported_b()

end # module
