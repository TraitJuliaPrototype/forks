# ColumnKernels: the trait module of DataFrames (forks/, plan §2.5). The column code of
# describe, sort, groupby, joins and row selection, written once against the `Column` trait
# (Tables.ColumnCore) and compiled per key, the column's type: never per schema or per tuple
# of column types. A kernel reads a column only through the trait's operations (`nrows`,
# `cell`, `emptycells`, `take`, `nlevels`, `levelcode`, `level`); it never unwraps the
# stored vector. Where a kernel needs Base's or Statistics' code over many cells (describe's
# statistics), it gathers the cells into a plain `Vector{T}` first, so that code is compiled
# per cell type `T`, which is what the bound sees, and shared by every column type with
# those cells.
# Upstream reaches the same code through function barriers into code compiled per column
# type (`get_stats(@nospecialize(col))`), or per tuple of column types (`DFPerm`,
# `row_group_slots!`).
@trait_module module ColumnKernels
using TraitWorld
using Tables.ColumnCore: Column, nrows, cell, emptycells, take, nlevels, levelcode, level, vector,
                         TableSource, tablenames, tablecolumn, tablerows
using Statistics
const _DF = parentmodule(@__MODULE__)
export colstats, aggregate, refine!, firstcodes!, refcodes, innerrows, semirows, fromsource

"The cells of `c`, in a new plain `Vector{T}`."
function cells(c::Column)
    n = nrows(c)
    v = emptycells(c, n)
    @inbounds for i in 1:n
        v[i] = cell(c, i)
    end
    return v
end

"The type of the cells of `c` (`T` of `Column{T}`), as a constant of the worker."
celltype(c::Column) = eltype(emptycells(c, 0))

# --- describe -------------------------------------------------------------------------------

"""
`describe`'s predefined statistics of one column, in a `Dict` (a worker per column type).
Missing values are skipped as upstream does: for a cell type that admits `missing`, the
statistics are those of `skipmissing` of the cells.
"""
function colstats(c::Column, stats::Vector{Symbol})::Dict{Symbol, Any}
    n = nrows(c)
    v = cells(c)
    d = eltype(v) >: Missing ? _stats(skipmissing(v), stats) : _stats(v, stats)
    if :nmissing in stats
        k = 0
        for i in 1:n
            k += ismissing(cell(c, i))
        end
        d[:nmissing] = k
    end
    if :nnonmissing in stats
        k = 0
        for i in 1:n
            k += !ismissing(cell(c, i))
        end
        d[:nnonmissing] = k
    end
    :first in stats && (d[:first] = n == 0 ? nothing : cell(c, 1))
    :last in stats && (d[:last] = n == 0 ? nothing : cell(c, n))
    :eltype in stats && (d[:eltype] = eltype(v))
    return d
end

# upstream's `get_stats` (abstractdataframe.jl), without its `@nospecialize`: here it is
# called with the cells, a `Vector{T}` or its `skipmissing`, so it is compiled per cell type
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

# --- combine: fast aggregates over the cells ------------------------------------------------------

"""
A fast aggregate whose result does not depend on the column's kind (`Reduce`: `sum`, `prod`,
`mean`, with or without `skipmissing`; `var`, `std`, `length`) of one column per group of
`gd`: upstream's `groupreduce` over the cells, a plain `Vector{T}`, so its code is compiled per
cell type and aggregate, not per column type. A worker per column type.
"""
aggregate(c::Column, agg, gd)::AbstractVector = agg(cells(c), gd)

# --- sorting --------------------------------------------------------------------------------

"""
Refine the stable order `perm` by column `c`: afterwards the cells of `c` at `perm` are
sorted (by `isless`, reversed if `rev`), rows with equal cells keeping their order. A worker
per column type, comparing cells. Applied to the sort columns from the last to the first, it
sorts lexicographically, as upstream's stable default algorithms do (`MergeSort`, `TimSort`,
`RadixSort`), without code compiled per tuple of column types.
"""
function refine!(perm::Vector{Int}, c::Column, rev::Bool)::Nothing
    sort!(perm; alg = Base.Sort.DEFAULT_STABLE, lt = (i, j) -> isless(cell(c, i), cell(c, j)), rev = rev)
    return nothing
