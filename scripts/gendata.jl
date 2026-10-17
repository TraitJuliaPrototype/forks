# The data of the interactive workload (plan §4.1), deterministic:
#     julia scripts/gendata.jl [dir]        # default data/
using Random, Dates
dir = get(ARGS, 1, joinpath(@__DIR__, "..", "data"))
mkpath(dir)
rng = Xoshiro(20261017)
const CITIES = ["Berlin", "Potsdam", "Hamburg", "Munich", "Cologne", "Leipzig", "Dresden", "Bremen", "Kiel", "Mainz", "Bonn", "Ulm"]
const ITEMS = ["item$(lpad(k, 2, '0'))" for k in 1:40]
const TAGS = ["alpha", "beta", "gamma", "delta"]
randname(rng) = String(rand(rng, 'a':'z', rand(rng, 3:12)))
maybe(rng, p, x) = rand(rng) < p ? "" : string(x)

open(joinpath(dir, "people.csv"), "w") do io
    println(io, "id,name,city,age,income,joined,active")
    for i in 1:10_000
        println(io, i, ",", randname(rng), ",", rand(rng, CITIES), ",", maybe(rng, 0.05, rand(rng, 18:90)), ",",
                maybe(rng, 0.02, round(20_000 + 80_000 * rand(rng); digits = 2)), ",",
                Date(2010, 1, 1) + Day(rand(rng, 0:5000)), ",", rand(rng, Bool))
    end
end
open(joinpath(dir, "orders.csv"), "w") do io
    println(io, "order_id,id,amount,item,ts")
    for k in 1:50_000
        println(io, k, ",", rand(rng, 1:10_000), ",", round(500 * rand(rng); digits = 2), ",", rand(rng, ITEMS), ",",
                DateTime(2024, 1, 1) + Second(rand(rng, 0:31_000_000)))
    end
end
open(joinpath(dir, "sensors.csv"), "w") do io
    println(io, "t,s1,s2,s3,s4,s5,s6,tag")
    for k in 1:10_000
        print(io, round(0.1k; digits = 1))
        for j in 1:6
            print(io, ",", maybe(rng, 0.03, round(randn(rng) + j; digits = 4)))
        end
        println(io, ",", rand(rng, TAGS))
    end
end
open(joinpath(dir, "big.csv"), "w") do io
    println(io, "k,x,s,y")
    for k in 1:1_000_000
        println(io, rand(rng, 1:1000), ",", round(rand(rng); digits = 6), ",", rand(rng, ITEMS), ",", maybe(rng, 0.05, round(randn(rng); digits = 6)))
    end
end
