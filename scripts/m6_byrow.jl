# E-216 (the forks' M6): user functions in `ByRow`. A new closure's first `transform` after a warm-up
# with another closure (10^4 rows), five closures; then the steady state on 10^6 rows (minimum of 5).
#     julia --project=<env> scripts/m6_byrow.jl <label>
using DataFrames, Random
const LABEL = isempty(ARGS) ? "?" : ARGS[1]
Random.seed!(1)
small = DataFrame(a = rand(1:100, 10^4), x = randn(10^4), s = rand(["p", "q"], 10^4))
big = DataFrame(a = rand(1:100, 10^6), x = randn(10^6))
transform(small, :a => ByRow(v -> v + 1) => :w)                     # the machinery, compiled once
transform(small, [:a, :x] => ByRow((v, y) -> v * y) => :w)
firsts = [
    "Int -> Int"            => () -> transform(small, :a => ByRow(v -> 3v - 1) => :b),
    "Float64 -> Float64"    => () -> transform(small, :x => ByRow(y -> y^2 + 1) => :b),
    "String -> String"      => () -> transform(small, :s => ByRow(t -> t * "!") => :b),
    "Int -> Bool"           => () -> transform(small, :a => ByRow(v -> v > 50) => :b),
    "(Int, Float64) -> F64" => () -> transform(small, [:a, :x] => ByRow((v, y) -> v + 2y) => :b),
]
for (name, f) in firsts
    t = @elapsed f()
    println("M6 ", rpad(LABEL, 9), "first  ", rpad(name, 24), lpad(round(t * 1e3; digits = 2), 9), " ms")
end
steady = [
    "Int -> Int"            => () -> transform(big, :a => ByRow(v -> 2v + 1) => :b),
    "Float64 -> Float64"    => () -> transform(big, :x => ByRow(y -> y * y) => :b),
    "(Int, Float64) -> F64" => () -> transform(big, [:a, :x] => ByRow((v, y) -> v * y) => :b),
]
for (name, f) in steady
    f(); f()
    t = minimum(@elapsed(f()) for _ in 1:5)
    println("M6 ", rpad(LABEL, 9), "steady ", rpad(name, 24), lpad(round(t * 1e3; digits = 2), 9), " ms")
end
println("M6 ", rpad(LABEL, 9), "eltype of a widening result: ", eltype(transform(small, :a => ByRow(v -> v > 50 ? 1 : 1.5) => :b).b),
        ", of a narrow one: ", eltype(transform(small, :a => ByRow(v -> v > 200 ? nothing : v) => :b).b))
