# Tables, DataFrames and CSV in the trait world (demonstrator 4)

Forks of Tables 1.14.0, DataFrames 1.8.2 and CSV 1.1.0 with traits brought in where they fit, measured as an interactive session against the unmodified upstream packages and against pandas. The plan is `../writeup/plans/2026-10-17-dataframes-traits-plan.md`; `git diff upstream` is the port.

## On the unified build (branch `unified`, W-104)

This branch follows the design under "traits are abstract types" on Julia's unified build (`julia-unified`, branch `unified`), with TraitWorld's branch `unified`. The sections below describe the earlier build (branch `main`).

- A DataFrame's columns are a `Vector{Column}`, each the stored vector itself (`tocolumn` is the identity: `Dynamic{Column}` with its parameter open is refused). `tocolumn` takes the column `@specialize`, so the call dispatches on the column's type and a column that does not conform is refused at `DataFrame(...)` (the member's first use, traits §5.10). The kernels take `@specialize`, the pooled kernel `All{Column, PooledColumn}`; `byrow` computes its result type by `promote_op` (traits §9), and a function with no method at the cells' type (`!` over a `Vector{Any}`) takes `byrow`'s plain methods, called per cell as upstream's `map`.
- `scripts/check_session.sh ../julia-unified/julia env_forks`: digests equal upstream's at 26 steps, the REPL session's 20 marks print (2026-11-08, `unified` 350c5b1c59, TraitWorld bd9a721; `logs/w104e/check-session.log`).

Upstream suites on the unified build (dated; the current state is the last row):

| Date | Build | Tables | CSV | DataFrames | Logs |
|---|---|---|---|---|---|
| 2026-11-08 | `unified` 9dab7b6983, forks 8228f18 | pass | 6 of 330,545 fail: cell access allocates (open issue 158) | 14 fail: `ByRow(!)` over `Any` cells, the refused column not refused, `@inferred` at `tables.jl:86` | `logs/w104/` |
| 2026-11-08 | `unified` 350c5b1c59, TraitWorld bd9a721, forks this commit | pass (86 s) | the same 6 (open issue 158) | 4 fail at `tables.jl:86`, `@inferred` of `DataFrame(columns)` (open issue 158's second case, compiler C-36); `constructors.jl:456` failed on the earlier library's wording, updated after this run | `logs/w104e/` |
| 2026-11-08 | `unified` e9b9261808, TraitWorld 1f0f78e, forks this commit (CSV's reader and DataFrames' module compiled by facts, E-302, E-305) | not run | pass, 330,545 (open issue 158's six gone) | 7 fail: the 4 at `tables.jl:86`, and 3 `@inferred` widened to `Any` by facts (`sort`, `dropmissing`, `first` with `view`: a result through a call at no fact signature is what the callee declares; compiler C-36) | `logs/w104/suite-*-e30[25]-*.log` |

Status (2026-10-28): the forks follow [the design memo](../writeup/plans/2026-10-28-dataframes-lean-core.md) (W-79, W-14). **D2 done** (E-211; julia-1.13 a4e9ad5da9, TraitWorld 3fcff02, forks 30f77b3): `Column{T}` asks only what every vector can do; the reference pool is `PooledColumn{T}`, a trait of its own, implemented in the Tables fork's extensions for PooledArrays and CategoricalArrays (`Tables/ext/`); the groupby kernel's `refcodes` is chosen at a stored column by its object's traits. The three forks precompile and their upstream suites pass (`logs/*-D2c.log`); the pooled path is taken for pooled and categorical columns stored as `Dynamic{Column}` (`scripts/d2_pooled.jl`, `logs/d2/`). **D0 done** (E-212; results below): the control, `scripts/measure_session.sh` with the configs `up-patched`, `up-wrapped` (upstream wrapped as trait modules: the branch `wrapped`, checked out at `../forks-wrapped`, and `env_wrapped/`), `up-all` and `fk-patched`. **D1 done** (E-213): about 0.45 s of the forks' 1.59 s import is 28 family members of `Column` checked again at load (W-84). **D3 done** (E-214): the columns opened at the kernels' entries (an `Opened{Column}` bound on each kernel, TraitWorld e99851b; times and allocations unchanged, `logs/w88/`); a closure in `_group_rows!` that boxed a counter fixed; aggregates and `describe` read the cells in place through `CellVector` (open issue 96, TraitWorld bdaf4b3). **D4 done** (E-215): no kernel worker for a schema whose column types were seen. **M6 done** (E-216, forks 576eeaa): `ByRow` over one or two columns through `ColumnCore.byrow`, the function a `Callable` at the cells' types, its result type inferred at the entry; results equal to upstream's. A new closure costs the kernel 6 ms against `map`'s 18 ms, but a whole `transform` the same as upstream (24–25 ms): the plain mini-language is compiled per closure. Steady state 2.2–2.9× upstream's (the `Dynamic` call per row). **M7 done** (E-217): `CSV.write`'s fallback columns (pooled, InlineStrings', a user's cell type) are staged by a `Column` kernel, `ColumnParsers.stagecells!`, and held as `Vector{Dynamic{Column}}`: a schema of seen column types compiles nothing (0.8 ms for 10⁴ rows, upstream 368 ms); the steady write of 10⁵ rows 7.75 ms (upstream 21 ms). A width of unknown cell types is estimated from a sample for sizing blocks (it was the whole buffer: blocks of two rows). **M8 done** (E-224): joins on several key columns through the kernel `jointcodes!` (the columns passed `Dynamic`: a worker per pair of cell types), the codes folded into one integer key per row and joined by `innerrows`/`semirows`; 110 joins equal to upstream's with their order; a key schema over seen column types compiles nothing (3 ms, upstream 314 ms); steady joins of 10⁶ rows 190 / 33 ms (upstream 159 / 35). `subset` needs nothing more: its `ByRow` predicates reach M6's kernel through `select`, and whole-column predicates stay plain (the memo §3.3). **W-84** (2026-10-29, E-231, TraitWorld ca92f22): members fixed from their images' records at load, the import 1.42 → 1.21 s (below). **The memo's questions decided:** a column that does not conform raises the member check's error (the user; a test in `DataFrames/test/constructors.jl`); joins on pooled keys need no capability of their own (E-232, below).

Session 29 (2026-10-19): M0, M1 done; M2–M5 redone as a trait port (below); M6 in part; one round on the facts+traits compiler (julia-1.13 61852d8fb1, TraitWorld 375a930):
- the upstream suites of Tables, CSV and DataFrames pass on it (forks 8c6366a);
- the scripted session's digests equal upstream's at all 26 steps; the REPL session has 20 marks and 0 errors;
- the session was measured: "Measured in session 29" below, this file's dated results. **The current numbers** are in the design repository's [`../writeup/design/evidence.md`](../writeup/design/evidence.md) §3, from the measurement round of 2026-10-20 (julia-1.13 3b8085c222, TraitWorld bed3782; a loaded machine, so indicative), which reran the session after the `String15` fixes.

All runs: the patched build, `JULIA_TW_VIEWCACHE=0`, no TraitWorld system image, no witness tables.

## The workload

`scripts/session.jl`, fed line by line to a real REPL on a pseudo-terminal (`script`), results displayed as at the prompt; `scripts/session.py` is the same in pandas 3.0.6. Data from `scripts/gendata.jl` (deterministic): `people.csv` (10 000 rows: `Int`, two strings, `Int` and `Float64` with missing values, `Date`, `Bool`), `orders.csv` (50 000 rows, joined on `id`), `sensors.csv` (a second schema). Steps: read, show, describe, select and filter (`subset` with `ByRow`), sort on two columns, groupby-combine, a user function (`transform` with `ByRow`), join, add a column, write; then a second schema (read and show, describe, sort, groupby-combine); then `using InlineStrings` and a read with `stringtype = String15`, describe, groupby-combine.

Harness: `scripts/measure_session.sh [runs] [configs]` (one job at a time under `flock`, niced; each run's 1-minute load average logged), `scripts/summarize.py` (min and median per step, runs with load above 4 dropped).

## D0: the control on one build (2026-10-28)

julia-1.13 a4e9ad5da9, TraitWorld 3fcff02, forks 408dff9, wrapped upstream 3687dc6; `scripts/measure_session.sh 3 "up-patched up-wrapped up-all fk-patched"`; the first run of each a warm-up, ranges over the other 2; load average 1.5–2.7, the machine otherwise idle; `logs/d0/session.log`. Current numbers: [the evidence](../writeup/design/evidence.md) §3.

| | forks | upstream plain | upstream wrapped | upstream `all` |
|---|---|---|---|---|
| imports | 2.25–2.30 s | 1.14–1.17 s | 1.42–1.44 s | 0.56 s |
| without start and imports | 1.82–1.87 s | 10.5–10.7 s | 7.9–8.7 s | 6.5 s |
| wall | 4.4–4.5 s | 11.9–12.5 s | 9.6–10.5 s | 7.5–7.6 s |

Wrapping upstream (porting 0.1a; `scripts/d0_pirates.jl`, `logs/d0/pirates.log`): rule 3 refuses Tables' `DataAPI.nrow` and `ncol` for `NamedTuple`s (4 methods) and DataFrames' `Base.vcat(dfs::AbstractDataFrame...)` (2: at zero arguments it names nothing of DataFrames'). Resolved: DataAPI, a copy on the branch `wrapped`, names Tables a joint owner; `vcat` names its first frame. `scripts/check_session.sh ../julia-1.13/julia env_wrapped`: digests equal at 26 steps, the REPL session 20 marks and 0 errors (`logs/d0/check-wrapped.log`).

## D3 and D4: the kernels, and schema independence (2026-10-28)

D3 (`scripts/d3_kernels.jl`, 10⁶ rows, minimum of 5 after a warm-up, one process per setting; `logs/d3/`), upstream against the forks as they were, with the columns opened and the boxed counter fixed (`fixed`), and with `CellVector` (`cellvec`, TraitWorld bdaf4b3):

| | upstream | forks as they were | fixed | cellvec |
|---|---|---|---|---|
| sort Int | 141 ms | 119 | 69 | 68 |
| sort String, Float64 | 303 ms | 742 | 320 | 314 |
| groupby-sum Int key | 2.6 ms | 34.6 | 5.8 | 4.4 |
| groupby-sum two keys | 3.3 ms | 36.1 | 11.0 | 7.1 |
| groupby-sum pooled key | 1.8 ms | 48.0 | 5.2 | 4.2 |
| groupby-mean skipmissing | 1.7 ms | 14.3 | 3.8 | 1.6 |
| describe | 53 ms | 114 | 95 | 77 |
| innerjoin Int key | 27 ms | 25 | 32 | 26 |
| combine SubDataFrame fn | 2.0 ms | 2.2 | 2.5 | 2.5 |

D4 (`scripts/d4_schemas.jl`, 10⁴ rows; `logs/d4/`): the same work over three schemas with the same column types. Forks 367 / 78 / 51 ms, upstream 5,084 / 113 / 114 ms; no kernel worker for schemas 2 and 3.

## M8: joins on several key columns (2026-10-28, E-224)

Upstream joins on several keys through `OnCol`, a vector of row tuples compiled per tuple of key column types. The fork codes each pair of key columns with the kernel `jointcodes!(lc, rc, l::Column, r::Column, order)` (the columns passed `Dynamic`: a worker per pair of cell types): equal codes for `isequal` cells, in `isless` order when all cells can be compared. `joinkeys` (plain code over `Vector{Int}`, compiled once) folds the codes into one integer per row, the first column most significant; before the product of the code counts would overflow, it renumbers the keys densely in their order. The one-column kernels `innerrows` and `semirows` then join the keys with upstream's algorithms: a sorted merge only if the keys keep the rows' order. `OnCol` stays (upstream's tests use it), unused by the joins.

Checks (`scripts/m8_joins.jl check`, `logs/m8/check-*.log`): 110 joins (inner, left, right, outer, semi, anti, `order = :left`; two and three keys; `Int`, `String`, `Float64`, `Bool`, pooled, `missing` with `matchmissing = :equal`, `Complex` keys that cannot be ordered, `Int` against `Float64` keys, sorted frames, an empty side; each with the right and the left side shorter): the rows and their order equal to upstream's.

Times (`scripts/m8_joins.jl time`, `logs/m8/time-*.log`; one process per setting, julia-1.13 a4e9ad5da9, TraitWorld 38a3abf):

| | upstream | forks |
|---|---|---|
| first `innerjoin` on `[:a, :s]` (`Int`, `String`; after a join on `:a`), 2,000 × 1,000 rows | 907 ms | 978 |
| then on `[:s, :x]` (`String`, `Float64`) | 235 ms | 316 |
| then on `[:x, :a, :s]`: column types seen | 314 ms | 3.1 |
| steady `innerjoin`, 10⁶ × 10⁵ rows, two keys | 159 ms | 190 |
| steady `semijoin`, the same | 34.5 ms | 32.8 |

The first two schemas compile a worker per new pair of column types (about 300 ms each); a third schema over seen column types compiles nothing. The steady join's steps (`scripts/m8_split.jl`, `logs/m8/split-fixed.log`): the codes 5 ms (`Int`) and 17 ms (`String`), the fold 25 ms in all, `innerrows` on the keys 59–95 ms. On the way, a plain bug of the fold: the row counts read from an untyped vector of columns were `Any`, so every row's arithmetic dispatched (443 ms; `logs/m8/split.log`).

Not the same as upstream in one case: where a key column's cells cannot be ordered, the fork always hashes; upstream may still merge sorted rows when the earlier key columns decide every comparison. The rows are the same; their order, which upstream leaves undefined by default (`order = :undefined`), may differ.

## W-84: members fixed from their images' records at load (2026-10-29, E-231)

TraitWorld ca92f22 against c39fedc (the change: a family member fixed while a package image is built is recorded in that image and fixed from the record at load, while the methods that serve it are the same; [the plan](../writeup/plans/2026-10-29-w84-member-checks-at-load.md)); julia-1.13 bfca89decc; forks c1ac52d; `JULIA_TW_LOADREPORT=1 julia --project=env_forks ../experiments/tools/scripts/forks_loadreport.jl`, two processes a side, the forks precompiled for each side; logs `../experiments/checks/logs/w84/forks-{before,after}-*.log`. Current numbers: [the evidence](../writeup/design/evidence.md) §3.

| | before | after |
|---|---|---|
| `using CSV, DataFrames, Statistics, Dates` | 1.421–1.427 s | 1.206–1.213 s |
| members fixed at load | 27 checked, 390–394 ms | 26 from records, 134–135 ms; 1 checked, 22 ms |
| first uses (a frame, `CSV.write`, `CSV.read`, groupby-combine) | 0.38 s | 0.33–0.34 s |

The one member checked, `Column` for `Vector{Union{Missing, String15}}`, has no record: it is fixed while Julia writes an image (lowering L-45). The records' 134 ms is the first lookup's compilation, about 70 ms, and about 2 ms per member. Checks: the session's digests equal upstream's at 26 steps, the REPL session 20 marks and 0 errors (`../experiments/checks/logs/w84/forks-check-session.log`); D2's output unchanged (`d2-pooled.log`).

## A column that does not conform is refused (2026-10-29)

The user's decision ([decisions](../writeup/record/decisions.md) §8): a column that fails `Column`'s member check raises the member check's error at `DataFrame(...)`, not copied. `DataFrames/test/constructors.jl`, testset "forks: a column that does not conform to Column": a vector type whose `length` infers `Any`, stored as given (`copycols = false`), raises `ImplementError` naming the operation and both types (`` `nrows` at Tuple{AnyLengthVector} returns `Any`, declared `Int64` ``). By default the frame stores a copy (upstream's `copycols`), a `Vector{Int}`, which conforms. The test file passes (`../experiments/checks/logs/w84/dataframes-constructors.log`).

## Joins on pooled keys (2026-10-29, E-232)

The memo's question 1: is the pool through DataAPI enough for joins, or do joins want a capability of their own (`refpool` of both sides)? `scripts/w14_pooled_joins.jl` (`logs/w14/`): a fact table of 10⁶ rows (keys from 10⁴ levels) against a dimension table with unique keys (9,000 rows on `:k`, 90,000 on `[:k, :a]`); the first join on small frames (compile included) and the steady join (minimum of 5); forks in `env_d2`, upstream in `env_upstream` with CategoricalArrays stacked; one process a side; TraitWorld ca92f22. The results' digests are equal in all 20 cases.

| keys (left/right), steady ms | forks inner `:k` | upstream | forks left `:k` | upstream | forks inner `[:k, :a]` | upstream |
|---|---|---|---|---|---|---|
| String/String | 40.2 | 36.6 | 30.8 | 36.6 | 51.2 | 56.6 |
| pooled/pooled | 20.6 | 12.1 | 22.1 | 14.5 | 45.9 | 45.7 |
| pooled/String | 18.7 | 11.6 | 21.8 | 14.7 | 41.3 | 39.9 |
| String/pooled | 26.2 | 26.2 | 29.5 | 28.4 | 45.8 | 47.7 |
| categorical/categorical | 20.4 | 13.4 | 22.4 | 16.9 | 40.2 | 46.2 |

- **The pooled path is taken:** a join on a pooled or categorical key of the longer side is twice as fast as on its strings, in the forks as upstream. The plain preprocessing maps the shorter side to the longer side's reference codes (DataAPI's `refarray`, `invrefpool`); the kernel then joins integer codes.
- **On one pooled key the forks are 1.3–1.7× upstream's steady time** (6–8 ms on 10⁶ rows). Both join the same integer codes with the same algorithm (`_innerjoin_unsorted_int`). The difference is not in reaching the pool. Likely cause, not measured: `innerrows` takes its columns `Dynamic` (a call per cell), where the other kernels open them (`Opened{Column}`, E-214).
- **On two keys, and on unpooled keys,** the forks equal upstream within 10%.
- **First joins:** both compile per key type, similar amounts (forks 5–525 ms, upstream 54–563 ms per new case).
- **The answer: no capability of its own.** A capability for both sides' pools would give the kernel what the preprocessing already gives it.

## Phase 2's starting point: the session against pandas (2026-10-29, E-233, E-234)

julia-1.13 bfca89decc, TraitWorld ca92f22, forks 115c208; `scripts/measure_session.sh 3 "py fk-patched up-patched"`, a warm-up and 2 runs; pandas 3.0.6 on the same machine; load average 0.1 before the runs. Logs and the breakdown: `../experiments/phase2-round/` (its README). Current numbers: [the evidence](../writeup/design/evidence.md) §3.

| | start | imports | steps | exit | wall |
|---|---|---|---|---|---|
| pandas | 0.010 s | 0.20 s | 0.30 s | 0.03 s | **0.54 s** |
| forks | 0.58–0.59 s | 1.86–2.00 s | 2.11–2.15 s | 0.13 s | **4.71–4.83 s** |
| upstream | 0.34–0.59 s | 1.22–1.23 s | 10.9 s | 0.09–0.12 s | **12.55–12.79 s** |

- Of the forks' steps (2.0 s with the REPL's typing hints off) 1.55 s is compilation; the rest is about pandas' 0.30 s.
- The imports: validation of the images' edges about 0.6 s, TraitWorld's member records and image hook about 0.2 s.
- An emulated cache across sessions (E-234) takes the steps to 1.1 s and the session (hints off) from 3.9–4.1 s to 3.0–3.2 s.

## W-92: the invalidated plain code, and the public layer as trait-module code (2026-10-29, E-238)

julia-1.13 bfca89decc, TraitWorld ca92f22, forks ba71341 and the branch `w92-wrapped` (0f0c518); the REPL's typing hints off; logs and the census in `../experiments/w92-forks-invalidation/` (its README), the checks in `logs/w92/`. Current numbers: [the evidence](../writeup/design/evidence.md) §3.

- Of what the session compiles again after the load, DataFrames' API code (`manipulate`, `innerjoin`, `combine`, 0.23 s) is image code rejected at load: its plain untyped calls of `Column`'s operations (`vector(::Any)`) match the methods that CSV's subtraits (`CSVColumn`, `TextColumn`) add to those functions. The rest is the compiler's code (0.14 s) and Base's methods compiled plainly beside a facts copy (0.08 s).
- The branch `w92-wrapped` puts the whole `DataFrames` module in `@trait_module` (porting 0.1a): `vcat` names its first frame; `@nospecialize` on varargs spelled `args::Vararg{T}`. The rejection is gone, but the session compiles the facts owner's copies of the display, `describe` and the `ByRow` paths:

| session without its start, 2 runs | wall | steps (compiling) | imports |
|---|---|---|---|
| main | 3.60 s | 2.08–2.10 s (1.59–1.60) | 1.39–1.40 s |
| `w92-wrapped` | 3.84–3.94 s | 2.26–2.31 s (1.78–1.80) | 1.46–1.50 s |
| main under `all` | 3.27–3.30 s | 1.89–1.90 s (1.16) | 1.26–1.29 s |

- Not adopted on main ([the note](../writeup/plans/2026-10-29-w92-forks-invalidation.md)). The branch passes `check_session.sh` (26 digests equal, 20 marks, 0 errors), D2 (`d2_pooled.jl`, output equal to `logs/d2/pooled.log`) and DataFrames' `cat`, `insertion`, `subset`, `select` test files (7,853 tests).
- `scripts/measure_session.sh` holds the lock (and `experiments/tools/jl`'s gate) before its clock starts.

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
| the joins on several key columns | `OnCol`, per tuple of key column types | `jointcodes!(lc, rc, l::Column, r::Column, order)` per pair; the codes folded into one integer key, joined by `innerrows`/`semirows` (M8) |
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
2. `scripts/check_session.sh`: "digests equal", the REPL session with 20 marks and 0 errors; its last line is the verdict, `check_session: pass`, and it exits non-zero on a failure.
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
