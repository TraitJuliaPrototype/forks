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
export Column, nrows, cell, emptycells, take, vector, tocolumn, byrow, PooledColumn, nlevels, levelcode, level,
       TableSource, tablenames, tablecolumn, tablerows

"""
A column of a table, cells of type `T`: what every column can do.

- `nrows(c)`: the number of rows.
- `cell(c, i)`: the cell in row `i` (`1 ≤ i ≤ nrows(c)`).
- `emptycells(c, n)`: a new `Vector{T}` of `n` undefined cells: a plain vector of the
  column's cell type (a buffer; it also names `T` in code bounded by `Column`).
- `take(c, rows)`: rows `rows` as a new column of the same kind (upstream: `col[rows]`;
  a pooled column stays pooled).
- `vector(c)`: the stored vector itself, for the API.

A capability that only some columns have is a trait of its own (`PooledColumn`): code that
can use it has a method bounded by both, selected by what the column's object can do, also
for a column stored as a `Dynamic{Column}` (traits reference §6.5).
"""
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T
    emptycells(c::Column{T}, n::Int)::Vector{T}
    take(c::Column, rows::AbstractVector{Int})::AbstractVector
    vector(c::Column)::AbstractVector
end
@implement Column A where {A <: AbstractVector} begin
    # Base's contract for every vector, asserted: `length` is an `Int`, a cell is of the element type (a vector
    # that keeps its data at an abstract type, as DataFrames' `RepeatedVector`, infers neither)
    nrows(c) = length(c)::Int
    cell(c, i) = (@inbounds c[firstindex(c) + i - 1])::eltype(c)
    emptycells(c, n) = Vector{eltype(c)}(undef, n)
    take(c, rows) = c[rows]
    vector(c) = c
end

"""
A column with a reference pool whose levels are unique (DataAPI's `refpool`/`refarray`:
pooled and categorical columns): `nlevels(c)` levels; row `i` holds level `levelcode(c, i)`
(in `1:nlevels(c)`), whose value is `level(c, k)`. Implemented for PooledArrays' and
CategoricalArrays' vectors by this package's extensions.
"""
@trait PooledColumn{T} begin
    T = eltype(Self)
    nlevels(c::PooledColumn)::Int
    levelcode(c::PooledColumn, i::Int)::Int
    level(c::PooledColumn{T}, k::Int)::T
end
"The pool's operations through DataAPI, for an extension's implementation (its levels are unique by construction)."
_pool_nlevels(c::AbstractVector) = length(DataAPI.refpool(c))
_pool_levelcode(c::AbstractVector, i::Int) = @inbounds Int(DataAPI.refarray(c)[firstindex(c) + i - 1]) - firstindex(DataAPI.refpool(c)) + 1
_pool_level(c::AbstractVector, k::Int) = convert(eltype(c), @inbounds DataAPI.refpool(c)[firstindex(DataAPI.refpool(c)) + k - 1])

"A column of any conforming type, kept as a dynamic value (one dispatch per operation, workers per column type): it enters `Dynamic` at the bound, whatever the caller knows."
tocolumn(c::Dynamic{Column{T}}) where {T} = Dynamic{Column}(c)::Dynamic{Column}

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


"""
`ByRow(f)` over one column (or two): `f` called once per row with the cells, in order, as upstream's
`map`. The function is a `Callable` at the cells' types, its result type inferred at the entry (traits
reference §5.8): `Dynamic` by `Callable`'s default, so this loop is compiled once per cell type and
result type, and a new closure compiles only its own body; `compiled_for(f)` compiles it per function.
Where the inferred result type is not concrete, the result's element type is narrowed from the values,
as `map` gives it.
"""
function byrow(f::Callable{Tuple{T}, S}, c::Column{T}) where {T, S}
    n = nrows(c)
    out = Vector{S}(undef, n)
    for i in 1:n
        out[i] = f(cell(c, i))
    end
    return isconcretetype(S) ? out : _narrowed(out)
end
function byrow(f::Callable{Tuple{T1, T2}, S}, a::Column{T1}, b::Column{T2}) where {T1, T2, S}
    n = nrows(a)
    out = Vector{S}(undef, n)
    for i in 1:n
        out[i] = f(cell(a, i), cell(b, i))
    end
    return isconcretetype(S) ? out : _narrowed(out)
end
"The values of `v` in a vector whose element type is what `collect` gives them (`map`'s widening)."
_narrowed(v::Vector) = [x for x in v]

end