end

# --- groupby: group codes per column -----------------------------------------------------------

"""
The group codes of one column by first appearance, into `codes` (1, 2, … in order of first
appearance; 0 for `missing` when `skipmissing`); returns the number of codes. Equality is
`isequal`, as upstream's row hashing. A worker per column type.
"""
function firstcodes!(codes::Vector{Int}, c::Column, skipmissing::Bool)::Int
    d = Dict{celltype(c), Int}()
    n = 0
    @inbounds for i in 1:nrows(c)
        x = cell(c, i)
        if skipmissing && ismissing(x)
            codes[i] = 0
            continue
        end
        g = get(d, x, 0)
        if g == 0
            g = n += 1
            d[x] = g
        end
        codes[i] = g
    end
    return n
end

"""
Upstream's fast grouping path for one column (`row_group_slots!` with reference pools,
groupeddataframe/utils.jl): `nothing` if the column has no usable reference pool; otherwise
the 0-based code of each row (-1 for a skipped `missing`), the number of codes, and whether
the codes follow the sorted order of the values. A column has a reference pool if the
`Column` implementation gives it levels (pooled and categorical columns), or, as upstream's
`refpool_and_array` decides, if its cells are integers in a narrow range. With `sort`, codes
follow the sorted order of the pool. A worker per column type.
"""
function refcodes(c::Column, skipmissing::Bool, sort::Bool)::Union{Nothing, Tuple{Vector{Int}, Int, Bool}}
    n = nrows(c)
    L = nlevels(c)
    if L > 0
        levels = emptycells(c, L)
        for k in 1:L
            levels[k] = level(c, k)
        end
        codes = Vector{Int}(undef, n)
        for i in 1:n
            codes[i] = levelcode(c, i)
        end
        return _poolcodes!(codes, levels, skipmissing, sort)
    end
    return _integercodes(c, skipmissing)
end

# Codes from a pool `levels` (1-based codes in `codes`, rewritten in place to 0-based).
# Plain code over plain vectors: compiled per cell type.
function _poolcodes!(codes::Vector{Int}, levels::AbstractVector, skipmissing::Bool, sort::Bool)
    len = length(levels)
    missingind = something(findfirst(ismissing, levels), len + 1)
    ng = skipmissing && missingind <= len ? len - 1 : len
    nmind = missingind > len ? collect(1:len) : setdiff(1:len, missingind)
    sorted = sort && (skipmissing ? issorted(view(levels, nmind)) : issorted(levels))
    if sort && !sorted
        refmap = collect(0:len-1)
        if skipmissing
            if missingind <= len
                refmap[missingind] = -1
                refmap[missingind+1:end] .-= 1
            end
            invpermute!(view(refmap, nmind), sortperm(view(levels, nmind)))
        else
            invpermute!(refmap, sortperm(levels))
        end
        @inbounds for i in eachindex(codes)
            codes[i] = refmap[codes[i]]
        end
    else
        @inbounds for i in eachindex(codes)
            r = codes[i]
            if skipmissing
                r = r == missingind ? 0 : (r > missingind ? r - 1 : r)
            end
            codes[i] = r - 1
        end
    end
    return (codes, ng, sorted)
end

