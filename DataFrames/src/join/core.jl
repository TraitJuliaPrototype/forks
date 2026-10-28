### Common preprocessing

struct OnColRow{T}
    row::Int
    cols::T
    h::Vector{UInt}

    OnColRow(row::Union{Signed,Unsigned},
             cols::NTuple{<:Any, AbstractVector}, h::Vector{UInt}) =
        new{typeof(cols)}(Int(row), cols, h)
end

struct OnCol{T,N} <: AbstractVector{OnColRow{T}}
    len::Int
    cols::T
    h::Vector{UInt}

    function OnCol(cs::AbstractVector...)
        @assert length(cs) > 1
        len = length(cs[1])
        @assert all(x -> firstindex(x) == 1, cs)
        @assert all(x -> lastindex(x) == len, cs)
        new{typeof(cs), length(cs)}(len, cs, UInt[])
    end
end

Base.IndexStyle(::Type{<:OnCol}) = Base.IndexLinear()

@inline Base.size(oc::OnCol) = (oc.len,)

@inline function Base.getindex(oc::OnCol, i::Int)
    @boundscheck checkbounds(oc, i)
    return OnColRow(i, oc.cols, oc.h)
end

# Note second argument is ignored as it is always zero in practice
@inline Base.hash(ocr1::OnColRow, ::UInt) = @inbounds ocr1.h[ocr1.row]

# Hashing one column at a time is faster since it can use SIMD
function _prehash(oc::OnCol)
    h = oc.h
    resize!(h, oc.len)
    h0 = @static Base.VERSION >= v"1.13.0-DEV" ? Base.HASH_SEED : UInt(0)
    h0 ⊻= Base.tuplehash_seed
    fill!(h, h0)
    for col in reverse(oc.cols)
        h .= hash.(col, h)
    end
end

# TODO: rewrite isequal and isless to use @generated
# or some other approach that would keep them efficient and avoid code duplication

Base.:(==)(x::OnColRow, y::OnColRow) = throw(MethodError(==, (x, y)))

@inline function Base.isequal(ocr1::OnColRow{<:NTuple{2, AbstractVector}},
                              ocr2::OnColRow{<:NTuple{2, AbstractVector}})
    r1 = ocr1.row
    c11, c12 = ocr1.cols
    r2 = ocr2.row
    c21, c22 = ocr2.cols

    return @inbounds isequal(c11[r1], c21[r2]) && isequal(c12[r1], c22[r2])
end

Base.isequal(ocr1::OnColRow{<:NTuple{N,AbstractVector}},
             ocr2::OnColRow{<:NTuple{N,AbstractVector}}) where {N} =
    isequal(ntuple(i -> @inbounds(ocr1.cols[i][ocr1.row]), N),
            ntuple(i -> @inbounds(ocr2.cols[i][ocr2.row]), N))

@inline function Base.isless(ocr1::OnColRow{<:NTuple{2, AbstractVector}},
                             ocr2::OnColRow{<:NTuple{2, AbstractVector}})
    r1 = ocr1.row
    c11, c12 = ocr1.cols
    r2 = ocr2.row
    c21, c22 = ocr2.cols

    c11r = @inbounds c11[r1]
    c12r = @inbounds c12[r1]
    c21r = @inbounds c21[r2]
    c22r = @inbounds c22[r2]

    isless(c11r, c21r) || (isequal(c11r, c21r) && isless(c12r, c22r))
end

@inline Base.isless(ocr1::OnColRow{<:NTuple{N,AbstractVector}},
                    ocr2::OnColRow{<:NTuple{N,AbstractVector}}) where {N} =
    isless(ntuple(i -> @inbounds(ocr1.cols[i][ocr1.row]), N),
           ntuple(i -> @inbounds(ocr2.cols[i][ocr2.row]), N))

prepare_on_col() = throw(ArgumentError("at least one on column required when joining"))
prepare_on_col(c::AbstractVector) = c
prepare_on_col(cs::AbstractVector...) = OnCol(cs...)

