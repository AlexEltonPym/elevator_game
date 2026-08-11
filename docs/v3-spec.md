# Prototype v3 spec — "Path Drawing" experiment

Experiment: instead of fixed vertical shafts + door toggles (v2), the player **drags each
elevator's route** as a polyline through a maze-like grid of the building. Elevators move
up/down AND left/right along their drawn path. Blockages force detours ("up 2, then right");
gate cells allow only ONE elevator through at a time (throughput chokepoints). Transfers:
people ride a local to the nearest shared stop and switch to an express — this must emerge
from time-based pathfinding, not scripting.

Chill pacing as in v2: pause/1×/3×, edit anytime, generous patience. v2 must remain playable:
boot into a tiny menu scene with two buttons — "v2 Network Planner" and "v3 Path Drawing".

## Grid & maze

7 columns × 10 rows (row 0 = bottom/lobby). Cell types:
- `.` open shaft — routes may pass
- `#` blocked — routes may NOT pass
- `R` room — routes may pass; if a route passes through it, it's a **stop** on that route.
  Passengers spawn at rooms and want to reach other rooms; they queue beside the room.
- `G` gate — open like `.`, but only one elevator may occupy it at a time (see Gates).

Layout, top row first (row 9 → row 0), each string is cols 0→6:

```
row 9:  R . . # R . R      (penthouse rooms)
row 8:  . # . # . # .
row 7:  R # . G . # R
row 6:  . # # # G # .      (central artery squeezes through the gate at col 4)
row 5:  . . R # R . .
row 4:  # # . # . # #
row 3:  R . . G . . R
row 2:  . # . # . # .
row 1:  . # . # . # .
row 0:  R . R . R . R      (lobby)
```

Intended topology (verify in smoke tests): col 4 is the only straight lobby→penthouse
artery and it passes gate (4,6); the left tower above row 3 is reachable only by winding
col 2 → row 5 → col 0; the right edge col 6 climbs freely but is cut at (6,4), rejoining
via row 3. Gates (3,3) and (3,7) are the only mid-building horizontal crossovers.

## Routes (the core interaction)

- 3 elevator cards: 2× standard (capacity 4, 260 px/s), 1× express (capacity 4, 520 px/s,
  accent color + chevrons). One car per route. No rewards/economy in this experiment.
- Tap a card chip (bottom panel) → draw its route by dragging across the grid: start on any
  open cell, extend through orthogonally adjacent non-blocked cells, no revisiting a cell
  within the same route. Ignore illegal moves mid-drag (stroke continues from last valid
  cell only into legal neighbors). Dragging back onto a cell already in the stroke
  RETRACTS it to that cell (ONI-pipe-style mid-draw undo). Live preview while dragging;
  release commits.
- Drawing again for the same card REPLACES its route (free redraw — instant, no cost).
  "Clear" button when a route's card is selected. Routes of different cars MAY overlap cells.
- A committed route with fewer than 2 room-stops shows a warning hint ("needs 2 stops");
  its car doesn't run.
- The car ping-pongs along the polyline end↔end, dwelling 1.0 s at room cells to
  unload-then-load (slot-aware). Riders alight only at room stops.

## Gates (throughput challenge)

- A gate cell is a mutex: a car must acquire it to enter; otherwise it waits in its current
  cell (small "waiting" indicator, e.g. a pulsing outline). Lock released on fully exiting
  the gate cell. First-come-first-served queue. Because gates are single cells and transit
  always completes, no deadlock is possible.
- Non-gate cells have NO occupancy rule (cars ghost through each other) — congestion is a
  designed feature of gates, not an emergent everywhere-hazard.
- Draw gates with hazard-striped borders; visibly show a queued car's wait.

## Passengers & pathfinding

- Types: visitor (green, 1 slot, 90 s patience) and patient (blue, 1 slot, 75 s). Spawn at
  a random room, destination another random room; 60% of trips involve a lobby room. Spawn
  interval starts 5.5 s, ramps slowly to 3.0 s over 4 minutes. Patience drains only while
  waiting.
- **Time-based Dijkstra** over the stop graph: nodes = rooms; for each route, edge between
  every pair of its room-stops with cost = ride time along the route between them (path
  distance / route speed) + a flat 5 s expected-wait; each additional leg (transfer) adds
  its own 5 s wait. Passenger takes the min-time path. This is what makes "ride local to
  the express stop and transfer" happen naturally when the express is genuinely faster.
- Replan all waiting passengers on ANY route commit/clear; riders replan on alight. No path
  → "?" bubble, patience keeps draining, replanned when the network changes.
- Lost passenger (patience empty) → Lost +1.

## Session structure

Single experimental level "X-1": win at Served 30 before Lost 8. Win overlay offers
"Keep playing" (endless, ramp continues) or "Restart". Lose → retry overlay (routes kept,
counters reset). HUD like v2: Served n/30, Lost n/8, pause/1×/3×.

## Layout (portrait 720×1280)

- Top HUD ~92 px. Grid area: 7×10 cells at 90 px → 630×900, x-centered (45..675),
  y ≈ 100..1000. Bottom panel (~1010..1280): 3 route card chips (colored, show route
  length + stop count), Clear button, hint line.
- Reuse v2's project settings; touch drag via InputEventScreenDrag/Touch; drag targets are
  whole 90 px cells so fat fingers are fine.

## Engineering notes

- Keep v2 fully intact: rename its entry scene if needed, add scenes/menu.tscn as the
  project main scene with the two mode buttons. Shared-looking code (patience bars, HUD
  patterns) may be duplicated into v3 scripts rather than refactored — prototype speed
  over DRY; do not destabilize v2.
- Suggested new files: scripts/v3/grid.gd (maze data + drawing), route.gd (polyline data +
  editing), car3.gd, passenger3.gd, pathfind3.gd, main3.gd, hud3.gd; scenes/v3_main.tscn.
- Game-side time_scale like v2 (no Engine.time_scale).

## Out of scope

Sound, art, passenger variety beyond 2 types, campaign/levels, economy, tenant events.
This build answers: does dragging maze routes + gate throughput + emergent express
transfers FEEL like a good planning game?
