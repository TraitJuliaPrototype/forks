# E-217: the staging of one block (4096 rows) per fallback column type: the `Column` kernel against the plain
# loop the writer had (copied here), both on the same column.
#     julia --project=env_forks scripts/m7_stage_split.jl
using CSV, PooledArrays, InlineStrings, TraitWorld, Random, Tables
Random.seed!(1)
const C = CSV
function plainstage!(st, col::AbstractVector, lo::Int, hi::Int, o)
    C._reset!(st, hi - lo + 1)
    k = 0
    @inbounds for r in lo:hi
        C._stagecell!(st, col[r], o)
        C._endcell!(st, k += 1)
    end
    return st
end
o = C._writeopts()
n = 4096
cols = ["pooled" => PooledArray(rand(["x", "y", "z"], n)), "String7" => String7.(rand(["ab", "cde"], n)),
        "Symbol" => rand([:u, :v], n), "Int (as fallback)" => rand(1:9, n)]
for (name, v) in cols
    st = C.ColStage()
    d = Tables.ColumnCore.tocolumn(v)
    plainstage!(st, v, 1, n, o); C.ColumnParsers.stagecells!(st, compiled_for(d), 1, n, o)
    tp = minimum(@elapsed(plainstage!(st, v, 1, n, o)) for _ in 1:50)
    tk = minimum(@elapsed(C.ColumnParsers.stagecells!(st, compiled_for(d), 1, n, o)) for _ in 1:50)
    td = minimum(@elapsed(C.ColumnParsers.stagecells!(st, d, 1, n, o)) for _ in 1:50)
    println("M7S ", rpad(name, 20), " plain ", round(tp * 1e6; digits = 1), " µs, kernel opened ", round(tk * 1e6; digits = 1),
            " µs, kernel Dynamic ", round(td * 1e6; digits = 1), " µs")
end
for (name, v) in cols
    st = C.ColStage(); d = Tables.ColumnCore.tocolumn(v); cd = compiled_for(d)
    ap = @allocated plainstage!(st, v, 1, n, o)
    ak = @allocated C.ColumnParsers.stagecells!(st, cd, 1, n, o)
    println("M7A ", rpad(name, 20), " plain ", ap, " B, kernel opened ", ak, " B")
end
