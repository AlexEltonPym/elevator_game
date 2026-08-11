# v3 balance pass + test-level suite

Goal: get TIMING and STRATEGIC DEPTH working. Each test level is a thesis about strategy
("here, the express is the answer"), and a persistent headless balance harness proves the
intended strategy beats the naive one. Balance numbers below are STARTING points — the
harness loop is the authority; tune until the per-level assertions pass.

## Global balance changes (all v3 levels)

### Door timing (slower, watchable)
Replace the flat 1.0 s dwell at room stops with phases:
- OPEN 0.5 s (doors visibly slide open on the car)
- EXCHANGE: unload then load; duration max(0.8 s, 0.35 s × passenger-moves this stop)
- CLOSE 0.5 s (doors slide shut)
Late arrivals may board during OPEN/EXCHANGE only, never CLOSE. Minimum full stop ≈ 1.8 s.
Passengers keep their pathfinding wait constant in sync (raise the per-leg flat wait from
5 s to 7 s so plans stay honest).

### Idle behavior
Unchanged: a car with nothing to do waits at its last floor, doors closed. With the slower
pacing this should now VISIBLY happen between demand pulses. Add (code-only, no UI) a
`home_cell` variable on Car3 — when non-null, an idle empty car travels there and waits.
Leave it null everywhere; it's the hook for a future "default waiting floor" upgrade.
Structure it so wiring a UI to it later is trivial.

### Pacing
Chill overall: spawn intervals per level below; patience is generous except for hasty types.
Spawns come in gentle PULSES (e.g. every ~25 s a burst of 2-4 within a few seconds, quiet
between) rather than a metronome — pulses are what make idle moments and door timing read.

## New passenger type

| type | slots | patience | visual        | behavior |
|------|-------|----------|---------------|----------|
| exec | 1     | 40 s     | amber, small briefcase tick or ring | spawns ONLY at level-designated origin rooms, destination ONLY level-designated target rooms (the "hasty penthouse guys") |

Existing visitor (90 s) / patient (75 s) unchanged.

## Level system

v3 becomes data-driven: `scripts/v3/levels3.gd` holds per-level {id, name, grid strings,
cards, quota, max_lost, spawn: {interval_start, interval_end, ramp_seconds, pulse config},
mix (type weights), exec_origins/exec_dests (cells), intro text}. Entering v3 from the boot
menu opens a LEVEL SELECT list (big buttons: id + name + one-line thesis). Win overlay:
Next Level / Level Select / Keep Playing. Lose: Retry (routes kept) / Level Select.
Keep the existing maze as the last entry, "X-1 Sandbox".

## Test levels (the suite)

Grids use the legend from v3-spec.md (`.` open, `#` blocked, `R` room, `G` gate), row 0 =
bottom. Exact L2/L3 grids are the builder's to design within the stated constraints — they
must satisfy the harness assertions, and simpler/smaller is better (these are test cases,
not content). Cell size may shrink per level if a grid needs more columns; keep cells ≥80 px.

### L1 "Tower" — thesis: dedicate the express
- Linear tower, NO maze: a single column of rooms (lobby row 0 through penthouse row 9,
  rooms every other row plus lobby and penthouse), open shaft cells beside them; no gates,
  no blockages. Routes will all be near-identical vertical lines — the strategy is purely
  WHICH FLOORS each card serves... which in v3 terms means how LONG each route is drawn
  (a lobby→penthouse express line vs short local lines over the low rooms).
- Cards: 2× standard, 1× express. Mix: visitor .45 / patient .30 / exec .25;
  exec origins = lobby, dests = penthouse (+ optionally the room one below it).
- Start interval ~6.5 s → 4.0 s over 3 min, in pulses.
- HARNESS: naive = all three cards drawn full-height (everyone serves everything);
  intended = express drawn lobby→penthouse only (it stops only at rooms it passes — full
  height passes all rooms... therefore design the room column so an express CAN skip:
  put low/mid rooms on a SIDE column reachable by a parallel line, penthouse + lobby on the
  main spine, so a straight spine line passes only lobby/penthouse = a true express).
  Assert: intended wins quota with lost ≤ 2; naive loses ≥ max_lost before quota (execs
  starve waiting for cars busy with locals). Tune spawn/patience until both hold.

### L2 "Detour" — thesis: the long way around becomes optimal
- A gate chokepoint on the short path between the lower rooms and upper rooms, plus a
  LONG gate-free perimeter path (roughly 2.5-3× the ride distance). 3× standard cards.
- Demand heavy enough that two routes through the gate saturate it (cars queue several
  seconds per transit) — the third card routed the long way must outperform adding it
  through the gate.
- HARNESS: naive = all 3 routes through the gate; intended = 2 through gate + 1 perimeter.
  Assert: intended wins with lost ≤ 3; naive accumulates ≥ 2× intended's lost (or outright
  loses); and measured gate wait time per car in naive ≥ 2× intended.

### L3 "Junction" — thesis: feeder + express transfer
- An express spine (lobby, mid HUB room, penthouse) and side-arm rooms reachable only by
  short feeder lines that pass the HUB. Passengers from arms to penthouse should ride
  feeder → transfer at HUB → express.
- Cards: 2× standard (feeders), 1× express (spine).
- HARNESS: intended = feeders + spine sharing the HUB stop. Assert: wins with lost ≤ 3 AND
  ≥ 40% of served arm→penthouse passengers used a 2-leg plan (count actual transfers);
  naive = three direct winding routes (no shared hub) is worse on lost count.

### X-1 "Sandbox" — existing maze, existing tuning (only the global door/pulse changes
apply). No harness assertions beyond "still winnable by the old smoke strategy".

## The balance harness (PERSISTENT — this is a deliverable, not scaffolding)

- `tests/balance.gd` (+ whatever helpers): runs headless at high time scale with a FIXED
  RNG seed per scenario. Scenario = level + scripted route set (the naive/intended routes
  above, stored as data). Runs each scenario to win/lose/timeout, collects served, lost,
  avg wait, transfer count, gate wait time.
- Invocation documented in README, e.g.:
  `& "<godot_console.exe>" --headless --path . --script tests/run_balance.gd` (or a scene
  with a `--balance` user arg — builder's choice, but ONE command, documented).
- Prints a per-scenario table + PASS/FAIL per assertion above, exits nonzero on FAIL (as
  well as possible given the mono wrapper's benign exit-1; print a final ALL PASS line).
- Tuning loop: adjust level spawn/patience numbers (NOT the assertions) until all pass.
  If an assertion is truly unreachable, the level design is wrong — redesign the grid, and
  note it in the final report.

## Out of scope
Home-floor upgrade UI, economy/cards-as-rewards for v3, sound, art, new gates in X-1.
v2 untouched.
