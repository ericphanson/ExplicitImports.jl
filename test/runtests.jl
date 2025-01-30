using Pkg
Pkg.develop(; path=joinpath(@__DIR__, "TestPkg"))
Pkg.precompile()
using ExplicitImports
using ExplicitImports: analyze_all_names, has_ancestor, should_skip,
                       module_path, explicit_imports_nonrecursive,
                       inspect_session, get_parent, choose_exporter,
                       get_import_lhs, analyze_import_type,
                       analyze_explicitly_imported_names, owner_mod_for_printing,
                       get_names_used
using Test
using DataFrames
using Aqua
using Logging, UUIDs
using AbstractTrees
using ExplicitImports: is_function_definition_arg, SyntaxNodeWrapper, get_val
using ExplicitImports: is_struct_type_param, is_struct_field_name, is_for_arg,
                       is_generator_arg, analyze_qualified_names
using TestPkg, Markdown

function exception_string(f)
    str = try
        f()
        false
    catch e
        sprint(showerror, e)
    end
    @test str isa String
    return str
end

# DataFrames version of `filter_to_module`
function restrict_to_module(df, mod)
    mod_path = module_path(mod)
    return subset(df,
                  :module_path => ByRow(ms -> all(Base.splat(isequal), zip(ms, mod_path))))
end

# old definition for simple 1-line using statement
# (now we do linelength aware printing)
function using_statement(row)
    name = row.name
    exporters = row.exporters
    # skip `Main.X`, just do `.X`
    e = choose_exporter(name, exporters)
    v = replace(string(e), "Main" => "")
    return "using $v: $name"
end

function only_name_source(nt::@NamedTuple{name::Symbol,source::Module,
                                          exporters::Vector{Module},location::String})
    @test !isempty(nt.exporters)
    return (; nt.name, nt.source)
end

function only_name_source(nt::@NamedTuple{name::Symbol,location::String})
    return (; nt.name)
end
only_name_source(::Nothing) = nothing
only_name_source(v::Vector) = only_name_source.(v)
only_name_source(p::Pair) = first(p) => only_name_source(last(p))

include("public_compat.jl")
include("Exporter.jl")
include("TestModA.jl")
include("test_mods.jl")
include("DynMod.jl")
include("TestModArgs.jl")
include("examples.jl")
include("script.jl")
include("imports.jl")
include("test_qualified_access.jl")
include("test_explicit_imports.jl")
include("main.jl")

# For deprecations, we are using `maxlog`, which
# the TestLogger only respects in Julia 1.8+.
# (https://github.com/JuliaLang/julia/commit/02f7332027bd542b0701956a0f838bc75fa2eebd)
if VERSION >= v"1.8-"
    @testset "deprecations" begin
        include("deprecated.jl")
    end
end

# package extension support needs Julia 1.9+
if VERSION > v"1.9-"
    @testset "Extensions" begin
        submods = ExplicitImports.find_submodules(TestPkg)
        @test length(submods) == 2
        DataFramesExt = Base.get_extension(TestPkg, :DataFramesExt)
        @test haskey(Dict(submods), DataFramesExt)

        ext_imports = Dict(only_name_source(explicit_imports(TestPkg)))[DataFramesExt]
        @test ext_imports == [(; name=:DataFrames, source=DataFrames),
                              (; name=:DataFrame, source=DataFrames),
                              (; name=:groupby, source=DataFrames)] ||
              ext_imports == [(; name=:DataFrames, source=DataFrames),
                              (; name=:DataFrame, source=DataFrames),
                              (; name=:groupby, source=DataFrames.DataAPI)]
    end
end

@testset "function arg bug" begin
    # https://github.com/ericphanson/ExplicitImports.jl/issues/62
    df = DataFrame(get_names_used("test_mods.jl").per_usage_info)
    subset!(df, :name => ByRow(==(:norm)), :module_path => ByRow(==([:TestMod13])))

    @test_broken check_no_stale_explicit_imports(TestMod13, "test_mods.jl") === nothing
end

@testset "owner_mod_for_printing" begin
    @test owner_mod_for_printing(Core, :throw, Core.throw) == Base
    @test owner_mod_for_printing(Core, :println, Core.println) == Core
end

# https://github.com/ericphanson/ExplicitImports.jl/issues/69
@testset "Reexport support" begin
    @test check_no_stale_explicit_imports(TestMod15, "test_mods.jl") === nothing
    @test isempty(improper_explicit_imports_nonrecursive(TestMod15, "test_mods.jl"))
    @test isempty(improper_explicit_imports(TestMod15, "test_mods.jl")[1][2])
end

if VERSION >= v"1.7-"
    # https://github.com/ericphanson/ExplicitImports.jl/issues/70
    @testset "Compat skipping" begin
        @test check_all_explicit_imports_via_owners(TestMod14, "test_mods.jl") === nothing
        @test check_all_qualified_accesses_via_owners(TestMod14, "test_mods.jl") === nothing

        @test isempty(improper_explicit_imports_nonrecursive(TestMod14, "test_mods.jl"))
        @test isempty(improper_explicit_imports(TestMod14, "test_mods.jl")[1][2])

        @test isempty(improper_qualified_accesses_nonrecursive(TestMod14, "test_mods.jl"))

        @test isempty(improper_qualified_accesses(TestMod14, "test_mods.jl")[1][2])
    end
