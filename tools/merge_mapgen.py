#!/usr/bin/env python3
"""Merge parallel mapgen worker archives into a master (best-per-niche).

usage: merge_mapgen.py <master.json> <partial1.json> [partial2.json ...]

Each file is a mapgen archive: {"evals", "archive":[feasible cands], "infeasible":[...]}.
Feasible niches (keyed by "key") keep the highest-sweep design; infeasible niches keep the
first seen; evals sum. The master is rewritten in the same schema so it stays mapgen- and
report-loadable and can seed further rounds. No Godot involved -- pure JSON, fast, robust.
"""
import json
import os
import sys


def _sweep(c):
    return c.get("sweep", c.get("fitness", 0.0))


def ingest(d, feas, infeas, counters):
    counters["evals"] += int(d.get("evals", 0))
    for c in d.get("archive", []):
        k = c.get("key")
        if k is None:
            continue
        if k not in feas or _sweep(c) > _sweep(feas[k]):
            feas[k] = c
    for c in d.get("infeasible", []):
        k = c.get("key")
        if k is None:
            continue
        if k not in infeas:
            infeas[k] = c


def main():
    master = sys.argv[1]
    parts = sys.argv[2:]
    feas, infeas, counters = {}, {}, {"evals": 0}
    # existing master first (carries cumulative evals + prior rounds), then the new partials
    for path in [master] + parts:
        if os.path.exists(path):
            try:
                with open(path) as f:
                    ingest(json.load(f), feas, infeas, counters)
            except (json.JSONDecodeError, OSError) as e:
                print(f"  skip {path}: {e}", file=sys.stderr)
    sigs = {}
    for c in feas.values():
        sigs[c.get("sig", "")] = sigs.get(c.get("sig", ""), 0) + 1
    out = {
        "evals": counters["evals"],
        "feasible_niches": len(feas),
        "infeasible_niches": len(infeas),
        "distinct_types": len(sigs),
        "archive": list(feas.values()),
        "infeasible": list(infeas.values()),
    }
    with open(master, "w") as f:
        json.dump(out, f)
    print(f"merged -> {master}: evals={counters['evals']} feasible={len(feas)} "
          f"infeasible={len(infeas)} distinct_types={len(sigs)}")


if __name__ == "__main__":
    main()
