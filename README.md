# Tables, DataFrames and CSV in the trait world (demonstrator 4)

Forks of Tables 1.14.0, DataFrames 1.8.2 and CSV 1.1.0 with traits brought in where they fit, measured as an interactive session against the unmodified upstream packages and against pandas. The plan is `../writeup/plans/2026-10-17-dataframes-traits-plan.md`; `git diff upstream` is the port.

Status (session 27, 2026-10-17): M0 (baseline and harness) done.

## The workload

`scripts/session.jl`, fed line by line to a real REPL on a pseudo-terminal (`script`), results displayed as at the prompt; `scripts/session.py` is the same in pandas 3.0.6. Data from `scripts/gendata.jl` (deterministic): `people.csv` (10 000 rows: `Int`, two strings, `Int` and `Float64` with missing values, `Date`, `Bool`), `orders.csv` (50 000 rows, joined on `id`), `sensors.csv` (a second schema). Steps: read, show, describe, select and filter (`subset` with `ByRow`), sort on two columns, groupby-combine, a user function (`transform` with `ByRow`), join, add a column, write; then a second schema (read and show, describe, sort, groupby-combine); then `using InlineStrings` and a read with `stringtype = String15`, describe, groupby-combine.

Harness: `scripts/measure_session.sh [runs] [configs]` (one job at a time under `flock`, niced; each run's 1-minute load average logged), `scripts/summarize.py` (min and median per step, runs with load above 4 dropped).

## M0: the baseline (5 runs, medians, seconds)

"start" is process start to the first prompt input (the REPL's own start); "session" is the sum of the steps after the imports.

| step | pandas | upstream, stock | upstream, patched |
|---|---|---|---|
| start | 0.011 | 0.609 | 0.607 |
| imports | 0.189 | 1.019 | 1.477 |
| read | 0.009 | 4.280 | 3.647 |
| show | 0.005 | 1.113 | 1.032 |
| describe | 0.012 | 1.119 | 1.113 |
| select_filter | 0.003 | 0.196 | 0.190 |
| sort | 0.005 | 1.260 | 1.172 |
| groupby_combine | 0.005 | 0.902 | 0.793 |
| user_function | 0.153 | 0.273 | 0.270 |
| join | 0.041 | 1.348 | 1.290 |
| add_column | 0.000 | 0.113 | 0.106 |
| write | 0.023 | 0.174 | 0.173 |
| 2_read_show | 0.009 | 0.007 | 0.007 |
| 2_describe | 0.011 | 0.030 | 0.031 |
| 2_sort | 0.006 | 0.448 | 0.447 |
| 2_groupby_combine | 0.005 | 0.135 | 0.133 |
| 3_using | 0.000 | 0.001 | 0.001 |
| 3_read_show | 0.017 | 0.216 | 0.205 |
| 3_describe | 0.009 | 0.132 | 0.130 |
| 3_groupby_combine | 0.004 | 0.121 | 0.119 |
| exit | 0.038 | 0.104 | 0.105 |
| **session** | **0.318** | **12.16** | **10.92** |

- The upstream session is 34× pandas' on the patched build. The patch (piece 5) changes little here: CSV's and DataFrames' workloads are in their own packages, so there is no foreign code for piece 5 to keep.
- **The first read costs 3.6 s,** almost all compilation inside CSV (`--trace-compile`): `CSV._parse` is recompiled (marked `# recompile`: its precompiled code was invalidated), `parsecolchunk!` is compiled for `UnionColumn{Int64}` and `UnionColumn{Float64}` (columns with missing values, outside CSV's workload), and `CSV.read(…, DataFrame)` with the sink. `CSV.File` alone on `people.csv`: 1.18 s with only CSV loaded, 1.59 s after InlineStrings, 2.30 s after DataFrames.
- show (PrettyTables, 0.73 s in one keyword call), describe (per column type), sort on two columns (per tuple of column types), groupby-combine and join are about 1 s each at first call. A second schema with the same column types is fast except for sorting (0.45 s: a new tuple of column types).
- The second schema and the `String15` part cost 0.7 s together; pandas 0.06 s.
