"""Min and median per step of measure_session.sh output (stdin). Runs whose 1-minute load exceeds
MAXLOAD (default 4) are dropped and counted."""
import os, sys, statistics as st
from collections import defaultdict
maxload = float(os.environ.get("MAXLOAD", "4"))
runs = defaultdict(list); dropped = defaultdict(int); order = {}
for line in sys.stdin:
    if " load " not in line: continue
    parts = [p.strip() for p in line.split("|")]
    c, _, _, load = parts[0].split()
    if float(load) > maxload: dropped[c] += 1; continue
    d = {}
    for p in parts[1:]:
        k, v = p.rsplit(" ", 1); d[k] = float(v); order.setdefault(c, []); 
        if k not in order[c]: order[c].append(k)
    runs[c].append(d)
for c, rs in runs.items():
    print(f"== {c}: {len(rs)} runs ({dropped[c]} dropped for load)")
    for k in order[c]:
        xs = [r[k] for r in rs if k in r]
        print(f"  {k:20s} min {min(xs):7.3f}  median {st.median(xs):7.3f}")
    xs = [r["wall"] - r.get("imports", 0) - r.get("start", 0) - r.get("exit", 0) - r.get("loads", 0) for r in rs]
    print(f"  {'session (no imports)':20s} min {min(xs):7.3f}  median {st.median(xs):7.3f}")
