module TestModEmpty end # module

module TestMod1

using ExplicitImports

f() = print_explicit_imports

end # module
