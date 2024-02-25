module TestModEmpty end

module TestMod1

using ExplicitImports

f() = print_explicit_imports

g() = ExplicitImports.check_no_implicit_imports

end # TestMod1

module DynMod

using ExplicitImports
f() = print_explicit_imports

get_file() = "hi.jl"

include(get_file())

end # DynMod