# Return if it is allowed to use refpool instead of the original array for joining.
# There are multiple conditions that must be met to allow for this.
# If it is allowed we are sure that missing can be used as a sentinel
check_mapping_allowed(short::AbstractVector, refarray_long::AbstractVector,
                      refpool_long, invrefpool_long) =
    !isempty(short) && !isnothing(refpool_long) && !isnothing(invrefpool_long) &&
        eltype(refarray_long) <: Union{Signed, Unsigned}

@noinline map_refarray(mapping::AbstractVector, refarray::AbstractVector,
                       ::Val{fi})  where {fi} =
    [@inbounds mapping[r - fi + 1] for r in refarray]

function map2refs(x::AbstractVector, invrefpool)
    x_refpool = DataAPI.refpool(x)
    if x_refpool isa AbstractVector{<:Integer} && 0 <= firstindex(x_refpool) <= 1
        # here we know that x_refpool is AbstractVector that allows integer indexing
        # and its firstindex must be an integer
        # if firstindex is not 0 or 1 then we fallback to slow path for safety reasons
        # all refpool we currently know have firstindex 0 or 1
        # if there is some very strange firstindex we might run into overflow issues
        # below use function barrier as mapping is not type stable
        mapping = [get(invrefpool, v, missing) for v in x_refpool]
        return map_refarray(mapping, DataAPI.refarray(x), Val(Int(firstindex(x_refpool))))
    else
        return [get(invrefpool, v, missing) for v in x]
    end
end

function preprocess_columns(joiner::DataFrameJoiner)
    right_len = length(joiner.dfr_on[!, 1])
    left_len = length(joiner.dfl_on[!, 1])
    right_shorter = right_len < left_len

    left_cols = collect(eachcol(joiner.dfl_on))
    right_cols = collect(eachcol(joiner.dfr_on))

    # if column of the longer table supports DataAPI.refpool and DataAPI.invrefpool
    # remap matching left and right columns to use refs
    if right_shorter
        for i in eachindex(left_cols, right_cols)
            rc = right_cols[i]
            lc = left_cols[i]

            lc_refs = DataAPI.refarray(lc)
            lc_refpool = DataAPI.refpool(lc)
            lc_invrefpool = DataAPI.invrefpool(lc)
            if check_mapping_allowed(rc, lc_refs, lc_refpool, lc_invrefpool)
                right_cols[i] = map2refs(rc, lc_invrefpool)
                left_cols[i] = lc_refs
            end
        end
    else
        for i in eachindex(left_cols, right_cols)
            rc = right_cols[i]
            lc = left_cols[i]

            rc_refs = DataAPI.refarray(rc)
            rc_refpool = DataAPI.refpool(rc)
            rc_invrefpool = DataAPI.invrefpool(rc)
            if check_mapping_allowed(lc, rc_refs, rc_refpool, rc_invrefpool)
                right_cols[i] = rc_refs
                left_cols[i] = map2refs(lc, rc_invrefpool)
            end
        end
    end

    disallow_sorted = false

    for (lc, rc) in zip(left_cols, right_cols)
        @assert length(lc) == left_len
        @assert length(rc) == right_len
        lc_et = nonmissingtype(eltype(lc))
        rc_et = nonmissingtype(eltype(rc))

        # special case common safe scenarios when eltype between left and right
        # column can be different or non-concrete
        lc_et <: Real && rc_et <: Real && continue
        lc_et <: AbstractString && rc_et <: AbstractString && continue

        # otherwise we require non-missing eltype of both sides to be the same and concrete
        lc_et === rc_et && isconcretetype(lc_et) && continue

        # we disallow using sorted branch for some columns that theoretically
        # could be safely sorted (e.g. having Any eltype but holding strings)
        # for safety reasons assuming that such cases will be rare in practice
        disallow_sorted = true
    end

    # TODO:
    # If DataAPI.invrefpool vectors are found in the "on" columns
    # then potentially the following optimizations can be done:
    # 1. identify rows in shorter table that should be dropped
    # 2. develop custom _innerjoin_sorted and _innerjoin_unsorted that drop rows
    #    from shorter table that do not match rows from longer table based on
    #    PooledArray refpool check
    # This optimization would significantly complicate the code (especially
    # sorted path). It should be added if in practice we find that the use case
    # is often enough and that the benefits are significant. The two cases when
    # the benefits should be expected are:
    # 1. Shorter table is sorted when we drop rows not matching longer table rows
    # 2. Shorter table does not have duplicates when we drop rows not matching
    #    longer table rows

    # forks: the key columns themselves, not upstream's `OnCol`, which is compiled per tuple of
    # key column types (`OnCol` stays, unused by the joins)
    isempty(left_cols) && prepare_on_col()

    return left_cols, right_cols, right_shorter, disallow_sorted
