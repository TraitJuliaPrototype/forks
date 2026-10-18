#!/bin/bash
# The upstream test suites of the forks, one at a time, niced, under the shared lock:
#     scripts/testsuites.sh [julia] [pkgs] [tag]        logs to logs/<pkg>-<tag>.log
cd "$(dirname "$0")/.."
J=${1:-../julia-1.13/julia}
TAG=${3:-M6}
LOCK=${JULIA_LOCK:-/tmp/claude-1000/julia-review.lock}
export JULIA_NUM_PRECOMPILE_TASKS=4 JULIA_TW_VIEWCACHE=0 JULIA_PKG_OFFLINE=true
for p in ${2:-Tables CSV DataFrames}; do
    s=$(date +%s)
    flock "$LOCK" nice -n 19 timeout 5400 $J --startup-file=no --project=env_forks -e "using Pkg; Pkg.test(\"$p\")" > logs/$p-$TAG.log 2>&1
    echo "$p exit $? $(( $(date +%s) - s )) s"; grep -E 'Test Summary|tests passed|did not pass|Test Failed|Error During' logs/$p-$TAG.log | head -20
done
