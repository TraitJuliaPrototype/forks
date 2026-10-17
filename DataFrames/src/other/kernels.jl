# ColumnKernels: the trait module of DataFrames (forks/, plan §2.5). The functions of the
# interactive path that read columns, written once against the `Column` trait
# (Tables.ColumnCore) and compiled per column type, the key: never per schema, per tuple of
# column types or per closure. Their code, and the code of Base and Statistics they reach at
# concrete types, is compiled under the trait world's facts policy and kept in this package's
# image for the keys its workload covers, so later loads do not discard it (writeup/notes/3-wrapping.md).
# Upstream reaches the same code through `@nospecialize` barriers into native code compiled at
# run time per column type.
@trait_module module ColumnKernels
using TraitWorld
using Tables.ColumnCore: Column, nrows, cell, vector
using Statistics
using DataAPI, Missings
using ..DataFrames: refpool_and_array
const _DF = parentmodule(@__MODULE__)
export colstats, refine!, takerows, firstcodes!, refcodes, aggregate, innerrows

# --- describe -------------------------------------------------------------------------------

"""
`describe`'s predefined statistics of one column, in a `Dict` (a worker per column type).
Missing values are skipped as upstream does: for an element type that admits `missing`, the
statistics are those of `skipmissing(col)`.
"""
function colstats(c::Column, stats::Vector{Symbol})::Dict{Symbol, Any}
    col = vector(c)
    d = eltype(col) >: Missing ? _stats(skipmissing(col), stats) : _stats(col, stats)
    :nmissing in stats && (d[:nmissing] = count(ismissing, col))
    :nnonmissing in stats && (d[:nnonmissing] = count(!ismissing, col))
    :first in stats && (d[:first] = isempty(col) ? nothing : first(col))
    :last in stats && (d[:last] = isempty(col) ? nothing : last(col))
    :eltype in stats && (d[:eltype] = eltype(col))
    return d
end

# upstream's `get_stats` (abstractdataframe.jl), without its `@nospecialize`: here it is
# called at the column's concrete type
function _stats(col, stats::Vector{Symbol})
    d = Dict{Symbol, Any}()
    if :q25 in stats || :median in stats || :q75 in stats
        T = eltype(col)
        if isconcretetype(T) && !hasmethod(-, Tuple{T, T})
            d[:q25] = d[:median] = d[:q75] = nothing
        else
            mcol = Base.copymutable(col)
            :q25 in stats && (d[:q25] = try quantile!(mcol, 0.25) catch; nothing; end)
            :median in stats && (d[:median] = try quantile!(mcol, 0.50) catch; nothing; end)
            :q75 in stats && (d[:q75] = try quantile!(mcol, 0.75) catch; nothing; end)
        end
    end
    if :min in stats || :max in stats
        ex = try extrema(col) catch; (nothing, nothing) end
        d[:min] = ex[1]
        d[:max] = ex[2]
    end
    if :mean in stats || :std in stats
        m = try mean(col) catch end
        d[:mean] = m
        :std in stats && (d[:std] = try std(col, mean = m) catch end)
    end
    if :nunique in stats
        d[:nunique] = eltype(col) <: Real ? nothing : try length(Set(col)) catch end
    end
    :nuniqueall in stats && (d[:nuniqueall] = try length(Set(col)) catch end)
    :sum in stats && (d[:sum] = try sum(col) catch end)
    return d
end

# --- rows: selection and sorting ------------------------------------------------------------

"The rows `rows` of a column, a new vector (upstream: `col[rows]`), a worker per column type."
takerows(c::Column, rows::AbstractVector{Int})::AbstractVector = vector(c)[rows]

"""
Refine the stable order `perm` by column `c`: afterwards `c[perm]` is sorted (by `isless`,
reversed if `rev`), rows equal in `c` keeping their order. A worker per column type. Applied to
the sort columns from the last to the first, it sorts lexicographically, as upstream's stable
default algorithms do, without code compiled per tuple of column types.
"""
function refine!(perm::Vector{Int}, c::Column, rev::Bool)::Nothing
    v = vector(c)
    p = sortperm(view(v, perm); alg = Base.Sort.DEFAULT_STABLE, rev = rev)
    permute!(perm, p)
    return nothing
