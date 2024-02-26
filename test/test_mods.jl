module TestModEmpty end

module TestMod1

using ExplicitImports: ExplicitImports
using ExplicitImports

f() = print_explicit_imports

g() = ExplicitImports.check_no_implicit_imports

end # TestMod1
