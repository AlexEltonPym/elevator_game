# Elevator Prototype v3 — Path Drawing

A chill "design the system, watch it run" prototype built in Godot 4.2
(GDScript, programmer art only). Drag each elevator's route as a polyline
through a maze of a building (up/down AND left/right), detour around
blockages, squeeze through one-car-at-a-time gate corridors, close a route
into a one-way LOOP, and let local-to-express transfers emerge from
time-based pathfinding. Five levels behind a level select, each a strategy
thesis proven by a headless balance harness (`tests/`) — and watchable
in-game (specs: `docs/v3-spec.md`, `docs/v3-balance-spec.md`,
`docs/v3-watch-spec.md`, `docs/v3.3-spec.md`, `docs/v3.4-spec.md`;
`docs/v2-spec.md` is history from the retired v2 prototype).

## Run it

- Open the Godot 4.2 project manager, Import, and pick this folder's
  `project.godot` (works fine in the mono build; there is no C#).
- Press F5 (Run Project). The main scene is the level select
  (`scenes/v3_select.tscn`); the in-game **LEVELS** button returns to it.
- Portrait 720x1280 viewport, `canvas_items` stretch, expand aspect.
  `emulate_touch_from_mouse` is on, so mouse clicks/drags work like touch.

Or from a terminal:

```
& "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64.exe" --path <this folder>
```

Note: if you add scripts with new `class_name`s, open the project in the
editor once (or run `--headless --editor --quit`) so Godot refreshes its
global class cache.

## Levels

Each level is a thesis about strategy; serve its quota before losing its
max. The loop is **design -> commit -> watch -> learn -> retry** (v4 phase 1,
`docs/v4-spec.md`) and there is **no mid-run editing**:

| phase | what it is | the button |
|---|---|---|
| **BRIEFING** | the level's thesis and intro, the **elevator roster** you get (type, capacity, speed character) and the **passenger mix** to expect, plus the goal. Generated from the level data by `Levels3.briefing_body`, so it cannot describe a level the game is not running. | PLAN |
| **PLAN** | the grid is fully editable and nothing is running — no clock, no passengers. Draw, redraw, CLEAR freely. | RUN (disabled until every card has a route with >= 2 room stops; the hint line names the ones holding it up) |
| **RUN** | the simulation. **Every editing path is dead**: grid taps, chip selection, CLEAR and `commit_route()` itself all refuse. Speed controls stay live, because watching is now the point. | ABORT (back to PLAN, counters reset, routes kept) |
| **RESULT** | win or lose, with served/lost, average wait and shift length. | RETRY (back to PLAN with your routes) / NEXT LEVEL (on a win) / LEVEL SELECT |

Because every commit now happens in PLAN, **every car deploys instantly**.
The v3.3 recall -> ghost-countdown -> redeploy machinery is still in `car3.gd`,
still correct and still tested, but it is out of the main loop: only
`main3.commit_route_mid_run()` reaches it and nothing in the player flow calls
it (a future "place-only mid-run" mode might).

| level | name    | quota / max lost | thesis                                              |
|-------|---------|------------------|-----------------------------------------------------|
| L1    | Tower   | 90 / 5           | two wings that meet only in the lobby: a local per wing, and the express spine dedicated to the execs. One long line that reaches everything is the cheapest plan *on paper* for every rider in the building, so every rider queues for its four seats |
| L2    | Detour  | 105 / 6          | spend the gate wisely: ONE shuttle crosses the 4-cell tunnel for the cross-cluster crowds, a local weaves the bottom cluster, and the express takes the long gate-free perimeter for the execs. Three cars that all want a single-file corridor spend the level queueing |
| L3    | Junction| 145 / 5          | most of this building only wants the LOBBY: run each feeder arm → HUB → lobby so it serves its own half on its own, and let the express be the only car that ever enters the single-file service loft. Direct winding climbs carry a rider who wanted downstairs over the roof, then queue under the penthouse |
| L4    | Ring    | 110 / 4          | a two-lane ring: the outer lane passes every room, the inner lane passes none. Every commute crosses the building (half a lap), so CLOSE your routes into one-way loops — and WEAVE them, swinging out only for your own crowd. A loop that hugs the outer lane pays eight door cycles a lap for the two rooms it needed |
| X-1   | Sandbox | 90 / 6           | the original maze, no thesis, just the toys — with the demand turned up until coverage alone stops being enough |

Every room in every level generates and receives demand — there are no
decoy rooms — and each level's thesis route set serves every room (the
balance harness lints both).

