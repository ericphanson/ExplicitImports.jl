module TestModEmpty end # module

module TestMod1

using ExplicitImports

f() = print_explicit_imports

g() = ExplicitImports.check_no_implicit_imports

end # module
