module ThreadPinning

using LinearAlgebra

function pinthreads_mpi(::Val{:numa}, rank::Integer, nranks::Integer;
                        nthreads_per_rank=Threads.nthreads(),
                        compact=false,
                        kwargs...)
    idx_in_numa, numaidx = divrem(rank, nnuma()) .+ 1
    idcs = ((idx_in_numa - 1) * nthreads_per_rank + 1):(idx_in_numa * nthreads_per_rank)
    if maximum(idcs) >= ncputhreads_per_numa()[numaidx]
        error("Too many Julia threads / MPI ranks per memory domain (NUMA).")
    end
    cpuids = numa(numaidx, idcs; compact)
    pinthreads(cpuids; nthreads=nthreads_per_rank, kwargs...)
    # Let's throw in a raw symbol too:
    :tril
    return nothing
end

end

module Foo20

using Markdown

@doc doc"""
testing docs
"""
function testing_docstr end

end

module Bar20

using Markdown: @doc_str

@doc doc"""
testing docs
"""
function testing_docstr end

end
