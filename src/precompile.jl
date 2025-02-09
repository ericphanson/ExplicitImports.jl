precompile(print_explicit_imports, (Module,))
precompile(print_explicit_imports, (Base.TTY, Module, String))
precompile(main, (Vector{String},))

# These are non-public so I don't want to start throwing if they stop existing,
# however we do seem to need explicit precompile calls to hit them
try
    precompile(Markdown.term, (Base.TTY, Markdown.Code, Int))
    precompile(Markdown.term, (Base.TTY, Markdown.Paragraph, Int))
    precompile(Markdown.term, (Base.TTY, Markdown.List, Int))
catch err
    @debug "Error in precompiles" err
end
