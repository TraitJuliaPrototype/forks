# E-232 (W-14, the memo's question 1): joins on pooled and categorical keys, forks against upstream.
# Is the join's pooled path (DataAPI's pool, in the plain preprocessing that maps one side's keys to the
# other side's reference codes) enough, or do joins want a capability of their own?
#     julia --project=env_d2 scripts/w14_pooled_joins.jl forks
#     JULIA_LOAD_PATH="env_upstream:<an env with CategoricalArrays>:@stdlib" julia scripts/w14_pooled_joins.jl upstream
# One line per case: the first join (small frames, compile included) and the steady join (a fact table of 10^6
# rows against a dimension table of 9000 or 90000 rows, the minimum of 5 after 2 warm-ups), with the result's
# digest (equal across the two settings).
using DataFrames, PooledArrays, CategoricalArrays, Random
const LABEL = get(ARGS, 1, "?")
digest(df) = string(nrow(df), " ", repr(hash((names(df), [collect(c) for c in eachcol(df)]))))

function keys_of(kind, ks)
    kind === :string && return ks
    kind === :pooled && return PooledArray(ks)
    kind === :categorical && return categorical(ks)
    error(kind)
end
# a fact table (n rows, keys from 10^4 levels) against a dimension table whose keys are unique (90% of the
# levels; with `a`, every pair of such a level and `a` in 1:10): each left row matches at most one right row
function frames(n, lkind, rkind; nlev = 10^4, seed = 5)
    rng = MersenneTwister(seed)
    levels = ["k$i" for i in 1:nlev]
    l = DataFrame(k = keys_of(lkind, rand(rng, levels, n)), a = rand(rng, 1:10, n), v = 1:n)
    rl = shuffle(rng, levels[1:(9 * nlev ÷ 10)])
    r1 = DataFrame(k = keys_of(rkind, rl), w = 1:length(rl))
    rk = repeat(rl; inner = 10)
    r2 = DataFrame(k = keys_of(rkind, rk), a = repeat(1:10; outer = length(rl)), w = 1:length(rk))
    return l, r1, r2
end

cases = [("String/String", :string, :string), ("pooled/pooled", :pooled, :pooled),
         ("pooled/String", :pooled, :string), ("String/pooled", :string, :pooled),
         ("categorical/categorical", :categorical, :categorical)]
# the join machinery, compiled once on plain keys
let (l, r1, r2) = frames(2000, :string, :string; nlev = 100)
    innerjoin(l, r1; on = :k, makeunique = true); leftjoin(l, r2; on = [:k, :a], makeunique = true)
end
for (name, lk, rk) in cases
    sl, sr1, sr2 = frames(2000, lk, rk; nlev = 100, seed = 9)
    bl, br1, br2 = frames(10^6, lk, rk)
    for (op, f) in (("inner", innerjoin), ("left", leftjoin))
        for on in ([:k], [:k, :a])
            sr, br = on == [:k] ? (sr1, br1) : (sr2, br2)
            t1 = @timed f(sl, sr; on = on, makeunique = true)
            g() = f(bl, br; on = on, makeunique = true)
            res = g(); g()
            t = minimum(@elapsed(g()) for _ in 1:5)
            println("E232 ", rpad(LABEL, 9), rpad(name, 24), rpad(op, 6), rpad(string(on), 10),
                    " first ", lpad(round(t1.time * 1e3; digits = 1), 7), " ms (compile ", lpad(round(t1.compile_time * 1e3; digits = 1), 6),
                    ")  steady ", lpad(round(t * 1e3; digits = 1), 7), " ms  ", digest(res))
        end
    end
end
