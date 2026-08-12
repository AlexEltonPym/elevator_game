# Elevator Prototype v3 — Path Drawing

A chill "design the system, watch it run" prototype built in Godot 4.2
(GDScript, programmer art only). Drag each elevator's route as a polyline
through a maze of a building (up/down AND left/right), detour around
blockages, squeeze cars through gate corridors that are only so WIDE, close a
route into a one-way LOOP, give a car a HOME floor to wait on, and let
local-to-express transfers emerge from time-based pathfinding. Cars ACCELERATE,
so every stop costs momentum and not just door time. Eight levels behind a level
select, each a strategy thesis proven by a headless balance harness (`tests/`)
— and watchable in-game (specs: `docs/v3-spec.md`, `docs/v3-balance-spec.md`,
`docs/v3-watch-spec.md`, `docs/v3.3-spec.md`, `docs/v3.4-spec.md`,
`docs/v4-spec.md`; `docs/v2-spec.md` is history from the retired v2 prototype).

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
| L2    | Detour  | 95 / 6           | spend the gate wisely: ONE shuttle crosses the 4-cell tunnel for the cross-cluster crowds, a local weaves the bottom cluster, and the express takes the long gate-free perimeter for the execs. Three cars that all want a single-file corridor spend the level queueing |
| L3    | Junction| 116 / 5          | most of this building only wants the LOBBY: run each feeder arm → HUB → lobby so it serves its own half on its own, and let the express be the only car that ever enters the single-file service loft. Direct winding climbs carry a rider who wanted downstairs over the roof, then queue under the penthouse |
| L4    | Ring    | 110 / 4          | a two-lane ring: the outer lane passes every room, the inner lane passes none. Every commute crosses the building (half a lap), so CLOSE your routes into one-way loops — and WEAVE them, swinging out only for your own crowd. A loop that hugs the outer lane pays eight door cycles a lap for the two rooms it needed |
| W-1   | Freight | 80 / 5           | big deliveries (three crates wide) ride the dock↔delivery freight lane and only the cargo car fits them — dedicate the cargo car to that shuttle, run a local per wing. Three general sweeps cover every room and strand the freight, because the one cargo car crawls a ten-stop milk run while the crates pile up |
| W-2   | Narrows | 78 / 5           | the centre is a one-cell NARROWS only the pod fits — put the pod on it for the lobby↔roof rush and weave the wide cars round the perimeter for the couples. Sending everything the safe way round the outside leaves the middle rush dying a full lap away |
| W-3   | Momentum| 78 / 5           | the hauler is heavy — give it ONE nonstop express-shaft run lobby↔penthouse where its momentum pays, and let the sharp pods do the local hops. Stopping every car at every floor never lets the hauler get moving and the end-to-end crowd crawls |
| X-1   | Sandbox | 75 / 6           | the original maze, no thesis, just the toys — with the demand turned up until coverage alone stops being enough |

The four axiomatic mechanic levels planned for v4 phase 2 were W-1..W-4, one per
mechanic. **W-4 "Home" was cut**: the home floor (#29) measured as *chrome* — an
identical route-set with a home cell beat the same route-set without one by only
~2 of 16 seeds at the level's most sensitive tuning, never near the axiom bar.
See `docs/ablation-report.md` for the full restricted-play study (which mechanics
are load-bearing vs chrome, and the express accel-model decision).

Every room in every level generates and receives demand — there are no
decoy rooms — and each level's thesis route set serves every room (the
balance harness lints both).

**Every one of those numbers was re-tuned for v4 phase 2.** Acceleration made
every car slower (a standard loses ~0.8 s of momentum per stop, an express
~1.6 s), so quotas, spawn intervals and patience were re-measured against
`SEEDS_TUNE` until the axioms held again on the held-out `SEEDS_ASSERT`. No
assertion was weakened to get there.

