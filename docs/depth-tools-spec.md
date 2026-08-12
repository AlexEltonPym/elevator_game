# Depth measurement tools — phase A spec

Build an automated optimizer that plays our levels, so we can measure strategic depth
instead of guessing at it. Grounded in `docs/autodesign-research.md` (methods) and
`docs/sim-search-feasibility.md` (measured throughput/determinism).

Phase A = foundations + search + the core metrics + watchable results.
Phase B (NOT this build) = MAP-Elites/quality-diversity for strategy diversity, restricted-play
ablation, new mechanics (cargo lift, type-restricted corridors, mutex-2 gates), level generation.

## 0. Foundations (do first, verify nothing changes)

1. `main3.set_process(false)` when running headless/simulated (a flag on the game, set by the
   sim API). Today a node left in the tree double-ticks across engine frames.
2. **Route validation lifted out of the test file**: move `tests/balance.gd::_route_error`
   logic into `Route3.validate(cells, closed) -> String` ("" = OK). `commit_route` must reject
   invalid geometry (non-adjacent steps, duplicate cells, blocked cells, closed-loop head/tail
   not adjacent) instead of running nonsense. Keep the UI behaviour identical — the drag code
   already can't produce invalid strokes, so this is a safety net for programmatic callers.
   Log rejections; never crash.
3. `Levels3.LEVELS` const -> `static var` plus an `injected` slot in `get_level()` so a
   generated/parameterised level can be run without touching the table.
4. **Perf**: memoize `Route3.stop_cells()` (invalidate on route change) and give `Grid3` a
   room-set dictionary so `is_room` stops doing `String.substr` per call. Measured: 63.5 µs of
   the 84 µs/tick fixed overhead, ~4× projected on the tick loop.
   **Hard gate: this must not change results.** The balance harness fingerprints (every
   log_served/log_lost entry + car final positions) must be bit-identical before and after.
   Prove it in the report with the before/after fingerprints.

## 1. Scoring — continuous, and of THE REAL LEVEL

> **SUPERSEDED, 2026-08-12.** The original definition below the rule was: run `HORIZON = 240`
> sim-seconds in **endless** mode (win/lose disabled, spawns ramping forever) and score
> `served - 3*lost - 0.01*avg_wait`. That was a scoring-validity bug on my part, not a
> tuning choice. **It measured a game nobody plays.** Every level ends at its quota, so a
> large part of each 240 s evaluation happened in an overload regime the player never
> faces. The metric therefore punished route-sets that win the shipped level comfortably
> but degrade under an unbounded demand ramp — L4's one-way-loop thesis was the clearest
> victim — and rewarded coverage-heavy plans that survive overload but close no level
> faster. It also saturated: once a plan stopped losing anyone, its score plateaued just
> under the number of passengers spawned, so good plans were mutually indistinguishable.

Score the level the player actually plays. Run with the level's real `quota`, `max_lost`
and win/lose checks ACTIVE, and a generous `TIMEOUT = 300` sim-seconds:

- **WIN** → `score = WIN_BONUS + (TIMEOUT - time_to_quota)` — faster wins score higher.
- **LOSE or TIMEOUT** → `score = served - 3.0*lost - 0.01*avg_wait` — partial credit,
  always below any win. `lost` is the failure currency; `avg_wait` is a deliberately tiny
  tiebreak, applied on **this branch only** so it can never re-order two wins.
- `WIN_BONUS = 1000`. A non-win always has `served < quota`, so its score is bounded above
  by the largest quota in the table (90). The separation is **verified empirically, per
  level**, by `run_depth.gd --scorecheck`, not argued from the algebra.

Binary WIN/LOSE has no gradient, but this is not binary: wins are ranked by speed and
losses by partial credit, and both branches are continuous.

**Aggregation across seeds uses the LOWER median**, not the averaged one. With two branches
~1000 points apart, averaging the two middle values of an 8-seed sample would report a
route-set that wins 4 seeds at ~560 — a score no run can produce, sitting in the gap
between the branches, which every downstream metric would then treat as meaningful. An
actual order statistic keeps every reported number inside a real branch, and is the
conservative reading: a candidate counts as winning only if it wins the majority of its
seeds. Report the win count alongside the score so a 4/8 straddle is visible rather than
hidden inside an average.

**Measured gradient** (200 uniform random route-sets per level, one train seed, STEP 0.25;
`--scorecheck --n 200`). Undecodable samples are skipped, which is why the counts differ:

