# forks: columns of InlineStrings (`stringtype = String15`, or `InlineString` for the narrowest
# width) meet DataFrames' workers. The reader's implementations for them are CSVInlineStringsExt's;
# the code for reading such a table, showing it and the usual kernels over it is compiled in this
# extension's workload and kept in its image, which exists exactly when CSV, DataFrames and
# InlineStrings are loaded (as CSVDataFramesExt does for CSV's own column types). Without it the
# first such read compiled in the session (1.6 s, upstream 0.19 s: its image has InlineStrings' code).
module CSVDataFramesInlineStringsExt

using CSV, DataFrames, InlineStrings
using PrecompileTools: @compile_workload

const _M = DataFrames.Statistics.mean

@compile_workload begin
    text = "id,name,city,age,income,joined,ts,active\n" *
           "1,ab,Kiel,42,1.5,2020-01-02,2024-01-02T03:04:05,true\n" *
           "2,cd,Bonn,,2.5,2021-03-04,2024-02-03T04:05:06,false\n" *
           "3,ef,Kiel,30,,2022-05-06,2024-03-04T05:06:07,true\n" *
           "4,gh,Ulm,55,4.5,2023-07-08,2024-04-05T06:07:08,false\n"
    mktemp() do path, io
        Base.write(io, text); close(io)
        for st in (String15, InlineString)
            df = CSV.read(path, DataFrame; stringtype = st)
            show(IOBuffer(), df)
            show(IOContext(IOBuffer(), :limit => true, :displaysize => (40, 120)), MIME"text/plain"(), df)
            describe(df)
            sort(df, [:city, :income], rev = [false, true])
            combine(groupby(df, :city), :income => _M ∘ skipmissing => :m, nrow)
        end
    end
end

end
