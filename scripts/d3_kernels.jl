# E-214 (W-79's D3): the kernels' steady-state costs on 10^6 rows, in one setting (the env decides:
# env_forks or env_upstream). Minimum of 5 timings after a warm-up; allocations of the last.
#     julia --project=<env> scripts/d3_kernels.jl <label>
using CSV, DataFrames, PooledArrays, Statistics, Random
const LABEL = isempty(ARGS) ? "?" : ARGS[1]
Random.seed!(1)
const N = 10^6
const WORDS = [randstring(8) for _ in 1:1000]
df = DataFrame(i = rand(1:1000, N), j = rand(1:10, N), f = randn(N), s = rand(WORDS, N),
               p = PooledArray(rand(WORDS[1:50], N)), m = [rand() < 0.1 ? missing : randn() for _ in 1:N])
keys = DataFrame(i = 1:1000, w = randn(1000))
gi = groupby(df, :i)
cases = [
    "sort Int"                 => () -> sort(df, :i),
    "sort String, Float64"     => () -> sort(df, [:s, :f]),
    "groupby-sum Int key"      => () -> combine(groupby(df, :i), :f => sum),
    "groupby-sum two keys"     => () -> combine(groupby(df, [:i, :j]), :f => sum),
    "groupby-sum pooled key"   => () -> combine(groupby(df, :p), :f => sum),
    "groupby-mean skipmissing" => () -> combine(gi, :m => mean ∘ skipmissing),
    "describe"                 => () -> describe(df),
    "innerjoin Int key"        => () -> innerjoin(df, keys, on = :i),
    "combine SubDataFrame fn"  => () -> combine(gi, sdf -> sum(sdf.f)),
]
for (name, f) in cases
    f(); f()
    t = minimum(@elapsed(f()) for _ in 1:5)
    a = @allocated f()
    println("D3 ", rpad(LABEL, 9), rpad(name, 26), lpad(round(t * 1e3; digits = 2), 10), " ms ", lpad(round(a / 2^20; digits = 1), 8), " MiB")
end