**How hard is a level?** The honest measure is the *uniform-random* win
rate: what fraction of randomly drawn route-sets beat the level outright.
A level most random plans win is not a level. Measured with
`tools/run_depth.gd -- --scorecheck --n 600` (share of DECODABLE samples):

| level | random win rate, before the v3.5 pass | after |
|---|---|---|
| L1 Tower    | 27.0 % (44/163) | **1.0 % (1/102)** |
| L2 Detour   | 46.9 % (91/194) | **0.3 % (1/305)** |
| L3 Junction |  2.2 % (2/91)   | **2.7 % (8/292)** |
| L4 Ring     | 44.6 % (54/121) | **1.2 % (7/565)** |
| X-1 Sandbox | 32.9 % (24/73)  | **3.1 % (7/229)** |

## Watch mode

Every level row in the level select has, next to PLAY, **WATCH NAIVE** and
**WATCH THESIS** buttons (X-1 only has WATCH THESIS — its old smoke-test
strategy). Watching runs the normal level with:

- the scenario's routes pre-drawn and **route editing disabled** (grid taps
  do nothing, card chips are display-only),
- a colored **WATCHING: NAIVE / THESIS** banner naming the strategy,
- speed controls live (pause / 1x / 3x) and the top button reading **EXIT**
  (back to the level select),
- the harness's canonical fixed seed, so NAIVE and THESIS face the
  **identical demand sequence** — the comparison is fair and repeatable.
  (Normal PLAY stays unseeded.)
- win/lose overlays reporting the strategy's result, with **Watch Again /
  Level Select**.

The route sets live in `scripts/v3/scenarios3.gd` as shared data; the
balance harness imports the same table, so what you watch is exactly what
the harness proves.

## Controls (one thumb)

- **Draw a route**: tap one of the 3 card chips in the bottom panel (the
  cards vary per level, e.g. two locals + an express), then drag across the
  grid. The stroke starts on any open
  cell and extends through orthogonally adjacent open cells; it never enters
  blocked `#` cells and never revisits a cell of the same route. Fast drags
  that skip cells are filled in only along an unambiguous straight legal
  line; anything else is ignored mid-drag. A live colored preview follows
  your finger; **release to commit**.
- **The head is magnetic**, both ways, and purely positional (drag speed never
  matters). Drawing **on**, it walks toward your finger a cell at a time:
  straight skips fill themselves in, and a diagonal drag turns the corner on its
  own (longest axis first). Dragging **back**, it slides along the path to meet
  you: a straight run snaps back to its start, corners unwind, and at a junction
  the leg you're leaving pops off before the new one draws (go A→E→B, sweep to
  G, and it becomes A→E→G). The walk never teleports — it steps only into open,
  unused cells, so a wall or the stroke's own body just stops it where it
  stands, and brushing sideways past an earlier part of your path never eats it.
- **Close a LOOP** (v3.4): drag the stroke back onto its **first cell** (needs
  at least 4 cells and an adjacent step) — the ONE exception to the collision
  rule. The preview draws the closing segment and further forward drags are
  ignored; reverse back onto the tail cell to REOPEN it mid-draw (you cannot
  retract while closed). Release to commit. A **closed route runs one-way**:
  the car circles forever forward in the direction you drew — small
  **chevrons along the line show the travel direction** (only loops get
  arrows; ping-pong routes have none). The one-way-ness is real: a trip
  "against" the loop is honestly priced as almost a full lap, so passengers
  take another route or a transfer when one is cheaper. Recall and idle
  deadheads on a loop also only drive forward.
- **Redraw / clear**: drawing again for the same card replaces its route and
  **CLEAR** removes it. Both are PLAN-phase actions, and in PLAN nothing is
  running, so the car simply appears at the new start — no recall, no
  countdown, ever, in the shipped loop.
- A route needs **at least 2 room stops** to run; a card that has fewer keeps
  RUN disabled (and its car parks with a "!" if a run is somehow started
  programmatically without it).
