# Tables, DataFrames and CSV in the trait world (demonstrator 4)

Forks of Tables 1.14.0, DataFrames 1.8.2 and CSV 1.1.0 with traits brought in where they fit, measured as an interactive session against the unmodified upstream packages and against pandas. The plan is `../writeup/plans/2026-10-17-dataframes-traits-plan.md`; `git diff upstream` is the port.

Status (session 29, 2026-10-19): M0, M1 done; M2–M5 redone as a trait port (below); M6 in part. The forks are paused (the user, session 29), after one round on the facts+traits compiler (julia-1.13 61852d8fb1, TraitWorld 375a930):
- the upstream suites of Tables, CSV and DataFrames pass on it (forks 8c6366a);
- the scripted session's digests equal upstream's at all 26 steps; the REPL session has 20 marks and 0 errors;
- the session was measured: "Measured in session 29" below, this file's dated results. **The current numbers** are in the design repository's [`../writeup/design/evidence.md`](../writeup/design/evidence.md) §3, from the measurement round of 2026-10-20 (julia-1.13 3b8085c222, TraitWorld bed3782; a loaded machine, so indicative), which reran the session after the `String15` fixes.

All runs: the patched build, `JULIA_TW_VIEWCACHE=0`, no TraitWorld system image, no witness tables.

## The workload

`scripts/session.jl`, fed line by line to a real REPL on a pseudo-terminal (`script`), results displayed as at the prompt; `scripts/session.py` is the same in pandas 3.0.6. Data from `scripts/gendata.jl` (deterministic): `people.csv` (10 000 rows: `Int`, two strings, `Int` and `Float64` with missing values, `Date`, `Bool`), `orders.csv` (50 000 rows, joined on `id`), `sensors.csv` (a second schema). Steps: read, show, describe, select and filter (`subset` with `ByRow`), sort on two columns, groupby-combine, a user function (`transform` with `ByRow`), join, add a column, write; then a second schema (read and show, describe, sort, groupby-combine); then `using InlineStrings` and a read with `stringtype = String15`, describe, groupby-combine.