end

@testset "imports" begin
    cursor = TreeCursor(SyntaxNodeWrapper("imports.jl"))
    leaves = collect(Leaves(cursor))
    import_type_pairs = get_val.(leaves) .=> analyze_import_type.(leaves)
    filter!(import_type_pairs) do (k, v)
        return v !== :not_import
    end
    @test import_type_pairs ==
          [:Exporter => :import_LHS,
           :exported_a => :import_RHS,
           :exported_c => :import_RHS,
           :Exporter => :import_LHS,
           :exported_c => :import_RHS,
           :TestModA => :blanket_using_member,
           :SubModB => :blanket_using,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :h2 => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :h3 => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :h => :import_RHS,
           :Exporter => :blanket_using,
           :Exporter => :plain_import,
           :LinearAlgebra => :import_LHS,
           :map => :import_RHS,
           :_svd! => :import_RHS,
           :LinearAlgebra => :import_LHS,
           :svd => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :exported_b => :import_RHS,
           :TestModA => :import_LHS,
           :SubModB => :import_LHS,
           :f => :import_RHS]

    inds = findall(==(:import_RHS), analyze_import_type.(leaves))
    lhs_rhs_pairs = get_import_lhs.(leaves[inds]) .=> get_val.(leaves[inds])
    @test lhs_rhs_pairs == [[:., :., :Exporter] => :exported_a,
                            [:., :., :Exporter] => :exported_c,
                            [:., :., :Exporter] => :exported_c,
                            [:., :., :TestModA, :SubModB] => :h2,
                            [:., :., :TestModA, :SubModB] => :h3,
                            [:., :., :TestModA, :SubModB] => :h,
                            [:LinearAlgebra] => :map,
                            [:LinearAlgebra] => :_svd!,
                            [:LinearAlgebra] => :svd,
                            [:., :., :TestModA, :SubModB] => :exported_b,
                            [:., :., :TestModA, :SubModB] => :f]

    imps = DataFrame(improper_explicit_imports_nonrecursive(ModImports, "imports.jl";
                                                            allow_internal_imports=false))
    h_row = only(subset(imps, :name => ByRow(==(:h))))
    @test !h_row.public_import
    # Note: if this fails locally, try `include("imports.jl")` to rebuild the module
    @test h_row.whichmodule == TestModA.SubModB
    @test h_row.importing_from == TestModA.SubModB

    h2_row = only(subset(imps, :name => ByRow(==(:h2))))
    @test h2_row.public_import
    @test h2_row.whichmodule === TestModA.SubModB
    @test h2_row.importing_from == TestModA.SubModB
    _svd!_row = only(subset(imps, :name => ByRow(==(:_svd!))))
    @test !_svd!_row.public_import

    f_row = only(subset(imps, :name => ByRow(==(:f))))
    @test !f_row.public_import # not public in `TestModA.SubModB`
    @test f_row.whichmodule == TestModA
    @test f_row.importing_from == TestModA.SubModB

    imps = DataFrame(improper_explicit_imports_nonrecursive(ModImports, "imports.jl";
                                                            allow_internal_imports=true))
    # in this case we rule out all the `Main` ones, so only LinearAlgebra is left:
    @test all(==(LinearAlgebra), imps.importing_from)
end

#####
##### To analyze a test case
#####
# using ExplicitImports: js_node, get_parent, kind, parents_match
# using JuliaSyntax: @K_str

# cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"));
# leaves = collect(Leaves(cursor))
# leaf = leaves[end - 2] # select a leaf
# js_node(leaf) # inspect it
# p = js_node(get_parent(leaf, 3)) # see the tree, etc
# kind(p)

