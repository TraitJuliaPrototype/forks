# Open issue 101: which vectors that reach `Column` infer Base's contract (`length` an `Int`, `v[i]` of
# the element type), and whether each passes the member check of `@implement Column A where {A <: AbstractVector}`
# without assertions. Per type: `Base.infer_return_type` of `length` and `getindex(v, ::Int)`, and the
# problems `_member_problems(Column, T)` reports (meaningful when ColumnCore does not assert the contract).
#     julia --project=env_d2 scripts/rv_infer.jl
# With DataFrames' test-only vector packages (OffsetArrays, ShiftedArrays, DataValues, SparseArrays,
# FillArrays) from an extra environment on the load path, they are probed too:
#     JULIA_LOAD_PATH="@:<extra env>:@stdlib" julia --project=env_d2 scripts/rv_infer.jl
using DataFrames, CSV, PooledArrays, CategoricalArrays, InlineStrings, Dates, Tables, TraitWorld
const SentinelArrays = DataFrames.SentinelArrays      # CSV's fork does not use SentinelArrays; DataFrames imports it
const Column = Tables.ColumnCore.Column
const D = joinpath(@__DIR__, "..", "data")

# upstream DataFrames' two vectors, copied as they are there: the parent at an abstract type; the length
# summed over a `Vector{Any}` of components
struct UpstreamRepeatedVector{T} <: AbstractVector{T}
    parent::AbstractVector{T}; inner::Int; outer::Int
end
Base.parent(v::UpstreamRepeatedVector) = v.parent
Base.getindex(v::UpstreamRepeatedVector, i::Int) = (N = length(parent(v)); parent(v)[Base.fld1(mod1(i, v.inner*N), v.inner)])
Base.size(v::UpstreamRepeatedVector) = (length(v),)
Base.length(v::UpstreamRepeatedVector) = v.inner * v.outer * length(parent(v))
struct UpstreamStackedVector{T} <: AbstractVector{T}
    components::Vector{Any}
end
Base.getindex(v::UpstreamStackedVector{T}, i::Int) where {T} = DataFrames.StackedVector{T}(v.components)[i]
Base.size(v::UpstreamStackedVector) = (length(v),)
Base.length(v::UpstreamStackedVector) = sum(map(length, v.components))

vs = Any[UpstreamRepeatedVector{Int}([1, 2], 2, 1), UpstreamStackedVector{Int}(Any[[1, 2], [3]]),
         [1, 2], [1.0], ["a"], [:a], Any[1, "a"], [1, missing], [Date(2020)], String15["a"],
         1:3, Base.OneTo(3), 1:2:5, 0.0:0.5:1.0, view([1, 2, 3], 1:2), view([1, 2, 3], [1, 3]),
         view([1, 2, 3], [true, false, true]), reverse(view([1, 2, 3], 1:2)), BitVector([true]),
         PooledArray(["a"]), PooledArray(["a", missing]), view(PooledArray(["a", "b"]), [2]),
         categorical(["a"]), categorical(["a", missing]), view(categorical(["a", "b"]), 1:1),
         SentinelArrays.ChainedVector([[1], [2]]), SentinelArrays.MissingVector(2),
         SentinelArrays.SentinelVector{Int}(undef, 2),
         DataFrames.RepeatedVector([1, 2], 2, 1), DataFrames.RepeatedVector(categorical(["a"]), 1, 2),
         DataFrames.RepeatedVector(view([1, 2, 3], 1:2), 1, 2), DataFrames.StackedVector(Any[[1, 2], [3]])]

# the column types a short workload puts in a frame: CSV's reads, a stacked view, a frame's view
for (f, kw) in (("people.csv", (;)), ("orders.csv", (;)), ("sensors.csv", (;)), ("people.csv", (; stringtype = String15)))
    df = CSV.read(joinpath(D, f), DataFrame; kw...)
    append!(vs, eachcol(df)); append!(vs, eachcol(view(df, [1, 2], :))); append!(vs, eachcol(view(df, 1:2, :)))
end
let df = DataFrame(id = 1:3, a = [1.0, 2.0, 3.0], b = ["x", "y", "z"])
    for (what, f) in (("stack view", () -> stack(df, [:a]; view = true)),
                      ("stack view Symbol", () -> stack(df, [:a]; view = true, variable_eltype = Symbol)),
                      ("stack", () -> stack(df, [:a])), ("unstack", () -> unstack(stack(df, [:a]), :variable, :value)))
        try; append!(vs, eachcol(f())); catch e; println("workload ", what, ": ", sprint(showerror, e)); end
    end
end

# DataFrames' test-only vector packages, when reachable
for (pkg, mk) in ((:OffsetArrays, m -> Any[m.OffsetArray([1, 2], 1:2)]),
                  (:ShiftedArrays, m -> Any[m.ShiftedVector([1, 2], 1), m.CircShiftedVector([1, 2], 1)]),
                  (:DataValues, m -> Any[m.DataValueArray([1, 2])]),
                  (:SparseArrays, m -> Any[m.sparsevec([1], [1.0], 2)]),
                  (:FillArrays, m -> Any[m.Fill(1, 2), m.Zeros(2)]))
    m = try; Base.require(Main, pkg); catch; nothing; end
    m === nothing ? println("(", pkg, " not reachable)") : append!(vs, Base.invokelatest(mk, m))
end

seen = Set{Any}(); nref = 0
for v in vs
    T = typeof(v); T in seen && continue; push!(seen, T)
    l = Base.infer_return_type(length, (T,)); g = Base.infer_return_type(getindex, (T, Int))
    contract = l === Int && g <: eltype(T)
    ps = try; TraitWorld._latest(TraitWorld._member_problems, Column, T); catch e; ["error: " * sprint(showerror, e)]; end
    global nref += !isempty(ps)
    name = sprint(show, T; context = :compact => true)
    println(rpad(length(name) > 60 ? name[1:57] * "..." : name, 61), " length::", rpad(string(l), 6),
            " getindex::", rpad(string(g), 28), contract ? " contract" : " WIDER   ", isempty(ps) ? " member ok" : " REFUSED")
    isempty(ps) || foreach(p -> println("    ", p), ps)
end
println(length(seen), " types; refused by the member check: ", nref)
