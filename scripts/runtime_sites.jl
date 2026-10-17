# The run-time sites in code compiled under the facts policy, reached from given workers:
# every dynamic call in the policy's CodeInstances (walking `:invoke`s), with the argument
# types inference had there. A site at abstract types runs native code (which loads can
# invalidate) and widens what follows to `Any`; type assertions or concrete types fix it.
#
#     runtime_sites(f)        # f: a function with workers (a trait module's bounded function)
using TraitWorld
const TW = TraitWorld

function policy_cis(f)
    out = Core.CodeInstance[]
    for m in methods(f), mi in Base.specializations(m)
        mi isa Core.MethodInstance || continue
        isdefined(mi, :cache) || continue
        ci = mi.cache
        while true
            ci.owner isa TW.FactsOwner && ci.max_world == typemax(UInt) && push!(out, ci)
            isdefined(ci, :next) || break; ci = ci.next
        end
    end
    out
end

function _src(c::Core.CodeInstance)
    src = c.inferred
    mi = Core.Compiler.get_ci_mi(c)
    src isa String && (src = ccall(:jl_uncompress_ir, Ref{Core.CodeInfo}, (Any, Any, Any), mi.def, c, src))
    return src isa Core.CodeInfo ? src : nothing
end

function runtime_sites(roots::Vector{Core.CodeInstance}; limit = 3000, io = stdout, filter_mod = nothing)
    seen = Base.IdSet{Core.CodeInstance}()
    todo = copy(roots)
    nsites = 0
    while !isempty(todo) && length(seen) < limit
        c = pop!(todo)
        c in seen && continue
        push!(seen, c)
        c.owner isa TW.FactsOwner || continue
        src = _src(c)
        src === nothing && continue
        mi = Core.Compiler.get_ci_mi(c)
        where_ = mi.def isa Method ? "$(mi.def.name) @ $(mi.def.file):$(mi.def.line)" : string(mi)
        for (k, st) in enumerate(src.code)
            if Meta.isexpr(st, :invoke)
                t = st.args[1]
                t isa Core.CodeInstance && push!(todo, t)
            elseif Meta.isexpr(st, :call)
                g = st.args[1]
                gv = g isa GlobalRef ? (isdefined(g.mod, g.name) ? getglobal(g.mod, g.name) : nothing) : g isa QuoteNode ? g.value : g
                gv isa Core.Builtin && continue
                types = [a isa Core.SSAValue ? src.ssavaluetypes[a.id] : a isa Core.Argument ? (src.slottypes === nothing ? (mi.specTypes.parameters[a.n]) : src.slottypes[a.n]) :
                         a isa GlobalRef ? (isdefined(a.mod, a.name) ? typeof(getglobal(a.mod, a.name)) : Any) :
                         a isa QuoteNode ? typeof(a.value) : typeof(a) for a in st.args]
                filter_mod === nothing || mi.def isa Method && Base.moduleroot(mi.def.module) === filter_mod || continue
                nsites += 1
                println(io, "  in ", where_, ": ", join(string.(Core.Compiler.widenconst.(types)), ", ")[1:min(end, 300)])
            end
        end
    end
    println(io, nsites, " run-time sites in ", length(seen), " CodeInstances")
    return nothing
end
runtime_sites(f::Function; kw...) = runtime_sites(policy_cis(f); kw...)
