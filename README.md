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
Module ExplicitImports is relying on implicit imports for 4 names. These could be explicitly imported as follows:

```julia
using AbstractTrees: Leaves
using AbstractTrees: TreeCursor
using AbstractTrees: children
using AbstractTrees: nodevalue
```

````

Note: the `WARNING` is more or less harmless; the way this package is written, it will happen any time there is a clash, even if that clash is not realized in your code. I cannot figure out how to suppress it.

## Limitations

### Some tricky scoping situations are not handled correctly

These can likely all be fixed by improving the code in `src/get_names_used.jl`, so they aren't inherent limitations of this approach, but since we are re-implementing Julia's scoping rules on top of the parse tree, for fully accurate results we need to handle each situation correctly, which takes a lot of work.

Known issues:

- `global` and `local` keywords are currently ignored
- multi-argument `include` calls are ignored
- In Julia, `include` adds the included code at top-level in the module in which it is called. Here, when `include` is called within a local scope, all of the code being included is treated as being within that local scope.

The consequence of these issues is that ExplicitImports may misunderstand whether or not a particular name refers to a local variable or a global one, and thus whether or not some particular implicitly-available name (exported by some module) is in fact being used. This could cause it to suggest an unnecessary explicit import, fail to suggest an explicit import, or to falsely claim that an explicit import is stale.

Hopefully these situations are somewhat rare, because even if ExplicitExports misunderstands the scoping for one usage of a name, it may correctly parse the scoping of it in another usage in the same module, and could end up drawing the correct conclusion anyway.

Additionally, the testing-oriented functions `check_no_implicit_imports` and `check_no_stale_explicit_imports` have the ability to filter out problematic names or modules, to allow manual intervention in cases in which ExplicitImports gets it wrong.

### Cannot recurse through dynamic `include` statements

These are `include` in which the argument is not a string literal. For example, the package MathOptInterface.jl currently includes the following code in it's `Test` module:

```julia
for file in readdir(@__DIR__)
    if startswith(file, "test_") && endswith(file, ".jl")
        include(file)
    end
end
```

This is problematic for ExplicitImports.jl; unless we really use a full-blown interpreter (which I do think could be a viable strategy[^1]), we can't really execute this code to know what files are being included. Thus being unable to traverse dynamic includes is essentially an inherent limitation of the approach used in this package.

The consequence of missing files is that the any names used or imports made in those files are totally missed. Even if we did take a strategy like "scan the package `src` directory for Julia code, and analyze all those files", without understanding `includes`, we wouldn't understand which files belong to which modules, making this analysis useless.

However, we do at least detect this situation, so we can which modules are affected by the missing information, and (by default) refuse to make claims about them. For example, running `print_explicit_imports` on this module gives:

```sh
julia> print_explicit_imports(MathOptInterface.Test, pkgdir(MathOptInterface))
Module MathOptInterface.Test could not be accurately analyzed, likely due to dynamic `include` statements. You can pass `strict=false` to attempt to get (possibly inaccurate) results anyway.

Module MathOptInterface.Test._BaseTest could not be accurately analyzed, likely due to dynamic `include` statements. You can pass `strict=false` to attempt to get (possibly inaccurate) results anyway.
```

Note here we need to pass `pkgdir(MathOptInterface)` as the second argument, since `pathof(MathOptInterface.Test) === nothing` so otherwise we would get a `FileNotFoundException`.

If we do pass `strict=false`, in this case we get

```sh
julia> print_explicit_imports(MathOptInterface.Test, pkgdir(MathOptInterface); strict=false)
Module MathOptInterface.Test is not relying on any implicit imports.

Module MathOptInterface.Test._BaseTest is not relying on any implicit imports.
```

However, we can't really be sure there is't a reliance on implicit imports present in the files that we weren't able to scan (or perhaps some stale explicit imports made in those files).

### Need to load the package/module

This implementation relies on `Base.which` to introspect which module any given name comes from, and therefore we need to load the module, not just inspect its source code. We can't solely use the source code because implicit imports are implicit -- which is part of the criticism of them in the first place, that the source file alone does not tell you where the names come from.

In particular, this means it is hard to convert implicit imports to explicit as a formatting pass, for example.

Given a running [language server](https://github.com/julia-vscode/LanguageServer.jl), however, I think it should be possible to query that for the information needed.

[^1]: An alternate implementation using an `AbstractInterpreter` (like JET does) might solve this issue (at the cost of increased complexity), and possibly get some handling of tricky scoping situations "for free".