end

# --- groupby: group codes per column -----------------------------------------------------------

"""
The group codes of one column by first appearance, into `codes` (1, 2, … in order of first
appearance; 0 for `missing` when `skipmissing`); returns the number of codes. Equality is
`isequal`, as upstream's row hashing. A worker per column type.
"""
function firstcodes!(codes::Vector{Int}, c::Column, skipmissing::Bool)::Int
    v = vector(c)
    d = Dict{eltype(v), Int}()
    n = 0
    @inbounds for (k, i) in enumerate(eachindex(v))
        x = v[i]
        if skipmissing && ismissing(x)
            codes[k] = 0
            continue
        end
        g = get(d, x, 0)
        if g == 0
            g = n += 1
            d[x] = g
        end
        codes[k] = g
    end
    return n
end

"""
Upstream's fast grouping path for one column (`row_group_slots!` with reference pools,
groupeddataframe/utils.jl): `nothing` if the column has no usable reference pool; otherwise
the 0-based code of each row (-1 for a skipped `missing`), the number of codes, and whether
the pool is sorted. With `sort`, codes follow the sorted order of the pool. A worker per column type.
"""
function refcodes(c::Column, skipmissing::Bool, sort::Bool)::Union{Nothing, Tuple{Vector{Int}, Int, Bool}}
    v = vector(c)
    refpool, refarray = refpool_and_array(v)
    refpool === nothing && return nothing
    refarray isa Union{AbstractVector{<:Real},
                       Missings.EachReplaceMissing{<:AbstractVector{<:Union{Real, Missing}}}} || return nothing
    fi = firstindex(refpool)
    li = lastindex(refpool)
    missingind = eltype(refpool) >: Missing ? something(findfirst(ismissing, refpool), li + 1) : li + 1
    len = length(refpool)
    ng = skipmissing && missingind <= li ? len - 1 : len
    nmind = missingind > li ? collect(eachindex(refpool)) : setdiff(eachindex(refpool), missingind)
    sorted = sort && (skipmissing ? issorted(view(refpool, nmind)) : issorted(refpool))
    codes = Vector{Int}(undef, length(refarray))
    if sort && !sorted
        refmap = collect(0:len-1)
        if skipmissing
            if missingind <= li
                refmap[missingind-fi+1] = -1
                refmap[missingind-fi+2:end] .-= 1
            end
            perm = sortperm(view(refpool, nmind))
            invpermute!(view(refmap, nmind .- fi .+ 1), perm)
        else
            invpermute!(refmap, sortperm(collect(refpool)))
        end
        @inbounds for (k, i) in enumerate(eachindex(refarray))
            codes[k] = refmap[Int(refarray[i])-fi+1]
        end
    else
        @inbounds for (k, i) in enumerate(eachindex(refarray))
            r = Int(refarray[i])
            if skipmissing
                r = r == missingind ? fi - 1 : (r > missingind ? r - 1 : r)
            end
            codes[k] = r - fi
        end
    end
    return (codes, ng, sorted)
end

# --- combine: fast aggregates ------------------------------------------------------------------

"""
A fast aggregate (`Reduce`, `Aggregate`: `sum`, `mean∘skipmissing`, `maximum`, …) of one
column per group of `gd`, a new vector. A worker per column type and aggregate.
"""
aggregate(c::Column, agg, gd)::AbstractVector = agg(vector(c), gd)

# --- joins ---------------------------------------------------------------------------------------

"""
The matching rows of an inner join on one column each side, `(left rows, right rows)`, by
upstream's algorithms (sorted merge, or hashing the shorter side). A worker per pair of column types.
"""
innerrows(l::Column, r::Column, right_shorter::Bool, disallow_sorted::Bool)::Tuple{Vector{Int}, Vector{Int}} =
    _DF._find_inner_rows(vector(l), vector(r), right_shorter, disallow_sorted)

end
