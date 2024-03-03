# API

The main entrypoint for interactive use is [`print_explicit_imports`](@ref). ExplicitImports.jl API also includes several other functions to provide programmatic access to the information gathered by the package, as well as utilities to use in regression testing.

## Detecting implicit imports which could be made explicit

```@docs
print_explicit_imports
explicit_imports
```

## Looking just for stale explicit exports

While [`print_explicit_imports`](@ref) prints stale explicit exports, and [`explicit_imports`](@ref) by default provides a warning when stale explicit exports are present, sometimes one wants to only look for stale explicit imports without looking at implicit imports. Here we provide some entrypoints that help for this use-case.

```@docs
print_stale_explicit_imports
stale_explicit_imports
```

## Checks to use in testing

ExplicitImports.jl provides two functions which can be used to regression test that there is no reliance on implicit imports or stale explicit imports:

```@docs
check_no_implicit_imports
check_no_stale_explicit_imports
```

## Usage with scripts (such as `runtests.jl`)

We also provide a helper function to analyze scripts (rather than modules).
If you are using a module in your script (e.g. if your script starts with `module`),
then use the ordinary `print_explicit_imports` function instead.
This functionality is somewhat experimental and attempts to filter the relevant names in `Main`
to those used in your script.

```@docs
print_explicit_imports_script
```

## Non-recursive variants

The above functions all recurse through submodules of the provided module, providing information about each. Here, we provide non-recursive variants (which in fact power the recursive ones), in case it is useful, perhaps for building other tooling on top of ExplicitImports.jl.

```@docs
explicit_imports_nonrecursive
stale_explicit_imports_nonrecursive
```
