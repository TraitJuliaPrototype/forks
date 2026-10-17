#!/bin/bash
# The upstream test suites of the forks, one at a time, niced:  scripts/testsuites.sh [julia] [pkgs]
cd "$(dirname "$0")/.."
J=${1:-../julia-1.13/julia}
LOG=${TMPDIR:-/tmp}/forks_tests; mkdir -p $LOG
for p in ${2:-Tables CSV DataFrames}; do
    s=$(date +%s)
    JULIA_NUM_PRECOMPILE_TASKS=4 nice -n 19 $J --startup-file=no --project=env_forks -e "using Pkg; Pkg.test(\"$p\")" > $LOG/$p.log 2>&1
    echo "$p exit $? $(( $(date +%s) - s )) s"; tail -5 $LOG/$p.log | grep -E 'Test Summary|tests passed|Testing .* tests' 
done
