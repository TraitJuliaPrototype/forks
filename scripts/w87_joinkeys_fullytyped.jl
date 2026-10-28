using TraitWorld, Tables, DataFrames
using TraitWorld: Dynamic, fully_typed, isfullytyped
using Tables.ColumnCore: Column
r = fully_typed(DataFrames.joinkeys, (Vector{Dynamic{Column}}, Vector{Dynamic{Column}}, Bool))
println("joinkeys: fully typed ", isfullytyped(r), ", ", length(r.sites), " sites, ", r.dynamic, " declared dynamic")
show(stdout, MIME"text/plain"(), r); println()
