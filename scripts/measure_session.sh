#!/bin/bash
# Fresh-process timings of the interactive workload (plan §4.3).
#
#     scripts/measure_session.sh [runs] [configs]       # default 5 runs, configs "py up-stock up-patched"
#
# Configs: py (pandas), up-stock / up-patched (upstream CSV + DataFrames, env_upstream),
#          fk-stock / fk-patched / fk-image (the forks, env_forks; fk-image with the TraitWorld system image).
# Julia runs in a real REPL on a pseudo-terminal (`script`), fed scripts/session.jl; $LOADS (e.g.
# "OffsetArrays StatsBase Unitful") are loaded first, $LATE after the first part (before step 2_*).
# Output: one line per run, "config run start imports read ... | wall", in seconds; then
# scripts/summarize.py prints min and median per step. One Julia job at a time (flock), niced.
set -u
cd "$(dirname "$0")/.."
RUNS=${1:-5}
CONFIGS=${2:-"py up-stock up-patched"}
ROOT=/home/hellmann/Repos/julia-trait-bound
PYENV=${PYENV:-/tmp/claude-1000/pyenv}
STOCK=${STOCK:-$HOME/.julia/juliaup/julia-1.13.2+0.x64.linux.gnu/bin/julia}
PATCHED=${PATCHED:-$ROOT/julia-1.13/julia}
IMAGE=${IMAGE:-${TMPDIR:-/tmp}/systw/systw.so}
LOCK=${JULIA_LOCK:-/tmp/claude-1000/-home-hellmann-Repos-julia-trait-bound/6c8f1719-6fc1-42fb-a8dc-c45452eef443/scratchpad/julia.lock}
OUT=${TMPDIR:-/tmp}/forks_session; mkdir -p "$OUT"
export JULIA_PKG_OFFLINE=true DATA=$PWD/data LINES=40 COLUMNS=120

session() {     # the session text with the load lines inserted
    awk -v loads="${LOADS:-}" -v late="${LATE:-}" '
        /^using CSV/ && loads != "" { gsub(/ /, ", ", loads); print "using " loads; print "_m(\"loads\")" }
        /^s2 = / && late != "" { l = late; gsub(/ /, ", ", l); print "using " l; print "_m(\"late\")" }
        { print }' scripts/session.jl
}

marks() {   # "T name time" lines -> "start x | name dt | ... | exit y | wall z"
    tr -d '\r' | grep -ao 'T [0-9a-z_]* [0-9.e]*$' | awk -v s="$1" -v e="$2" '
        { n[NR] = $2; t[NR] = $3 }
        END { printf "start %.3f", t[1] - s
              for (i = 2; i <= NR; i++) printf " | %s %.3f", n[i], t[i] - t[i-1]
              printf " | exit %.3f | wall %.3f\n", e - t[NR], e - s }'
}

for c in $CONFIGS; do
    case $c in
        py) ;;
        up-stock) J=$STOCK; env=env_upstream; flags="" ;;
        up-patched) J=$PATCHED; env=env_upstream; flags="" ;;
        fk-stock) J=$STOCK; env=env_forks; flags="" ;;
        fk-patched) J=$PATCHED; env=env_forks; flags="" ;;
        fk-image) J=$PATCHED; env=env_forks; flags="-J $IMAGE" ;;
        *) echo "unknown config $c"; exit 1 ;;
    esac
    for i in $(seq "$RUNS"); do
        load=$(cut -d' ' -f1 /proc/loadavg)
        s=$(date +%s.%N)
        if [ $c = py ]; then
            flock "$LOCK" nice -n 10 "$PYENV/bin/python" scripts/session.py > "$OUT/$c.out" 2>&1
        else
            session > "$OUT/session.jl"
            flock "$LOCK" nice -n 10 script -qec "$J $flags ${JFLAGS:-} --startup-file=no -i --banner=no --project=$env" /dev/null \
                < "$OUT/session.jl" > "$OUT/$c.out" 2>&1
        fi
        e=$(date +%s.%N)
        echo "$c $i load $load | $(marks "$s" "$e" < "$OUT/$c.out")"
    done
done
