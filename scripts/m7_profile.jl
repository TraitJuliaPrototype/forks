# E-217: where the steady write of 10^5 rows with fallback columns spends its time (a flat profile, 40 writes).
#     julia --project=env_forks scripts/m7_profile.jl
using CSV, DataFrames, PooledArrays, InlineStrings, Random, Profile
Random.seed!(1)
m = 10^5
big = DataFrame(a = rand(1:9, m), p = PooledArray(rand(["x", "y", "z"], m)), s = String7.(rand(["ab", "cde"], m)), y = rand([:u, :v], m))
CSV.write(IOBuffer(), big); CSV.write(IOBuffer(), big)
Profile.init(n = 10^7, delay = 0.0002)
@profile for _ in 1:40; CSV.write(IOBuffer(), big); end
Profile.print(IOContext(stdout, :displaysize => (2000, 250)); format = (get(ENV, "TREE", "0") == "1" ? :tree : :flat), sortedby = :count, mincount = (get(ENV, "TREE", "0") == "1" ? 300 : 60), C = false)