end

# forks: the join keys of several key columns, one integer per row, for the one-column kernels.
# Each pair of key columns is coded by `ColumnKernels.jointcodes!` (a worker per pair of column
# types): equal codes for `isequal` cells, in `isless` order when all cells can be compared.
# The codes are folded into one key per row, the first column most significant (mixed radix):
# two rows have equal keys exactly when their key cells are `isequal` (as upstream's `OnCol`
# rows), and the keys are ordered as the rows are when all codes are ordered. Plain code over
# `Vector{Int}`: compiled once, for every key schema.
function joinkeys(left_cols::AbstractVector, right_cols::AbstractVector, disallow_sorted::Bool)
    nl = length(left_cols[1])::Int
    nr = length(right_cols[1])::Int
    lk = ones(Int, nl)
    rk = ones(Int, nr)
    lc = Vector{Int}(undef, nl)
    rc = Vector{Int}(undef, nr)
    m = 1                               # the keys so far are in 1:m
    ordered = !disallow_sorted
    for i in eachindex(left_cols, right_cols)
        # the columns' types are not known here: the result asserted, so the loops below are typed
        n, o = jointcodes!(lc, rc, tocolumn(left_cols[i]), tocolumn(right_cols[i]), ordered)::Tuple{Int, Bool}
        ordered &= o
        # the keys would overflow: number them 1, 2, … in their order first (at most nl + nr)
        m > typemax(Int) ÷ n && (m = densekeys!(lk, rk))
        m = Base.checked_mul(m, n)
        @inbounds for j in 1:nl
            lk[j] = (lk[j] - 1) * n + lc[j]
        end
        @inbounds for j in 1:nr
            rk[j] = (rk[j] - 1) * n + rc[j]
        end
    end
    return lk, rk, ordered
end

# the keys of both sides renumbered 1, 2, … in their order; returns their number
function densekeys!(lk::Vector{Int}, rk::Vector{Int})
    u = sort!(union(lk, rk))
    @inbounds for j in eachindex(lk)
        lk[j] = searchsortedfirst(u, lk[j])
    end
    @inbounds for j in eachindex(rk)
        rk[j] = searchsortedfirst(u, rk[j])
    end
    return length(u)
end

function find_inner_rows(joiner::DataFrameJoiner)
    left_cols, right_cols, right_shorter, disallow_sorted = preprocess_columns(joiner)
    # forks: the rows matched by a kernel for one key column each side (ColumnKernels.innerrows,
    # a worker per pair of column types): on the key columns, or on the join keys of several,
    # with upstream's algorithms (a sorted merge only if the keys keep the rows' order)
    if length(left_cols) == 1
        return innerrows(tocolumn(left_cols[1]), tocolumn(right_cols[1]), right_shorter, disallow_sorted)
    end
    (isempty(left_cols[1]) || isempty(right_cols[1])) && return Int[], Int[]
    lk, rk, ordered = joinkeys(left_cols, right_cols, disallow_sorted)
    return innerrows(tocolumn(lk), tocolumn(rk), right_shorter, !ordered)
end

function find_semi_rows(joiner::DataFrameJoiner)
    left_cols, right_cols, right_shorter, disallow_sorted = preprocess_columns(joiner)
    # forks: as `find_inner_rows`, with ColumnKernels.semirows
    if length(left_cols) == 1
        return semirows(tocolumn(left_cols[1]), tocolumn(right_cols[1]), right_shorter, disallow_sorted)
    end
    (isempty(left_cols[1]) || isempty(right_cols[1])) && return falses(length(left_cols[1]))
    lk, rk, ordered = joinkeys(left_cols, right_cols, disallow_sorted)
    return semirows(tocolumn(lk), tocolumn(rk), right_shorter, !ordered)
end