Harness: `scripts/measure_session.sh [runs] [configs]` (one job at a time under `flock`, niced; each run's 1-minute load average logged), `scripts/summarize.py` (min and median per step, runs with load above 4 dropped).

## M0: the baseline

The M0 table (pandas and upstream, 5 runs, before the facts compiler) is under "History (before the facts compiler)". The session-29 upstream numbers are in "Measured in session 29".

## M1: the forks and the correctness bar

`Tables/`, `DataFrames/` and `CSV/` are the depot's sources of the three versions, committed unchanged and tagged `upstream`; `env_forks/` points at them with `[sources]` and keeps the upstream names and UUIDs. Their upstream test suites run unchanged (`scripts/testsuites.sh`; logs in `logs/*-M1-upstream.log`; patched build, one thread). The test dependencies missing from the depot (CategoricalArrays, DataValues, ShiftedArrays, DataDecimals, QueryOperators) were fetched from the package server, so nothing is skipped.

| suite | tests passed | time |
|---|---|---|
| Tables | 466 365 | 49 s |
| CSV | 330 549 | 5.8 min |
| DataFrames | 16 515 336 | 22.5 min |

Test lines that reach the column storage (`DataFrames._columns`), to be checked when the storage changes (M3): `constructors.jl:14–15`, `indexing_offset.jl:16–18`, `show.jl:600`, `indexing.jl:641, 643, 795, 802`, `dataframe.jl:137–148`, `io.jl:1047`, `join.jl:693, 1932`, `grouping.jl:118`, `iteration.jl:49`.

## M2–M6: the port (session 29, rebuilt on the declared operations)

Sessions 27–28 built M2–M5 with kernels that unwrapped each column (`vector(c)`) and ran upstream's code on it, and with `CSVSource` as CSV's only trait. The implementation review (2026-10-18, P7) found that this validates a function barrier, not keys. Session 29 rebuilt the port so that kernels read columns through the traits' operations, and the reader's columns and string types are declared implementations.

### The traits

| trait | where | operations | conforming |
|---|---|---|---|
| `Column{T}` | `Tables/src/ColumnCore.jl` | `nrows`, `cell`, `emptycells(c, n)::Vector{T}`, `take(c, rows)`, `nlevels`, `levelcode`, `level` (the reference pool, from DataAPI), `vector` (the API's way back) | every `AbstractVector` (a family) |
| `TableSource` | `Tables/src/ColumnCore.jl` | `tablenames`, `tablecolumn(t, i)::Dynamic{Column}`, `tablerows` | `NamedTuple`s of vectors; `DataFrame`, `SubDataFrame` (DataFrames); `CSV.File` (CSV) |
| `CSVColumn{T} <: Column` | `CSV/src/ColumnParsers.jl` | `parsecell!(c, i, buf, pos, len, esc, opts, scratch)::Bool` | `Vector` (a family): the vectors the reader parses into (`TypedColumn.values`, `UnionColumn.uvalues`) |
| `TextColumn{T} <: Column` | `CSV/src/ColumnParsers.jl` | `textcolumn(c, maxlen, n, withmissing)`, `settext!`, `rowtexttype`, `rowtext` | `Vector{S}`, `Vector{Union{S, Missing}}` for InlineStrings' 8 widths and `InlineString` (`CSV/ext/CSVInlineStringsExt.jl`) |
| `CSVSource` | `CSV/src/ColumnParsers.jl` | `rawsource` | paths, `IO`, bytes: the reader's entry is a worker per source type |

### The workers (compiled per key)

| function | upstream | the port |
|---|---|---|
| `describe` | `get_stats(@nospecialize(col))` | `colstats(c::Column, stats)`: the cells gathered by `cell` into `emptycells(c, n)`; Statistics runs on that `Vector{T}`, so it compiles per cell type, shared by every column kind |
| `sort`, `sortperm` (default order, columns by name) | `DFPerm{O, Tuple{…}}`, per tuple of column types | `refine!(perm, c::Column, rev)`: a stable sort of row indices comparing `cell`s, one column at a time from the last |
| `groupby` | `row_group_slots!(::Tuple{Vararg{AbstractVector}})` | per column: `refcodes` (the reference pool through `nlevels`/`levelcode`/`level`, or integers in a narrow range read by `cell`) and `firstcodes!` (a `Dict{T, Int}` over `cell`s); combined in integer code |
| `innerjoin`, `leftjoin`, `rightjoin`, `outerjoin`, `leftjoin!` on one key column (`find_inner_rows`) | `_innerjoin_sorted`, `_innerjoin_unsorted(_int)`, per pair of column types | `innerrows(l::Column, r::Column, …)`: upstream's three algorithms ported line by line onto `cell`/`nrows` |
| `semijoin`, `antijoin` on one key column (`find_semi_rows`) | `_semijoin_sorted`, `_semijoin_unsorted(_int)` | `semirows(l::Column, r::Column, …)`: ported the same way |
| `df[rows, cols]` | `col[rows]` | the operation `take` (the column's own selection; a pooled column stays pooled) |
| `combine` with `sum`, `prod`, `mean`, `var`, `std`, `length` (± `skipmissing`) | `groupreduce` per column type | `aggregate(c::Column, agg, gd)`: upstream's `groupreduce` over the gathered cells, compiled per cell type; `maximum`, `minimum`, `first`, `last` keep upstream's code (their result keeps the column's kind) |
| `DataFrame(x)` for a `TableSource`, so `CSV.read(src, DataFrame)` | `fromcolumns` via `Tables.getcolumn` per name | `fromsource(t::TableSource, copycols)` |
| `CSV.File`'s parse loop for typed columns | `parsecolchunk!(::Union{TypedColumn{T}, UnionColumn{T}})` per `T` | `parsecells!(c::CSVColumn, present, …)`, each cell through `parsecell!` |
| CSV's string types beyond `String`/`Symbol` | methods added by `CSVInlineStringsExt` to seven internal functions | `filltext!(c::TextColumn, col, n)` and the `TextColumn` operations; the validation is `conforms(Vector{S}, TextColumn)` |

Kept plain: the index, metadata, the `=>` mini-language, reshape, broadcasting, PrettyTables rendering (into a buffer, a plain fix of session 27), CSV's structural index, type detection, `Rows`/`Chunks`/`lazy` (they reach `TextColumn` only for string types), the writer.

Not done (M6–M9 of the plan): user functions as `Callable`s (`ByRow`, `subset`), multi-column join keys (`OnCol` stays upstream's), the writer per key (M7), workloads and the measurement (M8–M9, wait for part D).

The workloads of session 27 stay as they were (DataFrames' `other/precompile.jl`, `CSV/ext/CSVDataFramesExt.jl`); they are plain-Julia remedies and count as such. The InlineStrings extension's workload is gone: the extension is implementations only. *Later in session 29:* a new extension over CSV, DataFrames and InlineStrings, `CSV/ext/CSVDataFramesInlineStringsExt.jl`, carries the `String15` workload (forks 9d512a1). It is a plain-Julia remedy too. The performance review calls it a workaround; the design's answer is AOT from declared targets (`../writeup/design.md` §4.8), not built.

## Test status (session 29): what ran, what did not

**Update, later in session 29** (forks 8c6366a, on the facts+traits compiler): all three upstream suites pass. One port bug was fixed on the way (`_dcolumns` for any `AbstractDataFrame`), and `DataFrame(::TableSource)` asserts its result. `scripts/check_session.sh` passes: digests equal at 26 steps, the REPL session with 20 marks and 0 errors. What follows is the state when the port was committed (064a6cf).

The user stopped Julia runs mid-session (the compiler work needs the shared lock). So the port is committed partly untested.

Ran, on the patched build with `JULIA_TW_COMPILER_FACTS=0 JULIA_TW_VIEWCACHE=0`:
- **Tables' suite: green,** 466,365 tests as at M1 (`logs/Tables-M6.log`), with today's `ColumnCore`.
- **CSV's suite: not green on the last run** (`logs/CSV-M6-before-ext-fix.log`): 330,145 passed, 8 errors, all in tests that use InlineStrings. The extension had failed to precompile: the auto-width `rowtext` inferred `Any` against its declared `AbstractString`. Fixed since (an assertion in `_rowcell`); the run before had 7 failures and 1 error from `Missing` passing as a string type and a per-cell `conforms` call, also fixed. Since the fixes, only smoke checks ran: `CSV.File`/`CSV.read` with `stringtype = String15`, `InlineString`, `pool = true`, `CSV.Rows` and `CSV.lazy` with `InlineString`, an over-long `String15` cell (raises), `DataFrame(::CSV.File)`.
- **DataFrames: smoke checks only:** `describe`, `sort` on one and two columns (with `NaN`, `-0.0`, `missing`), `groupby`/`combine` with `nrow` on integer, string and pooled columns, `sort = true`, `skipmissing = true`, `DataFrame(::NamedTuple)`. The full suite was started and stopped before any test file finished.

Not run at all:
- DataFrames' suite (last green at M1, on the unchanged fork).
- The joins through `innerrows`/`semirows`, and the additive aggregates through `aggregate`: written after the last smoke run.
- CSV's suite after the two fixes.
- `scripts/check_session.sh`: the session's results, forks against upstream, digest by digest, and the REPL session end to end.

To run, in this order (one job at a time; `scripts/testsuites.sh` takes the lock):
1. `scripts/testsuites.sh ../julia-1.13/julia "CSV DataFrames" M6`: both suites green, the counts as at M1 (CSV 330,549; DataFrames 16,515,336).
2. `scripts/check_session.sh`: "digests equal", the REPL session with 20 marks and 0 errors.
3. Tables again only if TraitWorld changes the `@implement` machinery.

## Measured in session 29

A dated table: julia-1.13 61852d8fb1, TraitWorld 375a930 (the build of 2026-10-19), the patched build. `scripts/session.jl` at a REPL on a pty, 3 runs each. One machine, shared with other jobs. Upstream runs on the same build, in the default mode (not under `all`). The current numbers, from the round of 2026-10-20: [`../writeup/design/evidence.md`](../writeup/design/evidence.md) §3.

| | Forks | Upstream |
|---|---|---|
| imports | 1.70–2.09 s | 1.33–1.42 s |
| read / show / describe | 0.075 / 0.17 / 0.14–0.19 s | 3.4 / 0.97 / 1.0 s |
| sort / groupby-combine / join | 0.006 / 0.021 / 0.21 s | 1.15 / 0.77 / 1.24 s |
| `String15` read and show | 1.56–1.67 s (before the fixes) | 0.19 s |
| the session without imports | **2.85 s** | **10.40 s** |

The forks' first `String15` read alone (a script) took 1.74 s before and 0.04 s after the session-29 fixes (a workload extension and the first-call check by facts; their contributions were not separated). The session harness was rerun in the round of 2026-10-20 (julia-1.13 3b8085c222): the `String15` step 0.060–0.062 s, the session without imports 1.35–1.37 s against upstream's 10.7–11.2 s (indicative: load average 3.4–5.2; `evidence.md` §3).

- The earlier rows (session 28: 1.19 s; upstream 10.9 s) predate this rebuild and used the TraitWorld system image, the policy as a package and the kernels that unwrapped columns.
- The control under `--compile-by-facts=all` ran upstream CSV + DataFrames, not the forks: nine unrelated loads after the work lost 2 of 3,340 of their CodeInstances under `all` against 570 of 4,712 in plain mode; their work after the loads took 992 ms under `all` (not diagnosed) against 4,009 ms. The round of 2026-10-20 has newer numbers (`evidence.md` §1).

**Not measured yet** (each against upstream under `--compile-by-facts=all` with the same workloads, first call and steady state, first session and later sessions):

- The session harness on a quiet machine (the round's rerun after the `String15` fixes had a load average of 3.4–5.2).
- The session against upstream under `all` (the numbers above compare with upstream in the default mode).
- The cost of gathering cells (`describe`, the additive aggregates): one copy of each column per call. Against upstream's direct call on the vector, on `big.csv` (10⁶ rows).
- `refine!` (a comparison sort of row indices through `cell`) against upstream's `RadixSort`/`TimSort` on a column, single and two-column sorts on `big.csv`.
- `innerrows` and the group codes through `cell` on a `Dynamic{Column}` opened at the bound: the per-cell cost is the trait object's read, expected at plain speed (`writeup/design.md` §4.2).
- Code compiled per key: how many worker instances the session creates (column types × kernels) against upstream's per-tuple specializations (sort and groupby on several schemas).
- CSV's parse loop through `parsecell!` against upstream's `parsecolchunk!`, on `big.csv`.
- String types through `TextColumn`: the conversion is sequential (upstream converts with `_rowranges` over tasks); `CSV.Rows` with an InlineString type asks `conforms` and allocates an empty `Vector{S}` per cell.
- Loads: `using InlineStrings` before and after the first read (upstream's extension invalidated the reader, `TraitReport/README.md` row 3); lost CodeInstances by owner.
- A new string type conforming at the prompt (`@implement TextColumn Vector{MyStr}`), first call.

## TraitWorld issues found (session 29)

- **Family registries collide across packages.** A family implementation defines `TraitWorld._family_registry(::Val{name})` with `name = gensym(:family_builders)` (`TraitWorld/src/implement.jl:630–633`). Gensym counters start alike in each precompilation process, so CSV's registry got the name of one of Tables' (`##family_builders#156`), and precompiling CSV failed: "Method overwriting is not permitted during Module precompilation". Workaround in `CSV/src/ColumnParsers.jl` (advance the gensym counter). Fix: key the registry by module as well (for example `_family_registry(::Val{name}, ::Val{modulename-and-uuid})`, or a registry constant reached through the `conformance` method itself).
- **Result types: a family member is not checked like a single type.** `rowtext` with an `Any` result passed as part of a family implementation (`A where {A <: Vector{<:Union{Missing, InlineString}}}`), and was refused as a single-type implementation (`Vector{InlineString}`): "returns `Any`, declared `AbstractString`". The check should be the same, at the member's first use at the latest.
- **No `where` on bounded arguments.** `f(c::Column{T}) where {T}` gives `MethodError: no method matching f(::Dynamic{Column})`. The port names `T` through an operation (`emptycells(c, n)::Vector{T}`).
- **`@concrete_only` and missing values** (not tried; from the design text): "concrete all the way down" would refuse `Vector{Union{Missing, Int}}`, the standard column with missing values, although it is a concrete type. `CSVColumn` therefore declares no concreteness level; the plan had asked for `@concrete_only`.

## History (before the facts compiler)

Measurements before parts (B)–(D) of the compiler, unchanged.

### M0: the baseline (5 runs, medians, seconds)

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
