# E-214: where the forks' `groupby` on an integer key spends its time (10^6 rows, 30 calls, a flat profile).
#     julia --project=env_forks scripts/d3_profile_groupby.jl
using CSV, DataFrames, Random, Profile
Random.seed!(1)
df = DataFrame(i = rand(1:1000, 10^6), f = randn(10^6))
g() = DataFrames.groupindices(groupby(df, :i))
g(); g()
Profile.init(n = 10^7, delay = 0.0005)
@profile for _ in 1:30; g(); end
Profile.print(IOContext(stdout, :displaysize => (2000, 250)); format = :flat, sortedby = :count, mincount = 30, C = false)