**How hard is a level?** The honest measure is the *uniform-random* win
rate: what fraction of randomly drawn route-sets beat the level outright.
A level most random plans win is not a level. Measured with
`tools/run_depth.gd -- --scorecheck --n 900` (share of DECODABLE samples):

| level | before the v3.5 pass | after v3.5 | after the v4 phase 2 retune |
|---|---|---|---|
| L1 Tower    | 27.0 % (44/163) | 1.0 % (1/102) | **0.7 % (1/152)** |
| L2 Detour   | 46.9 % (91/194) | 0.3 % (1/305) | **0.4 % (2/481)** |
| L3 Junction |  2.2 % (2/91)   | 2.7 % (8/292) | **1.6 % (7/444)** |
| L4 Ring     | 44.6 % (54/121) | 1.2 % (7/565) | **0.5 % (4/854)** |
| X-1 Sandbox | 32.9 % (24/73)  | 3.1 % (7/229) | **3.3 % (11/334)** |

Levels got *slower* in v4 phase 2 but not easier: the retune moved quotas,
pace and patience, and every level still holds `thesis WINS >= 15/16` /
`naive LOSES >= 15/16` on the held-out seeds with a random win rate under
5 %.

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
- **Set a HOME floor** (v4 phase 2): with a card selected, **tap** (don't drag)
  a cell of its route. A house marker in the card's colour appears there and
  that car deadheads home whenever it is idle and empty; tap the same cell
  again to clear it. Taps anywhere off the route do nothing.
- **Redraw / clear**: drawing again for the same card replaces its route and
  **CLEAR** removes it. Both are PLAN-phase actions, and in PLAN nothing is
  running, so the car simply appears at the new start — no recall, no
  countdown, ever, in the shipped loop. A redraw that no longer covers the
  home cell drops the home too.
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
- **Acceleration** (v4 phase 2): a car ramps up to its top speed and must
  brake to arrive **at rest** — at a room stop, at the end of a ping-pong
  line, at the mouth of a corridor it cannot get into, and at the cell it is
  about to park or deadhead home to. So a stop costs momentum on top of door
  time (~0.5 s for a pod, ~0.8 s for a standard, ~1.6 s for an express,
  ~1.2 s for a cargo), queueing at a corridor costs momentum too, and a long
  uninterrupted run is where a heavy car finally wins. The planner knows:
  `Pathfind3` prices every intermediate stop on a leg at the car's own
  momentum loss, so a stop-everywhere line is no longer as cheap "on paper"
  as an express over the same ground. Integration is analytic per phase, so
  `advance(dt)` gives the same answer at 0.05 s and at 1 s and can never
  overshoot a stop.
- **Idle cars park**: a car with no riders and nobody planning to board it
  waits at its current cell, doors shut — watch for it between spawn pulses.
  **HOME FLOOR** (v4 phase 2): in PLAN, with a card selected, **tap a cell of
  its route** to make that the car's home (a little house marker appears in
  the card's colour; tap it again to clear it). An idle EMPTY car with a home
  deadheads back to it, skipping stops on the way, and waits there with a
  small roof lamp lit. The home is part of the plan: RETRY keeps it, a redraw
  that strands it drops it, and route-set data can carry it
  (`{"cells": ..., "home": Vector2i(3, 0)}`), so scenarios, watch mode and
  the depth tools can all express one.
- **WIDTH** (v4 phase 2) — one number in three places:
  - **Parties have a width**: visitor / patient / exec 1, couple / gurney /
    delivery 2, big delivery 3. A wide party is ONE party — a couple boards
    together or not at all — and it is drawn the full width it needs, so you
    can see what will not fit.
  - **Cars have a width**, and capacity is counted in width-units:
    pod (1, holds 2), standard (2, holds 4), cargo (3, holds 6). A party may
    board only if `party.width <= car.width`, and it eats its own width of the
    cabin: a standard takes 4 ordinary riders, or 2 couples, or a couple plus
    2 ordinary. Speed and acceleration are separate axes — an *express* is a
    fast width-2 car, not a wider one — so they can be ablated independently.
  - **Corridors have a width**: hazard-striped gate cells written `G` (= 2) or
    as a digit `1`/`2`/`3`, with the width drawn as that many bars. A car may
    enter only if `car.width <= corridor.width`, and cars SHARE a corridor
    while the sum of the widths inside is `<= corridor.width` — so a width-3
    tunnel takes three pods, or one cargo, or a pod plus a standard, while the
    default width-2 tunnel is exactly the old one-car mutex (2 + 2 > 2). A
    width-1 corridor is a pod-only passage. Admission is strict FIFO, so a
    stream of pods cannot starve a standard waiting behind them. Drawing a car
    down a corridor narrower than it is is felt as RESISTANCE — the magnetic
    drawing head treats a too-narrow corridor cell as a wall for the selected
    car — and if a fast drag reaches it anyway the commit is refused with the
    reason on the hint line, in the card's colour ("CARGO is width 3 — that
    corridor only fits width 2. Go around."), leaving the card unrouted.
  Orthogonally contiguous gate cells form ONE corridor: a car takes its share
  of the whole thing before entering the first cell and gives it back on
  reaching a cell fully outside. A car that cannot get in waits with a pulsing
  outline; an occupied corridor glows in its holders' colours. Everywhere else
  cars ghost through each other — congestion is a corridor feature.
- **Passengers**: visitors (green, 90 s patience), patients (blue, 75 s),
  and **execs** (amber ring + briefcase, hasty — patience tuned per level);
  plus the wide parties — **couples** (pink, two heads), **gurneys** (pale
  blue trolley), **deliveries** (courier + one crate) and **big deliveries**
  (courier + two crates, width 3, cargo-car-only):
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
  lap) plus **the momentum lost at every stop in between** (v4 phase 2) plus a
  flat 7 s expected wait per leg. A party only ever plans onto cars wide
  enough to carry it. When riding a slow LOCAL (260 px/s) to a room shared with
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
backward demand priced the long way, recall-on-loop drives forward).

