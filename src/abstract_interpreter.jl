using JET
using JET: AnalyzerState, AbstractAnalyzer, ReportPass, AnalysisCache, JETInterface,
           CachedMethodTable, OverlayMethodTable, JET_METHOD_TABLE, CC, MethodInstance,
           CodeInfo

struct ExternalGlobalUsage <: ReportPass end
(::ExternalGlobalUsage)(@nospecialize _...) = return false # ignore everything except UndefVarErrorReport and field error report

struct EEAnalyzer{RP<:ReportPass} <: AbstractAnalyzer
    state::AnalyzerState
    analysis_cache::AnalysisCache
    report_pass::RP
    method_table::CachedMethodTable{OverlayMethodTable}
end

function EEAnalyzer(world::UInt=Base.get_world_counter(); pass=ExternalGlobalUsage())
    state = AnalyzerState(world)
    method_table = CachedMethodTable(OverlayMethodTable(state.world, JET_METHOD_TABLE))

    return EEAnalyzer(state, AnalysisCache(), pass, method_table)
end

CC.maybe_compress_codeinfo(::EEAnalyzer, ::MethodInstance, ::CodeInfo) = nothing

# EEAnalyzer hooks on abstract interpretation only,
# and so the cost of running the optimization passes is just unnecessary
CC.may_optimize(::EEAnalyzer) = false
CC.method_table(analyzer::EEAnalyzer) = analyzer.method_table

JETInterface.AnalyzerState(analyzer::EEAnalyzer) = analyzer.state
function JETInterface.AbstractAnalyzer(analyzer::EEAnalyzer, state::AnalyzerState)
    return EEAnalyzer(state, AnalysisCache(analyzer), ReportPass(analyzer),
                      CC.method_table(analyzer))
end
JETInterface.ReportPass(analyzer::EEAnalyzer) = analyzer.report_pass
JETInterface.AnalysisCache(analyzer::EEAnalyzer) = analyzer.analysis_cache


# overloads
# =========

