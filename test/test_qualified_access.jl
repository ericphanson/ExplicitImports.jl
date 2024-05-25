module TestQualifiedAccess
# https://github.com/ericphanson/ExplicitImports.jl/issues/48
module Bar
struct ABC
end

struct DEF end

struct HIJ end

export ABC
end

module FooModule
using ..Main: @public_or_export
using ..Bar: ABC, DEF, HIJ
export DEF

@public_or_export HIJ

ABC()
HIJ()
end

# Qualified access to `ABC` from the wrong module
FooModule.ABC

# Qualified access to `DEF` from non-parent module, BUT `DEF` is exported in `FooModule`,
# so it's OK
FooModule.DEF

# This one is either exported again or marked public, depending on Julia version
FooModule.HIJ

# Accessing it again does not affect results (we only report one)
FooModule.DEF

end # TestQualifiedAccess