- **Speed**: `II` pause / `1x` / `3x` in the top bar, shown only during a RUN
  (there is nothing to speed up in PLAN). **LEVELS** returns to the level
  select.
- **The mid-run redeploy path** (v3.3, kept but unreachable from the UI): a
  commit through `commit_route_mid_run()` with riders aboard **recalls** — the
  car finishes driving its old line to the nearest room stop, cycles its doors,
  everyone steps out and replans — then vanishes and leaves a **ghost outline
  with a 3-second countdown** at the new start before resuming service. The
  balance harness drives it directly so it stays honest for whoever wants it
  back.

## Rules

- **Rooms** (lettered cells): a route passing through a room makes it a
  stop. Cars ping-pong end-to-end along their polyline (closed loops circle
  forward instead — no reversing, no end dwell); at each room stop
  (while the car has work) the **doors cycle**: OPEN 0.5 s (panels visibly
  slide apart) -> EXCHANGE max(0.8 s, 0.35 s x passenger moves this stop;
  unload then load, late arrivals may still hop on) -> CLOSE 0.5 s (nobody
  boards a closing door). Minimum full stop ~1.8 s; busy stops take longer.
- **Idle cars park**: a car with no riders and nobody planning to board it
  waits at its current cell, doors shut — watch for it between spawn pulses.
  (`Car3.home_cell` is a code-only hook: set it and an idle empty car
  deadheads there; the future "default waiting floor" upgrade wires a UI to
  `set_home_cell()`.)
- **Gate corridors** (hazard-striped cells): orthogonally contiguous `G`
  cells form ONE corridor with a single lock — a car acquires the whole
  corridor before entering its first cell and releases it only on reaching a
  cell fully outside, first-come first-served. A car that can't get the lock
  waits in its current cell with a pulsing outline; while a car is inside,
  the whole corridor glows faintly in its color ("the tunnel is occupied").
  A single isolated `G` cell is just a corridor of one. Everywhere else cars
  ghost through each other — congestion is a gate feature, not a hazard.
- **Passengers**: visitors (green, 90 s patience), patients (blue, 75 s),
  and **execs** (amber ring + briefcase, hasty — patience tuned per level):
  execs spawn only at level-designated origin rooms and want only
  level-designated targets (L1: lobby -> penthouse; L2: bottom -> top;
  L3: arms -> penthouse). Patience drains only while waiting. Empty patience
  = Lost +1.
- **Pulse spawning**: spawns come in bursts (per-level size/gap) with quiet
  lulls between; the average per-passenger interval ramps down over the
  session (per-level numbers in `scripts/v3/levels3.gd`).
- **Transfers (the point of the experiment)**: passengers run a time-based
  Dijkstra over the stop graph — every pair of stops on a route is an edge
  costing ride time (path distance / route speed; **direction-aware on
  loops**: a→b is measured forward-only, so the "wrong way" costs almost a
  lap) plus a flat 7 s expected wait per leg. When riding a slow LOCAL (260 px/s) to a room shared with
  the EXPRESS (520 px/s) is genuinely faster than staying aboard, the
  passenger plans the 2-leg trip on its own. All waiting passengers replan
  on every route commit/clear; riders replan when they step out. No possible
  path shows a "?" bubble until your next redraw fixes it.

## Balance harness (persistent, keep it green)

Headless scenarios prove each level's intended strategy WINS where the
naive one LOSES — **over a 16-seed set, not one seed** (route sets shared
with watch mode in `scripts/v3/scenarios3.gd`; harness adapter in
`tests/scenarios3.gd`; assertions in `tests/balance.gd`).

The seed set is the assertion. A single-seed axiom measures seed luck: the
2026-08-12 depth run held the old one-seed claim out on 8 unseen seeds and
L3's *naive* strategy won 6 of them. So every level now asserts
`thesis WINS >= 15/16` and `naive LOSES >= 15/16` on
`Scenarios3.SEEDS_ASSERT`, and the report prints the per-seed win count for
every scenario plus the name of any seed that broke ranks, so a straddle is
visible rather than hidden inside a median.

Those 16 seeds are **held out**: levels were tuned against the disjoint
`SEEDS_TUNE` (see `tools/run_depth.gd -- --tune`), and both sets are
disjoint from the depth tools' own train/test seeds. Never tune against the
assertion seeds — that reintroduces exactly the overfitting this replaced.
The full 16-seed suite is 144 simulated levels in **~16 s**, so it is the
default gate; `-- --quick` runs one canonical seed per level for fast
iteration and says loudly that it proves nothing about the axioms.

