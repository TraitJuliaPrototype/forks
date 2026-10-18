#!/bin/bash
# Correctness check of the interactive workload (no timing):
#   1. scripts/session_check.jl in env_forks and in env_upstream: the step digests must be equal;
#   2. scripts/session.jl fed line by line to a REPL over the forks: no step may raise.
#     scripts/check_session.sh [julia]          (one Julia job at a time, under the shared lock)
set -u
cd "$(dirname "$0")/.."
J=${1:-../julia-1.13/julia}
LOCK=${JULIA_LOCK:-/tmp/claude-1000/julia-review.lock}
OUT=${TMPDIR:-/tmp}/forks_check; mkdir -p "$OUT"
export DATA=$PWD/data JULIA_PKG_OFFLINE=true JULIA_NUM_PRECOMPILE_TASKS=4 JULIA_TW_VIEWCACHE=0 LINES=40 COLUMNS=120
run() { flock "$LOCK" nice -n 19 timeout 1800 "$J" --startup-file=no "$@"; }
run --project=env_forks scripts/session_check.jl > "$OUT/forks.txt" 2> "$OUT/forks.err"; echo "forks exit $?"
run --project=env_upstream scripts/session_check.jl > "$OUT/upstream.txt" 2> "$OUT/upstream.err"; echo "upstream exit $?"
if diff "$OUT/upstream.txt" "$OUT/forks.txt" > "$OUT/digest.diff"; then
    echo "digests equal: $(wc -l < "$OUT/forks.txt") steps"
else
    echo "digests differ:"; cat "$OUT/digest.diff"
fi
flock "$LOCK" nice -n 19 timeout 1800 script -qec "$J -i --banner=no --startup-file=no --project=env_forks" /dev/null \
    < scripts/session.jl > "$OUT/repl.txt" 2>&1
echo "repl exit $?; marks $(grep -ac '^T ' "$OUT/repl.txt"); errors $(grep -ac 'ERROR' "$OUT/repl.txt")"
