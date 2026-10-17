# forks: the reader's column types meet the table's workers. CSV produces column types that
# DataFrames does not know (`DataStringVector`, `Durations.Timestamp` columns, pooled strings);
# DataFrames' workers for them (ColumnKernels: describe, sort, groupby, joins, row selection) are
# compiled under the facts policy in this extension's workload and kept in its image, which
# exists exactly when both packages are loaded. A new key thus costs no compilation in the
# session, and other packages' loads do not discard it (writeup/notes/3-wrapping.md).
module CSVDataFramesExt

using CSV, DataFrames
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
        for df in (CSV.read(path, DataFrame), CSV.read(path, DataFrame; pool = true))
            show(IOBuffer(), df)
            describe(df)
            for c in names(df)
                sort(df, c); sort(df, c, rev = true)
                df[[2, 1, 3], :]
            end
            sort(df, [:city, :income], rev = [false, true])
            for g in (:city, :name, :active, :id)
                combine(groupby(df, g), :income => _M ∘ skipmissing => :m, nrow)
                try   # a group of missing values only has no maximum: the error path is compiled too
                    combine(groupby(df, g), :income => sum ∘ skipmissing, :income => maximum ∘ skipmissing,
                            :age => _M ∘ skipmissing, nrow)
                catch
                end
            end
            innerjoin(df, df[1:2, [:id, :income]], on = :id, makeunique = true)
            innerjoin(df, df[1:2, [:city, :income]], on = :city, makeunique = true)
            df.income ./ 1000
            CSV.write(path * ".out", df)
        end
    end
end

end
