# Tables, DataFrames and CSV with traits

Forks of Tables 1.14.0, DataFrames 1.8.2 and CSV 1.1.0 with traits brought in where they fit. Each fork keeps upstream's name, UUID, API and test suite; `git diff upstream` is the port. They are measured as an interactive session against the unmodified upstream packages and against pandas.

## The port

- **Tables** (`Tables/src/ColumnCore.jl`, a trait module):
  - `@trait Column{T}`: `nrows`, `cell`, `emptycells`, `take`, `vector`, with `T = eltype(Self)`. Every `AbstractVector` is a member by a family.
  - `@trait PooledColumn{T}`: `nlevels`, `levelcode`, `level`; PooledArrays' and CategoricalArrays' vectors are members in the extensions (`Tables/ext/`).
  - `@trait TableSource`: `tablenames`, `tablecolumn`, `tablerows`; a `NamedTuple` of vectors is a member.
  - `tocolumn` and `byrow` (`ByRow` over one or two columns, the function a `Callable` at the cells' types).
  - Tables' duck-typed interface (`istable`, `columns`, `getcolumn`, `schema`) stays as it is.
- **DataFrames:** a DataFrame's columns are a `Vector{Column}`, each the stored vector itself. `ColumnKernels` (`DataFrames/src/other/kernels.jl`, a trait module) holds the column code of `describe`, sorting, grouping, joins and row selection, written once against `Column` and compiled per column type, never per schema. `DataFrame` and `SubDataFrame` are members of `TableSource`.
- **CSV:** `ColumnParsers` (`CSV/src/ColumnParsers.jl`, a trait module): `@trait CSVSource` (a path, an `IO`, bytes), `@trait CSVColumn{T} <: Column{T}` (the columns the reader parses into), `@trait TextColumn{T} <: Column{T}` (text columns; InlineStrings' in `CSV/ext/CSVInlineStringsExt.jl`); `CSV.File` is a member of `TableSource`.
- The top modules of DataFrames and CSV are trait modules with `bounded = false no_pirates = false`: upstream's code, compiled by facts.
- A column that does not conform is refused where the table is made (`DataFrame(...)`), by the member's check at its first use.

## How it uses the design

- No trait of the forks erases by default (no `@default_dynamic`). `tocolumn` and the kernels take their trait arguments `@specialize`: code per column type. A table's columns are kept as given, each the stored vector, in a `Vector{Column}`.
- A join erases at its door: the key columns are boxed, `Dynamic{Column{T}}` (`DataFrames/src/join/core.jl`), so a join's worker (`innerrows`, `semirows`, `jointcodes!`) is compiled once per pair of cell types, whatever the columns' types.
- A trait argument is compiled as Julia compiles it, for the value's type: a column passed as itself compiles the kernel for its type, a box once per cell type. Where the session's caller does not know a column's type, the call dispatches once and runs the code for that type (a text column's `filltext!` for `Vector{String15}`, `CSV/src/ColumnParsers.jl`).
- `byrow`'s function is a `Callable`, which erases by default: the loop is compiled once per cell type, whatever the function; the wrapper `compiled_for(f)` compiles it for the function (`Tables/src/ColumnCore.jl`). On the build the wrapper at a `Callable` argument is compiled once too: the compiler still resolves `Callable`'s default at a call (deviation C-112 of the compiler reference). Tables' tests run `byrow` with the function plain, as the wrapper and as a box (`Tables/test/runtests.jl`).
- Upstream's `Tables.ByRow(Dict)` (Tables' suite) fails: a type used as a function is no member of `Callable`, which takes a subtype of `Function` and a callable type declared a member (traits §9).

## The workload

`scripts/session.jl` is fed line by line to a real REPL; `scripts/session.py` is the same in pandas. The data come from `scripts/gendata.jl` (deterministic) into `data/`: `people.csv`, `orders.csv`, `sensors.csv`. The steps: read, show, describe, select and filter, sort, group and combine, a user function with `ByRow`, join, add a column, write; a second schema; InlineStrings' `String15`.

## Running

From the workspace root, `source env.sh` first. The scripts take Julia's path as their first argument, relative to `forks/` or absolute.