The **v4 phase 2 mechanics** get their own fixtures, because they are rules of
the simulation rather than facts about any level: the card table really builds
pod 1/2, standard 2/4 and cargo 3/6; a width-3 party fits only the cargo car,
will not even PLAN onto a narrower one, and eats 3 of the cargo's 6 units; two
pods share a width-2 corridor while a standard cannot squeeze in beside them
and a cargo can never enter it at all (nor be committed through it); a car
ramps rather than stepping to top speed, opens its doors only at rest, never
overshoots a cell, gives a bit-identical trace on a repeated run and the same
outcome at 0.05 / 0.1 / 0.25 / 1.0 s steps; and an idle empty car deadheads to
its home cell, keeps it across RETRY, and loses it to a redraw that strands it.
One command, from the project root:

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
... --script tools/run_depth.gd -- --scorecheck --n 900 # score validity + the reported random win rate
powershell -File tools/tune_all.ps1                    # --tune for every level, one process each, in parallel
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
  — this is where balance tuning lives — plus the **car type table**
  (pod/standard/express/cargo: width, capacity, speed, acceleration) that
  `Car3.setup` and the briefing both read, so a card cannot advertise a car
  the simulation does not build. Also carries the `watch_strategy` handoff
  flag the level select sets.
- `scripts/v3/scenarios3.gd` — SHARED naive/thesis route sets + the three
  seed sets: `SEEDS` (one canonical per level, for watch mode), `SEEDS_TUNE`
  (16, the only seeds levels are tuned on) and `SEEDS_ASSERT` (16 held out,
  what the balance harness asserts on). Game watch mode and harness both
  read this file, so they can never drift apart.
