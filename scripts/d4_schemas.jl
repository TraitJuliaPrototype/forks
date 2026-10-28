# E-215 (W-79's D4): schema independence. The same work over three schemas whose columns have the same
# types (other names, order and number): the CodeInstances each schema's work makes, by the module of
# their method (the forks' kernels, DataFrames, Tables, CSV, other), and the compile time it takes.
# Upstream compiles per tuple of column types in places (`DFPerm`, `row_group_slots!`); the forks'
# kernels compile per column type, so schemas 2 and 3 should make no kernel worker.
#     julia --project=<env> scripts/d4_schemas.jl <label>
using CSV, DataFrames, Statistics, Random
Base.cumulative_compile_timing(true)
const LABEL = isempty(ARGS) ? "?" : ARGS[1]
Random.seed!(1)
const N = 10_000
ints() = rand(1:100, N); flts() = randn(N); strs() = rand(["a", "b", "c", "d"], N)
schemas = [
    "1: a::Int b::Float64 c::String"            => () -> DataFrame(a = ints(), b = flts(), c = strs()),
    "2: c::String x::Int y::Float64 (renamed)"  => () -> DataFrame(c = strs(), x = ints(), y = flts()),
    "3: five columns, the same types"           => () -> DataFrame(p = flts(), q = ints(), r = strs(), s = ints(), t = flts()),
]
function work(df)
    names_ = propertynames(df)
    ki = names_[findfirst(n -> eltype(df[!, n]) == Int, names_)]
    ks = names_[findfirst(n -> eltype(df[!, n]) == String, names_)]
    kf = names_[findfirst(n -> eltype(df[!, n]) == Float64, names_)]
    describe(df)
    sort(df, [ks, kf])
    combine(groupby(df, ks), kf => mean => :m, nrow)
    innerjoin(df, DataFrame(ki => 1:100, :w => randn(100)), on = ki)
    io = IOBuffer(); CSV.write(io, df); CSV.read(take!(io), DataFrame)
    return nothing
end
modkey(m::Module) = (r = string(Base.moduleroot(m)); s = string(m); occursin("ColumnKernels", s) || occursin("ColumnCore", s) || occursin("ColumnParsers", s) ? s : r)
for (name, make) in schemas
    df = make()
    new = Any[]
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), new)
    c0 = Base.cumulative_compile_time_ns()[1]
    t = @elapsed work(df)
    c1 = Base.cumulative_compile_time_ns()[1]
    ccall(:jl_set_newly_inferred, Cvoid, (Any,), nothing)
    by = Dict{String, Int}(); others = String[]
    for ci in new
        ci isa Core.CodeInstance || continue
        mi = ci.def isa Core.MethodInstance ? ci.def : ci.def.def
        m = mi.def
        k = m isa Method ? modkey(m.module) : "toplevel"
        by[k] = get(by, k, 0) + 1
        k in ("Base", "Core", "Main") || name[1] == '1' || push!(others, string(k, ": ", mi.specTypes))
    end
    println("D4 ", rpad(LABEL, 9), rpad(name, 42), " ", round(t * 1e3; digits = 1), " ms, compile ", round((c1 - c0) / 1e6; digits = 1), " ms, CodeInstances ", length(new))
    for (k, n) in sort!(collect(by); by = last, rev = true)
        println("D4 ", rpad(LABEL, 9), "    ", rpad(k, 40), lpad(n, 6))
    end
    foreach(o -> println("D4 ", rpad(LABEL, 9), "      ", o), others)
end