| level | valid samples | win | lose | win-score spread | losing-score spread | distinct losing scores | worst win − best loss |
|---|---|---|---|---|---|---|---|
| L1 Tower | 163 | 44 | 119 | 39.3 | 44.0 | 100 / 119 | 1054.2 |
| L2 Detour | 194 | 91 | 103 | 32.3 | 40.1 | 96 / 103 | 1125.8 |
| L3 Junction | 91 | 2 | 89 | 12.8 | 81.9 | 78 / 89 | 1077.9 |
| L4 Ring | 121 | 54 | 67 | 40.8 | 56.2 | 67 / 67 | 1095.2 |
| X-1 Sandbox | 73 | 24 | 49 | 71.5 | 28.3 | 48 / 49 | 1051.2 |

Read: **every level has a usable gradient on both branches.** No level is all-win (which
would make the metric a constant) and no level is all-lose. L3 is the one that comes close
— only 2 of 91 random samples win — and that is exactly the case the losing branch has to
carry: there it discriminates *best* of any level, 78 distinct scores across an 81.9-point
range (served ranges 0→82 against a quota of 90), so an optimizer on L3 has a dense,
monotone signal to climb all the way to the win boundary. Every win outranks every loss on
every level, with ≥1051 points to spare against a `WIN_BONUS` of 1000.

- `STEP` is part of the experiment spec (it changes results). Search at `STEP = 0.25`, then
  re-evaluate the top candidates at `STEP = 0.1` for reported numbers.
  **Report the rank correlation** between coarse and fine scoring on the top ~30 candidates per
  level — if it's poor, the shortcut is dishonest and we search at 0.1 instead. Say so plainly.

## 2. Seeds — the #1 pitfall

- `SEEDS_TRAIN` = 8 fixed seeds, `SEEDS_TEST` = 8 disjoint held-out seeds.
- Optimizers see ONLY train seeds; every reported number is the **median over test seeds**.
- Report `seed_fragility` = median(train score) - median(test score). A large positive gap means
  the optimizer memorised the arrival schedule and the result is not real.

## 3. Route representation (do NOT search raw polylines)

Per the research (TRNDP framing): a route gene is
`{stops: [room cells in visit order], closed: bool}`.
Decode to cells with A* between consecutive stops over passable cells, avoiding revisits;
if a leg can't be decoded, the gene is invalid (score it as -INF, don't crash). A route-set gene
is one route gene per card (cards keep their level-defined types/capacities/speeds).

Mutation operators (from the transit-network literature): add stop, delete stop, swap two stops,
move a stop between routes, replace a stop with a random room, toggle `closed`, and a
crossover that swaps one card's route between two parents.

## 4. Optimizers (these double as the ladder rungs)

- `random`: sample valid route-sets uniformly (weak rung).
- `greedy`: beam search over stop sequences, beam 8, cheap.
- `ea`: (μ+λ) evolutionary, μ=12 λ=24, seeded from BOTH random genes and hand-built primitives
  (spine lobby->top, per-cluster shuttle, ring loop, hub feeder, k-shortest-paths over the
  heaviest demand pairs). Budget-parameterised in evaluations.
- Ladder budgets: 100 / 400 / 1600 / 6400 evaluations.

## 5. Metrics (phase A subset)

Per level, all medians over TEST seeds:
- `thesis` — our hand-designed strategy's score (from `Scenarios3`).
- `naive` — the naive scenario's score.
- `random`, `greedy`, `ea@B` for each ladder budget.
- **Win/loss split per strategy** (how many of the 8 test seeds it actually wins), and the
  median time-to-quota for the ones that win. Under the §1 scoring these are the numbers
  that carry meaning; the raw score is only comparable *within* a branch, because the two
  branches are in different units (game-seconds saved vs passengers served). A `beat_thesis`
  that straddles the branch boundary must be read as "one wins, one loses", not as a margin.
- `skill_gap = ea@6400 - random@6400` — **equal budget on both sides**. Random-at-budget-B
  is best-of-B samples, which is a genuinely strong baseline, not a straw man; comparing an
  EA at 6400 against a single random draw would be dishonest. The report prints `random@B`
  next to `ea@B` at every rung.
- **EA instrumentation** — enough to tell "this level is shallow" apart from "this EA is
  broken", per level: percentage of proposed genes that fail to decode (scored -INF, no
  budget spent), percentage that were cache hits, generations actually completed at each
  budget, the best-so-far curve, population diversity over time (distinct genomes in the
  µ slots + mean pairwise Jaccard distance, so a collapse is visible), and per-operator
  effect size — for mutation, crossover and immigration: how often the child's score
  differs from its parent's at all, how often it improves, and the mean |Δscore|. An
  operator with a near-zero change rate is a broken operator; a flat ladder with healthy
  operators and healthy diversity is a shallow level.
- Because a run now ends when the level does, a budget unit is no longer a fixed amount of
  simulated time — winners are cheaper to evaluate than losers. The unit stays "one run",
  which is what keeps the rungs comparable.
- `ladder` — the score-vs-log(budget) curve, plus a step count: number of budget doublings that
  improve median score by more than the seed noise band (report the noise band too).