- `scripts/v3/grid.gd` — per-level maze data (X-1 layout as the default),
  geometry helpers, gate-corridor flood fill **and per-corridor width**, and
  all grid drawing (rooms, hazard-striped corridors + width bars + occupied
  tint, route polylines, home markers, drag preview).
- `scripts/v3/route.gd` — a drawn route: cell polyline + stop queries +
  the `closed` loop flag, direction-aware `ride_dist`, `stops_between` (what
  the acceleration cost is priced from) and `validate` (geometry, plus the
  car-width-vs-corridor-width rule when a card is in hand).
- `scripts/v3/main3.gd` — game controller: level loading, the
  BRIEFING/PLAN/RUN/RESULT phase machine (`to_plan()`, `start_run()`,
  `abort_run()`, `can_edit()`, `ready_to_run()`), drag-to-draw editing,
  per-corridor gate FIFO mutexes, seeded-RNG pulse spawning, replanning,
  watch-mode setup, time scale.
- `scripts/v3/pathfind3.gd` — time-based Dijkstra over the stop graph
  (ride time + per-stop momentum penalty + 7 s per-leg wait + sub-second
  per-passenger tie-break so identical routes share load), width-aware: a
  party only plans onto cars it fits in.
- `scripts/v3/car3.gd` — polyline ping-pong movement (forward-wrap on
  closed loops) with **acceleration** (braking lookahead + analytic
  per-phase integration), door-phase stops
  (open/exchange/close), the UNDEPLOYED / RUNNING / RECALLING / REDEPLOYING
  car state machine (the RECALLING/REDEPLOYING half is now reachable only
  through `commit_route_mid_run`, since the v4 loop commits everything in
  PLAN), idle parking + home-floor deadheading, width-aware load/unload and
  capacity in width-units, gate-group acquire/wait/release.
- `scripts/v3/passenger3.gd` — the party types (visitor/patient/exec at
  width 1; couple/gurney/delivery at 2; big delivery at 3), their widths and
  silhouettes, patience (per-level overrides), "?" bubble, wait/transfer
  stats.
- `scripts/v3/hud3.gd` — top bar (speed shown only during a RUN), route card
  chips, CLEAR, the RUN/ABORT action button, hint line, WATCHING banner, and
  the briefing/win/lose overlays (incl. watch variants).
- `scripts/v3/discovered3.gd` — GENERATED by the depth tools: the best
  route-set found per level, in the same shape as `scenarios3.gd`, feeding
  the WATCH BEST button.
- `tests/run_balance.gd`, `tests/balance.gd`, `tests/scenarios3.gd` — the
  persistent balance harness (see "Balance harness" above).
- `tools/run_depth.ps1`, `tools/run_depth.gd` — depth-tool entry points
  (shard runner + CLI: search, `--report`, `--selftest`, `--smoke`,
  `--scorecheck`, `--tune`); `tools/tune_all.ps1` runs `--tune` for every
  level in parallel, which is the level-design loop.
- `tools/sim_api.gd` — batched headless runs (fixed 240 s endless horizon,
  continuous score, train/test seed sets).
- `tools/routegen.gd` — route genes: decode, mutation/crossover operators,
  demand model, hand-built primitives, structural distance.
- `tools/optimizers.gd` — the random / greedy / EA ladder with anytime
  budget checkpoints.
- `tools/metrics.gd` — per-level metric computation (skill gap, ladder
  steps, seed/plan fragility, coarse-vs-fine rank correlation).
- `tools/fingerprint.gd`, `tools/run_fingerprint.gd` — bit-exact scenario
  fingerprints; the gate that proved the v3.5 perf work changed nothing, and
  that v4's WIDTH system changed nothing before acceleration was switched on.
  Current baseline: `FINGERPRINT-ALL 2879506936 len=24580`
  (v3.5 / pre-v4-phase-2 was `3101325335 len=25276`).

Everything is spawned from code (`Car3.new()` / `Passenger3.new()` etc.), so
tuning lives in script constants and the `levels3.gd` table.
