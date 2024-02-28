module DynMod

using ExplicitImports
using ExplicitImports: ExplicitImports
f() = print_explicit_imports

get_file() = "hi.jl"

include(get_file())

end # DynMod
