# v5 "Rooms" — feel-prototype spec

A prototype to FEEL a new spatial model. Keeps the v4 game's core verb (draw omnidirectional
elevator routes, magnetic drawing, cars with acceleration/doors/width/loops/gates) and changes
only what a "room" is and how elevators serve it. This is a fork: v4's 15 verified levels, the
balance suite, the depth tooling and the fingerprint stay UNTOUCHED. No verification pipeline
here yet — build it to play, not to prove.

## What changes vs v4

**Rooms are multi-cell areas, not points.** In v4 a room is a single grid cell that the route
passes THROUGH. In v5:
- A room is a connected set of cells with an id/letter and a type (lobby, office, department
  store, …). Mostly **2x1**; a few odd shapes (e.g. a **2x3** "department store"). Rooms are
  **NOT routable** — elevators never enter a room; they run in open cells BESIDE it.
- Most of the grid stays **empty/open** — do NOT tile the building. Routing freedom is the point.

**Dropoff points are BAKED INTO the room** (authored, not emergent from adjacency). Each room's
definition includes a FIXED set of dropoff points — like doors on specific sides. A plain 2x1
room might have exactly ONE dropoff; a hallway piece several; a big room 3+ (a main hub).
- An elevator **serves** a room if and only if its drawn route (open cells, omnidirectional,
  exactly as v4) passes orthogonally adjacent to one of that room's DESIGNATED dropoff points —
  NOT just anywhere along the room's edge. A one-dropoff room is a real placement constraint;
  a multi-dropoff room can be served from several spots and by several elevators.
- Represent a dropoff concretely (a specific room cell flagged as a dropoff, facing the open cell
  an elevator docks in) and DRAW it clearly so the player sees where an elevator must reach.
- One route reaching two rooms' dropoffs serves both.
- **A room whose dropoffs are reached by two+ different elevators => a transfer room**: a
  passenger alights at one dropoff and boards another. A 3+-dropoff hub is where many elevators
  converge. OCCASIONAL level feature, not on every level.

**Destinations are rooms.** Passengers spawn in a room (origin) and want another room (dest),
shown as the room (letter/colour), not a door. They wait rendered INSIDE the room area. Boarding:
when a serving elevator stops at a dropoff adjacent to their room with space and a useful
direction, they board (a short, near-free walk from the room to that dropoff cell — do not build
a full pedestrian sim; treat the in-room walk as ~0–1 s). They ride, alight at a dropoff adjacent
to the destination (or a transfer room), and are served on reaching the destination room.

**Variable elevator count.** Each level defines its roster; it can be **1** (R-1 is one
elevator). RUN requires each PROVIDED elevator to have a legal route; unused/absent cards are not
required (drop the v4 "every card must be routed" assumption — gate on the level's actual roster).

## Pathfinding (adapt v4's time-based Dijkstra)

Nodes = ROOMS. An elevator E contributes an edge between any two rooms it serves (adjacent to),
cost = ride time along E between their dropoff cells + door/wait terms (reuse v4's cost model).
A transfer room (served by 2+ elevators) is where legs join. Keep it time-based so "ride local to
a shared room, switch to the express" still emerges. The in-room walk is a small constant added
to a leg, not its own search.

## Reuse (copy/adapt from v3/v4, do not entangle v4)

Reuse the magnetic route-drawing (stroke logic), car kinematics + acceleration, door phases,
width (car-vs-corridor), loops, and gate mutex where they carry over. It is fine to duplicate v3
code into v5 scripts rather than share — prototype speed over DRY, and v4 must not be destabilised.

## Prototype levels (hand-made, feel-focused, no axioms/verification)

Enough to feel the model, not a campaign:
- **R-1 "One Lift"** — 1 elevator, ~3 small 2x1 rooms in open space. Draw one route past them,
  watch people get served. Near-unloseable.
- **R-2 "Double Duty"** — 1–2 elevators; a layout where one route naturally serves two rooms.
- **R-3 "Crossing"** — a transfer room with two dropoffs from two elevators; show a passenger
  ride, alight, walk across the room, board the other elevator.
- **R-4 "Big Store"** — include one odd 2x3 room (department store) among 2x1s, lots of empty
  grid, 2–3 elevators; show shape variety and routing freedom.

## In / out of scope

IN: the room model, adjacency service, room destinations, in-room queuing + tiny walk, transfer
rooms, variable roster, the 4 hand levels, and a way to launch the v5 prototype from the game
(a "v5 ROOMS (prototype)" entry on the level select or a separate scene — minimal, must not
disturb v4's worlds).

OUT (until the feel is validated): depth tooling / balance axioms / scorecheck / fingerprint for
v5, tutorials, a full campaign, the export schema, escalators as a real mechanic (flavor only).

## Rendering

Rooms as filled, labelled shapes with waiting people inside; elevators run in the open cells
beside them; mark dropoff cells subtly. Keep the calm, decluttered look from the UI pass — the
whole point is that "people want a room" reads at a glance. Reuse the grid-fit scaling so any
level size fits.

## Success = a good feel

The question this answers: does "people want rooms, elevators pass beside them, occasionally you
build a transfer room" feel clearer and better than v4's room-as-point model? If yes, we invest
in porting the tooling/levels. If no, we've spent a prototype, not a rebuild.
