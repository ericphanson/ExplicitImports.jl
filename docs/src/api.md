# API

The main entrypoint for interactive use is [`print_explicit_imports`](@ref). ExplicitImports.jl API also includes several other functions to provide programmatic access to the information gathered by the package, as well as utilities to use in regression testing.

## Detecting implicit imports which could be made explicit

```@docs
print_explicit_imports
explicit_imports
```

## Detecting "improper" explicit imports

```@docs
improper_explicit_imports
```

## Detecting "improper" access of names from other modules

```@docs
improper_qualified_accesses
```

## Checks to use in testing

ExplicitImports.jl provides three functions which can be used to regression test that there is no reliance on implicit imports, no stale explicit imports, and no qualified accesses to names from modules other than their owner as determined by `Base.which`:

```@docs
check_no_implicit_imports
check_no_stale_explicit_imports
check_all_qualified_accesses_via_owners
check_all_explicit_imports_via_owners
check_all_explicit_imports_are_public
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
improper_qualified_accesses_nonrecursive
improper_explicit_imports_nonrecursive
```
