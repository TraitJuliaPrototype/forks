# E-224: the steady multi-key join split into its steps (forks only): the codes of each key column pair,
# the fold, the one-column kernel on the keys. Minimum of 5.
#     julia --project=env_forks scripts/m8_split.jl
using DataFrames, Random
using DataFrames: jointcodes!, joinkeys, innerrows, semirows
using Tables.ColumnCore: tocolumn
rng = MersenneTwister(3)
n, m = 10^6, 10^5
bl = DataFrame(a = rand(rng, 1:1000, n), s = rand(rng, string.('a':'z'), n), v = 1:n)
br = DataFrame(a = rand(rng, 1:1000, m), s = rand(rng, string.('a':'z'), m), w = 1:m)
best(f) = (f(); f(); minimum(@elapsed(f()) for _ in 1:5) * 1e3)
lc = Vector{Int}(undef, n); rc = Vector{Int}(undef, m)
for col in (:a, :s), order in (true, false)
    t = best(() -> jointcodes!(lc, rc, tocolumn(bl[!, col]), tocolumn(br[!, col]), order))
    println("M8 split jointcodes! $col order=$order ", round(t; digits = 1), " ms")
end
lcols = Any[bl.a, bl.s]; rcols = Any[br.a, br.s]
println("M8 split joinkeys ", round(best(() -> joinkeys(lcols, rcols, false)); digits = 1), " ms")
lk, rk, o = joinkeys(lcols, rcols, false)
println("M8 split keys ordered=$o, distinct ", length(unique(lk)), " / ", length(unique(rk)))
println("M8 split innerrows on keys ", round(best(() -> innerrows(tocolumn(lk), tocolumn(rk), true, !o)); digits = 1), " ms")
println("M8 split semirows on keys ", round(best(() -> semirows(tocolumn(lk), tocolumn(rk), true, !o)); digits = 1), " ms")
println("M8 split innerrows on :a ", round(best(() -> innerrows(tocolumn(bl.a), tocolumn(br.a), true, false)); digits = 1), " ms")
println("M8 split semirows on :a ", round(best(() -> semirows(tocolumn(bl.a), tocolumn(br.a), true, false)); digits = 1), " ms")
println("M8 split whole innerjoin ", round(best(() -> innerjoin(bl, br; on = [:a, :s])); digits = 1), " ms")