@testset "qualified access" begin
    # analyze_qualified_names
    qualified = analyze_qualified_names(TestQualifiedAccess, "test_qualified_access.jl")
    @test length(qualified) == 6
    ABC, DEF, HIJ, X, map, x = qualified
    @test ABC.name == :ABC
    @test DEF.public_access
    @test HIJ.public_access
    @test DEF.name == :DEF
    @test HIJ.name == :HIJ
    @test X.name == :X
    @test map.name == :map
    @test x.name == :x
    @test x.self_qualified

    # improper_qualified_accesses
    ret = Dict(improper_qualified_accesses(TestQualifiedAccess,
                                           "test_qualified_access.jl";
                                           allow_internal_accesses=false))
    @test isempty(ret[TestQualifiedAccess.Bar])
    @test isempty(ret[TestQualifiedAccess.FooModule])
    @test !isempty(ret[TestQualifiedAccess])

    @test length(ret[TestQualifiedAccess]) == 4
    ABC, X, map, x = ret[TestQualifiedAccess]
    # Can add keys, but removing them is breaking
    @test keys(ABC) ⊇
          [:name, :location, :value, :accessing_from, :whichmodule, :public_access,
           :accessing_from_owns_name, :accessing_from_submodule_owns_name, :internal_access]
    @test ABC.name == :ABC
    @test ABC.location isa AbstractString
    @test ABC.whichmodule == TestQualifiedAccess.Bar
    @test ABC.accessing_from == TestQualifiedAccess.FooModule
    @test ABC.public_access == false
    @test ABC.accessing_from_submodule_owns_name == false

    @test X.name == :X
    @test X.whichmodule == TestQualifiedAccess.FooModule.FooSub
    @test X.accessing_from == TestQualifiedAccess.FooModule
    @test X.public_access == false
    @test X.accessing_from_submodule_owns_name == true

    @test map.name == :map

    @test x.name == :x
    @test x.self_qualified

    imps = DataFrame(improper_qualified_accesses_nonrecursive(TestQualifiedAccess,
                                                              "test_qualified_access.jl";
                                                              allow_internal_accesses=true))
    subset!(imps, :self_qualified => ByRow(!)) # drop self-qualified
    # in this case we rule out all the `Main` ones, so only LinearAlgebra is left:
    @test all(==(LinearAlgebra), imps.accessing_from)

    # check_no_self_qualified_accesses
    ex = SelfQualifiedAccessException
    @test_throws ex check_no_self_qualified_accesses(TestQualifiedAccess,
                                                     "test_qualified_access.jl")

    str = exception_string() do
        return check_no_self_qualified_accesses(TestQualifiedAccess,
                                                "test_qualified_access.jl")
    end
    @test contains(str, "has self-qualified accesses:\n- `x` was accessed as")

    @test check_no_self_qualified_accesses(TestQualifiedAccess,
                                           "test_qualified_access.jl"; ignore=(:x,)) ===
          nothing

    str = sprint(print_explicit_imports, TestQualifiedAccess,
                 "test_qualified_access.jl")
    @test contains(str, "has 1 self-qualified access:\n\n    •  x was accessed as ")

    # check_all_qualified_accesses_via_owners
    ex = QualifiedAccessesFromNonOwnerException
    @test_throws ex check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                            "test_qualified_access.jl";
                                                            allow_internal_accesses=false)

    # Test the printing is hitting our formatted errors
    str = exception_string() do
        return check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                       "test_qualified_access.jl";
                                                       allow_internal_accesses=false)
    end
    @test contains(str,
                   "has qualified accesses to names via modules other than their owner as determined")

    skip = (TestQualifiedAccess.FooModule => TestQualifiedAccess.Bar,)
    @test check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  skip, ignore=(:map,),
                                                  allow_internal_accesses=false) ===
          nothing

    @test check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  ignore=(:ABC, :map),
                                                  allow_internal_accesses=false) === nothing

    # allow_internal_accesses=true
    @test_throws ex check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                            "test_qualified_access.jl",
                                                            ignore=(:ABC,))

    @test check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  ignore=(:ABC, :map)) === nothing

    @test_throws ex check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                            "test_qualified_access.jl";
                                                            skip,
                                                            require_submodule_access=true,
                                                            allow_internal_accesses=false)

    skip = (TestQualifiedAccess.FooModule => TestQualifiedAccess.Bar,
            TestQualifiedAccess.FooModule => TestQualifiedAccess.FooModule.FooSub,
            LinearAlgebra => Base)
    @test check_all_qualified_accesses_via_owners(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  skip,
                                                  require_submodule_access=true,
                                                  allow_internal_accesses=false) === nothing

    # Printing via `print_explicit_imports`
    str = sprint(io -> print_explicit_imports(io, TestQualifiedAccess,
                                              "test_qualified_access.jl";
                                              allow_internal_accesses=false))
    str = replace(str, r"\s+" => " ")
    @test contains(str, "accesses 2 names from non-owner modules")
    @test contains(str, "ABC has owner")

    ex = NonPublicQualifiedAccessException
    @test_throws ex check_all_qualified_accesses_are_public(TestQualifiedAccess,
                                                            "test_qualified_access.jl";
                                                            allow_internal_accesses=false)
    str = exception_string() do
        return check_all_qualified_accesses_are_public(TestQualifiedAccess,
                                                       "test_qualified_access.jl";
                                                       allow_internal_accesses=false)
    end
    @test contains(str, "- `ABC` is not public in")

    @test check_all_qualified_accesses_are_public(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  ignore=(:X, :ABC, :map),
                                                  allow_internal_accesses=false) === nothing

    skip = (TestQualifiedAccess.FooModule => TestQualifiedAccess.Bar,)

    @test check_all_qualified_accesses_are_public(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  skip, ignore=(:X, :map),
                                                  allow_internal_accesses=false) === nothing

    # allow_internal_accesses=true
    @test check_all_qualified_accesses_are_public(TestQualifiedAccess,
                                                  "test_qualified_access.jl";
                                                  ignore=(:map,)) === nothing
end

