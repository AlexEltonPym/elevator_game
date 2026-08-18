# Game Design Concepts — the FUN we're aiming for

Companion to `game_level_rules.md` (hard constraints). This doc is the *why*: the puzzle
verbs and challenge patterns a good level should create. Rules say what's legal; concepts
say what's fun. Design levels to produce these feelings; don't railroad a single optimum.

## Core verb: disjoint snake-fitting

You draw one route per lift. Routes are **disjoint** (no two share a cell — every tunnel
holds one lift), so each route you commit becomes walls the next must weave around. The
puzzle is fitting all the snakes so every demanded connection is made. It's numberlink with
elevators: connect the rooms each lift must serve, without the snakes colliding.

**Softness is the goal.** There should be *many* valid weavings, and finding a good-enough
fit is the joy — not converging on one provably-optimal answer.

## Challenge patterns (the good stuff)

- **The threaded snake (multi-stop + escape).** A lift must hit several docks in one
  continuous route AND still be able to *get out* to reach its remaining targets. Placing
  docks in little pockets means a naive straight run misses some or dead-ends — so the
  player adds *wiggles* to collect them all and still thread free. (This is the moment that
  prompted this doc: a local route weaving to hit two docks and still exit toward a far
  apartment.) Design for it by putting a lift's targets in spots a straight line can't
  connect without doubling back.

- **The crossing forcer.** One lift's *required* connection cuts across the map (e.g. the
  cargo run from the delivery bay to the cafe), splitting the free space — so every other
  lift has to route *around* it. Whoever commits first shapes the puzzle for the rest;
  order of drawing becomes strategy.

- **The pocket / cul-de-sac.** A dock tucked in a dead-end forces a there-and-back wiggle
  (in and out on different cells, since you can't revisit). Rewards careful threading.

- **The long-way-around (why EXPRESS earns its place).** When the direct lane is taken by
  another snake, a lift must take a longer detour. The fast EXPRESS is the natural pick for
  those long routes — its speed pays for the extra distance the fit forces on it. So the
  express's value emerges from the *routing*, not from a bolted-on "skip" mechanic. (See
  the momentum investigation: demand alone never makes skipping optimal — obstacles/fitting
  do. Momentum/heatmap is flavour on top of the routing puzzle, not the puzzle.)

- **The shared-dock transfer.** Two rooms sharing one horizontal dock (or a room both lifts
  serve) is a transfer point — lets a passenger hop lifts, and lets the player split
  coverage instead of forcing one snake to reach everything.

## Difficulty dials

Tension comes from **competition for space**: number of disjoint routes vs. open area,
density/placement of room-islands, and forced crossings. Loosen by opening space or fewer
lifts; tighten with pockets, a bisecting cargo run, or another lift. Keep it SOLVABLE with
room to spare early; a level with no valid disjoint fit is broken (verify by actually
threading all lifts, or with the route tooling).

## Anti-patterns

- A level with one obvious good route and nothing to discover.
- Over-density: so many rooms/obstacles that NO disjoint fit exists (broken, not hard).
- Railroading toward a single optimum (kills the softness).
