# ExplicitImports

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/dev/)
[![Build Status](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ericphanson/ExplicitImports.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ericphanson/ExplicitImports.jl)

## Goal

Figure out what implicit exports a Julia module is relying on, in order to make them explicit.

## Strategy & status

1. [DONE hackily] Figure out what names are being used to refer to bindings in global scope
2. [DONE] Figure out what implicit exports are available in the module
3. [TODO] Which implicit exports are already made explicit in the module
4. [Partly done] Then we can put this information together to figure out what names are actually being used from other modules, and whose usage could be made explicit.

## Example

```julia
julia> using ExplicitImports

julia> foreach(println, explicit_imports(ExplicitImports))
using AbstractTrees: Leaves
using AbstractTrees: TreeCursor
using AbstractTrees: children
using AbstractTrees: nodevalue
using DataFrames: DataFrame
using DataFrames: combine
using DataFrames: groupby
using DataFrames: select!
using DataFrames: subset!
using JuliaSyntax: SyntaxNode
using JuliaSyntax: kind
using JuliaSyntax: parseall
using Tables: ByRow
```
