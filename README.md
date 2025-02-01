# ExplicitImports

[![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/stable/)
[![Build Status](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/ericphanson/ExplicitImports.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/ericphanson/ExplicitImports.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/ericphanson/ExplicitImports.jl)

## Quickstart

Install ExplicitImports.jl with `using Pkg; Pkg.add("ExplicitImports")`, then run
```julia
using MyPackage # the package you want to analyze
using ExplicitImports
print_explicit_imports(MyPackage)
```

## Summary

ExplicitImports.jl helps detect implicit imports and mitigate issues with the alternatives (explicit imports and qualified accesses).

| Problem               | Example                             | Interactive detection                                  | Programmatic detection        | Regression-testing check                  |
| --------------------- | ----------------------------------- | ------------------------------------------------------ | ----------------------------- | ----------------------------------------- |
| Implicit imports      | `using LinearAlgebra`               | `print_explicit_imports`                               | `explicit_imports`            | `check_no_implicit_imports`               |
| Non-owning import     | `using LinearAlgebra: map`          | `print_explicit_imports`                               | `improper_explicit_imports`   | `check_all_explicit_imports_via_owners`   |
| Non-public import     | `using LinearAlgebra: _svd!`        | `print_explicit_imports` with `report_non_public=true` | `improper_explicit_imports`   | `check_all_explicit_imports_are_public`   |
| Stale import          | `using LinearAlgebra: svd # unused` | `print_explicit_imports`                               | `improper_explicit_imports`   | `check_no_stale_explicit_imports`         |
| Non-owning access     | `LinearAlgebra.map`                 | `print_explicit_imports`                               | `improper_qualified_accesses` | `check_all_qualified_accesses_via_owners` |
| Non-public access     | `LinearAlgebra._svd!`               | `print_explicit_imports` with `report_non_public=true` | `improper_qualified_accesses` | `check_all_qualified_accesses_are_public` |
| Self-qualified access | `Foo.bar` within the module `Foo`   | `print_explicit_imports`                               | `improper_qualified_accesses` | `check_no_self_qualified_accesses`        |

To understand these examples, note that:

- `svd` is an API function of LinearAlgebra
- `map` is an API function of Base, which happens to be present in the LinearAlgebra namespace
- `_svd!` is a private function of LinearAlgebra

## Goals

- Figure out what implicit imports a Julia module is relying on, in order to make them explicit.
- Provide tools to help make explicit imports and (more recently) qualified accesses more ergonomic

## Terminology

- _implicit import_: a name `x` available in a module due to `using XYZ` for some package or module `XYZ`. This name has not been explicitly imported; rather, it is simply available since it is exported by `XYZ`.
- _explicit import_: a name `x` available in a module due to `using XYZ: x` or `import XYZ: x` for some package or module `XYZ`.
- _qualified access_: a name `x` accessed via `XYZ.x`

## Why

Relying on implicit imports can be problematic, as Base or another package can start exporting that name as well, resulting in a clash. This is a tricky situation because adding a new feature to Base (or a package) and exporting it is not considered a breaking change to its API, but it can cause working code to stop working due to these clashes.

If you've even seen a warning like:

> WARNING: both X and Y export "foo"; uses of it in module MyPackage must be qualified

Then this is the kind of clash at issue. When this occurs, the name `foo` won't point to either package's name, since it is ambiguous which one it should be. However, if the package code is relying on the name `foo` existing, then there's trouble.

One fix, as the warning suggests, is to qualify the use `foo` by writing e.g. `X.foo` or `Y.foo`. Another option is to explicitly import it, by writing `using X: foo` instead of just `using X`.

There are various takes on _how problematic_ this issue is, to what extent this occurs in practice, and to what extent it is worth mitigating. See [julia#42080](https://github.com/JuliaLang/julia/pull/42080) for some discussion on this.

Personally, I don't think this is always a huge issue, and that it's basically fine for packages to use implicit imports if that is their preferred style and they understand the risk. But I do think this issue is somewhat a "hole" in the semver system as it applies to Julia packages, and I wanted to create some tooling to make it easier to mitigate the issue for package authors who would prefer to not rely on implicit imports.

## Example

````julia
julia> using ExplicitImports

julia> print_explicit_imports(ExplicitImports)
WARNING: both JuliaSyntax and Base export "parse"; uses of it in module ExplicitImports must be qualified
  Module ExplicitImports is relying on implicit imports for 7 names. These could be explicitly imported as follows:

  using AbstractTrees: AbstractTrees, Leaves, TreeCursor, children, nodevalue
  using JuliaSyntax: JuliaSyntax, @K_str

  Additionally, module ExplicitImports has 1 self-qualified access:

    •  parent was accessed as ExplicitImports.parent inside ExplicitImports at /Users/eph/ExplicitImports/src/deprecated.jl:79:21

  Additionally, module ExplicitImports accesses 1 name from non-owner modules:

    •  parent has owner AbstractTrees but it was accessed from ExplicitImports at
       /Users/eph/ExplicitImports/src/deprecated.jl:79:21
````

Note: the `WARNING` is more or less harmless; the way this package is written, it will happen any time there is a clash, even if that clash is not realized in your code. I cannot figure out how to suppress it.

You can also pass `show_locations=true` for more details:

````julia
  Module ExplicitImports is relying on implicit imports for 7 names. These could be explicitly imported as follows:

  using AbstractTrees: AbstractTrees # used at /Users/eph/ExplicitImports/src/parse_utilities.jl:51:10
  using AbstractTrees: Leaves # used at /Users/eph/ExplicitImports/src/get_names_used.jl:453:17
  using AbstractTrees: TreeCursor # used at /Users/eph/ExplicitImports/src/parse_utilities.jl:129:18
  using AbstractTrees: children # used at /Users/eph/ExplicitImports/src/get_names_used.jl:380:26
  using AbstractTrees: nodevalue # used at /Users/eph/ExplicitImports/src/get_names_used.jl:359:16
  using JuliaSyntax: JuliaSyntax # used at /Users/eph/ExplicitImports/src/get_names_used.jl:439:53
  using JuliaSyntax: @K_str # used at /Users/eph/ExplicitImports/src/get_names_used.jl:299:33

  Additionally, module ExplicitImports has 1 self-qualified access:

    •  parent was accessed as ExplicitImports.parent inside ExplicitImports at /Users/eph/ExplicitImports/src/deprecated.jl:79:21

  Additionally, module ExplicitImports accesses 1 name from non-owner modules:

    •  parent has owner AbstractTrees but it was accessed from ExplicitImports at
       /Users/eph/ExplicitImports/src/deprecated.jl:79:21
````

Note the paths of course will differ depending on the location of the code on your system.

This can be handy for debugging; if you find that in fact ExplicitImports thinks a local variable is a global from another module, please file an issue and include the code snippet!

## Command-line usage

ExplicitImports provides a `main` function to facilitate using ExplicitImports directly from the command line. For example,

```bash
julia <path/to/ExplicitImports.jl>/scripts/explicit-imports.jl path_to_package
```
or

```bash
./scripts/explicit-imports.jl path_to_package
```
from this directory.

Alternatively, one can use the `main` function directly:

```bash
julia -e 'using ExplicitImports: main;maini(["--print", "--checklist", "exclude_all_qualified_accesses_are_public"])'
```

On Julia v1.12+, one can use the syntax `julia -m ExplicitImports path` to run ExplicitImports on a particular path (defaulting to the current working directory). See [here](https://docs.julialang.org/en/v1.12-dev/NEWS/#Command-line-option-changes) for the `-m` flag. ExplicitImports.jl must be installed in the project you start Julia with (e.g. in your v1.12 default environment), and the target package to analyze must be installable on the same version of Julia (e.g. no out-of-date Manifest.toml present in the package environment).

For example, using [`juliaup`](https://github.com/JuliaLang/juliaup)'s `nightly` feature, one can run ExplicitImports on v1.12 as follows.

```bash
julia +nightly -m ExplicitImports --print --checklist exclude_all_qualified_accesses_are_public
```

To see all the options, use one of:

```bash
julia +nightly -m ExplicitImports --help
julia <path/to/ExplicitImports.jl>/scripts/explicit-imports.jl --help
julia -e 'using ExplicitImports: main; exit(main(["--help"]))'
```

The output should be something like:

```man
NAME
       ExplicitImports.main - analyze a package's namespace

SYNOPSIS
       julia -m ExplicitImports [OPTIONS] <path>

DESCRIPTION
       `ExplicitImports.main` (typically invoked as `julia -m ExplicitImports`)
       analyzes a package's imports and qualified accesses, and prints the results.

OPTIONS
       <path>
           Path to the root directory of the package (default: pwd)
       --help
           Show this message
       --check
           Run checks instead of printing. If --checklist is not specified, all checks are run
       --checklist <check1,check2>,...
           Run checks specified by <check1>,<check2>,...
           This will imply --check.

           Valid values for each check are:
           - Individual checks:
                 all_explicit_imports_are_public,
                 all_qualified_accesses_are_public,
                 all_explicit_imports_via_owners,
                 all_qualified_accesses_via_owners,
                 no_implicit_imports,
                 no_self_qualified_accesses,
                 no_stale_explicit_imports
           - Select all checks: all
           - Exclude a check: prepend an individual check with 'exclude_'

           The selection logic is performed in the order given.
           If you pass only exclusions, it will assume that it starts from a complete list, and then excludes.
           If you pass any individual checks, it will assume that it starts from an empty list, and then includes.
           Passing both individual and exclusion checks does not make sense.
```

## Pre-commit hooks

Another way to use ExplicitImports is with [pre-commit](https://pre-commit.com/).
Simply add the following to `.pre-commit-config.yaml`:

```yaml
- repo: https://github.com/ericphanson/ExplicitImports.jl
  rev: v1.10.0
  hooks:
    - id: explicit-imports
      args: [--print,--checklist,"exclude_all_qualified_accesses_are_public"]
```

The hook will run a selection of the tests and fail if any of them fail.

This simply invokes the `ExplicitImports.main` with the `--check` flag (see the previous section), and additional valid arguments may be passed with the `args` parameter as shown.

Note that the `--print` argument will print the explicit_imports, which might be useful for fixing the issues.
The issues are only shown if the checks fail, or if you run pre-commit with `--verbose`.

The `--checklist` argument allows you to specify which checks to run. If omitted, all checks are run.

## Limitations

### Some tricky scoping situations are not handled correctly

These can likely all be fixed by improving the code in `src/get_names_used.jl`, so they aren't inherent limitations of this approach, but since we are re-implementing Julia's scoping rules on top of the parse tree, for fully accurate results we need to handle each situation correctly, which takes a lot of work.

Known issues:

- `global` and `local` keywords are currently ignored
- `baremodule` is currently not handled
- arguments in macro definitions are not handled (may be treated incorrectly as globals)
- arguments to `let` blocks are not handled (may be treated incorrectly as globals)
- multi-argument `include` calls are ignored
- In Julia, `include` adds the included code at top-level in the module in which it is called. Here, when `include` is called within a local scope, all of the code being included is treated as being within that local scope.
- quoted code (e.g. when building Julia expressions programmatically) may be analyzed incorrectly
- default values in function definitions can be incorrectly treated as local variables ([#62](https://github.com/ericphanson/ExplicitImports.jl/issues/62))

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

However, we do at least detect this situation, so we can know which modules are affected by the missing information, and (by default) refuse to make claims about them. For example, running `print_explicit_imports` on this module gives:

```sh
julia> print_explicit_imports(MathOptInterface.Test, pkgdir(MathOptInterface))
  Module MathOptInterface.Test could not be accurately analyzed, likely due to dynamic include statements. You can pass strict=false to
  attempt to get (possibly inaccurate) results anyway.

  Module MathOptInterface.Test._BaseTest could not be accurately analyzed, likely due to dynamic include statements. You can pass
  strict=false to attempt to get (possibly inaccurate) results anyway.
```

Note here we need to pass `pkgdir(MathOptInterface)` as the second argument, as `pathof(MathOptInterface.Test) === nothing` and we would get a `FileNotFoundException`.

If we do pass `strict=false`, in this case we get

```sh
julia> print_explicit_imports(MathOptInterface.Test, pkgdir(MathOptInterface); strict=false)
  Module MathOptInterface.Test is not relying on any implicit imports.

  Module MathOptInterface.Test._BaseTest is not relying on any implicit imports.
```

However, we can't really be sure there isn't a reliance on implicit imports present in the files that we weren't able to scan (or perhaps some stale explicit imports made in those files, or perhaps usages of names explicitly imported in the files we could scan, which would prove those explicit imports are in fact not stale).

### Need to load the package/module

This implementation relies on `Base.which` to introspect which module any given name comes from, and therefore we need to load the module, not just inspect its source code. We can't solely use the source code because implicit imports are implicit -- which is part of the criticism of them in the first place, that the source file alone does not tell you where the names come from.

In particular, this means it is hard to convert implicit imports to explicit as a formatting pass, for example.

Given a running [language server](https://github.com/julia-vscode/LanguageServer.jl), however, I think it should be possible to query that for the information needed.

[^1]: An alternate implementation using an `AbstractInterpreter` (like JET does) might solve this issue (at the cost of increased complexity), and possibly get some handling of tricky scoping situations "for free".
