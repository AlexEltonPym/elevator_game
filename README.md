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
max. Winning offers **Next Level / Level Select / Keep Playing** (endless);
losing offers **Retry** (routes stay drawn, counters reset) / **Level
Select**.

| level | name    | quota / max lost | thesis                                              |
|-------|---------|------------------|-----------------------------------------------------|
| L1    | Tower   | 45 / 5           | dedicate the express: straight spine for the execs, locals milk the side rooms |
| L2    | Detour  | 50 / 6           | spend the gate wisely: a dedicated shuttle crosses the tunnel for the mid-cluster crowds, a local keeps the bottom, and the express takes the long gate-free perimeter for the execs |
| L3    | Junction| 90 / 6           | short feeder shuttles sweep the room hallway into the HUB and only the express climbs the single-file service loft; direct winding climbs all queue up there |
| L4    | Ring    | 60 / 7           | a donut corridor with a strongly clockwise demand cycle: CLOSE the ring into one-way loops (staggered starts = short headways) and ride the tide; honest ping-pong coverage of the same rooms wastes half of every sweep driving back against the flow |
| X-1   | Sandbox | 30 / 8           | the original maze, original tuning (plus the global door/pulse changes) |

Every room in every level generates and receives demand — there are no
decoy rooms — and each level's thesis route set serves every room (the
balance harness lints both).

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
- **Redraw / redeploy**: drawing again for the same card replaces its route,
  and **CLEAR** removes it — but mid-game the car no longer teleports. If it
  has riders it first **recalls**: it finishes driving its old line to the
  nearest room stop, cycles its doors, and everyone steps out there and
  replans (an empty car skips this). Then the car vanishes (quick
  shrink/fade) and a **ghost outline with a 3-second countdown** appears at
  the new route's start; when the countdown ends the car appears there and
  starts service. The countdown runs on game time, so pause holds it.
  Re-committing while a car is recalling or redeploying just retargets the
  pending route (the countdown only restarts if the start cell moved), and
  CLEAR mid-recall means the car simply vanishes after the drop. Only the
  **first** commit of a never-deployed card appears instantly — the delay is
  the cost of mid-game redesign, not of designing.
- A route needs **at least 2 room stops** to run; otherwise its car parks
  with a "!" and the hint line explains.
- **Speed**: top-right `II` pause / `1x` / `3x` — the grid stays fully
  editable in every state, including paused. **LEVELS** returns to the level
  select.

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

Fixed-seed headless scenarios prove each level's intended strategy WINS
(lost <= 3) where the naive one LOSES (route sets shared with watch mode in
`scripts/v3/scenarios3.gd`; harness adapter in `tests/scenarios3.gd`;
assertions in `tests/balance.gd`). On top of the per-level win/lose checks
it asserts L2's thesis actually USES the gate (>= 10 corridor transits),
lints every level for dead rooms (every room must spawn, receive, and be
covered by the thesis routes), smoke-tests the redeploy flow (mid-run
redraw with riders aboard: recall drop at an old-route room, ~3 s ghost
countdown, service resuming at the new start; session-start commits stay
instant), and unit-checks the v3.4 loop mechanics through the real editing
path (closing needs >= 4 cells + adjacency, 3-cell strokes cannot close,
reopen by reversing onto the tail, closed cars advance forward-only and
glide across the wrap seam, directional ride_dist identity a→b + b→a = n,
backward demand priced the long way, recall-on-loop drives forward). One
command, from the project root:

```
& "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe" --headless --path . --script tests/run_balance.gd
```

Prints a per-scenario stats table (served, lost, avg/p90 wait, transfers,
gate wait), PASS/FAIL per assertion, and a final `BALANCE: ALL PASS` line
(trust that line over the exit code — the mono wrapper exits 1 benignly).
Tuning lives in `scripts/v3/levels3.gd` (spawn/patience/quota numbers);
never fix a red harness by weakening its assertions.

## Files

- `scenes/v3_select.tscn` + `scripts/v3/select3.gd` — level select (project
  main scene): PLAY / WATCH NAIVE / WATCH THESIS per level.
- `scenes/v3_main.tscn` — the game: Main3 / Grid / Cars / Passengers / HUD.
- `scripts/v3/levels3.gd` — the data-driven level table (grids, cards,
  quotas, pulse-spawn configs, type mixes, exec rooms, trip tables, intros)
  — this is where balance tuning lives. Also carries the `watch_strategy`
  handoff flag the level select sets.
- `scripts/v3/scenarios3.gd` — SHARED naive/thesis route sets + canonical
  per-level seeds (game watch mode and harness both read this).
- `scripts/v3/grid.gd` — per-level maze data (X-1 layout as the default),
  geometry helpers, gate-corridor flood fill, and all grid drawing (rooms,
  hazard-striped corridors + occupied tint, route polylines, drag preview).
- `scripts/v3/route.gd` — a drawn route: cell polyline + stop queries +
  the `closed` loop flag and direction-aware `ride_dist`.
- `scripts/v3/main3.gd` — game controller: level loading, drag-to-draw
  editing, per-corridor gate FIFO mutexes, seeded-RNG pulse spawning,
  replanning, session flow, watch-mode setup, time scale.
- `scripts/v3/pathfind3.gd` — time-based Dijkstra over the stop graph
  (ride time + 7 s per-leg wait + sub-second per-passenger tie-break so
  identical routes share load).
- `scripts/v3/car3.gd` — polyline ping-pong movement (forward-wrap on
  closed loops), door-phase stops
  (open/exchange/close), the UNDEPLOYED / RUNNING / RECALLING / REDEPLOYING
  car state machine (mid-game commits recall riders, then redeploy behind a
  3 s ghost countdown), idle parking + `home_cell` hook, slot-aware
  load/unload, gate-group acquire/wait/release.
- `scripts/v3/passenger3.gd` — visitor/patient/exec, patience (per-level
  overrides), "?" bubble, wait/transfer stats.
- `scripts/v3/hud3.gd` — top bar, route card chips, CLEAR, hint line,
  WATCHING banner, intro/win/lose overlays (incl. watch variants).
- `tests/run_balance.gd`, `tests/balance.gd`, `tests/scenarios3.gd` — the
  persistent balance harness (see "Balance harness" above).

Everything is spawned from code (`Car3.new()` / `Passenger3.new()` etc.), so
tuning lives in script constants and the `levels3.gd` table.
