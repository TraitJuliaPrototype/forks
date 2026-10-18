# ColumnParsers: the trait module of CSV (forks/, plan §2.4). The columns the reader produces
# are traits, subtraits of Tables' `Column`:
#   - `CSVColumn{T}`: a column the reader parses typed cells into, cell by cell. The
#     conforming values are the vectors the reader fills: `Vector{T}` (the values of a
#     `TypedColumn{T}`) and `Vector{Union{T, Missing}}` (a `UnionColumn{T}`). `parsecell!`
#     parses one cell's bytes as `T` and stores it, or answers that it does not fit. The
#     parse loop over a chunk (`parsecells!`) is a worker per key, written once.
#   - `TextColumn{T}`: a column text cells are converted into after the parse, for a string
#     type other than CSV's own (`DataString`, `String`, `Symbol`). `Vector{S}` conforms
#     for each such string type `S`; InlineStrings' types conform in `CSVInlineStringsExt`.
#     A conformance is a method of the conformance registry: declaring one adds no method
#     to CSV's internal functions, so it invalidates none of the reader's compiled code.
#     CSV.jl's extension added methods to seven internal functions instead.
# The reader's entry is bounded by `CSVSource`, what it reads from, so the read runs in a
# worker compiled per source type. `CSV.File` conforms to Tables' `TableSource`.
@trait_module module ColumnParsers
using TraitWorld
using Tables.ColumnCore: Column, nrows, cell, emptycells, TableSource
const _CSV = parentmodule(@__MODULE__)
# WORKAROUND (TraitWorld issue, reported): a family conformance names its builder registry
# `gensym(:family_builders)` and defines `TraitWorld._family_registry(::Val{name})`. Gensym
# counters start alike in every precompilation process, so CSV's first family registry got the
# name of one of Tables' (`##family_builders#156`) and precompiling CSV failed with "Method
# overwriting is not permitted". Advancing the counter here avoids the collision; the fix is a
# registry key unique per module in TraitWorld.
foreach(_ -> gensym(), 1:4096)
export CSVSource, rawsource, readfile, CSVColumn, parsecell!, parsecells!,
       TextColumn, textcolumn, settext!, rowtexttype, rowtext, filltext!

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

# --- typed cells ---------------------------------------------------------------------------------

"""
A column the reader parses typed cells into. `parsecell!(c, i, buf, pos, len, esc, opts,
scratch)` parses the cell content `buf[pos:pos+len-1]` (`esc`: it holds escapes) as the
column's non-missing cell type, stores it in row `i`, and returns `true`; it returns `false`
and stores nothing if the content is not a value of that type.
"""
@trait CSVColumn{T} <: Column begin
    T = eltype(Self)
    parsecell!(c::CSVColumn, i::Int, buf::Vector{UInt8}, pos::Int, len::Int, esc::Bool,
               opts::_CSV.ValueOpts, scratch::Vector{UInt8})::Bool
end
@implement CSVColumn A where {A <: Vector} begin
    parsecell!(c, i, buf, pos, len, esc, opts, scratch) = _parseinto!(c, i, buf, pos, len, esc, opts, scratch)
end
@inline function _parseinto!(c::Vector{E}, i::Int, buf::Vector{UInt8}, pos::Int, len::Int, esc::Bool,
                             opts::_CSV.ValueOpts, scratch::Vector{UInt8}) where {E}
    v, ok = _CSV._parsecontent(nonmissingtype(E), buf, pos, len, esc, opts, scratch)
    ok && (@inbounds c[i] = v)
    return ok
end