On top of the per-level win/lose axioms it asserts L2's thesis actually USES the gate (>= 10 corridor transits),
lints every level for dead rooms (every room must spawn, receive, and be
covered by the thesis routes, and its BRIEFING names every card, passenger
type and goal number), checks the v4 phase machine (a level opens on the
briefing; PLAN is editable and gates RUN on every card having a 2-stop route;
during a RUN taps, chip selection, CLEAR and `commit_route` all refuse and no
car ever recalls or redeploys; ABORT and RETRY return to PLAN with routes kept
and counters reset; watch mode skips straight to RUN), smoke-tests the
redeploy flow through `commit_route_mid_run` (recall drop at an old-route
room, ~3 s ghost countdown, service resuming at the new start; PLAN commits
stay instant), and unit-checks the v3.4 loop mechanics through the real editing
path (closing needs >= 4 cells + adjacency, 3-cell strokes cannot close,
reopen by reversing onto the tail, closed cars advance forward-only and
glide across the wrap seam, directional ride_dist identity a→b + b→a = n,
backward demand priced the long way, recall-on-loop drives forward). One
command, from the project root:

```
& "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe" --headless --path . --script tests/run_balance.gd
& "C:\Program Files\...\Godot_..._console.exe" --headless --path . --script tests/run_balance.gd -- --quick
```

Prints a per-scenario stats table (W/L split over the seed set, then medians
of served, lost, avg/p90 wait, transfers, gate wait), PASS/FAIL per
assertion, and a final `BALANCE: ALL PASS` line
(trust that line over the exit code — the mono wrapper exits 1 benignly).
Tuning lives in `scripts/v3/levels3.gd` (spawn/patience/quota numbers);
never fix a red harness by weakening its assertions.

The harness also unit-checks the plumbing the depth tools stand on:
`Route3.validate` accepts good geometry and rejects each bad kind (and
`commit_route` really refuses it), a route GENE decodes to legal cells that
keep its stops in order, and an INJECTED (generated) level builds and plays.
Those are cheap; the heavy search lives in `tools/` and is never run here.

## Depth tools (manual, `tools/`)

An automated optimizer that plays the levels, so strategic depth is
*measured* rather than guessed. Methods: `docs/autodesign-research.md`;
spec: `docs/depth-tools-spec.md`; measured throughput/determinism:
`docs/sim-search-feasibility.md`. Output: `docs/depth-report.md`
(generated) plus `scripts/v3/discovered3.gd`, which puts a **WATCH BEST**
button on every level row whose search found a route-set.

```
powershell -File tools/run_depth.ps1            # all 5 levels, ~1 h
powershell -File tools/run_depth.ps1 -Quick     # small budgets, ~3.5 min
powershell -File tools/run_depth.ps1 -Levels L3,L4
```

Two lighter modes of the same tool are the level-DESIGN loop, and they are
what you iterate on before touching the balance gate:

```
... --script tools/run_depth.gd -- --tune --n 300      # random win rate + thesis/naive over SEEDS_TUNE
... --script tools/run_depth.gd -- --scorecheck --n 600 # score validity + the reported random win rate
```

One long-lived Godot process per level (Grid3's maze is static, so a process
can only hold one level at a time; process startup is 375 ms, ~4x a run, so
never fork per candidate), then a merge pass writing the report. Diagnostics:

```
... --script tools/run_depth.gd -- --selftest   # A/B/A batching, throughput
... --script tools/run_depth.gd -- --smoke      # the GAME still builds/plays
... --script tools/run_fingerprint.gd           # scenario determinism hashes
```

How it works: a route **gene** is `{stops: [rooms in visit order], closed}`,
decoded to cells by BFS between consecutive stops (never revisiting a cell);
an undecodable gene scores -INF instead of crashing. Three optimizers form a
ladder — uniform `random`, a beam-search `greedy`, and a (12+24) `ea` seeded
from generic route primitives — all budgeted in *simulation runs*. Search
happens on 8 TRAIN seeds at STEP 0.25; every reported number is a median over
8 disjoint TEST seeds at STEP 0.1, and the train-vs-test gap is reported as
`seed_fragility` (a search that memorises the arrival schedule is worthless).

