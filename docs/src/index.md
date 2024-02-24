```@meta
CurrentModule = ExplicitImports
```

```@eval
using ExplicitImports, Markdown
contents = read(joinpath(pkgdir(ExplicitImports), "README.md"), String)
contents = replace(contents, "[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://ericphanson.github.io/ExplicitImports.jl/dev/)" => "")
Markdown.parse(contents)
```

## Documentation Index
```@index
```
