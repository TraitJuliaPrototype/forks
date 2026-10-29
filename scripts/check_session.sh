#!/bin/bash
# Correctness check of the interactive workload (no timing):
#   1. scripts/session_check.jl in <env> and in env_upstream: the step digests must be equal;
#   2. scripts/session.jl fed line by line to a REPL over <env>: every mark `_m("…")` prints, no step may raise.
# The last line is the verdict, "check_session: pass" or "check_session: FAIL (<reasons>)"; the exit status is 0
# only on a pass.
#     scripts/check_session.sh [julia] [env]    (env: env_forks (default) or env_wrapped; one Julia job at a time)
set -u
cd "$(dirname "$0")/.."
J=${1:-../julia-1.13/julia}
E=${2:-env_forks}
LOCK=${JULIA_LOCK:-/tmp/claude-1000/julia-review.lock}
OUT=${TMPDIR:-/tmp}/forks_check; mkdir -p "$OUT"
export DATA=$PWD/data JULIA_PKG_OFFLINE=true JULIA_NUM_PRECOMPILE_TASKS=4 JULIA_TW_VIEWCACHE=0 LINES=40 COLUMNS=120
run() { flock "$LOCK" nice -n 19 timeout 1800 "$J" --startup-file=no "$@"; }
fail=()
run --project=$E scripts/session_check.jl > "$OUT/forks.txt" 2> "$OUT/forks.err"; rc=$?; echo "$E exit $rc"
[ $rc = 0 ] || fail+=("session_check.jl in $E exited $rc")
run --project=env_upstream scripts/session_check.jl > "$OUT/upstream.txt" 2> "$OUT/upstream.err"; rc=$?; echo "upstream exit $rc"
[ $rc = 0 ] || fail+=("session_check.jl in env_upstream exited $rc")
if [ ! -s "$OUT/forks.txt" ]; then
    echo "no digests from $E"; fail+=("no digests")
elif diff "$OUT/upstream.txt" "$OUT/forks.txt" > "$OUT/digest.diff"; then
    echo "digests equal: $(wc -l < "$OUT/forks.txt") steps"
else
    echo "digests differ:"; cat "$OUT/digest.diff"; fail+=("digests differ")
fi
flock "$LOCK" nice -n 19 timeout 1800 script -qec "$J -i --banner=no --startup-file=no --project=$E" /dev/null \
    < scripts/session.jl > "$OUT/repl.txt" 2>&1
rc=$?
clean() { tr -d '\r' < "$OUT/repl.txt" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'; }   # a terminal transcript: carriage returns, escapes
# what the REPL session must print: one `T <step> <time>` line per mark `_m("…")` in scripts/session.jl,
# and one ERROR per line marked `# ERROR expected` (none today)
want=$(grep -c '^_m("' scripts/session.jl); want_err=$(grep -c '# ERROR expected$' scripts/session.jl)
marks=$(clean | grep -ac '^T '); errs=$(clean | grep -ac '^ERROR')
echo "repl exit $rc; marks $marks of $want; errors $errs, $want_err expected (transcript: $OUT/repl.txt)"
[ $rc = 0 ] || fail+=("the REPL exited $rc")
[ "$marks" = "$want" ] || fail+=("marks $marks of $want")
[ "$errs" -le "$want_err" ] || fail+=("errors $errs, $want_err expected")
if [ ${#fail[@]} = 0 ]; then
    echo "check_session: pass"
else
    r=$(printf '; %s' "${fail[@]}"); echo "check_session: FAIL (${r:2})"; exit 1
fi
