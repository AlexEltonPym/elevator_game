# v3 sim: feasibility for large-scale automated search

Can we run thousands of simulated games headless to score generated level
designs? **Yes.** The sim is bit-for-bit deterministic, leak-free across runs,
and already reaches ~150 000 full games/hour on this machine with 8 processes.
The work needed is plumbing (inject a level, lift the route validator, kill the
frame coupling) plus two cheap hot-path fixes, not a rewrite.

Everything below is **measured** on:
Windows 10, Intel i7-11700K (8 physical / 16 logical cores),
Godot v4.2.2.stable.mono, `--headless --path . --script <bench>.gd`.
Benchmarks were throwaway scripts in a scratchpad; no repo file was modified.

---

## Summary of measured numbers

| Metric | Measured |
| --- | --- |
| One full scenario, end to end, `STEP = 0.1` | **37 – 199 ms** wall (median ~113 ms) |
| … `load()` (PackedScene, cached after first) | 0.7 – 1.0 ms |
| … `instantiate()` | 0.04 – 0.11 ms |
| … `add_child()` (`_ready`: grid + 3 cars + HUD build) | **3.4 – 6.3 ms** |
| … `start_session()` + 3 × `commit_route()` | 2.8 – 4.3 ms |
| … **ticking loop** (`advance(0.1)` to WIN/LOSE) | **28 – 214 ms** (dominant) |
| … `remove_child()` + `free()` | 0.47 – 0.86 ms |
| Same run with a 7-line stub HUD, scene built in code | build **0.25 ms** vs 5.2 ms; **identical results** |
| Sim throughput, 1 thread, ticking only, `STEP = 0.1` | **759 (L4) – 1 690 (L1) sim-s per real-s** |
| Sim throughput, 1 process, whole runs incl. setup/free | **7.6 – 8.4 runs/s ≈ 1 050 sim-s/real-s** |
| Sim throughput, 8 processes | **40.8 runs/s ≈ 5 600 sim-s/real-s ≈ 147 000 games/hour** |
| Sim throughput, 16 processes | 43.9 runs/s ≈ 6 000 sim-s/real-s |
| Max observed (`STEP = 1.0`, 1 thread, ticking only) | **6 826 sim-s/real-s** (L1) — but results change, see §1 |
| Godot process startup (`--headless --quit`) | **375 ms** — batch in-process, don't fork per run |
| Boot → first `_process` of the harness script | ~7 ms |
| Determinism (same seed + same STEP) | **bit-identical**, 8/8 repeats, same-frame, cross-process, after 300 runs, interleaved with other levels |
| Memory over 300 runs | flat: **18.54 MB static, 1300 objects, 1 live node** — no growth |
| `Grid3.is_room()` | **0.68 – 0.73 µs/call** (a `String.substr` allocation per call) |
| `Route3.stop_cells()` on a 24-cell route | **19.7 – 20.2 µs/call** |
| `Car3.running()` × 3 cars (once per game tick) | **63.5 µs/tick = 76 % of the 84 µs/tick fixed overhead** |
| `Pathfind3.find_path()`, 3 × 10-stop loops | **736 µs/call** |
| Dead (`queue_free`d, unflushed) passenger nodes at end of an L4 run | **79 %** of the per-tick passenger loop |

Headline: **1 000 candidate designs ≈ 25 s** on 8 processes today, without any
optimisation.

---

## 1. Speed

`STEP` is `tests/balance.gd:26` — `const STEP := 0.1` game-seconds, with
`TIMEOUT := 900.0` game-seconds. The harness drives `main3.advance(STEP)` in a
plain `while` loop; nothing else advances the clock.

### Per-scenario breakdown (`STEP = 0.1`, warm process)

