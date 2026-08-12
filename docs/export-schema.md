# Training-data export schema

The contract between the deterministic labeler (`tools/sim_api.gd`) and a future
surrogate model (`docs/surrogate-design.md` §6). The exporter logs every VALID
simulation the depth tools run as **one JSONL row per `(level, route_set, seed)`
evaluation** — a self-contained INPUT plus the full outcome LABEL — so the ML
side can build a training set without ever re-running the sim, and can re-derive
any label if it wants to.

Implemented in `tools/export.gd`; round-trip checker in `tools/export_verify.gd`.

## Off by default

The exporter does **nothing** unless a caller explicitly constructs an
`Export` and assigns it to `SimApi.exporter`. A normal search, the balance suite
(`tests/balance.gd`) and the determinism fingerprint (`tools/fingerprint.gd`)
never build one, so with export off the simulation is byte-identical
(`FINGERPRINT-ALL 2472496005 len=33980`, balance `146 ALL PASS`). "Off" means the
code path is absent, not merely skipped.

## How to enable it

**Single process (`tools/run_depth.gd`)** — add `--export` (writes under
`tools/out/export/`) or `--export <dir>`:

```
godot --headless --path . --script tools/run_depth.gd -- --scorecheck --levels L3 --n 200 --export
godot --headless --path . --script tools/run_depth.gd -- --levels L3 --export      # a full search
```

Wired into the search path (`_run_one`) and the score-audit path (`_scorecheck`,
which samples the uniform-random route_sets §4.1 calls for). Uniform-random,
EA-elite and greedy candidates all flow through `SimApi.run`, so a normal search
dumps the whole labeled mixture for free.

**Parallel pool (`tools/pool.ps1` → `tools/pool_worker.gd`)** — add `-Export`:

```
powershell -File tools/pool.ps1 -Workers 8 -Level L3 -N 100000 -Export
```

Each worker writes its own shard under `<WorkDir>/export/`.

Outputs land under `tools/out/` (gitignored) by default.

## Concurrency & durability

One **shard file per process**: `shard_<tag>_<pid>.jsonl`. The OS process id
makes the name unique across concurrent workers *and* across restarts, so two
handles never alias and there is no cross-process interleaving to corrupt a row.
Within a process the writes are sequential and each row is one whole line
(`JSON.stringify` emits no newline; newlines inside strings are escaped) flushed
immediately — a kill mid-batch truncates at a row boundary, never inside a row.
To assemble a dataset, concatenate every shard; row count equals evaluation
count (invalid geometry and cache-replayed runs are not exported — see below).

## What is NOT exported

- **Invalid route_sets** (illegal geometry): `valid == false`, no label, skipped.
- **Cache-replayed runs**: when `SimApi` serves a run from its resume cache, the
  row is not re-emitted (it was emitted the first time it was truly simulated).
  The pool runs with the cache off, so a pool batch emits exactly one row per
  candidate.

## Row format

One JSON object per line. Annotated example (an L3 losing sample, trimmed):

