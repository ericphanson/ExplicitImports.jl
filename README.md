# ExplicitImports

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/dev/)
[![Build Status](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ericphanson/ExplicitImports.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ericphanson/ExplicitImports.jl)

## Goal

Figure out what implicit imports a Julia module is relying on, in order to make them explicit.

## Terminology

- _implicit import_: a name `x` available in a module due to `using XYZ` for some package or module `XYZ`. This name has not been explicitly imported; rather, it is simply available since it is exported by `XYZ`.
- _explicit import_: a name `x` available in a module due to `using XYZ: x` or `import XYZ: x` for some package or module `XYZ`.

## Why

Relying on implicit imports can be problematic, as Base or another package can start exporting that name as well, resulting in a clash. This is a tricky situation because adding a new feature to Base (or a package) and exporting it is not considered a breaking change to its API, but it can cause working code to stop working due to these clashes.

If you've even seen a warning like:

> WARNING: both X and Y export "foo"; uses of it in module MyPackage must be qualified

Then this is the kind of clash at issue. When this occurs, the name `foo` won't point to either package's name, since it is ambiguous which one it should be. However, if the package code is relying on the name `foo` existing, then there's trouble.

One fix, as the warning suggests, is to qualify the use `foo` by writing e.g. `X.foo` or `Y.foo`. Another option is to explicitly import it, by writing `using X: foo` instead of just `using X`.

There are various takes on _how problematic_ this issue is, to what extent this occurs in practice, and to what extent it is worth mitigating. See [julia#42080](https://github.com/JuliaLang/julia/pull/42080) for some discussion on this.

Personally, I don't think this is always a huge issue, and that it's basically fine for packages to use implicit imports if that is their preferred style and they understand the risk. But I do think this issue is somewhat a "hole" in the semver system as it applies to Julia packages, and I wanted to create some tooling to make it easier to mitigate the issue for package authors who would prefer to not rely on implicit imports.

## Implementation status

This seems to be working! However it has not been extensively used or tested.

See the [API docs](https://ericphanson.github.io/ExplicitImports.jl/dev/api/) for the available functionality.

## Example

````julia
julia> using ExplicitImports

julia> print_explicit_imports(ExplicitImports)
WARNING: both JuliaSyntax and Base export "parse"; uses of it in module ExplicitImports must be qualified
Module ExplicitImports is relying on implicit imports for 13 names. These could be explicitly imported as follows:

```julia
using AbstractTrees: Leaves
using AbstractTrees: TreeCursor
using AbstractTrees: children
using AbstractTrees: nodevalue
using DataAPI: outerjoin
using DataFrames: AsTable
using DataFrames: DataFrame
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

Currently, my parsing implementation does not take into account the `global` keyword, and thus results may be inaccurate when that is used. This could be fixed by improving the code in `src/get_names_used.jl`.

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

This is essentially an inherent limitation of the approach used in this package. An alternate implementation using an `AbstractInterpreter` (like JET does) may be able to handle this (at the cost of increased complexity).

### Need to load the package/module

This implementation relies on `Base.which` to introspect which module any given name comes from, and therefore we need to load the module, not just inspect its source code. We can't solely use the source code because implicit imports are implicit -- which is part of the criticism of them in the first place, that the source file alone does not tell you where the names come from.

In particular, this means it is hard to convert implicit imports to explicit as a formatting pass, for example.

Given a running [language server](https://github.com/julia-vscode/LanguageServer.jl), however, I think it should be possible to query that for the information needed.
