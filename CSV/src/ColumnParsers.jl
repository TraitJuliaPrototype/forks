# ColumnParsers: the trait module of CSV (forks/, plan §2.4). The reader's entry is bounded by
# `CSVSource`, what it reads from, so that the read runs in a worker compiled per source type:
# the reader's own code, which it reaches at concrete types, is then compiled under the trait
# world's facts policy and kept in this package's image, and other packages' loads do not
# discard it (writeup/notes/3-wrapping.md). Upstream's reader reaches the same code through
# `@nospecializeinfer` barriers, as native code that loads invalidate (forks/README.md, M0).
@trait_module module ColumnParsers
using TraitWorld
export CSVSource, rawsource, readfile
const _CSV = parentmodule(@__MODULE__)

"What the reader reads: a path, an `IO`, or bytes; `rawsource` is the value itself."
@trait CSVSource begin
    rawsource(s::CSVSource)::Any
end
@implement CSVSource A where {A <: AbstractString} begin
    rawsource(s) = s
end
@implement CSVSource A where {A <: IO} begin
    rawsource(s) = s
end
@implement CSVSource A where {A <: AbstractVector{UInt8}} begin
    rawsource(s) = s
end

"`CSV.File(source; …)` with the keywords resolved: a worker per source type."
readfile(src::CSVSource, types, select, drop, scan, pool, downcast::Bool, transpose::Bool, stringtype::Val,
         on_error::Symbol, maxproblems::Int, ntasks, parallel::Bool, validate::Bool, kw) =
    _CSV._file(rawsource(src), types, select, drop, scan, pool, downcast, transpose, stringtype,
                                    on_error, maxproblems, ntasks, parallel, validate, kw)

end
# 
# 
# 
