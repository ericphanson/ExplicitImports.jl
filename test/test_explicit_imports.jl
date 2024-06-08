module TestExplicitImports
module Bar
struct ABC end

struct DEF end

struct HIJ end

export ABC
end # Bar

module FooModule
using ..Main: @public_or_export
using ..Bar: ABC, DEF, HIJ
export DEF

@public_or_export HIJ

module FooSub
struct X end
end # FooSub

using .FooSub: X
X()

ABC()
HIJ()
X()
end # FooModule

# Explicit import of `ABC` from the wrong module
using .FooModule: ABC

# Explicit import of `DEF` from non-owner module, BUT `DEF` is exported in `FooModule`,
# so it's OK
using .FooModule: DEF

# This one is either exported again or marked public, depending on Julia version
import .FooModule: HIJ

# Accessing it again does not affect results (we only report one)
import .FooModule: DEF

# This is allowed unless `require_submodule_access=true`
import .FooModule: X

end # TestExplicitImports