# Upstream's `IntegerRefpool`: the cells, if they are integers (or real numbers holding
# integers, not -0.0) in a range at most twice the number of rows, are their own codes:
# `x - min`, `missing` after the largest value. The pool is sorted by construction.
function _integercodes(c::Column, skipmissing::Bool)::Union{Nothing, Tuple{Vector{Int}, Int, Bool}}
    T = celltype(c)
    n = nrows(c)
    (T <: Union{Real, Missing} && n > 0) || return nothing
    if !(T <: Union{Integer, Missing})
        for i in 1:n
            x = cell(c, i)
            (ismissing(x) || (isinteger(x) && !isequal(x, -0.0))) || return nothing
        end
    end
    seen = false
    minval = maxval = 0
    hasmissing = false
    for i in 1:n
        x = cell(c, i)
        if ismissing(x)
            hasmissing = true
            continue
        end
        if !seen
            seen = true
            minval = maxval = x
        else
            minval = min(minval, x)
            maxval = max(maxval, x)
        end
    end
    seen || return nothing                              # only missing values
    ngroups = BigInt(maxval) - BigInt(minval) + 1
    (typemin(Int) < minval <= maxval < typemax(Int) && ngroups + 1 <= Int64(2) * n <= typemax(Int)) ||
        return nothing
    ng = Int(ngroups)
    lo = Int(minval)
    codes = Vector{Int}(undef, n)
    @inbounds for i in 1:n
        x = cell(c, i)
        codes[i] = ismissing(x) ? (skipmissing ? -1 : ng) : Int(x) - lo
    end
    # the pool holds a `missing` level exactly when the cell type admits it
    return (codes, (T >: Missing && !skipmissing) ? ng + 1 : ng, true)
end

# --- joins ---------------------------------------------------------------------------------------

"""
The matching rows of an inner join on one column each side, `(left rows, right rows)`, by
upstream's algorithms (join/core.jl: a sorted merge if both columns are sorted, else hashing
the shorter side, with a direct table for integers in a narrow range), over the cells of the
two columns. A worker per pair of column types.
"""
function innerrows(l::Column, r::Column, right_shorter::Bool, disallow_sorted::Bool)::Tuple{Vector{Int}, Vector{Int}}
    (nrows(l) == 0 || nrows(r) == 0) && return Int[], Int[]
    if !disallow_sorted
        try
            if _issorted(l) && _issorted(r)
                return _innerjoin_sorted(l, r)
            end
        catch
            # one of the columns is not sortable: the unsorted case
        end
    end
    if right_shorter
        return _innerjoin_unsorted(l, r)
    else
        a, b = _innerjoin_unsorted(r, l)
        return b, a
    end
end

function _issorted(c::Column)
    for i in 1:nrows(c)-1
        isless(cell(c, i + 1), cell(c, i)) && return false
    end
    return true
end

function _next_range(c::Column, start::Int, start_value)
    stop_value = start_value
    n = nrows(c)
    stop = start + 1
    while stop <= n
        stop_value = cell(c, stop)
        isequal(start_value, stop_value) || break
        stop += 1
    end
    return stop, stop_value
end

function _innerjoin_sorted(left::Column, right::Column)
    left_n = nrows(left)
    right_n = nrows(right)
    left_ixs = Int[]
    right_ixs = Int[]
    sizehint!(left_ixs, min(left_n, right_n))
    sizehint!(right_ixs, min(left_n, right_n))
    left_cur = 1
    left_val = cell(left, left_cur)
    left_new, left_tmp = _next_range(left, left_cur, left_val)
    right_cur = 1
    right_val = cell(right, right_cur)
    right_new, right_tmp = _next_range(right, right_cur, right_val)
    while left_cur <= left_n && right_cur <= right_n
        if isequal(left_val, right_val)
            if left_new - left_cur == right_new - right_cur == 1
                push!(left_ixs, left_cur)
                push!(right_ixs, right_cur)
            else
                idx = length(left_ixs)
                left_range = left_cur:left_new - 1
                right_range = right_cur:right_new - 1
                to_grow = Base.checked_add(idx, Base.checked_mul(length(left_range), length(right_range)))
                resize!(left_ixs, to_grow)
                resize!(right_ixs, to_grow)
                @inbounds for right_i in right_range, left_i in left_range
                    idx += 1
                    left_ixs[idx] = left_i
                    right_ixs[idx] = right_i
                end
            end
            left_cur, left_val = left_new, left_tmp
            left_new, left_tmp = _next_range(left, left_cur, left_val)
            right_cur, right_val = right_new, right_tmp
            right_new, right_tmp = _next_range(right, right_cur, right_val)
        elseif isless(left_val, right_val)
            left_cur, left_val = left_new, left_tmp
            left_new, left_tmp = _next_range(left, left_cur, left_val)
        else
            right_cur, right_val = right_new, right_tmp
            right_new, right_tmp = _next_range(right, right_cur, right_val)
        end
    end
    return left_ixs, right_ixs
