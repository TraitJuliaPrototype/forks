# E-212 (D0), before wrapping (porting 0.1a): the methods of upstream Tables, CSV and DataFrames that rule 3
# refuses in a trait module (TraitWorld's `owned_method`): neither the function nor a type in every alternative
# of the signature is the package's own. Extensions are not wrapped and not counted.
#     JULIA_LOAD_PATH="env_upstream:../TraitWorld:@stdlib" julia scripts/d0_pirates.jl
using CSV, DataFrames, TraitWorld
const Tables = only(m for (id, m) in Base.loaded_modules if id.name == "Tables")
const PKGS = Dict(Tables => "Tables", CSV => "CSV", DataFrames => "DataFrames")
root(m::Module) = (p = parentmodule(m); p === m || p === Main ? m : root(p))
found = Dict{String, Vector{Method}}()
Base.visit(Core.methodtable) do m
    r = root(m.module)
    haskey(PKGS, r) || return
    TraitWorld.owned_method(m) && return
    push!(get!(found, PKGS[r], Method[]), m)
end
for p in ("Tables", "CSV", "DataFrames")
    ms = sort!(get(found, p, Method[]); by = m -> (string(m.file), m.line))
    println("P ", p, ": ", length(ms), " methods rule 3 refuses")
    byfn = Dict{String, Int}()
    for m in ms
        f = string(parentmodule(Base.unwrap_unionall(m.sig).parameters[1]), ".", m.name)
        byfn[f] = get(byfn, f, 0) + 1
    end
    for (f, n) in sort!(collect(byfn); by = last, rev = true)
        println("P   ", rpad(f, 40), n)
    end
    for m in ms
        println("M ", p, "  ", m.name, "  ", m.sig, "  ", relpath(string(m.file), dirname(pathof(root(m.module)))), ":", m.line)
    end
end
