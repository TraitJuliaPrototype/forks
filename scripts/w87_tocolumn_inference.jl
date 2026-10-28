# W-87 / open issue 100: a bounded function's declared `Dynamic{X}` result reaches plain callers.
#     julia --project=env_forks scripts/w87_tocolumn_inference.jl
using Tables, DataFrames
using Tables.ColumnCore: tocolumn
for T in (Vector{Int}, Vector{String}, AbstractVector, Any)
    println("tocolumn(::", T, ") infers ", Base.return_types(tocolumn, (T,)))
end
println("_dcolumn infers ", Base.return_types(DataFrames._dcolumn, (DataFrame, Int)))
