# Elevator Prototypes — v2 Network Planner + v3 Path Drawing

Two chill "design the system, watch it run" prototypes built in Godot 4.2
(GDScript, programmer art only), sharing one project. Boot into a tiny menu
and pick a mode:

- **v2 Network Planner** (`docs/v2-spec.md`) — cutout side view of a 10-floor
  hospital with 4 vertical shafts. Place elevator cards, toggle doors,
  passengers transfer between shafts on transfer floors.
- **v3 Path Drawing** (`docs/v3-spec.md`) — a 7x10 maze of the building.
  Drag each elevator's route as a polyline (up/down AND left/right), detour
  around blockages, squeeze through one-car-at-a-time gates, and let
  local-to-express transfers emerge from time-based pathfinding.

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

Single experimental level **X-1**: serve **30** passengers before losing
**8**. Win offers "Keep playing" (endless, spawn ramp continues) or
"Restart"; lose offers "Retry" (routes stay drawn, counters reset).

## Controls (one thumb)

- **Draw a route**: tap one of the 3 card chips in the bottom panel (LOCAL A,
  LOCAL B, EXPRESS), then drag across the grid. The stroke starts on any open
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

- **Rooms** (lettered cells `A`..`M`): a route passing through a room makes
  it a stop. Cars ping-pong end-to-end along their polyline and dwell 1.0 s
  at each room stop to unload then load (4 slots per car).
- **Gates** (hazard-striped cells): one car at a time, first-come
  first-served. A car that can't get the lock waits in its current cell with
  a pulsing outline and enters when the gate frees. Everywhere else cars
  ghost through each other — congestion is a gate feature, not a hazard.
  Gates: (3,3) and (3,7) are the only mid-building horizontal crossovers;
  (4,6) sits on the single straight lobby-to-penthouse corridor (column 4).
- **Passengers**: visitors (green, 90 s patience) and patients (blue, 75 s)
  spawn at rooms wanting other rooms (60% of trips involve a lobby room).
  Patience drains only while waiting. Empty patience = Lost +1. Spawn
  interval ramps 5.5 s -> 3.0 s over 4 minutes.
- **Transfers (the point of the experiment)**: passengers run a time-based
  Dijkstra over the stop graph — every pair of stops on a route is an edge
  costing ride time (path distance / route speed) plus a flat 5 s expected
  wait per leg. When riding a slow LOCAL (260 px/s) to a room shared with
  the EXPRESS (520 px/s) is genuinely faster than staying aboard, the
  passenger plans the 2-leg trip on its own. All waiting passengers replan on
  every route commit/clear; riders replan when they step out. No possible
  path shows a "?" bubble until your next redraw fixes it.

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
- `scenes/v3_main.tscn` — v3: Main3 / Grid / Cars / Passengers / HUD.
- `scripts/v3/grid.gd` — maze data (7x10 layout string per spec), geometry
  helpers, and all grid drawing (rooms, hazard-striped gates, route
  polylines, drag preview).
- `scripts/v3/route.gd` — a drawn route: cell polyline + stop queries.
- `scripts/v3/main3.gd` — v3 controller: drag-to-draw editing, gate FIFO
  mutexes, spawning, replanning, session flow, time scale.
- `scripts/v3/pathfind3.gd` — time-based Dijkstra over the stop graph
  (ride time + 5 s per-leg wait).
- `scripts/v3/car3.gd` — polyline ping-pong movement, 1.0 s room dwells,
  slot-aware load/unload, gate acquire/wait/release.
- `scripts/v3/passenger3.gd` — visitor/patient, patience, "?" bubble.
- `scripts/v3/hud3.gd` — top bar, route card chips, CLEAR, hint line,
  intro/win/lose overlays.

Everything is spawned from code (`Car3.new()` / `Passenger3.new()` etc.), so
tuning lives in script constants.