end

# upstream's `_innerjoin_unsorted` and `_innerjoin_unsorted_int`: `right` is hashed (or
# tabled, for integers in a narrow range); it is assumed to have no duplicates until one is
# found, then the duplicate-aware path continues from there
function _innerjoin_unsorted(left::Column, right::Column)
    if celltype(left) <: Union{Integer, Missing} && celltype(right) <: Union{Integer, Missing}
        res = _innerjoin_unsorted_int(left, right)
        res === nothing || return res
    end
    dict = Dict{celltype(right), Int}()
    right_len = nrows(right)
    sizehint!(dict, 2 * min(right_len, typemax(Int) >> 2))
    for idx_r in 1:right_len
        val_r = cell(right, idx_r)
        haskey(dict, val_r) && return _innerjoin_dup(left, right, dict, idx_r)
        dict[val_r] = idx_r
    end
    left_ixs = Int[]
    right_ixs = Int[]
    sizehint!(left_ixs, right_len)
    sizehint!(right_ixs, right_len)
    for idx_l in 1:nrows(left)
        idx_r = get(dict, cell(left, idx_l), -1)
        if idx_r != -1
            push!(left_ixs, idx_l)
            push!(right_ixs, idx_r)
        end
    end
    return left_ixs, right_ixs
end

# upstream's `extrema_missing`: the extrema of the non-missing integer cells, `(1, 0)` if there are none
function _extrema_missing(c::Column)
    seen = false
    minv = maxv = 0
    for i in 1:nrows(c)
        x = cell(c, i)
        ismissing(x) && continue
        if !seen
            seen = true
            minv = maxv = x
        else
            minv = min(minv, x)
            maxv = max(maxv, x)
        end
    end
    return seen ? (BigInt(minv), BigInt(maxv)) : (BigInt(1), BigInt(0))
end

function _innerjoin_unsorted_int(left::Column, right::Column)::Union{Nothing, Tuple{Vector{Int}, Vector{Int}}}
    minv, maxv = _extrema_missing(right)
    val_range = maxv - minv
    if val_range > typemax(Int) - 3 || val_range ÷ 2 > max(64, nrows(right)) ||
       minv < typemin(Int) + 2 || maxv > typemax(Int) - 3
        return nothing
    end
    mn = Int(minv)
    mx = Int(maxv)
    offset = 1 - mn
    len = mx - mn + 2
    group_map = zeros(Int, len)
    right_len = nrows(right)
    @inbounds for idx_r in 1:right_len
        val_r = cell(right, idx_r)
        i = ismissing(val_r) ? length(group_map) : Int(val_r) + offset
        if group_map[i] > 0
            return _innerjoin_dup_int(left, right, group_map, idx_r, offset, mn, mx)
        end
        group_map[i] = idx_r
    end
    left_ixs = Int[]
    right_ixs = Int[]
    sizehint!(left_ixs, right_len)
    sizehint!(right_ixs, right_len)
    @inbounds for idx_l in 1:nrows(left)
        val_l = cell(left, idx_l)
        if ismissing(val_l)
            idx_r = group_map[end]
            if idx_r > 0
                push!(left_ixs, idx_l)
                push!(right_ixs, idx_r)
            end
        elseif mn <= val_l <= mx
            idx_r = group_map[Int(val_l) + offset]
            if idx_r > 0
                push!(left_ixs, idx_l)
                push!(right_ixs, idx_r)
            end
        end
    end
    return left_ixs, right_ixs
end