@testset "improper explicit imports" begin
    imps = Dict(improper_explicit_imports(TestModA, "TestModA.jl";
                                          allow_internal_imports=false))
    row = only(imps[TestModA])
    @test row.name == :un_exported
    @test row.whichmodule == Exporter

    row1, row2 = imps[TestModA.SubModB.TestModA.TestModC]
    # Can add keys, but removing them is breaking
    @test keys(row1) ⊇
          [:name, :location, :value, :importing_from, :whichmodule, :public_import,
           :importing_from_owns_name, :importing_from_submodule_owns_name, :stale,
           :internal_import]
    @test row1.name == :exported_c
    @test row1.stale == true
    @test row2.name == :exported_d
    @test row2.stale == true

    @test check_all_explicit_imports_via_owners(TestModA, "TestModA.jl";
                                                allow_internal_imports=false) === nothing
    @test_throws ExplicitImportsFromNonOwnerException check_all_explicit_imports_via_owners(ModImports,
                                                                                            "imports.jl";
                                                                                            allow_internal_imports=false)

    # allow_internal_imports=true
    @test_throws ExplicitImportsFromNonOwnerException check_all_explicit_imports_via_owners(ModImports,
                                                                                            "imports.jl";)
    @test check_all_explicit_imports_via_owners(ModImports,
                                                "imports.jl"; ignore=(:map,)) === nothing
    # Test the printing is hitting our formatted errors
    str = exception_string() do
        return check_all_explicit_imports_via_owners(ModImports,
                                                     "imports.jl";
                                                     allow_internal_imports=false)
    end

    @test contains(str,
                   "explicit imports of names from modules other than their owner as determined ")

    @test check_all_explicit_imports_via_owners(ModImports, "imports.jl";
                                                ignore=(:exported_b, :f, :map),
                                                allow_internal_imports=false) === nothing

    # We can pass `skip` to ignore non-owning explicit imports from LinearAlgebra that are owned by Base
    @test check_all_explicit_imports_via_owners(ModImports, "imports.jl";
                                                skip=(LinearAlgebra => Base,),
                                                ignore=(:exported_b, :f),
                                                allow_internal_imports=false) === nothing

    @test_throws ExplicitImportsFromNonOwnerException check_all_explicit_imports_via_owners(TestExplicitImports,
                                                                                            "test_explicit_imports.jl";
                                                                                            allow_internal_imports=false)

    # test ignore
    @test check_all_explicit_imports_via_owners(TestExplicitImports,
                                                "test_explicit_imports.jl";
                                                ignore=(:ABC,),
                                                allow_internal_imports=false) === nothing

    # test skip
    @test check_all_explicit_imports_via_owners(TestExplicitImports,
                                                "test_explicit_imports.jl";
                                                skip=(TestExplicitImports.FooModule => TestExplicitImports.Bar,),
                                                allow_internal_imports=false) ===
          nothing

    @test_throws ExplicitImportsFromNonOwnerException check_all_explicit_imports_via_owners(TestExplicitImports,
                                                                                            "test_explicit_imports.jl";
                                                                                            ignore=(:ABC,),
                                                                                            require_submodule_import=true,
                                                                                            allow_internal_imports=false)

    @test check_all_explicit_imports_via_owners(TestExplicitImports,
                                                "test_explicit_imports.jl";
                                                ignore=(:ABC, :X),
                                                require_submodule_import=true,
                                                allow_internal_imports=false) === nothing

    # allow_internal_imports = true
    @test_throws NonPublicExplicitImportsException check_all_explicit_imports_are_public(ModImports,
                                                                                         "imports.jl";)
    @test check_all_explicit_imports_are_public(ModImports,
                                                "imports.jl"; ignore=(:map, :_svd!)) ===
          nothing
end

