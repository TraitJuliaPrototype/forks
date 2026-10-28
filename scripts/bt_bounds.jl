# BaseTraits' BoundedText in CSV's writer: per column, the sampled estimate (64 cells) against the bound
# from `textbound` over every cell, and the time of each (minimum of 5).
#     julia --project=env_forks scripts/bt_bounds.jl
using CSV, DataFrames
include(joinpath(@__DIR__, "bt_write.jl"))   # builds `df` (and prints its write digests)
o = CSV._writeopts(; bufsize = 2^22)
best(f) = (f(); minimum(@elapsed(f()) for _ in 1:5) * 1e6)
for name in names(df)
    col = df[!, name]
    T = Base.nonmissingtype(eltype(col))
    b = CSV._boundedtext(T, o)
    s = CSV._sampledcellbound(col, o)
    t = b ? CSV._textboundmax(col, o) : -1
    println("BT bound ", rpad(name, 5), rpad(string(T), 22), "BoundedText ", rpad(b, 6), "sampled ", lpad(s, 5),
            " (", round(best(() -> CSV._sampledcellbound(col, o)); digits = 1), " µs)  textbound ", lpad(t, 5),
            b ? " (" * string(round(best(() -> CSV._textboundmax(col, o)); digits = 1)) * " µs)" : "")
end
