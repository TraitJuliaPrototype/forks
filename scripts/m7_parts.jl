# E-217: the parts of a steady write (10^5 rows, three fallback columns): the whole write, the staging of every
# block alone, the descriptors' copy alone; each the minimum of 10.
#     julia --project=env_forks scripts/m7_parts.jl
using CSV, DataFrames, PooledArrays, InlineStrings, Random, Tables
Random.seed!(1)
m = 10^5
big = DataFrame(a = rand(1:9, m), p = PooledArray(rand(["x", "y", "z"], m)), s = String7.(rand(["ab", "cde"], m)), y = rand([:u, :v], m))
o = CSV._writeopts()
cols = CSV._writecolumns(Tables.columns(big), collect(Symbol, Tables.columnnames(big)))
wc, rowbound = CSV._preparewritecolumns(cols, m, o)
blocks = [(lo, min(lo + 4095, m)) for lo in 1:4096:m]
stageall() = for (lo, hi) in blocks; CSV.ColumnParsers.stageblock(wc.stagers, lo, hi, o); end
copyall() = for _ in blocks; copy(wc.direct); end
CSV.write(IOBuffer(), big); stageall(); copyall()
b(f) = round(minimum(@elapsed(f()) for _ in 1:10) * 1e3; digits = 2)
println("M7P whole write ", b(() -> CSV.write(IOBuffer(), big)), " ms; staging ", b(stageall), " ms; descriptors' copies ", b(copyall), " ms; blocks ", length(blocks))
for _ in 1:3
    s = @timed CSV.write(IOBuffer(), big)
    println("M7P timed: ", round(s.time * 1e3; digits = 2), " ms, gc ", round(s.gctime * 1e3; digits = 2), " ms, ", round(s.bytes / 2^20; digits = 2), " MiB")
end
br = CSV._writerblockrows(rowbound, o, CSV._identity_transform)
println("M7P rowbound ", rowbound, " bytes, block rows ", br, ", blocks ", cld(m, br))
