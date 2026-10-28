# E-214: the groupby-sum case split into its parts, in one setting.
#     julia --project=<env> scripts/d3_split.jl <label>
using CSV, DataFrames, PooledArrays, Statistics, Random
const LABEL = isempty(ARGS) ? "?" : ARGS[1]
Random.seed!(1)
const N = 10^6
df = DataFrame(i = rand(1:1000, N), f = randn(N), p = PooledArray(rand([randstring(8) for _ in 1:50], N)))
gi = groupby(df, :i); gp = groupby(df, :p)
cases = [
    "groupby Int key"         => () -> groupby(df, :i),
    "groupby Int, rows"       => () -> DataFrames.groupindices(groupby(df, :i)),
    "groupby pooled, rows"    => () -> DataFrames.groupindices(groupby(df, :p)),
    "combine sum (gd built)"  => () -> combine(gi, :f => sum),
    "combine sum pooled gd"   => () -> combine(gp, :f => sum),
]
for (name, f) in cases
    f(); f()
    t = minimum(@elapsed(f()) for _ in 1:5)
    a = @allocated f()
    println("D3 ", rpad(LABEL, 9), rpad(name, 26), lpad(round(t * 1e3; digits = 2), 10), " ms ", lpad(round(a / 2^20; digits = 1), 8), " MiB")
end