- `forks/scripts/check_session.sh $PWD/julia-next/julia env_forks`: the session's step digests in `env_forks/` must equal upstream's (`env_upstream/`), and the REPL session's marks must print. Its last line is the verdict.
- `forks/scripts/testsuites.sh $PWD/julia-next/julia "Tables CSV DataFrames" <tag>`: upstream's suites against the forks, one after another; logs to `logs/<pkg>-<tag>.log`.
- `forks/scripts/measure_session.sh [runs] [configs]`: fresh-process timings of the session, pandas (`py`), upstream and the forks. Its defaults point at other trees: set `PATCHED` (the Julia with the design), `STOCK` (plain Julia, `julia-vanilla/julia`) and `PYENV`. `scripts/summarize.py` prints min and median per step.
- The other scripts (`d*_…`, `m*_…`, `w*_…`) are the experiments recorded in `HISTORY.md`.

## Results

The current numbers, each against plain Julia or Python, are in the design repository's `writeup/design/evidence.md`. The suites' last results are in its `writeup/state.md` §3; on `julia-next` the forks' session gives upstream's digests at 26 steps.

- `scripts/check_session.sh ../julia-unified/julia env_forks`: digests equal upstream's at 26 steps, the REPL session's 20 marks print (2026-11-08, `unified` 350c5b1c59, TraitWorld bd9a721; `logs/w104e/check-session.log`).

- On `julia-next` (2026-11-18, `next` 02139b2168, TraitWorld 3e64ede): the session's digests equal upstream's at 26 steps; Tables' suite passes but for upstream's `Tables.ByRow(Dict)` (a type as a function is no `Callable`), as before this branch; DataFrames' `test/join.jl` alone, 1,465,119 pass (`experiments/implementation/w156/logs/after-digests.log`, `after-forks-tables.log`, `after-dataframes-join.log`).

Upstream's suites against the forks (dated):

| Date | Build | Tables | CSV | DataFrames | Logs |
|---|---|---|---|---|---|
| 2026-11-08 | `unified` 9dab7b6983, forks 8228f18 | pass | 6 of 330,545 fail: cell access allocates (open issue 158) | 14 fail: `ByRow(!)` over `Any` cells, the refused column not refused, `@inferred` at `tables.jl:86` | `logs/w104/` |
| 2026-11-08 | `unified` 350c5b1c59, TraitWorld bd9a721, forks this commit | pass (86 s) | the same 6 (open issue 158) | 4 fail at `tables.jl:86`, `@inferred` of `DataFrame(columns)` (open issue 158's second case, compiler C-36); `constructors.jl:456` failed on the earlier library's wording, updated after this run | `logs/w104e/` |
| 2026-11-08 | `unified` e9b9261808, TraitWorld 1f0f78e, forks this commit (CSV's reader and DataFrames' module compiled by facts, E-302, E-305) | not run | pass, 330,545 (open issue 158's six gone) | 7 fail: the 4 at `tables.jl:86`, and 3 `@inferred` widened to `Any` by facts (`sort`, `dropmissing`, `first` with `view`: a result through a call at no fact signature is what the callee declares; compiler C-36) | `logs/w104/suite-*-e30[25]-*.log` |
| 2026-11-09 | `unified` 523214899f (lowering records `f(…)::RT`), forks 27d4baa; DataFrames' `tables.jl`, `data.jl`, `dataframe.jl`, `sort.jl` only (E-315) | not run | not run | `tables.jl:86` passes; `Tables.subset` (`tables.jl:326`, reached after it) and the 3 `@inferred` see `Any`: run-time sites in facts code (open issue 157 (a)) | `../experiments/implementation/e289/logs/e315-*.log` |
| 2026-11-14 | `unified` 86deee2f98, TraitWorld baadf9f, forks d27f1db (E-373, phase 4: `@unbounded` for `@open`); the three suites in full, and `scripts/check_session.sh` | pass (78 s) | pass, 330,546 | 4 errors, each an `@inferred` that sees `Any` (`data.jl:283`, `dataframe.jl:1180`, `sort.jl:282`, `tables.jl:326`): open issue 157 (a). The session check passes: digests equal at 26 steps, 20 marks | `../experiments/implementation/w104/logs/forks-*.log` |

## The design

- The design: the design repository's `writeup/reference/` (traits, facts, compiler, lowering).
- The lessons of the ports: `writeup/intro/porting.md`.