@static if VERSION ≥ v"1.11.0-DEV.843"
    function CC.InferenceState(result::InferenceResult, cache_mode::UInt8, analyzer::EEAnalyzer)
        frame = @invoke CC.InferenceState(result::InferenceResult, cache_mode::UInt8, analyzer::AbstractAnalyzer)
        if isnothing(frame) # indicates something bad happened within `retrieve_code_info`
            ReportPass(analyzer)(GeneratorErrorReport, analyzer, result)
        end
        return frame
    end
    else
    function CC.InferenceState(result::InferenceResult, cache_mode::Symbol, analyzer::EEAnalyzer)
        frame = @invoke CC.InferenceState(result::InferenceResult, cache_mode::Symbol, analyzer::AbstractAnalyzer)
        if isnothing(frame) # indicates something bad happened within `retrieve_code_info`
            ReportPass(analyzer)(GeneratorErrorReport, analyzer, result)
        end
        return frame
    end
    end

    function CC.finish!(analyzer::EEAnalyzer, caller::InferenceState)
        src = caller.result.src

        if isnothing(src)
            # caught in cycle, similar error should have been reported where the source is available
        elseif src isa CodeInfo
            # report pass for uncaught `throw` calls
            ReportPass(analyzer)(UncaughtExceptionReport, analyzer, caller, src.code)
        else
            # NOTE `src` never be `OptpimizationState` since `CC.may_optimize(::EEAnalyzer) === false`
            Core.eval(@__MODULE__, :(src = $src))
            throw("unexpected state happened, inspect `$(@__MODULE__).src`")
        end

        return @invoke CC.finish!(analyzer::AbstractAnalyzer, caller::InferenceState)
    end

    function CC.abstract_call_gf_by_type(analyzer::EEAnalyzer,
        @nospecialize(f), arginfo::ArgInfo, si::StmtInfo, @nospecialize(atype), sv::InferenceState,
        max_methods::Int)
        ret = @invoke CC.abstract_call_gf_by_type(analyzer::AbstractAnalyzer,
            f::Any, arginfo::ArgInfo, si::StmtInfo, atype::Any, sv::InferenceState, max_methods::Int)
        ReportPass(analyzer)(MethodErrorReport, analyzer, sv, ret, arginfo.argtypes, atype)
        ReportPass(analyzer)(UnanalyzedCallReport, analyzer, sv, ret, atype)
        return ret
    end

    function CC.from_interprocedural!(analyzer::EEAnalyzer,
        @nospecialize(rt), sv::InferenceState, arginfo::ArgInfo, @nospecialize(maybecondinfo))
        ret = @invoke CC.from_interprocedural!(analyzer::AbstractAnalyzer,
            rt::Any, sv::InferenceState, arginfo::ArgInfo, maybecondinfo::Any)
        if EEAnalyzerConfig(analyzer).ignore_missing_comparison
            # Widen the return type of comparison operator calls to ignore the possibility of
            # they returning `missing` when analyzing from top-level.
            # Otherwise we will see frustrating false positive errors from branching on the
            # return value (aviatesk/JET.jl#542), since the analysis often uses loose
            # top-level argument types as input.
            if ret === Union{Bool,Missing}
                ret = Any
            end
        end
        return ret
    end

    """
        Core.Compiler.bail_out_call(analyzer::EEAnalyzer, ...)

    This overload makes call inference performed by `EEAnalyzer` not bail out even when
    inferred return type grows up to `Any` to collect as much error reports as possible.
    That potentially slows down inference performance, but it would stay to be practical
    given that the number of matching methods are limited beforehand.
    """
    CC.bail_out_call(::EEAnalyzer, ::CC.InferenceLoopState, ::InferenceState) = false

    struct __DummyRettype__ end

    """
        Core.Compiler.add_call_backedges!(analyzer::EEAnalyzer, ...)

    An overload for `abstract_call_gf_by_type(analyzer::EEAnalyzer, ...)`, which always add
    backedges (even if a new method can't refine the return type grew up to `Any`).
    This is because a new method definition always has a potential to change `EEAnalyzer`'s analysis result.
    """
    function CC.add_call_backedges!(
        analyzer::EEAnalyzer, @nospecialize(rettype), effects::CC.Effects,
        edges::Vector{MethodInstance}, matches::Union{MethodMatches,UnionSplitMethodMatches}, @nospecialize(atype),
        sv::InferenceState)
        return @invoke CC.add_call_backedges!(
            # NOTE this `__DummyRettype__()` hack forces `add_call_backedges!(::AbstractInterpreter,...)` to add backedges
            analyzer::AbstractInterpreter, __DummyRettype__()::Any, effects::CC.Effects,
            edges::Vector{MethodInstance}, matches::Union{MethodMatches,UnionSplitMethodMatches}, atype::Any,
            sv::InferenceState)
    end

    # TODO Reasons about error found by [semi-]concrete evaluation:
    # For now EEAnalyzer allows the regular constant-prop' only,
    # unless the analyzed effects are proven to be `:nothrow`.
    function CC.concrete_eval_eligible(analyzer::EEAnalyzer,
        @nospecialize(f), result::MethodCallResult, arginfo::ArgInfo, sv::InferenceState)
        if CC.is_nothrow(result.effects)
            neweffects = CC.Effects(result.effects;
                nonoverlayed=@static VERSION ≥ v"1.11.0-beta2.49" ? CC.ALWAYS_TRUE : true)
            @static if VERSION ≥ v"1.11.0-DEV.945"
            newresult = MethodCallResult(result.rt, result.exct, result.edgecycle, result.edgelimited,
                                         result.edge, neweffects)
            else
            newresult = MethodCallResult(result.rt, result.edgecycle, result.edgelimited,
                                         result.edge, neweffects)
            end
            res = @invoke CC.concrete_eval_eligible(analyzer::AbstractAnalyzer,
                f::Any, newresult::MethodCallResult, arginfo::ArgInfo, sv::InferenceState)
            if res === :concrete_eval
                return :concrete_eval
            end
        elseif istopfunction(f, :fieldindex)
            if concrete_eval_eligible_ignoring_overlay(result, arginfo)
                return :concrete_eval
            end
        end
        # disables both concrete evaluation and semi-concrete interpretation
        return :none
    end

    function concrete_eval_eligible_ignoring_overlay(result::MethodCallResult, arginfo::ArgInfo)
        result.edge !== nothing || return false
        return CC.is_foldable(result.effects) && CC.is_all_const_arg(arginfo, #=start=#2)
    end

    function CC.return_type_tfunc(analyzer::EEAnalyzer, argtypes::Argtypes, si::StmtInfo, sv::InferenceState)
        # report pass for invalid `Core.Compiler.return_type` call
        ReportPass(analyzer)(InvalidReturnTypeCall, analyzer, sv, argtypes)
        return @invoke CC.return_type_tfunc(analyzer::AbstractAnalyzer, argtypes::Argtypes, si::StmtInfo, sv::InferenceState)
    end

    function CC.abstract_invoke(analyzer::EEAnalyzer, arginfo::ArgInfo, si::StmtInfo, sv::InferenceState)
        ret = @invoke CC.abstract_invoke(analyzer::AbstractAnalyzer, arginfo::ArgInfo, si::StmtInfo, sv::InferenceState)
        ReportPass(analyzer)(InvalidInvokeErrorReport, analyzer, sv, ret, arginfo.argtypes)
        return ret
    end

    # report pass for undefined static parameter
    @static if VERSION ≥ v"1.11.0-DEV.888"
    function CC.abstract_eval_statement_expr(analyzer::EEAnalyzer, e::Expr, vtypes::VarTable, sv::InferenceState)
        ret = @invoke CC.abstract_eval_statement_expr(analyzer::AbstractAnalyzer, e::Expr, vtypes::VarTable, sv::InferenceState)
        if e.head === :static_parameter
            ReportPass(analyzer)(UndefVarErrorReport, analyzer, sv, e.args[1]::Int)
        end
        return ret
    end
    else
    function CC.abstract_eval_value_expr(analyzer::EEAnalyzer, e::Expr, vtypes::VarTable, sv::InferenceState)
        ret = @invoke CC.abstract_eval_value_expr(analyzer::AbstractAnalyzer, e::Expr, vtypes::VarTable, sv::InferenceState)
        if e.head === :static_parameter
            ReportPass(analyzer)(UndefVarErrorReport, analyzer, sv, e.args[1]::Int)
        end
        return ret
    end
    end

    function CC.abstract_eval_special_value(analyzer::EEAnalyzer,
        @nospecialize(e), vtypes::VarTable, sv::InferenceState)
        ret = @invoke CC.abstract_eval_special_value(analyzer::AbstractAnalyzer,
            e::Any, vtypes::VarTable, sv::InferenceState)

        if isa(e, GlobalRef)
            # report pass for undefined global reference
            ReportPass(analyzer)(UndefVarErrorReport, analyzer, sv, e)
        # elseif isa(e, SlotNumber)
        #     # TODO enable this (aviatesk/JET.jl#596)
        #     # report pass for (local) undef var error
        #     ReportPass(analyzer)(UndefVarErrorReport, analyzer, sv, e, vtypes, ret)
        end

        return ret
    end

    # N.B. this report pass won't be necessary as the frontend will generate code
    # that `typeassert`s the value type as the binding type beforehand
    @inline function CC.abstract_eval_basic_statement(analyzer::EEAnalyzer,
        @nospecialize(stmt), pc_vartable::VarTable, frame::InferenceState)
        ret = @invoke CC.abstract_eval_basic_statement(analyzer::AbstractAnalyzer,
            stmt::Any, pc_vartable::VarTable, frame::InferenceState)
        if isexpr(stmt, :(=)) && (lhs = stmt.args[1]; isa(lhs, GlobalRef))
            rt = @static VERSION ≥ v"1.11.0-DEV.945" ? ret.rt : ret.type
            ReportPass(analyzer)(InvalidGlobalAssignmentError, analyzer,
                frame, lhs.mod, lhs.name, rt)
        end
        return ret
    end

    function CC.abstract_eval_value(analyzer::EEAnalyzer, @nospecialize(e), vtypes::VarTable, sv::InferenceState)
        ret = @invoke CC.abstract_eval_value(analyzer::AbstractAnalyzer, e::Any, vtypes::VarTable, sv::InferenceState)

        # report non-boolean condition error
        stmt = get_stmt((sv, get_currpc(sv)))
        if isa(stmt, GotoIfNot)
            t = widenconst(ret)
            if t !== Bottom
                ReportPass(analyzer)(NonBooleanCondErrorReport, analyzer, sv, t)
            end
        end

        return ret
    end

    @static if VERSION ≥ v"1.11.0-DEV.1080"
    function CC.abstract_throw(analyzer::EEAnalyzer, argtypes::Vector{Any}, sv::InferenceState)
        ft = popfirst!(argtypes)
        ReportPass(analyzer)(SeriousExceptionReport, analyzer, sv, argtypes)
        pushfirst!(argtypes, ft)
        return @invoke CC.abstract_throw(analyzer::AbstractAnalyzer, argtypes::Vector{Any}, sv::InferenceState)
    end
    end

    function CC.builtin_tfunction(analyzer::EEAnalyzer,
        @nospecialize(f), argtypes::Vector{Any}, sv::InferenceState) # `AbstractAnalyzer` isn't overloaded on `return_type`
        ret = @invoke CC.builtin_tfunction(analyzer::AbstractAnalyzer,
            f::Any, argtypes::Vector{Any}, sv::InferenceState)

        if f === fieldtype
            # the valid widest possible return type of `fieldtype_tfunc` is `Union{Type,TypeVar}`
            # because fields of unwrapped `DataType`s can legally be `TypeVar`s,
            # but this will lead to lots of false positive `MethodErrorReport`s for inference
            # with accessing to abstract fields since most methods don't expect `TypeVar`
            # (e.g. `@report_call readuntil(stdin, 'c')`)
            # JET.jl further widens this case to `Any` and give up further analysis rather than
            # trying hard to do sound and noisy analysis
            # xref: https://github.com/JuliaLang/julia/pull/38148
            if ret === Union{Type, TypeVar}
                ret = Any
            end
        end

        if f === throw
            # here we only report a selection of "serious" exceptions, i.e. those that should be
            # reported even if they may be caught in actual execution;
            ReportPass(analyzer)(SeriousExceptionReport, analyzer, sv, argtypes)

            # other general `throw` calls will be handled within `_typeinf(analyzer::AbstractAnalyzer, frame::InferenceState)`
        else
            ReportPass(analyzer)(AbstractBuiltinErrorReport, analyzer, sv, f, argtypes, ret)
        end

        # `IntrinsicError` is a special marker object that JET uses to indicate an erroneous
        # intrinsic function call, so fix it up here to `Bottom`
        if ret isa IntrinsicError
            ret = Bottom
        end

        return ret
    end