```jsonc
{
  // ---- keys / provenance ----
  "schema_version": 1,                 // bump on any row-shape change; reject mismatches
  "level_id": "L3",
  "level_hash": "8f3c…",               // sha1 of rows+cards+quota/max_lost+mix+patience+spawn+demand
  "route_set_key": "0|0|0.000|O1,3;…", // SimApi._key of the decoded routes; dedupe / group-by
  "seed": 500002,                      // the spawn RNG seed (the only per-row nuisance input)
  "step": 0.25,                        // sim step (STEP_COARSE search / STEP_FINE reporting)
  "score_rule": "t420_w1000_l3.0_a0.010_v3", // SimApi._cache_version(); reject stale scoring

  // ---- INPUT: level (self-contained; enough to REBUILD and re-run) ----
  "level": {
    "id": "L3", "name": "Junction", "thesis": "…",
    "rows": ["###R###","#GGGGG#", …],  // maze, TOP row first (Grid3 legend)
    "quota": 116, "max_lost": 5,
    "spawn": {"interval_start":0.88,"interval_end":0.59,"ramp":85,"burst_min":4,"burst_max":6,"gap":0.45},
    "mix": {"visitor":0.43,"patient":0.42,"exec":0.15},
    "mix_order": ["visitor","patient","exec"],  // load-bearing: _pick_type rolls mix in THIS order
    "cards": [ {"name":"FEEDER A","type":"standard","width":2,"cap":6,"speed":260,"accel":300}, … ],
    "passenger_types": {"visitor":{"width":1,"patience":72}, …},  // widths + effective patience
    "rooms": [[3,9],[1,3],[2,3],[3,3],[4,3],[5,3],[3,0]],         // node id = index into this list
    "room_demand": [ {"cell":[3,9],"in":0.20,"out":0.11}, … ],   // per-room in/out weight
    "demand_pairs": [ [from_idx,to_idx,weight], … ],             // edges over `rooms` (for a GNN)
    "exec_origins": [[1,3],[5,3]], "exec_dests": [[3,9]],
    "groups": {"arms":[[1,3],[5,3]], …}, "trips": [{"w":0.24,"from":"lobby","to":"arms"}, …],
    "type_rooms": {}, "patience": {"visitor":72,"patient":64,"exec":44}
  },

  // ---- INPUT: route_set (the "set of loadouts" §2.2.D — trivial to tensorize) ----
  "routes": [
    { "card":0, "type":"standard","width":2,"cap":6,"speed":260,"accel":300,
      "stops":[[1,3],[3,3],[3,0]],              // room cells the polyline visits, in travel order
      "closed":false, "home":null,
      "cells":[[1,3],[2,3],[3,3], … ,[3,0]] },  // decoded polyline — re-run consumes THIS
    { "card":1, … }, { "card":2, … }
  ],

  // ---- LABEL: the full outcome vector (SimApi._harvest) ----
  "label": {
    "result":"lose", "score":33.71, "t_end":125.0,
    "served":49, "lost":5,
    "avg_wait":29.0, "p90_wait":57.75, "avg_transfers":0.47,
    "waiting_end":54, "no_path_end":0,
    "gate_wait":5.47, "gate_transits":16,
    "served_by_type":{"exec":12,"patient":19,"visitor":18},  // NEW (added to _harvest)
    "lost_by_type":{"exec":1,"patient":4}                    // NEW
  },

  // ---- META: provenance to filter stale rows ----
  "meta": {
    "level_index":2, "injected":false,   // injected=true -> a parameterised level, not LEVELS[index]
    "accel_model":"width", "restrict":"", // the two sim-global ablation knobs in force
    "timeout":420, "win_bonus":1000, "lost_weight":3, "wait_weight":0.01,
    "seeds_train":[1101, …], "seeds_test":[2903, …],
    "run_tag":"scorecheck", "shard":"scorecheck", "pid":12564,
    "exported_at":"2026-08-13T09:10:12"
  }
}
```

### Field notes

- **`cards` / `routes[*]` features are resolved and stored explicitly** (width,
  cap, speed, accel), through the same `Levels3` accessors `Car3.setup` uses.
  Because they are explicit, rebuilding a card from the row makes those accessors
  return the identical numbers *regardless of the `accel_model` / `restrict`
  globals at rebuild time* — a row re-runs to the same label without knowing the
  config it was captured under. The globals are still in `meta` so a row captured
  under a non-default ablation is filterable.
- **`mix_order`** exists because `main3._pick_type()` rolls the type mix in dict
  iteration order, and `JSON.stringify` alphabetizes keys — dropping the order
  would change the spawn stream. It is the one place dict order is load-bearing;
  everything else order-sensitive (routes, trips, group cells, exec rooms) is
  already an array. The round-trip check fails without it.
- **`cells`** is the decoded polyline; **`stops`** is its room-cell subsequence.
  A re-run consumes `cells` + `closed` + `home`; `stops` + `rooms` is the
  set-of-sequences view for the encoder. Both are emitted so the representation
  choice stays open (§6.4).
- **Aggregation** to a per-`(level, route_set)` example (win_fraction + mean
  outcome over the 8 train seeds) is a group-by on `route_set_key` at train time.
  Rows are kept per-seed on disk so the seed-level distribution stays available.

## Versioning policy

Three independent version stamps, coarse to fine — a consumer should **reject
any row whose stamps do not match the experiment it is assembling**:

1. **`schema_version`** (integer) — the row *shape*. Bump when a field is added,
   removed, or retyped. The "can I still parse this" gate.
2. **`score_rule`** (`SimApi._cache_version()`) — what a run *means*: timeout,
   win bonus, lost/wait weights, scoring version. A row with a different
   `score_rule` was labeled under different scoring and must not be mixed in.
3. **`meta.accel_model` / `meta.restrict`** — the two sim-global ablation knobs.
   Rows captured under a non-default model describe a different physics.

`level_hash` is not a version but a **grouping key**: two rows share it iff their
levels are simulation-identical, so the ML side can pool seeds/route_sets per
level even as `level_index` shifts under table edits. This is why levels are
stored self-contained rather than by index — early data is expected to be
discarded as the game changes, and versioning is what makes that a filter rather
than a guess (`docs/surrogate-design.md` §0, §4.3).

## Round-trip guarantee (how it is checked)

`tools/export_verify.gd` reads exported rows, rebuilds the level Dictionary and
the routes **purely from each row**, injects the rebuilt level into the
unmodified `SimApi` (so `LEVELS` is never consulted), re-runs, and asserts the
outcome matches the stored label bit-for-bit (`result`, `served`, `lost`,
`score`, `t_end`):

```
godot --headless --path . --script tools/export_verify.gd -- --dir tools/out/export --n 12
```

A passing row proves the schema is self-contained: the level spec + route_set it
carries are sufficient to reproduce the exact evaluation and label.
