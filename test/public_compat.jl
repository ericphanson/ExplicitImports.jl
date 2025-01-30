# based on:
# https://github.com/JuliaLang/Public.jl/blob/a0e40de2b67a255dee7ffdf392e7b794eb49d44f/src/Public.jl#L9-L19
@static if Base.VERSION >= v"1.11.0-DEV.469"
    macro public_or_export(symbol::Symbol)
        return esc(Expr(:public, symbol))
    end
    macro public(symbol::Symbol)
        return esc(Expr(:public, symbol))
    end

else
    macro public_or_export(symbol::Symbol)
        return esc(Expr(:export, symbol))
    end
    macro public(symbol::Symbol)
        return nothing
    end

end