@testset "structs" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))
    @test map(get_val, filter(is_struct_type_param, leaves)) == [:X, :Y, :QR]

    @test map(get_val, filter(is_struct_field_name, leaves)) == [:x, :x, :x, :qr, :qr]

    # Tests #34 and #36
    @test using_statement.(explicit_imports_nonrecursive(TestMod5, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra"]
end

if VERSION >= v"1.7-"
    @testset "loops" begin
        cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
        leaves = collect(Leaves(cursor))
        @test map(get_val, filter(is_for_arg, leaves)) == [:i, :I, :j, :k, :k, :j, :xi, :yi]

        # Tests #35
        @test using_statement.(explicit_imports_nonrecursive(TestMod6, "test_mods.jl")) ==
              ["using LinearAlgebra: LinearAlgebra"]
    end
end

@testset "nested local scope" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))
    # Test nested local scope
    @test using_statement.(explicit_imports_nonrecursive(TestMod7, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra"]
end

@testset "types without values in function signatures" begin
    # https://github.com/ericphanson/ExplicitImports.jl/issues/33
    @test using_statement.(explicit_imports_nonrecursive(TestMod8, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra", "using LinearAlgebra: QR"]
end

@testset "generators" begin
    cursor = TreeCursor(SyntaxNodeWrapper("test_mods.jl"))
    leaves = collect(Leaves(cursor))

    v = [:i1, :I, :i2, :I, :i3, :I, :i4, :I]
    w = [:i1, :I]
    @test map(get_val, filter(is_generator_arg, leaves)) ==
          [v; v; w; w; w; w; w]

    if VERSION >= v"1.7-"
        @test using_statement.(explicit_imports_nonrecursive(TestMod9, "test_mods.jl")) ==
              ["using LinearAlgebra: LinearAlgebra"]

        per_usage_info, _ = analyze_all_names("test_mods.jl")
        df = DataFrame(per_usage_info)
        subset!(df, :module_path => ByRow(==([:TestMod9])), :name => ByRow(==(:i1)))
        @test all(==(ExplicitImports.InternalGenerator), df.analysis_code)
    end
end

@testset "while loops" begin
    @test using_statement.(explicit_imports_nonrecursive(TestMod10, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra", "using LinearAlgebra: I"]

    per_usage_info, _ = analyze_all_names("test_mods.jl")
    df = DataFrame(per_usage_info)
    subset!(df, :module_path => ByRow(==([:TestMod10])), :name => ByRow(==(:I)))
    # First one is internal, second one external
    @test df.analysis_code == [ExplicitImports.InternalAssignment, ExplicitImports.External]
end

if VERSION >= v"1.7-"
    @testset "do- syntax" begin
        @test using_statement.(explicit_imports_nonrecursive(TestMod11, "test_mods.jl")) ==
              ["using LinearAlgebra: LinearAlgebra",
               "using LinearAlgebra: Hermitian",
               "using LinearAlgebra: svd"]

        per_usage_info, _ = analyze_all_names("test_mods.jl")
        df = DataFrame(per_usage_info)
        subset!(df, :module_path => ByRow(==([:TestMod11])))

        I_codes = subset(df, :name => ByRow(==(:I))).analysis_code
        @test I_codes ==
              [ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst,
               ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst,
               ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst,
               ExplicitImports.InternalFunctionArg, ExplicitImports.IgnoredNonFirst]
        svd_codes = subset(df, :name => ByRow(==(:svd))).analysis_code
        @test svd_codes == [ExplicitImports.InternalFunctionArg, ExplicitImports.External]
        Hermitian_codes = subset(df, :name => ByRow(==(:Hermitian))).analysis_code
        @test Hermitian_codes == [ExplicitImports.External, ExplicitImports.IgnoredNonFirst]
    end
end

@testset "try-catch" begin
    @test using_statement.(explicit_imports_nonrecursive(TestMod12, "test_mods.jl")) ==
          ["using LinearAlgebra: LinearAlgebra",
           "using LinearAlgebra: I",
           "using LinearAlgebra: svd"]

    per_usage_info, _ = analyze_all_names("test_mods.jl")
    df = DataFrame(per_usage_info)
    subset!(df, :module_path => ByRow(==([:TestMod12])))

    I_codes = subset(df, :name => ByRow(==(:I))).analysis_code
    @test I_codes == [ExplicitImports.InternalAssignment,
                      ExplicitImports.External,
                      ExplicitImports.External,
                      ExplicitImports.InternalAssignment,
                      ExplicitImports.InternalCatchArgument,
                      ExplicitImports.IgnoredNonFirst,
                      ExplicitImports.External]
    svd_codes = subset(df, :name => ByRow(==(:svd))).analysis_code
    @test svd_codes == [ExplicitImports.InternalAssignment,
                        ExplicitImports.External,
                        ExplicitImports.InternalAssignment,
                        ExplicitImports.External]
end

@testset "scripts" begin
    str = sprint(print_explicit_imports_script, "script.jl")
    str = replace(str, r"\s+" => " ")
    @test contains(str, "Script script.jl")
    @test contains(str, "relying on implicit imports for 1 name")
    @test contains(str, "using LinearAlgebra: norm")
    @test contains(str, "stale explicit imports for this 1 unused name")
    @test contains(str, "• qr")
end

@testset "Handle public symbols with same name as exported Base symbols (#88)" begin
    statements = using_statement.(explicit_imports_nonrecursive(Mod88, "examples.jl"))
    @test statements ==  ["using .ModWithTryparse: ModWithTryparse"]

end
@testset "Don't skip source modules (#29)" begin
    # In this case `UUID` is defined in Base but exported in UUIDs
    ret = ExplicitImports.find_implicit_imports(Mod29)[:UUID]
    @test ret.source == Base
    @test ret.exporters == [UUIDs]
    # We should NOT skip it, even though `skip` includes `Base`, since the exporters
    # are not skipped.
    statements = using_statement.(explicit_imports_nonrecursive(Mod29, "examples.jl"))
    @test statements == ["using UUIDs: UUIDs", "using UUIDs: UUID"]
end

@testset "Exported module (#24)" begin
    statements = using_statement.(explicit_imports_nonrecursive(Mod24, "examples.jl"))
    # The key thing here is we do not have `using .Exporter: exported_a`,
    # since we haven't done `using .Exporter` in `Mod24`, only `using .Exporter2`
    @test statements == ["using .Exporter2: Exporter2", "using .Exporter2: exported_a"]
end

@testset "string macros (#20)" begin
    foo = only_name_source(explicit_imports_nonrecursive(Foo20, "examples.jl"))
    @test foo == [(; name=:Markdown, source=Markdown),
                  (; name=Symbol("@doc_str"), source=Markdown)]
    bar = explicit_imports_nonrecursive(Bar20, "examples.jl")
    @test isempty(bar)
end

@testset "TestModArgs" begin
    # don't detect `a`!
    statements = using_statement.(explicit_imports_nonrecursive(TestModArgs,
                                                                "TestModArgs.jl"))
    @test statements ==
          ["using .Exporter4: Exporter4", "using .Exporter4: A", "using .Exporter4: Z"]

    statements = using_statement.(explicit_imports_nonrecursive(ThreadPinning,
                                                                "examples.jl"))

    @test statements == ["using LinearAlgebra: LinearAlgebra"]
end

@testset "is_function_definition_arg" begin
    cursor = TreeCursor(SyntaxNodeWrapper("TestModArgs.jl"))
    leaves = collect(Leaves(cursor))
    purported_function_args = filter(is_function_definition_arg, leaves)

    # written this way to get clearer test failure messages
    vals = unique(get_val.(purported_function_args))
    @test vals == [:a]

    # we have 9*4  functions with one argument `a`, plus 2 macros
    @test length(purported_function_args) == 9 * 4 + 2
    non_function_args = filter(!is_function_definition_arg, leaves)
    missed = filter(x -> get_val(x) === :a, non_function_args)
    @test isempty(missed)
end

@testset "has_ancestor" begin
    @test has_ancestor(TestModA.SubModB, TestModA)
    @test !has_ancestor(TestModA, TestModA.SubModB)

    @test should_skip(Base.Iterators; skip=(Base, Core))
end

function get_per_scope(per_usage_info)
    per_usage_df = DataFrame(per_usage_info)
    dropmissing!(per_usage_df, :external_global_name)
    return per_usage_df
end

@testset "file not found" begin
    for f in (check_no_implicit_imports, check_no_stale_explicit_imports,
              check_all_explicit_imports_via_owners, check_all_qualified_accesses_via_owners,
              explicit_imports,
              explicit_imports_nonrecursive, print_explicit_imports,
              improper_explicit_imports, improper_explicit_imports_nonrecursive,
              improper_qualified_accesses, improper_qualified_accesses_nonrecursive)
        @test_throws FileNotFoundException f(TestModA)
    end
    str = sprint(Base.showerror, FileNotFoundException())
    @test contains(str, "module which is not top-level in a package")
end

@testset "ExplicitImports.jl" begin
    @test using_statement.(explicit_imports_nonrecursive(TestModA, "TestModA.jl")) ==
          ["using .Exporter: Exporter", "using .Exporter: @mac",
           "using .Exporter2: Exporter2",
           "using .Exporter2: exported_a", "using .Exporter3: Exporter3"]

    per_usage_info, _ = analyze_all_names("TestModA.jl")
    df = get_per_scope(per_usage_info)
    locals = contains.(string.(df.name), Ref("local"))
    @test all(!, df.external_global_name[locals])

    # we use `x` in two scopes
    xs = subset(df, :name => ByRow(==(:x)))
    @test !xs[1, :external_global_name]
    @test !xs[2, :external_global_name]
    @test xs[2, :analysis_code] == ExplicitImports.InternalAssignment

    # we use `exported_a` in two scopes; both times refer to the global name
    exported_as = subset(df, :name => ByRow(==(:exported_a)))
    @test exported_as[1, :external_global_name]
    @test exported_as[2, :external_global_name]
    @test !exported_as[2, :is_assignment]

    # Test submodules
    @test using_statement.(explicit_imports_nonrecursive(TestModA.SubModB, "TestModA.jl")) ==
          ["using .Exporter3: Exporter3", "using .Exporter3: exported_b",
           "using .TestModA: f"]

    mod_path = module_path(TestModA.SubModB)
    @test mod_path == [:SubModB, :TestModA, :Main]
    sub_df = restrict_to_module(df, TestModA.SubModB)

    h = only(subset(sub_df, :name => ByRow(==(:h))))
    @test h.external_global_name
    @test !h.is_assignment

    # Nested submodule with same name as outer module...
    @test using_statement.(explicit_imports_nonrecursive(TestModA.SubModB.TestModA,
                                                         "TestModA.jl")) ==
          ["using .Exporter3: Exporter3", "using .Exporter3: exported_b"]

    # Check we are getting innermost names and not outer ones
    subsub_df = restrict_to_module(df, TestModA.SubModB.TestModA)
    @test :inner_h in subsub_df.name
    @test :h ∉ subsub_df.name
    # ...we do currently get the outer ones when the module path prefixes collide
    @test_broken :f ∉ subsub_df.name
    @test_broken :func ∉ subsub_df.name

    # starts from innermost
    @test module_path(TestModA.SubModB.TestModA.TestModC) ==
          [:TestModC, :TestModA, :SubModB, :TestModA, :Main]

    from_outer_file = using_statement.(explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                     "TestModA.jl"))
    from_inner_file = using_statement.(explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                                     "TestModC.jl"))
    @test from_inner_file == from_outer_file
    @test "using .TestModA: f" in from_inner_file
    # This one isn't needed bc all usages are fully qualified
    @test "using .Exporter: exported_a" ∉ from_inner_file

    # This one isn't needed; it is already explicitly imported
    @test "using .Exporter: exported_b" ∉ from_inner_file

    # This one shouldn't be there; we never use it, only explicitly import it.
    # So actually it should be on a list of unnecessary imports. BUT it can show up
    # because by importing it, we have the name in the file, so we used to detect it.
    @test "using .Exporter: exported_c" ∉ from_inner_file

    @test from_inner_file == ["using .TestModA: TestModA", "using .TestModA: f"]

    ret = improper_explicit_imports_nonrecursive(TestModA.SubModB.TestModA.TestModC,
                                                 "TestModC.jl";
                                                 allow_internal_imports=false)

    @test [(; row.name) for row in ret if row.stale] ==
          [(; name=:exported_c), (; name=:exported_d)]

    # Recursive version
    lookup = Dict(improper_explicit_imports(TestModA,
                                            "TestModA.jl"; allow_internal_imports=false))
    ret = lookup[TestModA.SubModB.TestModA.TestModC]

    @test [(; row.name) for row in ret if row.stale] ==
          [(; name=:exported_c), (; name=:exported_d)]
    @test isempty((row for row in lookup[TestModA] if row.stale))

    per_usage_info, _ = analyze_all_names("TestModC.jl")
    testmodc = DataFrame(per_usage_info)
    qualified_row = only(subset(testmodc, :name => ByRow(==(:exported_a))))
    @test qualified_row.analysis_code == ExplicitImports.IgnoredQualified
    @test qualified_row.qualified_by == [:Exporter]

    qualified_row2 = only(subset(testmodc, :name => ByRow(==(:h))))
    @test qualified_row2.qualified_by == [:TestModA, :SubModB]

    @test using_statement.(explicit_imports_nonrecursive(TestMod1,
                                                         "test_mods.jl")) ==
          ["using ExplicitImports: print_explicit_imports"]

    # Recursion
    nested = explicit_imports(TestModA, "TestModA.jl")
    @test nested isa Vector{Pair{Module,
                                 Vector{@NamedTuple{name::Symbol,source::Module,
                                                    exporters::Vector{Module},location::String}}}}
    @test TestModA in first.(nested)
    @test TestModA.SubModB in first.(nested)
    @test TestModA.SubModB.TestModA in first.(nested)
    @test TestModA.SubModB.TestModA.TestModC in first.(nested)

    # Printing
    # should be no logs
    str = @test_logs sprint(io -> print_explicit_imports(io, TestModA, "TestModA.jl";
                                                         allow_internal_imports=false))
    str = replace(str, r"\s+" => " ")
    @test contains(str, "Module Main.TestModA is relying on implicit imports")
    @test contains(str, "using .Exporter2: Exporter2, exported_a")
    @test contains(str,
                   "However, module Main.TestModA.SubModB.TestModA.TestModC has stale explicit imports for these 2 unused names")

    # should be no logs
    # try with linewidth tiny - should put one name per line
    str = @test_logs sprint(io -> print_explicit_imports(io, TestModA, "TestModA.jl";
                                                         linewidth=0))
    @test contains(str, "using .Exporter2: Exporter2,\n                    exported_a")

    # test `show_locations=true`
    str = @test_logs sprint(io -> print_explicit_imports(io, TestModA, "TestModA.jl";
                                                         show_locations=true,
                                                         allow_internal_imports=false))
    str = replace(str, r"\s+" => " ")
    @test contains(str, "using .Exporter3: Exporter3 # used at TestModA.jl:")
    @test contains(str, "is unused but it was imported from Main.Exporter at TestModC.jl")

    # test `separate_lines=true``
    str = @test_logs sprint(io -> print_explicit_imports(io, TestModA, "TestModA.jl";
                                                         separate_lines=true,
                                                         allow_internal_imports=false))
    str = replace(str, r"\s+" => " ")
    @test contains(str, "using .Exporter3: Exporter3 using .Exporter3: exported_b")

    # `warn_improper_explicit_imports=false` does something (also still no logs)
    str_no_warn = @test_logs sprint(io -> print_explicit_imports(io, TestModA,
                                                                 "TestModA.jl";
                                                                 warn_improper_explicit_imports=false))
    str = replace(str, r"\s+" => " ")
    @test length(str_no_warn) <= length(str)

    # in particular, this ensures we add `using Foo: Foo` as the first line
    @test using_statement.(explicit_imports_nonrecursive(TestMod4, "test_mods.jl")) ==
          ["using .Exporter4: Exporter4"
           "using .Exporter4: A"
           "using .Exporter4: Z"
           "using .Exporter4: a"
           "using .Exporter4: z"]
end

@testset "checks" begin
    @test check_no_implicit_imports(TestModEmpty, "test_mods.jl") === nothing
    @test check_no_stale_explicit_imports(TestModEmpty, "test_mods.jl") === nothing
    @test check_no_stale_explicit_imports(TestMod1, "test_mods.jl") === nothing

    @test_throws ImplicitImportsException check_no_implicit_imports(TestMod1,
                                                                    "test_mods.jl")

    # test name ignores
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    ignore=(:print_explicit_imports,)) === nothing

    # test name mod pair ignores
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    ignore=(:print_explicit_imports => ExplicitImports,)) ===
          nothing

    # if you pass the module in the pair, you must get the right one
    @test_throws ImplicitImportsException check_no_implicit_imports(TestMod1,
                                                                    "test_mods.jl";
                                                                    ignore=(:print_explicit_imports => TestModA,)) ===
                                          nothing

    # non-existent names are OK
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    ignore=(:print_explicit_imports => ExplicitImports,
                                            :does_not_exist)) === nothing

    # you can use skip to skip whole modules
    @test check_no_implicit_imports(TestMod1, "test_mods.jl";
                                    skip=(Base, Core, ExplicitImports)) === nothing

    @test_throws ImplicitImportsException check_no_implicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                    "TestModC.jl")

    # test submodule ignores
    @test check_no_implicit_imports(TestModA.SubModB.TestModA.TestModC, "TestModC.jl";
                                    ignore=(TestModA.SubModB.TestModA.TestModC,)) ===
          nothing

    @test_throws StaleImportsException check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                                                       "TestModC.jl")

    # make sure ignored names don't show up in error
    e = try
        check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                        "TestModC.jl";
                                        ignore=(:exported_d,))
        @test false # should error before this
    catch e
        e
    end
    str = sprint(Base.showerror, e)
    @test contains(str, "exported_c")
    @test !contains(str, "exported_d")

    # ignore works:
    @test check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                          "TestModC.jl";
                                          ignore=(:exported_c, :exported_d)) ===
          nothing

    # Test the printing is hitting our formatted errors
    str = exception_string() do
        return check_no_implicit_imports(TestMod1, "test_mods.jl")
    end
    @test contains(str, "is relying on the following implicit imports")

    str = exception_string() do
        return check_no_stale_explicit_imports(TestModA.SubModB.TestModA.TestModC,
                                               "TestModC.jl")
    end
    @test contains(str, "has stale (unused) explicit imports for:")

    @test check_all_explicit_imports_are_public(TestMod1, "test_mods.jl") === nothing
    @test_throws NonPublicExplicitImportsException check_all_explicit_imports_are_public(ModImports,
                                                                                         "imports.jl")
    str = exception_string() do
        return check_all_explicit_imports_are_public(ModImports, "imports.jl")
    end
    @test contains(str, "`_svd!` is not public in LinearAlgebra but it was imported")
    @test check_all_explicit_imports_are_public(ModImports, "imports.jl";
                                                ignore=(:_svd!, :exported_b, :f, :h, :map)) ===
          nothing

    @test check_all_explicit_imports_are_public(ModImports, "imports.jl";
                                                ignore=(:_svd!, :exported_b, :f, :h),
                                                skip=(LinearAlgebra => Base,)) ===
          nothing

    @testset "Tainted modules" begin
        # 3 dynamic include statements
        l = (:warn, r"Dynamic")
        log = (l, l, l)

        @test_logs log... @test only_name_source(explicit_imports(DynMod, "DynMod.jl")) ==
                                [DynMod => nothing, DynMod.Hidden => nothing]
        @test_logs log... @test only_name_source(explicit_imports(DynMod, "DynMod.jl";
                                                                  strict=false)) ==
                                [DynMod => [(; name=:print_explicit_imports,
                                             source=ExplicitImports)],
                                 # Wrong! Missing explicit export
                                 DynMod.Hidden => []]

        @test_logs log... @test explicit_imports_nonrecursive(DynMod, "DynMod.jl") ===
                                nothing

        @test_logs log... @test only_name_source(explicit_imports_nonrecursive(DynMod,
                                                                               "DynMod.jl";
                                                                               strict=false)) ==
                                [(; name=:print_explicit_imports, source=ExplicitImports)]

        @test @test_logs log... improper_explicit_imports(DynMod,
                                                          "DynMod.jl") ==
                                [DynMod => nothing,
                                 DynMod.Hidden => nothing]

        @test_logs log... @test improper_explicit_imports_nonrecursive(DynMod,
                                                                       "DynMod.jl") ===
                                nothing

        @test_logs log... @test improper_explicit_imports(DynMod,
                                                          "DynMod.jl";
                                                          strict=false) ==
                                [DynMod => [],
                                 # Wrong! Missing stale explicit export
                                 DynMod.Hidden => []]

        @test_logs log... @test improper_explicit_imports_nonrecursive(DynMod,
                                                                       "DynMod.jl";
                                                                       strict=false) ==
                                []

        str = @test_logs log... sprint(print_explicit_imports, DynMod, "DynMod.jl")
        @test contains(str, "DynMod could not be accurately analyzed")

        @test_logs log... @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                          allow_unanalyzable=(DynMod,
                                                                              DynMod.Hidden)) ===
                                nothing

        # Ignore also works
        @test_logs log... @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                          allow_unanalyzable=(DynMod,),
                                                          ignore=(DynMod.Hidden,)) ===
                                nothing

        e = UnanalyzableModuleException
        @test_logs log... @test_throws e check_no_implicit_imports(DynMod,
                                                                   "DynMod.jl")

        # Missed `Hidden`
        @test_logs log... @test_throws e check_no_implicit_imports(DynMod,
                                                                   "DynMod.jl";
                                                                   allow_unanalyzable=(DynMod,),)

        @test_logs log... @test check_no_stale_explicit_imports(DynMod, "DynMod.jl";
                                                                allow_unanalyzable=(DynMod,
                                                                                    DynMod.Hidden)) ===
                                nothing

        @test_logs log... @test_throws e check_no_stale_explicit_imports(DynMod,
                                                                         "DynMod.jl")

        str = sprint(Base.showerror, UnanalyzableModuleException(DynMod))
        @test contains(str, "was found to be unanalyzable")

        @test_logs log... @test check_no_implicit_imports(DynMod, "DynMod.jl";
                                                          allow_unanalyzable=(DynMod,
                                                                              DynMod.Hidden)) ===
                                nothing

        @test_logs log... @test_throws e check_no_implicit_imports(DynMod, "DynMod.jl";
                                                                   allow_unanalyzable=(DynMod,))
    end
end

@testset "Aqua" begin
    Aqua.test_all(ExplicitImports; ambiguities=false)
end

@testset "`inspect_session`" begin
    # We just want to make sure we are robust enough that this doesn't error
    big_str = with_logger(Logging.NullLogger()) do
        return sprint(inspect_session)
    end
end
