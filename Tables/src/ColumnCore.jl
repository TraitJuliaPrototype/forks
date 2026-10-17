# ColumnCore: the trait module of Tables (forks/, plan §2.1–2.2). What table code reads
# from a column and from a table, as traits:
#   - `Column{T}`: a column of a table, its rows and its cells. Every `AbstractVector`
#     conforms (a family declared here, by the trait's owner); the key is the vector's
#     concrete type, so code bounded by `Column` is compiled once per column type, never per
#     schema. `vector(c)` returns the stored vector itself, for the API (`df.a === v`).
#   - `TableSource`: names, columns as `Dynamic{Column}` values, the number of rows. A
#     consumer reads any conforming table without a type per schema.
# Tables' duck-typed interface (`istable`, `columns`, `getcolumn`, `schema`) stays as it
# is for every other table; `TableSource` is what the forks' own types conform to.
@trait_module module ColumnCore
using TraitWorld
export Column, nrows, cell, vector, tocolumn, TableSource, columnnames, column, nrow

"A column of a table: its number of rows, its cells, and the stored vector."
@trait Column{T} begin
    T = eltype(Self)
    nrows(c::Column)::Int
    cell(c::Column{T}, i::Int)::T
    vector(c::Column)::AbstractVector
end
@implement Column A where {A <: AbstractVector} begin
    nrows(c) = length(c)
    cell(c, i) = @inbounds c[i]
    vector(c) = c
end

"A column of any conforming type, kept as a dynamic value (one dispatch per operation, workers per column type)."
tocolumn(c::Column)::Dynamic{Column} = Dynamic{Column}(c)

"A table: its column names, its columns by position, its number of rows."
@trait TableSource begin
    columnnames(t::TableSource)::Vector{Symbol}
    column(t::TableSource, i::Int)::Dynamic{Column}
    nrow(t::TableSource)::Int
end

end
