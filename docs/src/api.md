## API

The main entrypoint for interactive use is `print_explicit_imports`. ExplicitImports.jl API also includes several other functions to provide programmatic access to the information gathered by the package, as well as utilities to use in regression testing.

```@docs
print_explicit_imports
explicit_imports
stale_explicit_imports
explicit_imports_single
```

### Usage in testing

ExplicitImports.jl provides two functions which can be used to regression test that there is no reliance on implicit imports or stale explicit imports:

```@docs
check_no_implicit_imports
check_no_stale_explicit_imports
```