- `beat_thesis = ea@6400 - thesis`, and a **structural distance** between the EA's best route-set
  and ours (Jaccard distance over per-card stop sets + a note on whether loops/gates are used
  differently). A high score with LOW structural distance means we found the same idea; a high
  score with HIGH distance means the level has a strategy we didn't know about.
- `plan_fragility` — median score drop when one random stop is perturbed in the best route-set.

## 6. Deliverables

- `tools/` (new dir, separate from `tests/` which stays the fast gate):
  `sim_api.gd` (batched headless runs; never fork per candidate — 375 ms startup),
  `routegen.gd` (gene <-> cells, validation, primitives), `optimizers.gd`, `metrics.gd`,
  `run_depth.gd` (entry point), and a shard runner for 8 processes.
- One documented command to run the whole thing, and a `--quick` mode (smaller budgets, 2 seeds)
  that finishes in a couple of minutes for iteration.
- **Runner hygiene.** A shard that fails must fail loudly and cheaply:
  - the shard runner watches every child's logs and KILLS it the moment they pass a size or
    line threshold, naming the likely cause, instead of letting it write tens of megabytes;
  - the summary reports each shard's exit code **and** whether it actually wrote a fresh
    `tools/out/depth_<ID>.json` this run — "exited 0" is not the same claim as "produced a
    result", and a stale JSON from a previous run must never be counted as a success;
  - the runner exits non-zero when any shard is missing, so the report is never quietly
    generated from a partial set.
- **Resumable shards.** On this machine long-lived headless processes are terminated from
  outside at unpredictable times (30 s to 10 min; no crash record, no stderr, exit -1), which
  is fatal to a ~20-minute search. So every completed run is memoised to
  `tools/out/runcache_<ID>.json`, keyed by (level, routes, seed, step) and stamped with a
  scoring-rule version so a cache from different rules is rejected rather than trusted. The
  whole search is deterministic — seeded RNG, deterministic BFS decode, deterministic tick
  loop — so a relaunched shard REPLAYS the identical trajectory and serves everything it
  already did from disk in microseconds. `runs` still increments on a replayed run, because
  the budget means "simulations this optimizer was allowed" and a replayed run was already
  paid for, so every rung's budget accounting is identical to an uninterrupted run. The
  runner relaunches any shard that dies without a result (bounded by `-MaxAttempts`), and
  reports the attempt count. The cache is deleted once the level's JSON is written.

  This exists because of a concrete failure (2026-08-12): a headless session builds and frees
  a whole scene per simulation run, and every CanvasItem/Control entering the tree pushes a
  deferred callable onto the GLOBAL `MessageQueue`, which is drained only at the end of an
  engine frame. A level's search runs inside ONE frame, so the queue only grew — ~132 stale
  messages per run — and at ~8 k runs it hit the 32 MB cap. From then on *every* push failed,
  and each failed push calls `CallQueue::statistics()`, which prints one
  `Object was deleted while awaiting a callback.` line **per queued message**: O(queue)
  output per push, i.e. 1.5 M lines, 65 MB per shard, then a segfault, and no JSON. The fix
  is in `tools/sim_api.gd` (the HUD builds nothing headless, and the session leaves the tree
  after `_ready`, since `queue_redraw()`/`update_minimum_size()` are no-ops outside it), but
  the runner must be able to catch the next one of these without a human watching.
- `docs/depth-report.md` — GENERATED. Per-level table of the metrics above, the ladder curves,
  the coarse-vs-fine rank correlation, and a short honest prose verdict per level: is there
  headroom over the thesis, did the optimizer find something structurally new, is the level
  deep or a one-weird-trick puzzle?
- **Watchable results**: write the best discovered route-set per level to
  `scripts/v3/discovered3.gd` (same data shape as `Scenarios3`), and add a **WATCH BEST** button
  on the level-select row when one exists. The research is explicit that QD/optimizer output must
  be eyeballed, not trusted numerically — this is that eyeball.

## 7. Validation gates

- `tests/run_balance.gd` stays ALL PASS, with bit-identical fingerprints after the perf work.
- New unit checks in the balance suite (cheap only): `Route3.validate` accepts good geometry and
  rejects each bad kind; gene decode round-trips; injected levels run.
- The depth tool runs end-to-end on all 5 levels and produces the report.
- Report the wall-clock of a full run and of `--quick`.

## 8. Honesty requirements (call these out in the final report)

- If the optimizer beats a hand-designed thesis, say so plainly with numbers — that is a useful
  finding about the level, not a failure.
- If a level turns out shallow (tiny skill gap, flat ladder), say that too.
- If coarse-step search proves unfaithful, or seed_fragility is large, report it rather than
  papering over it — a metric we can't trust is worse than no metric.
