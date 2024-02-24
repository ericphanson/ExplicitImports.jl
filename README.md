# ExplicitImports

<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/stable/) -->

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/dev/)
[![Build Status](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ericphanson/ExplicitImports.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ericphanson/ExplicitImports.jl)

## Goal

Figure out what implicit exports a Julia module is relying on, in order to make them explicit.

## Strategy & status

1. [DONE hackily] Figure out what names are being used to refer to bindings in global scope
   - We do this by parsing the code (thanks to JuliaSyntax), then reimplementing scoping rules on top of the parse tree
   - This is finicky, but assuming scoping doesn't change, should be robust enough (once the long tail of edge cases are dealt with...)
     - Currently, I don't handle the `global` keyword, so those may look like local variables and confuse things
   - This means we need access to the raw source code; `pathof` works well for packages, but for local modules one has to pass the path themselves. Also doesn't seem to work well for stdlibs in the sysimage
2. [DONE] Figure out what implicit exports are available in the module
3. [DONE] Which implicit exports are already made explicit in the module
   - Done via parsing

Then we can put this information together to figure out what names are actually being used from other modules, and whose usage could be made explicit, and also which existing explicit imports are not being used.

## Example

````julia
julia> using ExplicitImports

julia> print_explicit_imports(ExplicitImports)
WARNING: both JuliaSyntax and Base export "parse"; uses of it in module ExplicitImports must be qualified
Module ExplicitImports is relying on implicit imports for 14 names. These could be explicitly imported as follows:

```julia
using AbstractTrees: Leaves
using AbstractTrees: TreeCursor
using AbstractTrees: children
using AbstractTrees: nodevalue
using DataAPI: outerjoin
using DataFrames: AsTable
using DataFrames: DataFrame
using DataFrames: by
using DataFrames: combine
using DataFrames: groupby
using DataFrames: select!
using DataFrames: subset
using DataFrames: subset!
using Tables: ByRow
```

````

Note: the `WARNING` is more or less harmless; the way this package is written, it will happen any time there is a clash, even if that clash is not realized in your code. I cannot figure out how to suppress it.

## Limitations

### `global` scope quantifier ignored

Currently, my parsing implementation does not take into account the `global` keyword, and thus results may be inaccurate when that is used.

### Cannot recurse through dynamic `include` statements

These are `include` in which the argument is not a string literal. For example:

```julia
julia> print_explicit_imports(MathOptInterface)
┌ Warning: Dynamic `include` found at /Users/eph/.julia/packages/MathOptInterface/tpiUw/src/Test/Test.jl:631:9; not recursing
└ @ ExplicitImports ~/ExplicitImports/src/get_names_used.jl:37
...
```

In this case, names in files which are included via `include` are not analyzed while parsing.
This can result in inaccurate results, such as false positives in `explicit_imports` and false negatives (or false positives) in `stale_explicit_imports`.
