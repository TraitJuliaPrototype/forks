# The interactive workload (plan §4.2, the steps of scripts/session.jl) as a correctness check:
# each step's result is reduced to a digest line (size, names, element types, a hash of every
# column's cells; a hash of the printed text for show and describe). Run in env_forks and in
# env_upstream; the two outputs must be identical (scripts/check_session.sh). No timing.
#     DATA=data julia --project=env_forks scripts/session_check.jl > forks.txt
using CSV, DataFrames, Statistics, Dates
D = get(ENV, "DATA", "data")
tmp = tempname()

cellhash(col) = hash(Any[x for x in col])   # cells only, not the container type
function digest(x::AbstractDataFrame)
    s = string(size(x), " ", join(names(x), ","), " ", join(string.(eltype.(eachcol(x))), ","))
    return s * " " * join(string.(cellhash.(eachcol(x)), base = 16), ",")
end
digest(x::AbstractVector) = string(length(x), " ", eltype(x), " ", string(cellhash(x), base = 16))
digest(x) = repr(x)
texthash(x) = string(hash(sprint(show, MIME("text/plain"), x; context = (:displaysize => (40, 120), :limit => true))), base = 16)
step(name, x) = println(rpad(name, 18), digest(x))
showstep(name, x) = println(rpad(name, 18), "text ", texthash(x))

df = CSV.read(joinpath(D, "people.csv"), DataFrame);           step("read", df)
showstep("show", df)
d = describe(df);                                              showstep("describe", d); step("describe_df", d[:, [:variable, :nmissing]])
sub = subset(select(df, :id, :city, :income), :income => ByRow(x -> !ismissing(x) && x > 5e4)); step("select_filter", sub)
step("sort", sort(df, [:city, :income], rev = [false, true]))
step("groupby_combine", combine(groupby(df, :city), :income => mean ∘ skipmissing => :mean_income, nrow))
step("user_function", transform(df, [:age, :income] => ByRow((a, i) -> coalesce(i, 0.0) / max(coalesce(a, 1), 1)) => :ratio))
orders = CSV.read(joinpath(D, "orders.csv"), DataFrame);       step("read_orders", orders)
step("join", innerjoin(df, orders, on = :id))
df.income_k = df.income ./ 1000;                               step("add_column", df.income_k)
CSV.write(tmp, df);                                            step("write", hash(read(tmp, String)))
s2 = CSV.read(joinpath(D, "sensors.csv"), DataFrame);          step("2_read", s2); showstep("2_show", s2)
showstep("2_describe", describe(s2))
step("2_sort", sort(s2, [:tag, :s1]))
step("2_groupby_combine", combine(groupby(s2, :tag), :s1 => mean ∘ skipmissing => :m1, :s2 => maximum ∘ skipmissing => :x2, nrow))
using InlineStrings
df3 = CSV.read(joinpath(D, "people.csv"), DataFrame; stringtype = String15); step("3_read", df3); showstep("3_show", df3)
showstep("3_describe", describe(df3))
step("3_groupby_combine", combine(groupby(df3, :city), :income => mean ∘ skipmissing => :mean_income, nrow))
# beyond the session: pooled strings, the auto width, a join on a string key, sorting a pooled column
df4 = CSV.read(joinpath(D, "people.csv"), DataFrame; pool = true, stringtype = InlineString); step("4_read_pooled", df4)
step("4_groupby_pooled", combine(groupby(df4, [:city, :active], sort = true), nrow, :age => mean ∘ skipmissing => :a))
step("4_sort_pooled", sort(df4, [:city, :name]))
step("4_join_string", innerjoin(select(df4, :city, :id), combine(groupby(df, :city), nrow), on = :city))
step("4_rows", [r.name for r in CSV.Rows(joinpath(D, "people.csv"); stringtype = InlineString, limit = 5)])
