# E-211 (D2): the pooled path is taken for pooled columns, also for a column stored as `Dynamic{Column}`.
#     julia --project=env_d2 scripts/d2_pooled.jl   (env_forks with CategoricalArrays)
using DataFrames, PooledArrays, CategoricalArrays, Tables
const CC = Tables.ColumnCore
const K = DataFrames.ColumnKernels
for (name, v) in [("PooledVector{String}", PooledArray(["b", "a", "b", "c"])),
                  ("CategoricalVector{String}", categorical(["b", "a", "b", "c"])),
                  ("Vector{String}", ["b", "a", "b", "c"])]
    d = CC.tocolumn(v)                       # the column as a frame stores it
    r = K.refcodes(d, false, false)
    println("D2 ", rpad(name, 26), " stored: ", typeof(d).name.name, ", refcodes: ", r === nothing ? "nothing (no pool)" : r)
end
df = DataFrame(k = PooledArray(["b", "a", "b", "c"]), x = 1:4)
println("D2 groupby on a pooled column: ", combine(groupby(df, :k; sort = true), :x => sum => :s))