function _innerjoin_dup(left::Column, right::Column, dict::Dict, idx_r_start::Int)
    ngroups = idx_r_start - 1
    right_len = nrows(right)
    groups = Vector{Int}(undef, right_len)
    groups[1:ngroups] = 1:ngroups
    @inbounds for idx_r in idx_r_start:right_len
        val_r = cell(right, idx_r)
        group_id = get(dict, val_r, -1)
        if group_id == -1
            ngroups += 1
            groups[idx_r] = ngroups
            dict[val_r] = ngroups
        else
            groups[idx_r] = group_id
        end
    end
    starts, rperm = _join_indices(groups, ngroups)
    left_ixs = Int[]
    right_ixs = Int[]
    sizehint!(left_ixs, right_len)
    sizehint!(right_ixs, right_len)
    n = 0
    @inbounds for idx_l in 1:nrows(left)
        group_id = get(dict, cell(left, idx_l), -1)
        if group_id != -1
            n = _push_matches!(left_ixs, right_ixs, n, idx_l, group_id, starts, rperm)
        end
    end
    return left_ixs, right_ixs
end

function _innerjoin_dup_int(left::Column, right::Column, group_map::Vector{Int}, idx_r_start::Int,
                            offset::Int, minv::Int, maxv::Int)
    ngroups = idx_r_start - 1
    right_len = nrows(right)
    groups = Vector{Int}(undef, right_len)
    groups[1:ngroups] = 1:ngroups
    @inbounds for idx_r in idx_r_start:right_len
        val_r = cell(right, idx_r)
        i = ismissing(val_r) ? length(group_map) : Int(val_r) + offset
        group_map_val = group_map[i]
        if group_map_val > 0
            groups[idx_r] = group_map_val
        else
            ngroups += 1
            groups[idx_r] = ngroups
            group_map[i] = ngroups
        end
    end
    starts, rperm = _join_indices(groups, ngroups)
    left_ixs = Int[]
    right_ixs = Int[]
    sizehint!(left_ixs, right_len)
    sizehint!(right_ixs, right_len)
    n = 0
    @inbounds for idx_l in 1:nrows(left)
        val_l = cell(left, idx_l)
        group_id = ismissing(val_l) ? group_map[end] : (minv <= val_l <= maxv ? group_map[Int(val_l) + offset] : 0)
        if group_id > 0
            n = _push_matches!(left_ixs, right_ixs, n, idx_l, group_id, starts, rperm)
        end
    end
    return left_ixs, right_ixs
end

# upstream's `compute_join_indices!`: the rows of `right` by group, for `_push_matches!`
function _join_indices(groups::Vector{Int}, ngroups::Int)
    starts = zeros(Int, ngroups)
    rperm = Vector{Int}(undef, length(groups))
    @inbounds for gix in groups
        starts[gix] += 1
    end
    cumsum!(starts, starts)
    @inbounds for (i, gix) in enumerate(groups)
        rperm[starts[gix]] = i
        starts[gix] -= 1
    end
    push!(starts, length(groups))
    return starts, rperm
end

# the rows of group `group_id` of `right`, each matched with left row `idx_l`, in upstream's order
function _push_matches!(left_ixs::Vector{Int}, right_ixs::Vector{Int}, n::Int, idx_l::Int,
                        group_id::Int, starts::Vector{Int}, rperm::Vector{Int})
    ref_stop = starts[group_id + 1]
    l = ref_stop - starts[group_id]
    newn = n + l
    resize!(left_ixs, newn)
    @inbounds for i in n+1:n+l
        left_ixs[i] = idx_l
    end
    resize!(right_ixs, newn)
    @inbounds for i in 1:l
        right_ixs[n + i] = rperm[ref_stop - i + 1]
    end
    return newn
end


"""
The rows of the left column that have a match in the right column, for `semijoin` and
`antijoin` on one column each side (upstream's `find_semi_rows`, join/core.jl, ported onto
the cells: a sorted merge, a set or table of the shorter side). A worker per pair of column types.
"""
function semirows(l::Column, r::Column, right_shorter::Bool, disallow_sorted::Bool)::BitVector
    seen_rows = falses(nrows(l))
    (nrows(l) == 0 || nrows(r) == 0) && return seen_rows
    if !disallow_sorted
        try
            if _issorted(l) && _issorted(r)
                return _semijoin_sorted(l, r, seen_rows)
            end
        catch
            # one of the columns is not sortable: the unsorted case
        end
    end
    return right_shorter ? _semijoin_unsorted(l, r, seen_rows, true) : _semijoin_unsorted(r, l, seen_rows, false)
