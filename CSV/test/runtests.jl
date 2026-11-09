# CSV.jl test suite.
#
#   kernel.jl  — structural index, scanners, driver, columns, pooling (exhaustive
#                chunk-geometry determinism)
#   api.jl     — File/read/Rows/Chunks behavior and mode consistency
#   write.jl   — the writer, including round trips and exact output checks
#   fuzz.jl    — deterministic malformed and generated-input checks
#   scan.jl    — Tables.Scan pushdown (required by Tables 1.14)
using Test, CSV
using TraitWorld: detect_unused_casts

@testset "CSV" begin
    include("cpu.jl")
    include("tasks.jl")
    include("kernel.jl")
    include("api.jl")
    include("decimals.jl")
    include("write.jl")
    include("fuzz.jl")
    include("scan.jl")
    # a cast or a carried attribute at a parameter no trait types has no effect (open issue 162)
    @testset "no casts without effect" begin
        @test isempty(detect_unused_casts(CSV))
    end
end
