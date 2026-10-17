# The interactive workload (plan §4.2), fed line by line to a REPL:
#     DATA=data julia -i --banner=no --project=<env> < scripts/session.jl
# Each step is one REPL input (results displayed as at the prompt), followed by a mark
# `T <step> <time()>`; the harness takes the differences. Lines starting `#` are skipped by the REPL.
_m(s) = println("T ", s, " ", time())
_m("start")
using CSV, DataFrames, Statistics, Dates
_m("imports")
D = get(ENV, "DATA", "data"); tmp = tempname(); nothing
df = CSV.read(joinpath(D, "people.csv"), DataFrame);
_m("read")
df
_m("show")
describe(df)
_m("describe")
sub = subset(select(df, :id, :city, :income), :income => ByRow(x -> !ismissing(x) && x > 5e4))
_m("select_filter")
sort(df, [:city, :income], rev = [false, true])
_m("sort")
combine(groupby(df, :city), :income => mean ∘ skipmissing => :mean_income, nrow)
_m("groupby_combine")
transform(df, [:age, :income] => ByRow((a, i) -> coalesce(i, 0.0) / max(coalesce(a, 1), 1)) => :ratio)
_m("user_function")
innerjoin(df, CSV.read(joinpath(D, "orders.csv"), DataFrame), on = :id)
_m("join")
df.income_k = df.income ./ 1000;
_m("add_column")
CSV.write(tmp, df)
_m("write")
s2 = CSV.read(joinpath(D, "sensors.csv"), DataFrame)
_m("2_read_show")
describe(s2)
_m("2_describe")
sort(s2, [:tag, :s1])
_m("2_sort")
combine(groupby(s2, :tag), :s1 => mean ∘ skipmissing => :m1, :s2 => maximum ∘ skipmissing => :x2, nrow)
_m("2_groupby_combine")
using InlineStrings
_m("3_using")
df3 = CSV.read(joinpath(D, "people.csv"), DataFrame; stringtype = String15)
_m("3_read_show")
describe(df3)
_m("3_describe")
combine(groupby(df3, :city), :income => mean ∘ skipmissing => :mean_income, nrow)
_m("3_groupby_combine")
exit()
