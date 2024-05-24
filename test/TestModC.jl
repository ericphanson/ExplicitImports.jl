module TestModC

# go wayy up to get the top-level `TestModA` which exports `f`
using ....TestModA
using ....Exporter: Exporter, exported_b, exported_d # d is unnecessary

# unnecessary explicit imports
# TODO: write functionality to detect this...
using ....Exporter: exported_c
import ....Exporter: exported_c

func_c() = (local9 = 1; f())

# fully qualified usage of implicitly available exported name
y = Exporter.exported_a()

TestModA.SubModB.h

# explicitly imported name, which is also available implicitly
z = exported_b()

end # module
