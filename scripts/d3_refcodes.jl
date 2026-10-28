# E-214: the groupby kernel's per-column codes alone (`refcodes`), on 10^6 rows, the column opened and `Dynamic`;
# and `colstats`' gather alone; against the same loop in plain code.
#     julia --project=env_forks scripts/d3_refcodes.jl
using CSV, DataFrames, Random, TraitWorld
const K = DataFrames.ColumnKernels; const CC = DataFrames.Tables.ColumnCore
Random.seed!(1)
v = rand(1:1000, 10^6)
d = CC.tocolumn(v)
function plaincodes(v)
    lo, hi = extrema(v); codes = Vector{Int}(undef, length(v))
    @inbounds for i in eachindex(v); codes[i] = v[i] - lo; end
    return codes
end
bench(f) = (f(); f(); minimum(@elapsed(f()) for _ in 1:5) * 1e3)
println("R refcodes opened   ", round(bench(() -> K.refcodes(compiled_for(d), false, true)); digits = 2), " ms")
println("R refcodes Dynamic  ", round(bench(() -> K.refcodes(d, false, true)); digits = 2), " ms")
println("R plain codes       ", round(bench(() -> plaincodes(v)); digits = 2), " ms")
println("R nrows(opened)     ", round(bench(() -> K.nrows(compiled_for(d))) * 1e3; digits = 2), " µs")
