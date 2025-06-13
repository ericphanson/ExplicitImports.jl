using TestEnv # assumed globally installed
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
TestEnv.activate()
using ExplicitImports

cd(joinpath(pkgdir(ExplicitImports), "test"))
include("runtests.jl")
