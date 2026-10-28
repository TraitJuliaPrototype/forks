# E-216: a new closure's first call of the `byrow` kernel alone, against `map` (plain) and against the whole
# `transform`; after a warm-up with another closure at the same types.
#     julia --project=env_forks scripts/m6_kernel_first.jl
using DataFrames
v = rand(1:100, 10^4); df = DataFrame(a = v); map(x -> x + 1, v)
println("M6K map, new closure            ", round(@elapsed(map(x -> 3x - 4, v)) * 1e3; digits = 2), " ms")
println("M6K ByRow(f)(v), new closure    ", round(@elapsed(ByRow(x -> 7x - 1)(v)) * 1e3; digits = 2), " ms")
println("M6K transform, new closure      ", round(@elapsed(transform(df, :a => ByRow(x -> 9x - 1) => :b)) * 1e3; digits = 2), " ms")
println("M6K transform, new closure      ", round(@elapsed(transform(df, :a => ByRow(x -> 11x - 1) => :b)) * 1e3; digits = 2), " ms")
