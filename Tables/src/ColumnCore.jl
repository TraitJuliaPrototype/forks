# ColumnCore: the trait module of Tables (forks/, plan §2.1–2.2). What table code reads
# from a column and from a table, as traits:
#   - `Column{T}`: a column of a table: its rows, its cells, its reference pool if it has
#     one, a selection of its rows. Every `AbstractVector` conforms (a family declared here,
#     by the trait's owner); the key is the vector's concrete type, so code bounded by
#     `Column` is compiled once per column type, never per schema or per tuple of column
#     types. Kernels read a column through these operations only.
#     `vector(c)` is the API's way back to the stored vector itself (`df.a === v`, the
#     plan's decision D-a); kernels do not use it.
#   - `TableSource`: names, columns as `Dynamic{Column}` values, the number of rows. A
#     consumer reads any conforming table without a type per schema. Tables' own column
#     tables (`NamedTuple`s of vectors) conform here; `DataFrame`, `SubDataFrame` and
#     `CSV.File` conform in their packages.
# Tables' duck-typed interface (`istable`, `columns`, `getcolumn`, `schema`) stays as it
# is for every other table.
@trait_module module ColumnCore
using TraitWorld
using DataAPI
export Column, nrows, cell, emptycells, take, nlevels, levelcode, level, vector, tocolumn,
       TableSource, tablenames, tablecolumn, tablerows

"""
A column of a table, cells of type `T`.

- `nrows(c)`: the number of rows.
- `cell(c, i)`: the cell in row `i` (`1 ≤ i ≤ nrows(c)`).
- `emptycells(c, n)`: a new `Vector{T}` of `n` undefined cells: a plain vector of the
  column's cell type (a buffer; it also names `T` in code bounded by `Column`).
- `take(c, rows)`: rows `rows` as a new column of the same kind (upstream: `col[rows]`;
  a pooled column stays pooled).
- `nlevels(c)`, `levelcode(c, i)`, `level(c, k)`: the column's reference pool, if it has
  one whose levels are unique (DataAPI's `refpool`/`refarray`: pooled and categorical
  columns). `nlevels(c) == 0` when it has none; otherwise row `i` holds level
  `levelcode(c, i)` (in `1:nlevels(c)`), whose value is `level(c, k)`.
- `vector(c)`: the stored vector itself, for the API.
"""
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T
    emptycells(c::Column{T}, n::Int)::Vector{T}
    take(c::Column, rows::AbstractVector{Int})::AbstractVector
    nlevels(c::Column)::Int
    levelcode(c::Column, i::Int)::Int
    level(c::Column{T}, k::Int)::T
    vector(c::Column)::AbstractVector
end
@implement Column A where {A <: AbstractVector} begin
    nrows(c) = length(c)
    cell(c, i) = @inbounds c[firstindex(c) + i - 1]
    emptycells(c, n) = Vector{eltype(c)}(undef, n)
    take(c, rows) = c[rows]
    nlevels(c) = _nlevels(c)
    levelcode(c, i) = @inbounds Int(DataAPI.refarray(c)[firstindex(c) + i - 1]) - firstindex(DataAPI.refpool(c)) + 1
    level(c, k) = convert(eltype(c), @inbounds DataAPI.refpool(c)[firstindex(DataAPI.refpool(c)) + k - 1])
    vector(c) = c
end

# A reference pool counts only if its levels are unique (as DataFrames' `refpool_and_array`
# requires) and its references are integers.
function _nlevels(c::AbstractVector)
    rp = DataAPI.refpool(c)
    rp === nothing && return 0
    DataAPI.refarray(c) isa AbstractVector{<:Integer} || return 0
    DataAPI.invrefpool(c) !== nothing || allunique(rp) || return 0
    return length(rp)
end

"A column of any conforming type, kept as a dynamic value (one dispatch per operation, workers per column type)."
tocolumn(c::Column)::Dynamic{Column} = Dynamic{Column}(c)

"""
A table: its column names (`tablenames(t)`, a new vector), its columns by position
(`tablecolumn(t, i)`, a `Dynamic{Column}` holding the stored vector), its number of rows
(`tablerows(t)`).
"""
@trait TableSource begin
    tablenames(t::TableSource)::Vector{Symbol}
    tablecolumn(t::TableSource, i::Int)::Dynamic{Column}
    tablerows(t::TableSource)::Int
end
# Tables' column tables: a `NamedTuple` of vectors (`Tables.columntable`'s result)
@implement TableSource NT where {NT <: NamedTuple{<:Any, <:Tuple{Vararg{AbstractVector}}}} begin
    tablenames(t) = Symbol[keys(t)...]
    tablecolumn(t, i) = Dynamic{Column}(t[i])
    tablerows(t) = isempty(t) ? 0 : length(t[1])
end

end
