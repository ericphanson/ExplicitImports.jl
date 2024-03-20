module DynMod

using ExplicitImports
using ExplicitImports: ExplicitImports
f() = print_explicit_imports

get_file() = "hi.jl"

include(get_file())

include("$(get_file())")

hi = "hi"
include("$(hi).jl")

end # DynMod