| scenario | result | served/lost | sim s | ticks | ready | commit | **tick** | free | total | sim-s/real-s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L1_naive | LOSE | 23 / 5 | 134.3 | 1343 | 3.74 | 2.96 | **106.2** | 0.49 | 114.3 ms | 1265 |
| L1_intended | WIN | 45 / 0 | 175.2 | 1752 | 3.39 | 3.17 | **104.4** | 0.58 | 112.4 ms | 1678 |
| L2_naive | LOSE | 24 / 6 | 77.9 | 779 | 5.15 | 3.12 | **52.0** | 0.47 | 61.6 ms | 1500 |
| L2_intended | WIN | 51 / 0 | 113.8 | 1138 | 6.26 | 4.01 | **74.3** | 0.86 | 86.3 ms | 1531 |
| L3_naive | LOSE | 84 / 6 | 143.9 | 1439 | 4.01 | 2.98 | **104.9** | 0.75 | 113.6 ms | 1372 |
| L3_intended | WIN | 91 / 1 | 145.5 | 1455 | 4.04 | 3.44 | **91.5** | 0.74 | 100.6 ms | 1590 |
| L4_naive | LOSE | 28 / 7 | 115.8 | 1158 | 6.07 | 4.30 | **118.0** | 0.59 | 129.8 ms | 981 |
| L4_intended | WIN | 60 / 0 | 144.5 | 1445 | 3.51 | 3.21 | **190.3** | 0.65 | 198.6 ms | 759 |
| X1_smoke | WIN | 30 / 0 | 185.9 | 1859 | 3.42 | 3.15 | **127.9** | 0.47 | 135.7 ms | 1454 |

Scene instantiation is **~4 % of a run** (4 ms ready + 0.8 ms load + 0.05 ms
instantiate + 0.6 ms free ≈ 5.5 ms out of ~113 ms). Ticking is ~95 %. So
optimising scene setup barely matters; optimising the tick loop matters a lot.

`L4_intended` is the outlier (190 ms) because it runs **three closed 24-cell
loops** and `Car3.running()` rebuilds `Route3.stop_cells()` for each of them on
every tick — see §"hot paths".

### Wall-clock vs STEP — strongly sublinear

| STEP | L3_intended ticks / tick-ms / served | L1_intended ticks / tick-ms / served |
| --- | --- | --- |
| 0.05 | 2808 / 151.5 / **90** | 3426 / 183.9 / 45 |
| 0.10 | 1455 / 95.6 / **91** | 1752 / 103.7 / 45 |
| 0.20 | 731 / 59.1 / **91** | 910 / 65.5 / 45 |
| 0.50 | 292 / 42.1 / **95** | 376 / 40.2 / 45 |
| 1.00 | 185 / 35.7 / **91** | 194 / 28.4 / 45 |

A **20× coarser step buys only 4.2× (L3) / 6.5× (L1)**. Reason: `Car3._move_tick`
consumes `dt` in an inner `while rem > 0` loop, so movement/door work is roughly
invariant in `dt`; and `Pathfind3.find_path` is event-driven (spawn / alight /
commit), not per-tick. Only the fixed per-tick overhead (`advance` bookkeeping +
`running()` + the passenger loop) scales down.

**Results change with STEP** (L3 served 90 / 91 / 91 / 95 / 91). `STEP` is
therefore part of the experiment definition, exactly like the seed — a search
must pin it. `STEP = 0.1` is the value every existing balance assertion is tuned
against; `0.2` looks like a safe 1.6× speedup for cheap exploration with a
`0.1` re-score of finalists.

### Max throughput

* 1 thread, ticking only, `STEP = 0.1`: **1 690 sim-s/real-s** (L1_intended).
* 1 thread, ticking only, `STEP = 1.0`: **6 826 sim-s/real-s** (L1_intended).
* 1 process, whole runs: **~1 050 sim-s/real-s**.
* 8 processes, whole runs: **~5 600 sim-s/real-s**.
* 16 processes: **~6 000 sim-s/real-s**.

---

## 2. Determinism — verdict: **bit-for-bit reproducible**

Fingerprint used: final state + served + lost + sim time + `gate_wait_total()` +
`gate_transit_total()` + **every** `log_served` and `log_lost` entry
(type, origin, dest, wait to 9 dp, rides) + **every car's final
`car_state`, `idx`, `seg_t`, `dir` and float `position`**. 3 515 characters for
`L3_intended`.

