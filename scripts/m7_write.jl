# E-217 (the forks' M7): `CSV.write` with fallback columns. Three schemas with the same fallback column types
# in other combinations (10^4 rows): compile time and CodeInstances per write; then the steady state of
# 10^5 rows (minimum of 5).
#     julia --project=<env> scripts/m7_write.jl <label>
using CSV, DataFrames, PooledArrays, InlineStrings, Random
Base.cumulative_compile_timing(true)
const LABEL = isempty(ARGS) ? "?" : ARGS[1]
Random.seed!(1)
n = 10^4
P() = PooledArray(rand(["x", "y", "z"], n)); S() = String7.(rand(["ab", "cde"], n)); Y() = rand([:u, :v], n); I() = rand(1:9, n)
CSV.write(IOBuffer(), DataFrame(a = I(), b = randn(n)))            # the common path, compiled once
schemas = [
    "1: Int, pooled, String7"            => () -> DataFrame(a = I(), p = P(), s = S()),
    "2: pooled, Symbol, Int, String7"    => () -> DataFrame(p = P(), y = Y(), a = I(), s = S()),
    "3: String7, Symbol, pooled, pooled" => () -> DataFrame(s = S(), y = Y(), p = P(), q = P()),
]
for (name, make) in schemas
    df = make()
    new = Any[]
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), new)
    c0 = Base.cumulative_compile_time_ns()[1]
    t = @elapsed CSV.write(IOBuffer(), df)
    c1 = Base.cumulative_compile_time_ns()[1]
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), nothing)
    println("M7 ", rpad(LABEL, 9), rpad(name, 36), lpad(round(t * 1e3; digits = 1), 8), " ms, compile ",
            lpad(round((c1 - c0) / 1e6; digits = 1), 7), " ms, CodeInstances ", count(x -> x isa Core.CodeInstance, new))
end
m = 10^5
big = DataFrame(a = rand(1:9, m), p = PooledArray(rand(["x", "y", "z"], m)), s = String7.(rand(["ab", "cde"], m)), y = rand([:u, :v], m))
io = IOBuffer(); CSV.write(io, big); CSV.write(io, big)
t = minimum(@elapsed(CSV.write(IOBuffer(), big)) for _ in 1:5)
println("M7 ", rpad(LABEL, 9), "steady, 10^5 rows, 3 fallback columns   ", round(t * 1e3; digits = 2), " ms")