## Files

- `scenes/v3_select.tscn` + `scripts/v3/select3.gd` — level select (project
  main scene): PLAY / WATCH NAIVE / WATCH THESIS per level, plus WATCH BEST
  wherever the depth search has a discovered route-set.
- `scenes/v3_main.tscn` — the game: Main3 / Grid / Cars / Passengers / HUD.
- `scripts/v3/levels3.gd` — the data-driven level table (grids, cards,
  quotas, pulse-spawn configs, type mixes, exec rooms, trip tables, intros)
  — this is where balance tuning lives. Also carries the `watch_strategy`
  handoff flag the level select sets.
- `scripts/v3/scenarios3.gd` — SHARED naive/thesis route sets + the three
  seed sets: `SEEDS` (one canonical per level, for watch mode), `SEEDS_TUNE`
  (16, the only seeds levels are tuned on) and `SEEDS_ASSERT` (16 held out,
  what the balance harness asserts on). Game watch mode and harness both
  read this file, so they can never drift apart.
- `scripts/v3/grid.gd` — per-level maze data (X-1 layout as the default),
  geometry helpers, gate-corridor flood fill, and all grid drawing (rooms,
  hazard-striped corridors + occupied tint, route polylines, drag preview).
- `scripts/v3/route.gd` — a drawn route: cell polyline + stop queries +
  the `closed` loop flag and direction-aware `ride_dist`.
- `scripts/v3/main3.gd` — game controller: level loading, the
  BRIEFING/PLAN/RUN/RESULT phase machine (`to_plan()`, `start_run()`,
  `abort_run()`, `can_edit()`, `ready_to_run()`), drag-to-draw editing,
  per-corridor gate FIFO mutexes, seeded-RNG pulse spawning, replanning,
  watch-mode setup, time scale.
- `scripts/v3/pathfind3.gd` — time-based Dijkstra over the stop graph
  (ride time + 7 s per-leg wait + sub-second per-passenger tie-break so
  identical routes share load).
- `scripts/v3/car3.gd` — polyline ping-pong movement (forward-wrap on
  closed loops), door-phase stops
  (open/exchange/close), the UNDEPLOYED / RUNNING / RECALLING / REDEPLOYING
  car state machine (the RECALLING/REDEPLOYING half is now reachable only
  through `commit_route_mid_run`, since the v4 loop commits everything in
  PLAN), idle parking + `home_cell` hook, slot-aware load/unload, gate-group
  acquire/wait/release.
- `scripts/v3/passenger3.gd` — visitor/patient/exec, patience (per-level
  overrides), "?" bubble, wait/transfer stats.
- `scripts/v3/hud3.gd` — top bar (speed shown only during a RUN), route card
  chips, CLEAR, the RUN/ABORT action button, hint line, WATCHING banner, and
  the briefing/win/lose overlays (incl. watch variants).
- `scripts/v3/discovered3.gd` — GENERATED by the depth tools: the best
  route-set found per level, in the same shape as `scenarios3.gd`, feeding
  the WATCH BEST button.
- `tests/run_balance.gd`, `tests/balance.gd`, `tests/scenarios3.gd` — the
  persistent balance harness (see "Balance harness" above).
- `tools/run_depth.ps1`, `tools/run_depth.gd` — depth-tool entry points
  (shard runner + CLI: search, `--report`, `--selftest`, `--smoke`).
- `tools/sim_api.gd` — batched headless runs (fixed 240 s endless horizon,
  continuous score, train/test seed sets).
- `tools/routegen.gd` — route genes: decode, mutation/crossover operators,
  demand model, hand-built primitives, structural distance.
- `tools/optimizers.gd` — the random / greedy / EA ladder with anytime
  budget checkpoints.
- `tools/metrics.gd` — per-level metric computation (skill gap, ladder
  steps, seed/plan fragility, coarse-vs-fine rank correlation).
- `tools/fingerprint.gd`, `tools/run_fingerprint.gd` — bit-exact scenario
  fingerprints; the gate that proved the v3.5 perf work changed nothing.

Everything is spawned from code (`Car3.new()` / `Passenger3.new()` etc.), so
tuning lives in script constants and the `levels3.gd` table.
