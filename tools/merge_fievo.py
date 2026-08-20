#!/usr/bin/env python3
"""Merge parallel FI-MAP-Elites (fievo) island archives into a master.

usage: merge_fievo.py <master.json> <part1.json> [part2.json ...]

Island model: each worker loaded the CURRENT master (evals=E), evolved a chunk, and wrote
a part with evals = E + its_new. Feasible niches keep the highest-sweep design, infeasible
niches the min violation-distance; genomes (incl. blocks) ride along. Evals uses the DELTA
per worker (part.evals - E) so the shared baseline E isn't double-counted. Pure Python, no
Godot -- fast and leak-free. Master is rewritten in the fievo schema so workers can reseed
from it next round.
"""
import json
import os
import sys


def sweep(c):
    return c.get("sweep", c.get("fitness", 0.0))


def main():
    master = sys.argv[1]
    parts = sys.argv[2:]
    old_e = 0
    if os.path.exists(master):
        try:
            with open(master) as f:
                old_e = int(json.load(f).get("evals", 0))
        except (json.JSONDecodeError, OSError):
            old_e = 0
    feas, infeas, new_e = {}, {}, old_e

    def ingest(path, is_master):
        nonlocal new_e
        if not os.path.exists(path):
            return
        try:
            with open(path) as f:
                d = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"  skip {path}: {e}", file=sys.stderr)
            return
        for c in d.get("feasible", []):
            k = c.get("key")
            if k and (k not in feas or sweep(c) > sweep(feas[k])):
                feas[k] = c
        for c in d.get("infeasible", []):
            k = c.get("key")
            if k and (k not in infeas or c.get("distance", 9) < infeas[k].get("distance", 9)):
                infeas[k] = c
        if not is_master:
            new_e += int(d.get("evals", 0)) - old_e   # this worker's new evals only

    ingest(master, True)          # baseline: master's entries (no eval delta)
    for p in parts:
        ingest(p, False)

    out = {
        "evals": new_e,
        "feasible_niches": len(feas),
        "infeasible_niches": len(infeas),
        "feasible": list(feas.values()),
        "infeasible": list(infeas.values()),
    }
    with open(master, "w") as f:
        json.dump(out, f)
    print(f"merged fievo -> {master}: evals={new_e} feasible={len(feas)} infeasible={len(infeas)}")


if __name__ == "__main__":
    main()