end

function _semijoin_sorted(left::Column, right::Column, seen_rows::BitVector)
    left_n = nrows(left)
    right_n = nrows(right)
    left_cur = 1
    left_val = cell(left, left_cur)
    left_new, left_tmp = _next_range(left, left_cur, left_val)
    right_cur = 1
    right_val = cell(right, right_cur)
    right_new, right_tmp = _next_range(right, right_cur, right_val)
    while left_cur <= left_n && right_cur <= right_n
        if isequal(left_val, right_val)
            seen_rows[left_cur:left_new - 1] .= true
            left_cur, left_val = left_new, left_tmp
            left_new, left_tmp = _next_range(left, left_cur, left_val)
            right_cur, right_val = right_new, right_tmp
            right_new, right_tmp = _next_range(right, right_cur, right_val)
        elseif isless(left_val, right_val)
            left_cur, left_val = left_new, left_tmp
            left_new, left_tmp = _next_range(left, left_cur, left_val)
        else
            right_cur, right_val = right_new, right_tmp
            right_new, right_tmp = _next_range(right, right_cur, right_val)
        end
    end
    return seen_rows
end

# upstream's `_semijoin_unsorted(_int)`: with `right_shorter`, `seen_rows` marks rows of
# `left`; otherwise the columns come swapped (`left` is the right table's column) and it marks
# rows of `right`
function _semijoin_unsorted(left::Column, right::Column, seen_rows::BitVector, right_shorter::Bool)
    if celltype(left) <: Union{Integer, Missing} && celltype(right) <: Union{Integer, Missing}
        res = _semijoin_unsorted_int(left, right, seen_rows, right_shorter)
        res === nothing || return res
    end
    right_len = nrows(right)
    if right_shorter
        set = Set{celltype(right)}()
        sizehint!(set, 2 * min(right_len, typemax(Int) >> 2))
        for idx_r in 1:right_len
            push!(set, cell(right, idx_r))
        end
        @inbounds for idx_l in 1:nrows(left)
            seen_rows[idx_l] = cell(left, idx_l) in set
        end
    else
        dict = Dict{celltype(right), Int}()
        sizehint!(dict, 2 * min(right_len, typemax(Int) >> 2))
        for idx_r in 1:right_len
            val_r = cell(right, idx_r)
            haskey(dict, val_r) && return _semijoin_dup(left, right, dict, idx_r, seen_rows)
            dict[val_r] = idx_r
        end
        @inbounds for idx_l in 1:nrows(left)
            idx_r = get(dict, cell(left, idx_l), -1)
            idx_r != -1 && (seen_rows[idx_r] = true)
        end
    end
    return seen_rows
end

function _semijoin_unsorted_int(left::Column, right::Column, seen_rows::BitVector,
                                right_shorter::Bool)::Union{Nothing, BitVector}
    minv, maxv = _extrema_missing(right)
    val_range = maxv - minv
    if val_range > typemax(Int) - 3 || val_range ÷ 2 > max(64, nrows(right)) ||
       minv < typemin(Int) + 2 || maxv > typemax(Int) - 3
        return nothing
    end
    mn = Int(minv)
    mx = Int(maxv)
    offset = 1 - mn
    group_map = zeros(Int, mx - mn + 2)
    if right_shorter
        @inbounds for idx_r in 1:nrows(right)
            val_r = cell(right, idx_r)
            group_map[ismissing(val_r) ? length(group_map) : Int(val_r) + offset] = idx_r
        end
        @inbounds for idx_l in 1:nrows(left)
            val_l = cell(left, idx_l)
            if ismissing(val_l)
                seen_rows[idx_l] = group_map[end] > 0
            elseif mn <= val_l <= mx
                seen_rows[idx_l] = group_map[Int(val_l) + offset] > 0
            end
        end
    else
        @inbounds for idx_r in 1:nrows(right)
            val_r = cell(right, idx_r)
            i = ismissing(val_r) ? length(group_map) : Int(val_r) + offset
            group_map[i] > 0 && return _semijoin_dup_int(left, right, group_map, idx_r, offset, mn, mx, seen_rows)
            group_map[i] = idx_r
        end
        @inbounds for idx_l in 1:nrows(left)
            val_l = cell(left, idx_l)
            idx_r = ismissing(val_l) ? group_map[end] : (mn <= val_l <= mx ? group_map[Int(val_l) + offset] : 0)
            idx_r > 0 && (seen_rows[idx_r] = true)
        end
    end
    return seen_rows
