# D1 (E-213): where the forks' load goes. A sampling profile of `using CSV, DataFrames`; the frames of
# the flat report, by inclusive sample count.
#     julia --project=env_forks scripts/d1_profile_load.jl
using Profile
Profile.init(n = 10^7, delay = 0.001)
t = @elapsed @profile @eval using CSV, DataFrames, Statistics, Dates
println("LOAD ", round(t; digits = 3), " s")
Profile.print(IOContext(stdout, :displaysize => (2000, 260)); format = :flat, sortedby = :count, mincount = 40, C = false)
