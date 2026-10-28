# E-217: where a steady write's allocations come from (Profile.Allocs, every allocation sampled), by frame.
#     julia --project=env_forks scripts/m7_allocs.jl
using CSV, DataFrames, PooledArrays, InlineStrings, Random, Profile
Random.seed!(1)
m = 10^5
big = DataFrame(a = rand(1:9, m), p = PooledArray(rand(["x", "y", "z"], m)), s = String7.(rand(["ab", "cde"], m)), y = rand([:u, :v], m))
CSV.write(IOBuffer(), big); CSV.write(IOBuffer(), big)
Profile.Allocs.clear()
Profile.Allocs.@profile sample_rate = 1.0 CSV.write(IOBuffer(), big)
res = Profile.Allocs.fetch()
by = Dict{String, Int}()
for a in res.allocs
    # the innermost frame in CSV, ColumnParsers or TraitWorld code
    fr = findfirst(f -> occursin(r"CSV|TraitWorld|ColumnParsers", string(f.file)), a.stacktrace)
    k = fr === nothing ? "other" : string(a.stacktrace[fr].file, ":", a.stacktrace[fr].line, " ", a.stacktrace[fr].func, " (", a.type, ")")
    by[k] = get(by, k, 0) + a.size
end
for (k, n) in sort!(collect(by); by = last, rev = true)[1:min(15, end)]
    println("M7AL ", lpad(round(n / 2^20; digits = 2), 8), " MiB  ", k)
end
