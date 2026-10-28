# BaseTraits' BoundedText in CSV's writer: the bytes written for cell types the writer has no width for,
# compared between environments (the forks, upstream). One line per case: its name and a hash of the output.
#     julia --project=<env> scripts/bt_write.jl
using CSV, DataFrames
struct Pt; x::Int; y::Int; end
Base.print(io::IO, p::Pt) = print(io, "(", p.x, ";", p.y, ")")
n = 10_000
cols = (
    sym = [Symbol("s", i % 97) for i in 1:n],
    chr = [Char(0x41 + i % 26) for i in 1:n],
    rat = [i // (i % 7 + 1) for i in 1:n],
    big = [big(10)^(i % 40) for i in 1:n],
    cpx = [complex(i, -i / 3) for i in 1:n],
    bfl = [BigFloat(i) / 7 for i in 1:n],
    anyc = Any[isodd(i) ? i : "x$i" for i in 1:n],
    pt = [Pt(i, -i) for i in 1:n],
    msym = [isodd(i) ? missing : Symbol("m", i) for i in 1:n],
)
df = DataFrame(cols)
for (name, kw) in (("default", (;)), ("floatfmt", (; floatfmt = "%.3f")), ("delim;", (; delim = ';')), ("small bufsize", (; bufsize = 64)))
    io = IOBuffer()
    try
        CSV.write(io, df; kw...)
        s = String(take!(io))
        println("BT write ", rpad(name, 14), length(s), " bytes ", repr(hash(s)))
    catch e
        println("BT write ", rpad(name, 14), "error ", typeof(e))
    end
end
