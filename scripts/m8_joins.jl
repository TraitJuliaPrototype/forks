# E-224 (the forks' M8): joins on several key columns.
#     julia --project=<env> scripts/m8_joins.jl check <label>   the rows of each join, as digests (order included)
#     julia --project=<env> scripts/m8_joins.jl time <label>    three key schemas' first joins; the steady join
# `check` prints one line per case and join; the lines of two environments must be equal.
using DataFrames, PooledArrays, Random
const MODE = get(ARGS, 1, "check")
const LABEL = get(ARGS, 2, "?")

# the rows of a result, in order: its names and the cells of each column
digest(df) = string(nrow(df), " ", repr(hash((names(df), [collect(c) for c in eachcol(df)]))))

function frames(n, m)
    rng = MersenneTwister(7)
    l = DataFrame(a = rand(rng, 1:20, n), s = rand(rng, ["p", "q", "r", "t"], n), x = rand(rng, [0.5, 1.0, 2.0, 0.0], n),
                  b = rand(rng, Bool, n), am = rand(rng, [1, 2, 3, missing], n), z = rand(rng, [1 + 2im, 3 + 0im, 2im], n),
                  v = 1:n)
    r = DataFrame(a = rand(rng, 1:25, m), s = rand(rng, ["p", "q", "r", "u"], m), x = rand(rng, [0.5, 1, 2, 3], m),
                  b = rand(rng, Bool, m), am = rand(rng, [1, 2, 4, missing], m), z = rand(rng, [1 + 2im, 3 + 0im, 5im], m),
                  w = 1:m)
    r.x = Float64.(r.x)
    l.sp = PooledArray(l.s)
    r.sp = PooledArray(r.s)
    r.ai = r.a .+ 0.0                       # Float64 keys against left's Int keys
    return l, r
end

if MODE == "check"
    cases = Any[
        ("Int,Int unsorted",        :a, [:a, :b]),
        ("Int,String",              :a, [:a, :s]),
        ("String,Float64", :a, [:s, :x]),
        ("Int,String,Bool",         :a, [:a, :s, :b]),
        ("pooled,Int",              :a, [:sp, :a]),
        ("Int,missing (:equal)",    :a, [:a, :am]),
        ("Complex,Int (unsortable)", :a, [:z, :a]),
    ]
    for (shorter, nl, nr) in ((:right, 300, 120), (:left, 120, 300))
        l, r = frames(nl, nr)
        for (name, _, on) in cases
            kw = :am in on ? (matchmissing = :equal,) : (;)
            for (op, f0) in (("inner", innerjoin), ("left", leftjoin), ("right", rightjoin), ("outer", outerjoin),
                            ("semi", semijoin), ("anti", antijoin))
                f = op in ("semi", "anti") ? f0 : (a, b; k...) -> f0(a, b; makeunique = true, k...)
                res = f(l, r; on = on, kw...)
                println("M8 $shorter $name $op ", digest(res))
            end
            println("M8 $shorter $name inner order=:left ", digest(innerjoin(l, r; on = on, order = :left, makeunique = true, kw...)))
        end
        # sorted on both sides: the merge
        ls = sort(l, [:a, :s]); rs = sort(r, [:a, :s])
        println("M8 $shorter sorted Int,String inner ", digest(innerjoin(ls, rs; on = [:a, :s], makeunique = true)))
        println("M8 $shorter sorted Int,String semi ", digest(semijoin(ls, rs; on = [:a, :s])))
        # Int against Float64 keys
        rr = rename(select(r, :ai, :s, :w), :ai => :a)
        println("M8 $shorter Int~Float64,String inner ", digest(innerjoin(l, rr; on = [:a, :s], makeunique = true)))
        println("M8 $shorter sorted Int~Float64,String inner ",
                digest(innerjoin(sort(l, [:a, :s]), sort(rr, [:a, :s]); on = [:a, :s])))
        # an empty side
        println("M8 $shorter empty inner ", digest(innerjoin(l[1:0, :], r; on = [:a, :s], makeunique = true)))
        println("M8 $shorter empty semi ", digest(semijoin(l, r[1:0, :]; on = [:a, :s])))
    end
else
    small_l, small_r = frames(2000, 1000)
    innerjoin(small_l, small_r; on = :a, makeunique = true)                   # the join machinery, compiled once
    semijoin(small_l, small_r; on = :a)
    for on in ([:a, :s], [:s, :x], [:x, :a, :s])
        t = @timed innerjoin(small_l, small_r; on = on, makeunique = true)
        println("M8 ", rpad(LABEL, 9), "first innerjoin on ", rpad(string(on), 16), lpad(round(t.time * 1e3; digits = 1), 8),
                " ms (compile ", round(t.compile_time * 1e3; digits = 1), " ms)")
    end
    rng = MersenneTwister(3)
    n, m = 10^6, 10^5
    bl = DataFrame(a = rand(rng, 1:1000, n), s = rand(rng, string.('a':'z'), n), v = 1:n)
    br = DataFrame(a = rand(rng, 1:1000, m), s = rand(rng, string.('a':'z'), m), w = 1:m)
    for on in ([:a, :s],)
        f() = innerjoin(bl, br; on = on)
        f(); f()
        t = minimum(@elapsed(f()) for _ in 1:5)
        println("M8 ", rpad(LABEL, 9), "steady innerjoin 10^6 x 10^5 on ", rpad(string(on), 10), lpad(round(t * 1e3; digits = 1), 8), " ms")
        g() = semijoin(bl, br; on = on)
        g(); g()
        t = minimum(@elapsed(g()) for _ in 1:5)
        println("M8 ", rpad(LABEL, 9), "steady semijoin 10^6 x 10^5 on ", rpad(string(on), 10), lpad(round(t * 1e3; digits = 1), 8), " ms")
    end
end
