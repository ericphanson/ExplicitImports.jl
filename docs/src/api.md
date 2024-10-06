# API

The standard entrypoint for interactive use is [`print_explicit_imports`](@ref). ExplicitImports.jl API also includes several other functions to provide programmatic access to the information gathered by the package, as well as utilities to use in regression testing.

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

ExplicitImports.jl provides several functions (all starting with `check_`) which introspect a module for various kinds of potential issues, and throws errors if these issues are encountered. These "check" functions are designed to be narrowly scoped to detect one specific type of issue, and stable so that they can be used in testing environments (with the aim that non-breaking releases of ExplicitExports.jl will generally not cause new test failures).

The first such check is [`check_no_implicit_imports`](@ref) which aims to ensure there are no implicit exports used in the package.

```@docs
check_no_implicit_imports
```

Next, we have several checks related to detecting "improper" explicit imports. The function [`check_no_stale_explicit_imports`](@ref) checks that a module has no "stale" (unused) explicit imports. Next [`check_all_explicit_imports_via_owners`](@ref) and [`check_all_explicit_imports_are_public`](@ref) provide related checks. [`check_all_explicit_imports_via_owners`](@ref) is a weaker check which errors for particularly problematic imports of non-public names, namely those for which the module they are being imported from does not "own" the name (since it was not defined there). The typical scenario here is that the name may be public in some other module, but just happens to be present in the namespace of that module (consider `using LinearAlgebra: map` which imports Base's `map` function). Next, [`check_all_explicit_imports_are_public`](@ref) provides a stricter check that all names being explicitly imported are in fact public in the module they are being imported from, whether or not they are "owned" by that module.

```@docs
check_no_stale_explicit_imports
check_all_explicit_imports_via_owners
check_all_explicit_imports_are_public
```

Lastly, we have two checks related to detecting "improper" qualified accesses to names, which are analogous to checks related to improper explicit imports.  [`check_all_qualified_accesses_via_owners`](@ref) checks that all qualified accesses (e.g. usage of names in the form `Foo.bar`) are such that the name being accessed is "owned" by the module it is being accessed from (just like [`check_all_explicit_imports_via_owners`](@ref)). This would detect, e.g., `LinearAlgebra.map`. Likewise, [`check_all_qualified_accesses_are_public`](@ref) is a stricter check which verifies all qualified accesses to names are via modules in which that name is public. Additionally, [`check_no_self_qualified_accesses`](@ref) checks there are no self-qualified accesses, like accessing `Foo.foo` from within the module `Foo`.

```@docs
check_all_qualified_accesses_via_owners
check_all_qualified_accesses_are_public
check_no_self_qualified_accesses
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