"""
Parse column `j` of one chunk into `c` (upstream's `parsecolchunk!` for typed columns, a worker
per key): rows from `rowbase + 1`, a present cell marked in `present` (when given). Returns 0,
or the chunk-local row of the first cell that does not fit (an inferred column is then
promoted and parsed again), as upstream does.
"""
function parsecells!(c::CSVColumn, present::Union{Nothing, Vector{Bool}}, buf::Vector{UInt8},
                     ci::_CSV.ChunkIndex, j::Int, rowbase::Int, opts::_CSV.ValueOpts,
                     userprovided::Bool, problems, problemrowbase::Int,
                     mask::Union{Nothing, Vector{Bool}}, maskbase::Int, reportlimit::Int)::Int
    scratch = _CSV._scratchfor(opts)
    tape, rowfirst, rowstartrel, ext = ci.tape, ci.rowfirst, ci.rowstartrel, ci.ext
    start, skip, fdr, total = ci.start, ci.delimskip, ci.firstdatarow, _CSV.totalrows(ci)
    @inbounds first = fdr <= total ? Int(rowfirst[fdr]) : 0
    @inbounds for lr in fdr:total
        rowlo = first
        nextr = Int(rowfirst[lr + 1])
        first = nextr
        localrow = lr - fdr + 1
        out = rowbase + localrow
        mask !== nothing && !mask[maskbase + out] && continue   # excluded row: cell never parsed
        localrow > reportlimit && continue
        sp = _CSV._span(start, tape, rowstartrel, ext, skip, rowlo, nextr, lr, j)
        sp === nothing && continue                      # short row ⇒ missing (reported once per row by the driver)
        pos, len = sp
        len == 0 && continue                            # empty ⇒ missing
        cpos, clen, esc, st = _CSV.cellcontent(buf, pos, len, opts)
        st == _CSV.CELL_MISSING && continue             # sentinel / stripped-to-empty
        if st == _CSV.CELL_VALUE && clen > 0
            if parsecell!(c, out, buf, cpos, clen, esc, opts, scratch)
                present === nothing || (present[out] = true)
                continue
            end
        end
        # invalid for the cell type (also: malformed quoting or quoted-empty)
        if userprovided
            problemrow = problemrowbase + localrow
            if st == _CSV.CELL_BADQUOTE
                _CSV.pushcellproblem!(problems, problemrow, j, pos, len, :invalid_quoted_field,
                                      "malformed quoting in ", buf)
            else
                _CSV.pushcellproblem!(problems, problemrow, j, pos, len, :invalid_value,
                                      "cannot parse $(nonmissingtype(eltype(emptycells(c, 0)))) from ", buf)
            end
        else
            return lr                                   # inference conflict ⇒ promote & re-parse column
        end
    end
    return 0
end

# --- text cells ----------------------------------------------------------------------------------

"""
A column text cells are converted into, for a string type other than CSV's own.
`Vector{S}` conforms for a string type `S`:
- `textcolumn(c, maxlen, n, withmissing)`: a new column of `n` undefined cells for text whose
  longest value has `maxlen` bytes (`Vector{S′}`, or `Vector{Union{S′, Missing}}` with
  `withmissing`); `S′` is `S`, or a type `S` settles to (`InlineString` picks the narrowest
  width, or `String` past its limit);
- `settext!(c, i, x)`: store text `x` (a `DataString`, or `missing`) in row `i`;
- `rowtexttype(c)`, `rowtext(c, x)`: the type of a text cell read row by row, and the cell.
"""
@trait TextColumn{T} <: Column begin
    T = eltype(Self)
    textcolumn(c::TextColumn, maxlen::Int, n::Int, withmissing::Bool)::AbstractVector
    settext!(c::TextColumn, i::Int, x::Union{Missing, _CSV.DataString})::Nothing
    rowtexttype(c::TextColumn)::Type
    rowtext(c::TextColumn, x::_CSV.DataString)::AbstractString
end

"Convert the text cells of `col` (its first `n`) into `c` (a worker per key)."
function filltext!(c::TextColumn, col::_CSV.DataStringVector, n::Int)::Nothing
    @inbounds for i in 1:n
        settext!(c, i, col[i])
    end
    return nothing
end

end

# --- CSV.File as a TableSource (CSV owns the type) ---------------------------------------------

@implement Tables.ColumnCore.TableSource File begin
    tablenames(t) = copy(names(getfield(t, :table)))
    tablecolumn(t, i) = Tables.ColumnCore.tocolumn(columns(getfield(t, :table))[i])::TraitWorld.Dynamic{Tables.ColumnCore.Column}
    tablerows(t) = getfield(t, :table).nrows
end