end

function _semijoin_dup(left::Column, right::Column, dict::Dict, idx_r_start::Int, seen_rows::BitVector)
    ngroups = idx_r_start - 1
    right_len = nrows(right)
    groups = Vector{Int}(undef, right_len)
    groups[1:ngroups] = 1:ngroups
    @inbounds for idx_r in idx_r_start:right_len
        val_r = cell(right, idx_r)
        group_id = get(dict, val_r, -1)
        if group_id == -1
            ngroups += 1
            groups[idx_r] = ngroups
            dict[val_r] = ngroups
        else
            groups[idx_r] = group_id
        end
    end
    starts, rperm = _join_indices(groups, ngroups)
    @inbounds for idx_l in 1:nrows(left)
        group_id = get(dict, cell(left, idx_l), -1)
        group_id != -1 && _mark_group!(seen_rows, group_id, starts, rperm)
    end
    return seen_rows
end

function _semijoin_dup_int(left::Column, right::Column, group_map::Vector{Int}, idx_r_start::Int,
                           offset::Int, minv::Int, maxv::Int, seen_rows::BitVector)
    ngroups = idx_r_start - 1
    right_len = nrows(right)
    groups = Vector{Int}(undef, right_len)
    groups[1:ngroups] = 1:ngroups
    @inbounds for idx_r in idx_r_start:right_len
        val_r = cell(right, idx_r)
        i = ismissing(val_r) ? length(group_map) : Int(val_r) + offset
        group_map_val = group_map[i]
        if group_map_val > 0
            groups[idx_r] = group_map_val
        else
            ngroups += 1
            groups[idx_r] = ngroups
            group_map[i] = ngroups
        end
    end
    starts, rperm = _join_indices(groups, ngroups)
    @inbounds for idx_l in 1:nrows(left)
        val_l = cell(left, idx_l)
        group_id = ismissing(val_l) ? group_map[end] : (minv <= val_l <= maxv ? group_map[Int(val_l) + offset] : 0)
        group_id > 0 && _mark_group!(seen_rows, group_id, starts, rperm)
    end
    return seen_rows
end

function _mark_group!(seen_rows::BitVector, group_id::Int, starts::Vector{Int}, rperm::Vector{Int})
    ref_stop = starts[group_id + 1]
    l = ref_stop - starts[group_id]
    @inbounds for i in 1:l
        seen_rows[rperm[ref_stop - i + 1]] = true
    end
    return nothing
end

# --- tables: a DataFrame from any TableSource -------------------------------------------------

"""
    fromsource(t, copycols)

A `DataFrame` with the columns of `t`, any `TableSource` (a `CSV.File`, a column table, a
`DataFrame`): the columns are read by position as `Dynamic{Column}` values and kept as they
are, or copied with `copycols`, as upstream's `fromcolumns` does for a Tables.jl table.
"""
function fromsource(t::TableSource, copycols::Bool)::_DF.DataFrame
    nms = tablenames(t)
    cols = AbstractVector[vector(tablecolumn(t, i)::Dynamic{Column})::AbstractVector
                          for i in eachindex(nms)]
    return _DF.DataFrame(cols, _DF.Index(nms), copycols = copycols)
end

end

# --- DataFrame and SubDataFrame as TableSource (DataFrames owns the types) ----------------------

@implement TableSource DataFrame begin
    tablenames(t) = copy(_names(t))
    tablecolumn(t, i) = _dcolumn(t, i)
    tablerows(t) = nrow(t)
end
@implement TableSource SubDataFrame begin
    tablenames(t) = copy(_names(t))
    tablecolumn(t, i) = tocolumn(t[!, i])::Dynamic{Column}
    tablerows(t) = nrow(t)
end
