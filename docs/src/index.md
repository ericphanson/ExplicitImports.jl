```@meta
CurrentModule = ExplicitImports
```

```@eval
using ExplicitImports, Markdown
contents = read(joinpath(pkgdir(ExplicitImports), "README.md"), String)
contents = replace(contents, "[![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaTesting.github.io/ExplicitImports.jl/stable/)" => "")
Markdown.parse(contents)
```

## Documentation Index
```@index
```
