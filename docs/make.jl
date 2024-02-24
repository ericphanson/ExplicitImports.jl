using ExplicitImports
using Documenter

DocMeta.setdocmeta!(ExplicitImports, :DocTestSetup, :(using ExplicitImports);
                    recursive=true)

makedocs(;
         modules=[ExplicitImports],
         authors="Eric P. Hanson",
         repo="https://github.com/ericphanson/ExplicitImports.jl/blob/{commit}{path}#{line}",
         sitename="ExplicitImports.jl",
         format=Documenter.HTML(;
                                prettyurls=get(ENV, "CI", "false") == "true",
                                canonical="https://ericphanson.github.io/ExplicitImports.jl",
                                edit_link="main",
                                assets=String[],),
         pages=["Home" => "index.md"],)

deploydocs(;
           repo="github.com/ericphanson/ExplicitImports.jl",
           devbranch="main",)
