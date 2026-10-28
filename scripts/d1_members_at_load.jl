# D1 (E-213): the family members fixed at load (`_member_fold_at_load`), how many, and the time of the
# member check, the builder and the override index. A probe: it redefines the function in TraitWorld
# before the packages load.
#     julia --project=env_forks scripts/d1_members_at_load.jl
using TraitWorld
const TW = TraitWorld
const T = zeros(UInt64, 6); const N = Ref(0); const MEMBERS = Any[]
@eval TW function _member_fold_at_load(reg::Base.RefValue{IdDict{Any,Any}}, @nospecialize(X), @nospecialize(U))
    b = get(reg[], U, nothing)
    b isa Builder && return b
    $N[] += 1; push!($MEMBERS, (X, U))
    try
        t0 = time_ns(); _check_member(X, U); t1 = time_ns()
        b = _latest(_family_builder, X, U); t2 = time_ns()
        $T[1] += t1 - t0; $T[2] += t2 - t1
        b isa Builder || return nothing
        @lock _LOCK begin
            e = get(reg[], U, nothing)
            e isa Builder && return e
            d = copy(reg[]); d[U] = b; reg[] = d
        end
        t3 = time_ns(); if _OVR_BUILT[]; recs = _builder_records(X, U, b); t4 = time_ns(); ps = Any[(_opfn(Y, op), (Y, op, R, X2, U2)) for (Y, op, R, X2, U2) in recs]; t5 = time_ns(); _ovr_push!(ps); $T[4] += t4 - t3; $T[5] += t5 - t4; $T[6] += time_ns() - t5; end; $T[3] += time_ns() - t3
        return b
    catch e
        (e isa ImplementError || e isa TraitBoundError) || rethrow()
        return nothing
    end
end
t = @elapsed using CSV, DataFrames, Statistics, Dates
println("LOAD ", round(t; digits = 3), " s; members fixed at load: ", N[], "; override index built: ", TW._OVR_BUILT[])
println("INDEX records ", round(T[4] / 1e6; digits = 1), " ms, op functions ", round(T[5] / 1e6; digits = 1), " ms, push ", round(T[6] / 1e6; digits = 1), " ms")
println("TIME check ", round(T[1] / 1e6; digits = 1), " ms, builder ", round(T[2] / 1e6; digits = 1), " ms, index ", round(T[3] / 1e6; digits = 1), " ms")
for (X, U) in MEMBERS
    println("MEMBER ", X, "  ", U)
end
