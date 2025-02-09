var documenterSearchIndex = {"docs":
[{"location":"api/#API","page":"API reference","title":"API","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"The main entrypoint for interactive use is print_explicit_imports. ExplicitImports.jl API also includes several other functions to provide programmatic access to the information gathered by the package, as well as utilities to use in regression testing.","category":"page"},{"location":"api/#Detecting-implicit-imports-which-could-be-made-explicit","page":"API reference","title":"Detecting implicit imports which could be made explicit","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"print_explicit_imports\nexplicit_imports","category":"page"},{"location":"api/#ExplicitImports.print_explicit_imports","page":"API reference","title":"ExplicitImports.print_explicit_imports","text":"print_explicit_imports([io::IO=stdout,] mod::Module, file=pathof(mod); skip=(mod, Base, Core), warn_stale=true,\n                       warn_improper_qualified_accesses=true, strict=true)\n\nRuns explicit_imports and prints the results, along with those of stale_explicit_imports and improper_qualified_accesses.\n\nNote that the particular printing may change in future non-breaking releases of ExplicitImports.\n\nKeyword arguments\n\nskip=(mod, Base, Core): any names coming from the listed modules (or any submodules thereof) will be skipped. Since mod is included by default, implicit imports of names exported from its own submodules will not count by default.\nwarn_stale=true: if set, this function will also print information about stale explicit imports.\nwarn_improper_qualified_accesses=true: if set, this function will also print information about any \"improper\" qualified accesses to names from other modules.\nstrict=true: when strict is set, a module will be noted as unanalyzable in the case that the analysis could not be performed accurately, due to e.g. dynamic include statements. When strict=false, results are returned in all cases, but may be inaccurate.\nshow_locations=false: whether or not to print locations of where the names are being used (and, if warn_stale=true, where the stale explicit imports are).\nlinewidth=80: format into lines of up to this length. Set to 0 to indicate one name should be printed per line.\n\nSee also check_no_implicit_imports, check_no_stale_explicit_imports, and check_all_qualified_accesses_via_owners.\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.explicit_imports","page":"API reference","title":"ExplicitImports.explicit_imports","text":"explicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core), warn_stale=true, strict=true)\n\nReturns a nested structure providing information about explicit import statements one could make for each submodule of mod. This information is structured as a collection of pairs, where the keys are the submodules of mod (including mod itself), and the values are NamedTuples, with at least the keys name, source, exporters, and location, showing which names are being used implicitly, which modules they were defined in, which modules they were exported from, and the location of those usages. Additional keys may be added to the NamedTuple's in the future in non-breaking releases of ExplicitImports.jl.\n\nArguments\n\nmod::Module: the module to (recursively) analyze. Often this is a package.\nfile=pathof(mod): this should be a path to the source code that contains the module mod.\nif mod is the top-level module of a package, pathof will be unable to find the code, and a file must be passed which contains mod (either directly or indirectly through includes)\nmod can be a submodule defined within file, but if two modules have the same name (e.g. X.Y.X and X), results may be inaccurate.\n\nKeyword arguments\n\nskip=(mod, Base, Core): any names coming from the listed modules (or any submodules thereof) will be skipped. Since mod is included by default, implicit imports of names exported from its own submodules will not count by default.\nwarn_stale=true: whether or not to warn about stale explicit imports.\nstrict=true: when strict is set, results for a module will be nothing in the case that the analysis could not be performed accurately, due to e.g. dynamic include statements. When strict=false, results are returned in all cases, but may be inaccurate.\n\nnote: Note\nIf mod is a package, we can detect the explicit_imports in the package extensions if those extensions are explicitly loaded before calling this function.For example, consider PackageA has a weak-dependency on PackageB and PackageC in the module PkgBPkgCExtjulia> using ExplicitImports, PackageA\n\njulia> explicit_imports(PackageA) # Only checks for explicit imports in PackageA and its submodules but not in `PkgBPkgCExt`To check for explicit imports in PkgBPkgCExt, you can do the following:julia> using ExplicitImports, PackageA, PackageB, PackageC\n\njulia> explicit_imports(PackageA) # Now checks for explicit imports in PackageA and its submodules and also in `PkgBPkgCExt`\n\nSee also print_explicit_imports to easily compute and print these results, explicit_imports_nonrecursive for a non-recursive version which ignores submodules, and  check_no_implicit_imports for a version that throws errors, for regression testing.\n\n\n\n\n\n","category":"function"},{"location":"api/#Looking-just-for-stale-explicit-exports","page":"API reference","title":"Looking just for stale explicit exports","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"While print_explicit_imports prints stale explicit exports, and explicit_imports by default provides a warning when stale explicit exports are present, sometimes one wants to only look for stale explicit imports without looking at implicit imports. Here we provide some entrypoints that help for this use-case.","category":"page"},{"location":"api/","page":"API reference","title":"API reference","text":"print_stale_explicit_imports\nstale_explicit_imports","category":"page"},{"location":"api/#ExplicitImports.print_stale_explicit_imports","page":"API reference","title":"ExplicitImports.print_stale_explicit_imports","text":"print_stale_explicit_imports([io::IO=stdout,] mod::Module, file=pathof(mod); strict=true, show_locations=false)\n\nRuns stale_explicit_imports and prints the results.\n\nNote that the particular printing may change in future non-breaking releases of ExplicitImports.\n\nKeyword arguments\n\nstrict=true: when strict is set, a module will be noted as unanalyzable in the case that the analysis could not be performed accurately, due to e.g. dynamic include statements. When strict=false, results are returned in all cases, but may be inaccurate.\nshow_locations=false: whether or not to print where the explicit imports were made. If the same name was explicitly imported more than once, it will only show one such import.\n\nSee also print_explicit_imports and check_no_stale_explicit_imports.\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.stale_explicit_imports","page":"API reference","title":"ExplicitImports.stale_explicit_imports","text":"stale_explicit_imports(mod::Module, file=pathof(mod); strict=true)\n\nReturns a collection of pairs, where the keys are submodules of mod (including mod itself), and the values are either nothing if strict=true and the module couldn't analyzed, or else a vector of NamedTuples with at least the keys name and location, consisting of names that are explicitly imported in that submodule, but which either are not used, or are only used in a qualified fashion, making the explicit import a priori unnecessary.\n\nMore keys may be added to the NamedTuples in the future in non-breaking releases of ExplicitImports.jl.\n\nwarning: Warning\nNote that it is possible for an import from a module (say X) into one module (say A) to be relied on from another unrelated module (say B). For example, if A contains the code using X: x, but either does not use x at all or only uses x in the form X.x, then x will be flagged as a stale explicit import by this function. However, it could be that the code in some unrelated module B uses A.x or using A: x, relying on the fact that x has been imported into A's namespace.This is an unusual situation (generally B should just get x directly from X, rather than indirectly via A), but there are situations in which it arises, so one may need to be careful about naively removing all \"stale\" explicit imports flagged by this function.Running improper_qualified_accesses on downstream code can help identify such \"improper\" accesses to names via modules other than their owner.\n\nKeyword arguments\n\nstrict=true: when strict is set, results for a module will be nothing in the case that the analysis could not be performed accurately, due to e.g. dynamic include statements. When strict=false, results are returned in all cases, but may be inaccurate.\n\nSee stale_explicit_imports_nonrecursive for a non-recursive version, and check_no_stale_explicit_imports for a version that throws an error when encountering stale explicit imports.\n\nSee also print_explicit_imports which prints this information.\n\n\n\n\n\n","category":"function"},{"location":"api/#Detecting-\"improper\"-access-of-names-from-other-modules","page":"API reference","title":"Detecting \"improper\" access of names from other modules","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"improper_qualified_accesses\nprint_improper_qualified_accesses\nimproper_qualified_accesses_nonrecursive","category":"page"},{"location":"api/#ExplicitImports.improper_qualified_accesses","page":"API reference","title":"ExplicitImports.improper_qualified_accesses","text":"improper_qualified_accesses(mod::Module, file=pathof(mod); skip=(Base => Core,),\n                            require_submodule_access)\n\nAttempts do detect various kinds of \"improper\" qualified accesses taking place in mod and any submodules of mod.\n\nCurrently, only detects cases in which the name is being accessed from a module mod which:\n\nname is not exported from mod\nname is not declared public in mod (requires Julia v1.11+)\nname is not \"owned\" by mod. This is determined by calling owner = Base.which(mod, name) to obtain the module the name was defined in. If require_submodule_access=true, then mod must be exactly owner to not be considered \"improper\" access. Otherwise (the default), mod is allowed to be a module which contains owner.\n\nThe keyword argument skip is expected to be an iterator of accessing_from => parent pairs, where names which are accessed from accessing_from but whose parent is parent are ignored. By default, accesses from Base to names owned by Core are skipped.\n\nThis functionality is still in development, so the exact results may change in future non-breaking releases. Read on for the current outputs, what may change, and what will not change (without a breaking release of ExplicitImports.jl).\n\nReturns a nested structure providing information about improper accesses to names in other modules. This information is structured as a collection of pairs, where the keys are the submodules of mod (including mod itself). Currently, the values are a Vector of NamedTuples with the following keys:\n\nname::Symbol: the name being accessed\nlocation::String: the location the access takes place\naccessing_from::Module: the module the name is being accessed from (e.g. Module.name)\nwhichmodule::Module: the Base.which of the object\npublic_access::Bool: whether or not name is public or exported in accessing_from. Checking if a name is marked public requires Julia v1.11+.\n\nIn non-breaking releases of ExplicitImports:\n\nmore columns may be added to these rows\nadditional rows may be returned which qualify as some other kind of \"improper\" access\n\nHowever, the result will be a Tables.jl-compatible row-oriented table (for each module), with at least all of the same columns.\n\nSee also print_improper_qualified_accesses to easily compute and print these results, improper_qualified_accesses_nonrecursive for a non-recursive version which ignores submodules, and  check_all_qualified_accesses_via_owners for a version that throws errors, for regression testing.\n\nExample\n\njulia> using ExplicitImports\n\njulia> example_path = pkgdir(ExplicitImports, \"examples\", \"qualified.jl\");\n\njulia> print(read(example_path, String))\nmodule MyMod\nusing LinearAlgebra\n# sum is in `Base`, so we shouldn't access it from LinearAlgebra:\nn = LinearAlgebra.sum([1, 2, 3])\nend\n\njulia> include(example_path);\n\njulia> row = improper_qualified_accesses(MyMod, example_path)[1][2][1];\n\njulia> (; row.name, row.accessing_from, row.whichmodule)\n(name = :sum, accessing_from = LinearAlgebra, whichmodule = Base)\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.print_improper_qualified_accesses","page":"API reference","title":"ExplicitImports.print_improper_qualified_accesses","text":"print_improper_qualified_accesses([io::IO=stdout,] mod::Module, file=pathof(mod))\n\nRuns improper_qualified_accesses and prints the results.\n\nNote that the particular printing may change in future non-breaking releases of ExplicitImports.\n\nSee also print_explicit_imports and check_all_qualified_accesses_via_owners.\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.improper_qualified_accesses_nonrecursive","page":"API reference","title":"ExplicitImports.improper_qualified_accesses_nonrecursive","text":"improper_qualified_accesses_nonrecursive(mod::Module, file=pathof(mod); skip=(Base => Core,))\n\nA non-recursive version of improper_qualified_accesses, meaning it only analyzes the module mod itself, not any of its submodules; see that function for details, including important caveats about stability (outputs may grow in future non-breaking releases of ExplicitImports!).\n\nExample\n\njulia> using ExplicitImports\n\njulia> example_path = pkgdir(ExplicitImports, \"examples\", \"qualified.jl\");\n\njulia> print(read(example_path, String))\nmodule MyMod\nusing LinearAlgebra\n# sum is in `Base`, so we shouldn't access it from LinearAlgebra:\nn = LinearAlgebra.sum([1, 2, 3])\nend\n\njulia> include(example_path);\n\njulia> row = improper_qualified_accesses_nonrecursive(MyMod, example_path)[1];\n\njulia> (; row.name, row.accessing_from, row.whichmodule)\n(name = :sum, accessing_from = LinearAlgebra, whichmodule = Base)\n\n\n\n\n\n","category":"function"},{"location":"api/#Checks-to-use-in-testing","page":"API reference","title":"Checks to use in testing","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"ExplicitImports.jl provides three functions which can be used to regression test that there is no reliance on implicit imports, no stale explicit imports, and no qualified accesses to names from modules other than their owner as determined by Base.which:","category":"page"},{"location":"api/","page":"API reference","title":"API reference","text":"check_no_implicit_imports\ncheck_no_stale_explicit_imports\ncheck_all_qualified_accesses_via_owners","category":"page"},{"location":"api/#ExplicitImports.check_no_implicit_imports","page":"API reference","title":"ExplicitImports.check_no_implicit_imports","text":"check_no_implicit_imports(mod::Module, file=pathof(mod); skip=(mod, Base, Core), ignore::Tuple=(), allow_unanalyzable::Tuple=())\n\nChecks that neither mod nor any of its submodules is relying on implicit imports, throwing an ImplicitImportsException if so, and returning nothing otherwise.\n\nThis function can be used in a package's tests, e.g.\n\n@test check_no_implicit_imports(MyPackage) === nothing\n\nAllowing some submodules to be unanalyzable\n\nPass allow_unanalyzable as a tuple of submodules which are allowed to be unanalyzable. Any other submodules found to be unanalyzable will result in an UnanalyzableModuleException being thrown.\n\nThese unanalyzable submodules can alternatively be included in ignore.\n\nAllowing some implicit imports\n\nThe skip keyword argument can be passed to allow implicit imports from some modules (and their submodules). By default, skip is set to (Base, Core). For example:\n\n@test check_no_implicit_imports(MyPackage; skip=(Base, Core, DataFrames)) === nothing\n\nwould verify there are no implicit imports from modules other than Base, Core, and DataFrames.\n\nAdditionally, the keyword ignore can be passed to represent a tuple of items to ignore. These can be:\n\nmodules. Any submodule of mod matching an element of ignore is skipped. This can be used to allow the usage of implicit imports in some submodule of your package.\nsymbols: any implicit import of a name matching an element of ignore is ignored (does not throw)\nsymbol => module pairs. Any implicit import of a name matching that symbol from a module matching the module is ignored.\n\nOne can mix and match between these type of ignored elements. For example:\n\n@test check_no_implicit_imports(MyPackage; ignore=(:DataFrame => DataFrames, :ByRow, MySubModule)) === nothing\n\nThis would:\n\nIgnore any implicit import of DataFrame from DataFrames\nIgnore any implicit import of the name ByRow from any module.\nIgnore any implicit imports present in MyPackage's submodule MySubModule\n\nbut verify there are no other implicit imports.\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.check_no_stale_explicit_imports","page":"API reference","title":"ExplicitImports.check_no_stale_explicit_imports","text":"check_no_stale_explicit_imports(mod::Module, file=pathof(mod); ignore::Tuple=(), allow_unanalyzable::Tuple=())\n\nChecks that neither mod nor any of its submodules has stale (unused) explicit imports, throwing an StaleImportsException if so, and returning nothing otherwise.\n\nThis can be used in a package's tests, e.g.\n\n@test check_no_stale_explicit_imports(MyPackage) === nothing\n\nAllowing some submodules to be unanalyzable\n\nPass allow_unanalyzable as a tuple of submodules which are allowed to be unanalyzable. Any other submodules found to be unanalyzable will result in an UnanalyzableModuleException being thrown.\n\nAllowing some stale explicit imports\n\nIf ignore is supplied, it should be a tuple of Symbols, representing names that are allowed to be stale explicit imports. For example,\n\n@test check_no_stale_explicit_imports(MyPackage; ignore=(:DataFrame,)) === nothing\n\nwould check there were no stale explicit imports besides that of the name DataFrame.\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.check_all_qualified_accesses_via_owners","page":"API reference","title":"ExplicitImports.check_all_qualified_accesses_via_owners","text":"check_all_qualified_accesses_via_owners(mod::Module, file=pathof(mod); ignore::Tuple=(), require_submodule_access=false)\n\nChecks that neither mod nor any of its submodules has accesses to names via modules other than their owner as determined by Base.which (unless the name is public or exported in that module), throwing an QualifiedAccessesFromNonOwnerException if so, and returning nothing otherwise.\n\nThis can be used in a package's tests, e.g.\n\n@test check_all_qualified_accesses_via_owners(MyPackage) === nothing\n\nAllowing some qualified accesses via non-owner modules\n\nIf ignore is supplied, it should be a tuple of Symbols, representing names that are allowed to be accessed from non-owner modules. For example,\n\n@test check_all_qualified_accesses_via_owners(MyPackage; ignore=(:DataFrame,)) === nothing\n\nwould check there were no qualified accesses from non-owner modules besides that of the name DataFrame.\n\nSee also: improper_qualified_accesses, which also describes the meaning of the keyword argument require_submodule_access. Note that while that function may increase in scope and report other kinds of improper accesses, check_all_qualified_accesses_via_owners will not.\n\n\n\n\n\n","category":"function"},{"location":"api/#Usage-with-scripts-(such-as-runtests.jl)","page":"API reference","title":"Usage with scripts (such as runtests.jl)","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"We also provide a helper function to analyze scripts (rather than modules). If you are using a module in your script (e.g. if your script starts with module), then use the ordinary print_explicit_imports function instead. This functionality is somewhat experimental and attempts to filter the relevant names in Main to those used in your script.","category":"page"},{"location":"api/","page":"API reference","title":"API reference","text":"print_explicit_imports_script","category":"page"},{"location":"api/#ExplicitImports.print_explicit_imports_script","page":"API reference","title":"ExplicitImports.print_explicit_imports_script","text":"print_explicit_imports_script([io::IO=stdout,] path; skip=(Base, Core), warn_stale=true)\n\nAnalyzes the script located at path and prints information about reliance on implicit exports as well as any stale explicit imports (if warn_stale=true).\n\nNote that the particular printing may change in future non-breaking releases of ExplicitImports.\n\nwarning: Warning\n\n\nThe script (or at least, all imports in the script) must be run before this function can give reliable results, since it relies on introspecting what names are present in Main.\n\nKeyword arguments\n\nskip=(mod, Base, Core): any names coming from the listed modules (or any submodules thereof) will be skipped. Since mod is included by default, implicit imports of names exported from its own submodules will not count by default.\nwarn_stale=true: if set, this function will also print information about stale explicit imports.\n\n\n\n\n\n","category":"function"},{"location":"api/#Non-recursive-variants","page":"API reference","title":"Non-recursive variants","text":"","category":"section"},{"location":"api/","page":"API reference","title":"API reference","text":"The above functions all recurse through submodules of the provided module, providing information about each. Here, we provide non-recursive variants (which in fact power the recursive ones), in case it is useful, perhaps for building other tooling on top of ExplicitImports.jl.","category":"page"},{"location":"api/","page":"API reference","title":"API reference","text":"explicit_imports_nonrecursive\nstale_explicit_imports_nonrecursive","category":"page"},{"location":"api/#ExplicitImports.explicit_imports_nonrecursive","page":"API reference","title":"ExplicitImports.explicit_imports_nonrecursive","text":"explicit_imports_nonrecursive(mod::Module, file=pathof(mod); skip=(mod, Base, Core), warn_stale=true, strict=true)\n\nA non-recursive version of explicit_imports, meaning it only analyzes the module mod itself, not any of its submodules; see that function for details.\n\nKeyword arguments\n\nskip=(mod, Base, Core): any names coming from the listed modules (or any submodules thereof) will be skipped. Since mod is included by default, implicit imports of names exported from its own submodules will not count by default.\nwarn_stale=true: whether or not to warn about stale explicit imports.\nstrict=true: when strict=true, results will be nothing in the case that the analysis could not be performed accurately, due to e.g. dynamic include statements. When strict=false, results are returned in all cases, but may be inaccurate.\n\n\n\n\n\n","category":"function"},{"location":"api/#ExplicitImports.stale_explicit_imports_nonrecursive","page":"API reference","title":"ExplicitImports.stale_explicit_imports_nonrecursive","text":"stale_explicit_imports_nonrecursive(mod::Module, file=pathof(mod); strict=true)\n\nA non-recursive version of stale_explicit_imports, meaning it only analyzes the module mod itself, not any of its submodules.\n\nIf mod was unanalyzable and strict=true, returns nothing. Otherwise, returns a collection of NamedTuple's, with at least the keys name and location, corresponding to the names of stale explicit imports. More keys may be added in the future in non-breaking releases of ExplicitImports.jl.\n\nKeyword arguments\n\nstrict=true: when strict=true, results will be nothing in the case that the analysis could not be performed accurately, due to e.g. dynamic include statements. When strict=false, results are returned in all cases, but may be inaccurate.\n\nSee also print_explicit_imports and check_no_stale_explicit_imports, both of which do recurse through submodules.\n\n\n\n\n\n","category":"function"},{"location":"","page":"Home","title":"Home","text":"CurrentModule = ExplicitImports","category":"page"},{"location":"","page":"Home","title":"Home","text":"using ExplicitImports, Markdown\ncontents = read(joinpath(pkgdir(ExplicitImports), \"README.md\"), String)\ncontents = replace(contents, \"[![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/stable/)\" => \"\")\nMarkdown.parse(contents)","category":"page"},{"location":"#Documentation-Index","page":"Home","title":"Documentation Index","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"internals/#Internal-details","page":"Dev docs","title":"Internal details","text":"","category":"section"},{"location":"internals/#Implementation-strategy","page":"Dev docs","title":"Implementation strategy","text":"","category":"section"},{"location":"internals/","page":"Dev docs","title":"Dev docs","text":"[DONE hackily] Figure out what names used in the module are being used to refer to bindings in global scope (as opposed to e.g. shadowing globals).\nWe do this by parsing the code (thanks to JuliaSyntax), then reimplementing scoping rules on top of the parse tree\nThis is finicky, but assuming scoping doesn't change, should be robust enough (once the long tail of edge cases are dealt with...)\nCurrently, I don't handle the global keyword, so those may look like local variables and confuse things\nThis means we need access to the raw source code; pathof works well for packages, but for local modules one has to pass the path themselves. Also doesn't seem to work well for stdlibs in the sysimage\n[DONE] Figure out what implicit imports are available in the module, and which module they come from\ndone, via a magic ccall from Discourse, and Base.which.\n[DONE] Figure out which names have been explicitly imported already\nDone via parsing","category":"page"},{"location":"internals/","page":"Dev docs","title":"Dev docs","text":"Then we can put this information together to figure out what names are actually being used from other modules, and whose usage could be made explicit, and also which existing explicit imports are not being used.","category":"page"},{"location":"internals/#Internals","page":"Dev docs","title":"Internals","text":"","category":"section"},{"location":"internals/","page":"Dev docs","title":"Dev docs","text":"ExplicitImports.find_implicit_imports\nExplicitImports.get_names_used\nExplicitImports.analyze_all_names\nExplicitImports.inspect_session\nExplicitImports.FileAnalysis","category":"page"},{"location":"internals/#ExplicitImports.find_implicit_imports","page":"Dev docs","title":"ExplicitImports.find_implicit_imports","text":"find_implicit_imports(mod::Module; skip=(mod, Base, Core))\n\nGiven a module mod, returns a Dict{Symbol, @NamedTuple{source::Module,exporters::Vector{Module}}} showing names exist in mod's namespace which are available due to implicit exports by other modules. The dict's keys are those names, and the values are the source module that the name comes from, along with the modules which export the same binding that are available in mod due to implicit imports.\n\nIn the case of ambiguities (two modules exporting the same name), the name is unavailable in the module, and hence the name will not be present in the dict.\n\nThis is powered by Base.which.\n\n\n\n\n\n","category":"function"},{"location":"internals/#ExplicitImports.get_names_used","page":"Dev docs","title":"ExplicitImports.get_names_used","text":"get_names_used(file) -> FileAnalysis\n\nFigures out which global names are used in file, and what modules they are used within.\n\nTraverses static include statements.\n\nReturns a FileAnalysis object.\n\n\n\n\n\n","category":"function"},{"location":"internals/#ExplicitImports.analyze_all_names","page":"Dev docs","title":"ExplicitImports.analyze_all_names","text":"analyze_all_names(file)\n\nReturns a tuple of two items:\n\nper_usage_info: a table containing information about each name each time it was used\nuntainted_modules: a set containing modules found and analyzed successfully\n\n\n\n\n\n","category":"function"},{"location":"internals/#ExplicitImports.inspect_session","page":"Dev docs","title":"ExplicitImports.inspect_session","text":"ExplicitImports.inspect_session([io::IO=stdout,]; skip=(Base, Core), inner=print_explicit_imports)\n\nExperimental functionality to call inner (defaulting to print_explicit_imports) on each loaded package in the Julia session.\n\n\n\n\n\n","category":"function"},{"location":"internals/#ExplicitImports.FileAnalysis","page":"Dev docs","title":"ExplicitImports.FileAnalysis","text":"FileAnalysis\n\nContains structured analysis results.\n\nFields\n\nperusageinfo::Vector{PerUsageInfo}\nneeds_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},   location::String}}\nunnecessary_explicit_import::Set{@NamedTuple{name::Symbol,module_path::Vector{Symbol},         location::String}}\nuntainted_modules::Set{Vector{Symbol}}: those which were analyzed and do not contain an unanalyzable include\n\n\n\n\n\n","category":"type"}]
}
