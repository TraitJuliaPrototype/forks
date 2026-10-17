import PrecompileTools

PrecompileTools.@compile_workload begin
    df = DataFrame(a=[2, 5, 3, 1, 0], b=["a", "b", "c", "a", "b"], c=1:5,
                   p=PooledArray(["a", "b", "c", "a", "b"]),
                   q=[true, false, true, false, true],
                   f=Float64[2, 5, 3, 1, 0])
    describe(df)
    names(df[1, 1:2])
    sort(df, :a)
    combine(df, :c, [:c :f] .=> [sum, mean, std], :c => :d, [:a, :c] => cor)
    transform(df, :c, [:c :f] .=> [sum, mean, std], :c => :d, [:a, :c] => cor)
    groupby(df, :a)
    groupby(df, :p)
    groupby(df, :q)
    gdf = groupby(df, :b)
    combine(gdf, :c, [:c :f] .=> [sum, mean, std], :c => :d, [:a, :c] => cor)
    transform(gdf, :c, [:c :f] .=> [sum, mean, std], :c => :d, [:a, :c] => cor)
    innerjoin(df, df, on=:a, makeunique=true)
    innerjoin(df, df, on=:b, makeunique=true)
    innerjoin(df, df, on=:c, makeunique=true)
    outerjoin(df, df, on=:a, makeunique=true)
    outerjoin(df, df, on=:b, makeunique=true)
    outerjoin(df, df, on=:c, makeunique=true)
    leftjoin!(df, DataFrame(a=[2, 5, 3, 1, 0]), on=:a)
    leftjoin!(df, DataFrame(b=["a", "b", "c", "d", "e"]), on=:b)
    leftjoin!(df, DataFrame(c=1:5), on=:c)
    reduce(vcat, [df, df])
    show(IOBuffer(), df)
    subset(df, :q)
    subset!(copy(df), :q)
    df[:, 1:2]
    df[1:2, :]
    df[1:2, 1:2]
    @view df[:, 1:2]
    @view df[1:2, :]
    @view df[1:2, 1:2]
    transform!(df, :c, [:c :f] .=> [sum, mean, std], :c => :d, [:a, :c] => cor)
    deleteat!(df, 1)
    append!(df, copy(df))
    push!(df, copy(df[1, :]))
    eachrow(df)
    eachcol(df)
    empty(df)
    empty!(copy(df))
    filter(:q => identity, df)
    filter!(:q => identity, df)
    first(df)
    last(df)
    hcat(df, df, makeunique=true)
    issorted(df)
    pop!(df)
    popfirst!(df)
    repeat(df, 2)
    reverse(df)
    reverse!(df)
    unique(df, :a)
    unique!(df, :a)
    wide = DataFrame(id=1:6,
                     a=repeat(1:3, inner=2),
                     b=repeat(1.0:2.0, inner=3),
                     c=repeat(1.0:1.0, inner=6),
                     d=repeat(1.0:3.0, inner=2))
    long = stack(wide)
    unstack(long)
    unstack(long, :variable, :value, combine=sum)
    flatten(DataFrame(a=[[1, 2], [3, 4]], b=[1, 2]), :a)
    dropmissing(DataFrame(a=[1, 2, 3, missing], b=["a", missing, "c", "d"]))
    df = DataFrame(rand(20, 2), :auto)
    df.id = repeat(1:2, 10)
    combine(df, AsTable(r"x") .=> [ByRow(sum), ByRow(mean)])
    combine(groupby(df, :id), AsTable(r"x") .=> [ByRow(sum), ByRow(mean)])
end

# forks: the workers of ColumnKernels for the common column types (the keys), each with and
# without missing values. A key's workers are compiled once and kept in this image; a schema
# of these column types then compiles nothing at its first call.
PrecompileTools.@compile_workload begin
    let n = 6,
        cols = Any[[3, 1, 2, 3, 1, 2], [3, missing, 2, 3, 1, 2],
                   [0.5, 1.5, 0.5, 2.5, 1.0, 2.0], [0.5, missing, 0.5, 2.5, 1.0, 2.0],
                   ["b", "a", "c", "b", "a", "c"], ["b", missing, "c", "b", "a", "c"],
                   [true, false, true, true, false, false],
                   [Dates.Date(2020, 1, k) for k in 1:n], [Dates.DateTime(2020, 1, k, 1, 2, 3) for k in 1:n],
                   PooledArray(["b", "a", "c", "b", "a", "c"]), InlineStrings.String15.(["b", "a", "c", "b", "a", "c"])]
        for (k, c) in enumerate(cols)
            df = DataFrame(g = [1, 2, 1, 2, 1, 2], s = ["x", "y", "x", "y", "x", "y"], c = c)
            describe(df)
            sort(df, :c); sort(df, :c, rev = true); sort(df, [:s, :c], rev = [false, true]); sort(df, [:c, :g])
            df[[2, 1, 3], :]
            show(IOBuffer(), df)
            gd = groupby(df, :c)
            combine(gd, nrow)
            combine(groupby(df, :s), :c => length => :n, nrow)
            if nonmissingtype(eltype(c)) <: Real
                combine(groupby(df, :s), :c => sum, :c => mean, :c => maximum, :c => minimum,
                        :c => sum ∘ skipmissing, :c => mean ∘ skipmissing,
                        :c => maximum ∘ skipmissing, :c => minimum ∘ skipmissing)
            end
            innerjoin(df, df, on = :c, makeunique = true, matchmissing = :equal)
            nonmissingtype(eltype(c)) <: Union{Int, Float64} && (c ./ 2; c .* 2; c .+ 1; c .- 1)
            combine(groupby(df, :s), :c => first => :f, nrow)
            innerjoin(df, DataFrame(c = c[[1, 3, 4]], z = 1:3), on = :c, matchmissing = :equal)
            Base.nonmissingtype(eltype(c)) === eltype(c) && innerjoin(df, DataFrame(c = c[[1, 3, 4]], z = 1:3), on = :c)
        end
    end
end
