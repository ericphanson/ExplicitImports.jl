# Internal details

## Implementation strategy

1. [DONE hackily] Figure out what names used in the module are being used to refer to bindings in global scope (as opposed to e.g. shadowing globals).
   - We do this by parsing the code (thanks to JuliaSyntax), then reimplementing scoping rules on top of the parse tree
   - This is finicky, but assuming scoping doesn't change, should be robust enough (once the long tail of edge cases are dealt with...)
     - Currently, I don't handle the `global` keyword, so those may look like local variables and confuse things
   - This means we need access to the raw source code; `pathof` works well for packages, but for local modules one has to pass the path themselves. Also doesn't seem to work well for stdlibs in the sysimage
2. [DONE] Figure out what implicit imports are available in the module, and which module they come from
    * done, via a magic `ccall` from Discourse, and `Base.which`.
3. [DONE] Figure out which names have been explicitly imported already
   - Done via parsing

Then we can put this information together to figure out what names are actually being used from other modules, and whose usage could be made explicit, and also which existing explicit imports are not being used.

## Internals

```@docs
ExplicitImports.find_implicit_imports
ExplicitImports.get_names_used
ExplicitImports.analyze_all_names
ExplicitImports.inspect_session
ExplicitImports.FileAnalysis
```
