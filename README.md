# Elevator Prototypes — v2 Network Planner + v3 Path Drawing

Two chill "design the system, watch it run" prototypes built in Godot 4.2
(GDScript, programmer art only), sharing one project. Boot into a tiny menu
and pick a mode:

- **v2 Network Planner** (`docs/v2-spec.md`) — cutout side view of a 10-floor
  hospital with 4 vertical shafts. Place elevator cards, toggle doors,
  passengers transfer between shafts on transfer floors.
- **v3 Path Drawing** (`docs/v3-spec.md` + `docs/v3-balance-spec.md`) — maze
  test levels. Drag each elevator's route as a polyline (up/down AND
  left/right), detour around blockages, squeeze through one-car-at-a-time
  gates, and let local-to-express transfers emerge from time-based
  pathfinding. Four levels behind a level select, each a strategy thesis
  proven by a headless balance harness (`tests/`).

## Run it

- Open the Godot 4.2 project manager, Import, and pick this folder's
  `project.godot` (works fine in the mono build; there is no C#).
- Press F5 (Run Project). The main scene is `scenes/menu.tscn`; both modes
  have a MENU button in their top HUD to come back.
- Portrait 720x1280 viewport, `canvas_items` stretch, expand aspect.
  `emulate_touch_from_mouse` is on, so mouse clicks/drags work like touch.

Or from a terminal:

```
& "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64.exe" --path <this folder>
```

Note: if you add scripts with new `class_name`s, open the project in the
editor once (or run `--headless --editor --quit`) so Godot refreshes its
global class cache.

---

# v3 Path Drawing

Data-driven test levels (see `docs/v3-balance-spec.md`): picking "v3 Path
Drawing" in the boot menu opens a **level select**. Each level is a thesis
about strategy; serve its quota before losing its max. Winning offers
**Next Level / Level Select / Keep Playing** (endless); losing offers
**Retry** (routes stay drawn, counters reset) / **Level Select**.

| level | name    | quota / max lost | thesis                                              |
|-------|---------|------------------|-----------------------------------------------------|
| L1    | Tower   | 45 / 5           | dedicate the express: straight spine for the execs, locals milk the side rooms |
| L2    | Detour  | 45 / 8           | the long gate-free perimeter beats a third car queueing at the gate |
| L3    | Junction| 50 / 8           | short feeders + express sharing the HUB: transfers beat the winding climbs |
| X-1   | Sandbox | 30 / 8           | the original maze, original tuning (plus the global door/pulse changes) |

## Controls (one thumb)

- **Draw a route**: tap one of the 3 card chips in the bottom panel (the
  cards vary per level, e.g. two locals + an express), then drag across the
  grid. The stroke starts on any open
  cell and extends through orthogonally adjacent open cells; it never enters
  blocked `#` cells and never revisits a cell of the same route. Fast drags
  that skip cells are filled in only along an unambiguous straight legal
  line; anything else is ignored mid-drag. A live colored preview follows
  your finger; **release to commit**.
- **Backtrack while drawing**: drag back onto any cell already in your stroke
  to retract the path to that point (like Oxygen Not Included's pipe drawing)
  — make a wrong turn, reverse over it, keep going.
- **Redraw**: drawing again for the same card replaces its route instantly
  (free). **CLEAR** removes the selected card's route.
- A route needs **at least 2 room stops** to run; otherwise its car parks
  with a "!" and the hint line explains.
- **Speed**: top-right `II` pause / `1x` / `3x` — the grid stays fully
  editable in every state, including paused. **MENU** returns to the boot menu.

## Rules

- **Rooms** (lettered cells): a route passing through a room makes it a
  stop. Cars ping-pong end-to-end along their polyline; at each room stop
  (while the car has work) the **doors cycle**: OPEN 0.5 s (panels visibly
  slide apart) -> EXCHANGE max(0.8 s, 0.35 s x passenger moves this stop;
  unload then load, late arrivals may still hop on) -> CLOSE 0.5 s (nobody
  boards a closing door). Minimum full stop ~1.8 s; busy stops take longer.
- **Idle cars park**: a car with no riders and nobody planning to board it
  waits at its current cell, doors shut — watch for it between spawn pulses.
  (`Car3.home_cell` is a code-only hook: set it and an idle empty car
  deadheads there; the future "default waiting floor" upgrade wires a UI to
  `set_home_cell()`.)
- **Gates** (hazard-striped cells): one car at a time, first-come
  first-served. A car that can't get the lock waits in its current cell with
  a pulsing outline and enters when the gate frees. Everywhere else cars
  ghost through each other — congestion is a gate feature, not a hazard.
- **Passengers**: visitors (green, 90 s patience), patients (blue, 75 s),
  and **execs** (amber ring + briefcase, hasty — 40 s by default, tuned per
  level): execs spawn only at level-designated origin rooms and want only
  level-designated targets (L1: lobby -> penthouse; L3: arms -> penthouse).
  Patience drains only while waiting. Empty patience = Lost +1.
- **Pulse spawning**: spawns come in bursts (per-level size/gap) with quiet
  lulls between; the average per-passenger interval ramps down over the
  session (per-level numbers in `scripts/v3/levels3.gd`).
- **Transfers (the point of the experiment)**: passengers run a time-based
  Dijkstra over the stop graph — every pair of stops on a route is an edge
  costing ride time (path distance / route speed) plus a flat 7 s expected
  wait per leg (raised from 5 s to stay honest against the slower door
  cycle). When riding a slow LOCAL (260 px/s) to a room shared with the
  EXPRESS (520 px/s) is genuinely faster than staying aboard, the passenger
  plans the 2-leg trip on its own. All waiting passengers replan on every
  route commit/clear; riders replan when they step out. No possible path
  shows a "?" bubble until your next redraw fixes it.

## Balance harness (persistent, keep it green)

Fixed-seed headless scenarios prove each level's intended strategy beats the
naive one (naive/intended route sets live in `tests/scenarios3.gd` as data;
assertions in `tests/balance.gd`). One command, from the project root:

```
& "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe" --headless --path . --script tests/run_balance.gd
```

Prints a per-scenario stats table (served, lost, avg/p90 wait, transfers,
gate wait), PASS/FAIL per assertion, and a final `BALANCE: ALL PASS` line
(trust that line over the exit code — the mono wrapper exits 1 benignly).
Tuning lives in `scripts/v3/levels3.gd` (spawn/patience/quota numbers);
never fix a red harness by weakening its assertions.

---

# v2 Network Planner

Implements `docs/v2-spec.md` ("Network Planner", Direction A). Everything
below is unchanged from the v2 build except the MENU button in the HUD.

## Controls (one thumb)

- **Place a card**: tap a card in the bottom inventory panel (it highlights),
  then tap any empty shaft column (they glow). A new elevator serves all
  floors and starts selected.
- **Edit doors**: tap an installed car/column to select it (white outline),
  then tap floor cells in its column to toggle that door ON/OFF (green/red
  pills; minimum 2 doors ON). Toggling everything but two floors off makes an
  express. Tap empty space to deselect.
- **Remove**: with an elevator selected, the red REMOVE button returns its
  card to the inventory (free undo). Riders step out at the nearest floor.
- **Transfer floors** (gold bridge bands, floors 0 and 5, plus 7 in H-3):
  the only floors where a passenger may exit one shaft and walk to another
  mid-journey. Every network edit replans all waiting passengers; "?" means
  no path exists yet.
- **Speed**: `II` pause / `1x` / `3x`; **MENU** returns to the boot menu.

## Card types

| card     | slots | speed    | look                    |
|----------|-------|----------|-------------------------|
| standard | 4     | 300 px/s | gray-blue rect          |
| large    | 8     | 210 px/s | wide rect, slow         |
| express  | 4     | 540 px/s | orange accent, chevrons |

## Passengers

| type      | slots | patience | look              | notes                          |
|-----------|-------|----------|-------------------|--------------------------------|
| visitor   | 1     | 90 s     | green circle      |                                |
| patient   | 1     | 75 s     | blue circle       |                                |
| gurney    | 2     | 60 s     | wide orange rect  | from H-2                       |
| emergency | 1     | 30 s     | red, pulsing      | from H-3; always needs floor 7 (SURGERY) |

## Campaign

Serve the quota before losing `max_lost` passengers. Your network, door
settings, and inventory PERSIST between levels — set yourself up early.

| level | quota | max lost | spawn every | new stuff                        |
|-------|-------|----------|-------------|----------------------------------|
| H-1   | 15    | 5        | 6.0 s       | placement + door toggles, transfers at 0 & 5 |
| H-2   | 25    | 5        | 4.5 s       | gurneys (2 slots); reward from H-1: large or express |
| H-3   | 35    | 5        | 4.0 s       | emergencies (30 s, to SURGERY); floor 7 becomes a transfer; reward from H-2: express or standard |

Win a level: pick 1 of 2 reward cards, then the next level starts. Lose:
retry the same level — network intact, counters reset. Finish H-3:
campaign-complete overlay with totals and a full restart.

---

## Files

- `scenes/menu.tscn` + `scripts/menu.gd` — boot menu (project main scene).
- `scenes/main.tscn` — v2: Main / Building / Elevators / Passengers / HUD.
- `scripts/main.gd`, `levels.gd`, `pathfind.gd`, `building.gd`,
  `elevator.gd`, `passenger.gd`, `hud.gd` — v2 game (see v2 section; only
  hud.gd gained a MENU button).
- `scenes/v3_select.tscn` + `scripts/v3/select3.gd` — v3 level select.
- `scenes/v3_main.tscn` — v3: Main3 / Grid / Cars / Passengers / HUD.
- `scripts/v3/levels3.gd` — the data-driven level table (grids, cards,
  quotas, pulse-spawn configs, type mixes, exec rooms, trip tables, intros)
  — this is where balance tuning lives.
- `scripts/v3/grid.gd` — per-level maze data (X-1 layout as the default),
  geometry helpers, and all grid drawing (rooms, hazard-striped gates,
  route polylines, drag preview).
- `scripts/v3/route.gd` — a drawn route: cell polyline + stop queries.
- `scripts/v3/main3.gd` — v3 controller: level loading, drag-to-draw
  editing, gate FIFO mutexes, seeded-RNG pulse spawning, replanning,
  session flow, time scale.
- `scripts/v3/pathfind3.gd` — time-based Dijkstra over the stop graph
  (ride time + 7 s per-leg wait + sub-second per-passenger tie-break so
  identical routes share load).
- `scripts/v3/car3.gd` — polyline ping-pong movement, door-phase stops
  (open/exchange/close), idle parking + `home_cell` hook, slot-aware
  load/unload, gate acquire/wait/release.
- `scripts/v3/passenger3.gd` — visitor/patient/exec, patience (per-level
  overrides), "?" bubble, wait/transfer stats.
- `scripts/v3/hud3.gd` — top bar, route card chips, CLEAR, hint line,
  intro/win/lose overlays.
- `tests/run_balance.gd`, `tests/balance.gd`, `tests/scenarios3.gd` — the
  persistent balance harness (see "Balance harness" above).

Everything is spawned from code (`Car3.new()` / `Passenger3.new()` etc.), so
tuning lives in script constants and the `levels3.gd` table.