| test | result |
| --- | --- |
| Same scenario 8× in a row, one per engine frame | all 8 hashes `3022975494` — **identical** |
| Same scenario 8× **inside one engine frame** (no `queue_free` flush) | identical to the one-per-frame hash |
| A, B, A, C, A, D, A, E, A interleaving (4 different levels between) | every A run identical |
| Re-run after a 300-run mixed batch | identical |
| Two separate OS processes | all 5 level hashes identical |

### Randomness inventory — all deterministic

* `main3.rng` is the single `RandomNumberGenerator`. `_ready` calls
  `rng.randomize()` for normal play; the harness overwrites `rng.seed`
  **after** `add_child`, which fully resets the stream. Consumers:
  `_pick_type`, `_pick_room`, `_spawn_tick` (`randi_range`), `_spawn_random`
  (`randf`), and `Passenger3.salt = rng.randf()` at spawn.
* `Pathfind3._hash01` uses `sin()/floor()` on `(salt, car_index)` — pure.
* Dictionary iteration (`game.waiting`, `gates`, Dijkstra's `best`/`edges`) is
  Godot's insertion order, and the insertion order is fixed
  (`Grid3.rooms()` scans bottom-up/left-right, gate groups are flood-filled in
  the same scan order). No hash-order dependence observed.
* `passengers_node.get_children()` returns add-order.
* Float accumulation is identical run to run because the `dt` sequence is
  identical; car `position` floats matched to 9 dp across processes.
* `Time.get_ticks_msec()` appears only in `Grid3._draw_stroke_preview`
  (a pulsing cursor) — visuals, never read by logic.
* `Car3.vis_t` / `vanish_timer` and `Passenger3.vis_t` advance in `_process`
  and are visual-only.

### `advance(dt)` decoupling — one real hazard

`advance(dt)` itself is fully decoupled: it takes `dt` as an argument and no
node `_process` feeds logic. **But `main3._process` is left enabled** and calls
`advance(delta * time_scale)` whenever `state == PLAYING`. Measured: a game node
left in the tree while the harness ticks it manually gained **+0.047 game-s
after one engine frame** and **+0.172 game-s after three**.

`tests/run_balance.gd` avoids this by completing each scenario inside a single
`SceneTree._process` call, so the node's own `_process` never runs. **Any search
harness that lets a run span engine frames (or `await`s anything) will
silently double-tick.** Fix is one line: `game.set_process(false)` right after
`add_child`, or a `headless` flag main3 checks.

---

## 3. Batching in one process — works, no leaks, no growth

Pattern `instantiate → add_child → seed → start_session → commit_route ×N →
advance loop → remove_child → free` repeats cleanly.

* **A/B/A test**: `L3_intended` run interleaved with `L1_naive`, `L4_intended`,
  `X1_smoke`, `L2_naive` — every `L3_intended` run reproduced its first
  fingerprint exactly.
* **Sustained rate**: 300 mixed runs at **8.0 – 8.4 runs/s**, no decay
  (12.58 s / 11.87 s / 11.92 s per 100).
* **Memory**: static 18.41 → 18.54 MB after the first batch, then *flat*.
  `Performance.OBJECT_COUNT` constant at 1300, `OBJECT_NODE_COUNT` back to 1
  after every run. `game.free()` is immediate and recursive, so `queue_free`d
  passengers still parented under `Passengers` are reaped with it.

### Global state that must be managed

| Where | What | Reset by |
| --- | --- | --- |
| `Levels3.current` (`static var`) | which level `main3._ready` loads | harness must set it **before** `instantiate()` |
| `Levels3.watch_strategy` (`static var`) | if non-`""`, `_ready` **overwrites `rng.seed`** with `Scenarios3.SEEDS[level.id]` and auto-commits the scenario routes | harness must set it to `""` |
| `Grid3.maze_rows / ROWS / COLS / ORIGIN` (statics) | current maze + geometry | `Grid3.load_level()`, called by `main3._ready` |
| `Grid3._rooms_cache`, `_gates_dirty` | room list + gate-group cache | cleared by `Grid3.load_level()` |
| `Grid3._gate_groups`, `_gate_group_of` | corridor mutex groups | rebuilt lazily via `_gates_dirty` |
| `Scenarios3`, `Pathfind3`, `Route3` | fully stateless / per-instance | n/a |

There are **no autoloads** (`project.godot` has no `[autoload]` section); the
"globals" are `class_name` script classes with `static` members.

**Consequence for threads:** because `Grid3`'s maze *is* static, two sims of
different levels cannot run concurrently in one process. Sequential batching is
safe (every `_ready` reloads the level). Parallelism must be *process*-level
until `Grid3` state becomes per-instance.

Caveat: validating a route against `Grid3.passable()` *before* the scene is
instantiated reads the **previous** level's maze. `tests/balance.gd` gets this
right by validating after `add_child`; a search harness must do the same (or
call `Grid3.load_level(rows)` itself first).

---

## 4. Parallelism across processes

Same fixed 120-run workload per process, launched simultaneously:

| processes | wall | total runs | aggregate runs/s | speed-up | per-process runs/s |
| --- | --- | --- | --- | --- | --- |
| 1 | 15.70 s | 120 | 7.64 | 1.00× | 7.84 |
| 2 | 15.82 s | 240 | 15.17 | **1.99×** | 7.82 |
| 4 | 17.90 s | 480 | 26.81 | **3.51×** | 6.98 |
| 8 | 23.54 s | 960 | 40.78 | **5.34×** | 5.28 |
| 16 | 43.70 s | 1920 | 43.93 | 5.75× | 3.31 |

* **No licensing, port or file-lock issues.** 16 concurrent headless mono
  processes all ran to completion against the same project directory. Godot
  headless opens no window, binds no port, and only reads `res://`
  (the `.godot/` import cache is read-only once warm).
* Sweet spot is **8 processes** (= physical core count): 5.34× for 8× the
  processes, and per-run latency only degrades 1.5×. 16 adds 8 % throughput for
  2.4× worse latency — hyper-threads don't help this workload.
* Process startup is **375 ms**, ~3× the cost of one run. Each worker must
  therefore be a *long-lived* process fed many jobs (stdin/JSON, or a job-range
  argument), never one process per candidate.

---

## 5. API surface for a search harness

### Minimal programmatic path today

```gdscript
# 1. statics — MUST be set before instantiate()
Levels3.current = Levels3.index_of("L3")
Levels3.watch_strategy = ""          # non-"" reseeds the RNG and commits scenario routes

# 2. scene
var game = load("res://scenes/v3_main.tscn").instantiate()
tree.root.add_child(game)            # _ready: Grid3.load_level, gates, waiting, 3 Car3, HUD

# 3. run config — AFTER add_child (_ready calls rng.randomize())
game.rng.seed  = 303
game.auto_spawn = true               # false = only hand-placed spawn_passenger()
game.set_process(false)              # NOT done today; see §2 hazard

# 4. routes: plain Array[Vector2i], no UI involved
for i in routes.size():
    game.commit_route(i, cells_i, closed_i)
game.start_run()

# 5. tick
var t := 0.0
while game.state == game.State.PLAYING and t < TIMEOUT:
    game.advance(STEP); t += STEP

# 6. read stats, then
tree.root.remove_child(game); game.free()
```

**Updated for v4 phase 1** (this doc records the v3.5 measurement; the order
above has since inverted). Routes are now committed in the PLAN phase and
`start_run()` is called after — which is what the player does too, so the
optimizer and the player solve the same problem. `commit_route()` REFUSES once
a run has started; the recall → 3 s redeploy countdown (`Car3.apply_route`) is
reachable only through `commit_route_mid_run()`. Timings are unaffected: the
scenario fingerprints are byte-identical across the change.

### Stats available on the finished object

| Field | Type |
| --- | --- |
| `game.state` | `BRIEFING / PLAN / PLAYING / WIN / LOSE` |
| `game.served`, `game.lost`, `game.elapsed` | int, int, float |
| `game.QUOTA`, `game.MAX_LOST` | int (from the level dict) |
| `game.log_served` | `[{type, origin: Vector2i, dest: Vector2i, wait: float, rides: int}]` |
| `game.log_lost` | same shape |
| `game.gate_wait_total()` | float, game-seconds all cars spent blocked at gate corridors |
| `game.gate_transit_total()` | int, corridor lock acquisitions |
| `game.cars[i].gate_wait_total / gate_transits / idle / car_state / riders` | per car |
| `game.waiting[cell]` | `Array[Passenger3]` still queueing (`patience`, `wait_time`, `no_path`) |
| derived in `tests/balance.gd` | `avg_wait`, `p90_wait`, `avg_transfers` (`rides - 1`) |

**Gaps a search will want:**

* No in-vehicle time / total journey time — `Passenger3.wait_time` accumulates
  **only while not riding**.
* Passengers still waiting at the end are **never logged**; only reachable by
  walking `game.waiting`. Scoring "avg wait" off `log_served` alone is
  survivorship-biased toward designs that abandon hard riders.
* No per-car distance travelled / occupancy / stop count, no counter for
  `no_path` passengers (the "?" bubble state).

### Scene-tree and HUD coupling

* **SceneTree required.** All setup lives in `main3._ready`; before `add_child`,
  `game.level == {}` and `game.cars == [null, null, null]`. A search cannot
  construct a game object without a tree today.
* **HUD required but trivial to stub.** `main3` calls `hud.game = self`,
  `refresh_cards()`, `refresh_stats()`, `hide_overlay()`, `show_intro()`,
  `show_win()`, `show_lose()`. `hud3._ready` builds ~15 `Control` nodes with
  theme overrides. Measured: replacing it with a 7-method no-op `CanvasLayer`
  and building the scene in code drops setup from **5.2 ms → 0.25 ms** with
  **byte-identical results** on L1/L3/L4. Decoupling difficulty: **trivial** —
  either guard the six call sites with `if hud != null`, or keep a
  `NullHud` script in `scripts/v3/`.
* **`Grid` node is pure rendering.** `main3` only does `grid.game = self`;
  `Grid3._process`/`_draw` are never read by logic. All the logic lives in
  `Grid3`'s statics. A bare `Node2D` named `Grid` would work.
* **`main3._process`** must be disabled (§2).
* `next_level()`, `to_level_select()`, `watch_again()` call
  `get_tree().change_scene_to_file()` — reachable only from HUD buttons, never
  from the harness path. `select3.gd` is not involved at all.

---

## 6. Level parameterization — one `const` in the way

Everything downstream of the level dictionary is already fully data-driven:
`Grid3.load_level(rows)` accepts arbitrary row strings, gate groups are
flood-filled at load, `rooms()` is rescanned, the pulse spawner / type mix /
trip table / per-type patience / cards / quota all read from the dict.

**Proof (measured):** I subclassed `main3.gd` at runtime, replaced the single
line `level = Levels3.get_level(Levels3.current)` with `level = <injected dict>`,
and simulated **8 randomly generated 5×10 levels** (random walls, random room
placement, generated `groups` + `trips` + `spawn`) end to end — all reached WIN,
199 ms for all 8. **No other code needed changing.**

The blocker is exactly one keyword:

* `scripts/v3/levels3.gd:28` — `const LEVELS := [...]`. Measured at runtime:
  `Levels3.LEVELS.is_read_only() == true`, and each level `Dictionary` is
  read-only too. `LEVELS.append(generated)` is impossible.
* `scripts/v3/main3.gd:69` — `level = Levels3.get_level(Levels3.current)` is the
  only consumer that matters.

**Minimal change (preferred, ~4 lines in `levels3.gd`):**

```gdscript
static var LEVELS := [ ... ]        # was: const
static var injected = null          # a full level Dictionary, or null

static func get_level(i: int) -> Dictionary:
    if injected != null:
        return injected
    return LEVELS[clampi(i, 0, LEVELS.size() - 1)]
```

Use the `injected` slot rather than appending to `LEVELS`: appending would make
generated levels appear in `select3.gd`'s level list and would shift the indices
`Levels3.current` refers to.

Required keys in a generated level dict (all read somewhere):
`id`, `rows`, `cards`, `quota`, `max_lost`,
`spawn{interval_start, interval_end, ramp, burst_min, burst_max, gap}`,
`mix`, `exec_origins`, `exec_dests`, `groups`, `trips`.
`patience` is optional (`Passenger3.setup` uses `.has()`).
`name` / `thesis` / `intro` are only touched by the HUD and level select — but
`hud3.refresh_stats` does read `level.id`, so keep it present (or stub the HUD).

---

## 7. Route legality

### Where validation lives — and doesn't

* **`main3.commit_route()` validates nothing.** Measured: committing
  `[(2,0), (2,9), (2,0)]` on L1 (non-adjacent jump *and* a duplicate cell) was
  **accepted**, `car_state` went to `RUNNING`, the car "drove" the illegal
  polyline and served a passenger with nonsense geometry. No error, no assert.
  The only guard in the whole function is
  `r.closed = closed and cells.size() >= 4`.
* **The real validator is test-only:** `tests/balance.gd::_route_error(entry)`
  (lines 124–148). It checks: `>= 2` cells; closed loops `>= 4` cells; every
  cell `Grid3.passable()`; no cell visited twice; consecutive Manhattan distance
  exactly 1; and for closed loops, `cells[n-1]` adjacent to `cells[0]`.
  It reads `Grid3` statics, so the level must already be loaded.
* **The UI enforces the same invariants constructively**, in
  `main3.stroke_try_extend()` (lines 294–351): `_begin_stroke` refuses a
  non-passable start; the magnetic-extend walk only steps onto neighbours
  satisfying `Grid3.passable(n) and not stroke.has(n)`; closing requires
  `stroke.size() >= 4` plus head/tail adjacency. Those rules are *emergent from
  the drag algorithm*, not a callable check.
* **`>= 2 room stops` is not a rejection.** `Car3.running()` returns false and
  the car parks with a `!` marker (`main3.route_warning`). A search will see
  such designs simply underperform, which is correct behaviour.

### Can a search feed cell arrays directly? Yes.

`commit_route(i, cells: Array[Vector2i], closed: bool)` is already the
UI-independent entry point — `tests/balance.gd` and watch mode
(`main3._ready` → `Scenarios3.route_set`) both use it, no drag events involved.
`Scenarios3.path([waypoints])` / `Scenarios3.loop([waypoints])` are handy
generators (they expand axis-aligned waypoints into cell polylines).

**What must be lifted:** the validator. Move `_route_error` out of `tests/` into
`scripts/v3/route.gd` as e.g.
`static func Route3.validate(cells: Array, closed: bool) -> String` (returns
`""` when legal), have `tests/balance.gd` call it, and have the search call it
before every `commit_route`. Without that, a search silently explores illegal
routes and scores garbage.

Useful primitives already available for a route generator:
`Grid3.passable(c)`, `Grid3.is_room(c)`, `Grid3.rooms()`,
`Grid3.gate_group_of(c)`, `Grid3.in_bounds(c)`. A self-avoiding random walk over
passable cells is the natural generator; `Grid3.rooms()` gives the stop set to
cover.

### Hot paths (why the tick loop costs what it costs)

| call | measured | why |
| --- | --- | --- |
| `Grid3.is_room()` | 0.68 – 0.73 µs | `maze_rows[...].substr(x, 1)` allocates a `String` per call |
| `Route3.stop_cells()` (24 cells) | 19.7 – 20.2 µs | 24 × `is_room` + a fresh `Array` |
| `Route3.ride_dist()` | 0.66 µs | two `Array.find()` over the cells |
| `Car3.running()` × 3 cars | **63.5 µs per game tick** | `running()` → `stop_cells().size()`, once per car per tick |
| `advance(dt)` with 0 passengers, 3 loop cars | 84 µs/tick | 76 % of it is the line above |
| `Pathfind3.find_path()`, 3 × 10-stop loops | 736 µs/call | 3 × `stop_cells()` + 270 edge `Dictionary`s + `ride_dist` per pair |
| dead passenger nodes iterated per tick, end of an L4 run | 76 children, 16 active → **79 % waste** | `queue_free()` doesn't flush until an engine frame, and the harness runs a whole scenario inside one frame |

Projected wins (arithmetic from the measurements above, **not** measured
end to end):

* Room-set `Dictionary` instead of `substr`: `is_room` 0.725 → **0.045 µs (16×)**;
  `stop_cells` 19.66 → **2.08 µs**.
* Memoising `stop_cells()` on `Route3`: 19.66 → **0.018 µs (~1100×)**.
  That removes ~63 of the 84 µs/tick fixed overhead → **~4× on the tick loop**,
  biggest on loop-heavy levels like L4.

---

## What to build for a search harness — ranked by effort

### Tier 0 — correctness blockers (do these first, < 1 hour total)

1. **Kill the frame coupling.** `main3.set_process(false)` for headless runs
   (or a `headless := false` flag guarding `_process`). Measured drift today:
   +0.047 game-s per engine frame a run stays alive. *Effort: 1 line.*
2. **Lift the route validator** out of `tests/balance.gd::_route_error` into
   `Route3.validate(cells, closed) -> String`; call it from `commit_route`
   (push_error or reject) and from `tests/balance.gd`. Today `commit_route`
   accepts non-adjacent, blocked and duplicated cells silently. *Effort: move
   ~25 lines, one call site.*
3. **Make levels injectable.** `const LEVELS` → `static var LEVELS`, plus a
   `static var injected` slot honoured by `get_level()`. *Effort: 4 lines.*
   (Verified sufficient: 8 generated levels ran end to end with only
   `main3._ready`'s level lookup changed.)

### Tier 1 — the harness itself (half a day)

4. **`SimRunner` (RefCounted) in `scripts/v3/` or `tests/`:**
   `run(level: Dictionary, routes: Array, seed: int, step: float, timeout: float) -> Dictionary`.
   Builds the game node in code with a **stub HUD** (measured: 0.25 ms vs
   5.2 ms setup, identical results), sets the statics, ticks, harvests stats,
   frees. Needs `main3` to tolerate a no-op HUD — either six `if hud != null`
   guards or a `scripts/v3/null_hud.gd`. *Effort: ~60 lines + 6 guards.*
5. **Worker protocol.** Long-lived `--headless --script worker.gd` processes
   reading job JSON from stdin (or a job-index range) and writing result JSON.
   Process startup is 375 ms vs ~113 ms per run — never fork per candidate.
   Run **8** workers (measured 5.34× on this 8-core box; 16 adds only 8 %).
   *Effort: ~80 lines.*
6. **Richer stats.** Log serve timestamp + in-vehicle time, log the passengers
   still waiting at run end (currently invisible → survivorship bias), and
   per-car distance/occupancy. *Effort: ~30 lines across `main3` /
   `passenger3` / `car3`.*

### Tier 2 — throughput (optional; ~3–4× on the tick loop)

7. **Memoise `Route3.stop_cells()` / `stop_indices()`**, invalidated when
   `cells` is assigned, and back `Grid3.is_room()` with a room-set `Dictionary`
   built in `load_level()`. Measured components: 19.7 µs → 0.018 µs, and
   `Car3.running()` is 76 % of the per-tick fixed cost. *Effort: ~20 lines.*
8. **Cache the Pathfind3 stop graph per route**, rebuilt only on
   `commit_route`/`clear_route` instead of on every `find_path` (736 µs/call
   today with three 10-stop loops). *Effort: ~40 lines, needs care so the
   `salt` jitter stays per-passenger.*
9. **Stop iterating dead passengers.** Keep an explicit `active_passengers`
   array in `main3` instead of `passengers_node.get_children()` — 79 % of that
   loop is `queue_free`d-but-unflushed nodes at the end of an L4 run.
   *Effort: ~15 lines.*
10. **Cache the `PackedScene`** once instead of `load()` per run (0.8 ms/run).
    Moot if item 4 builds the node in code. *Effort: 1 line.*

### Tier 3 — only if process-level parallelism stops being enough

11. **Node-free sim core**: `Passenger3` / `Car3` as `RefCounted`, no
    `SceneTree`, and — critically — **`Grid3`'s statics moved to instance
    state** (`maze_rows`, `ROWS`, `COLS`, `ORIGIN`, `_rooms_cache`,
    `_gate_groups`, `_gate_group_of`). Those statics are the reason two sims
    cannot run concurrently in one process today. Would remove the 4 ms
    `_ready` per run and enable threads. *Effort: large, touches every file.*
    Given 8 processes already deliver ~147 000 games/hour, this is not needed
    for a first search.
