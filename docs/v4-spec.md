# v4 spec — plan-then-run, and the WIDTH system

Two phases. Phase 1 is the loop restructure; phase 2 is the mechanics.
Approved from `docs/mechanics-catalogue.md`: #24 acceleration, #1 cargo (as delivery people),
#26 small fast pod, #17 type-restricted corridors (via width), #29 home floor.

---

# PHASE 1 — plan then run

The core loop becomes **design → commit → watch → learn → retry**. No mid-run editing.

- **BRIEFING** — before planning: the level's name/thesis line, the **elevator roster** you get
  (card types with their width/speed/capacity), and the **passenger mix** to expect (which types,
  roughly how many). This must telegraph enough to plan against. Button: PLAN.
- **PLAN** — the grid is fully editable, no clock running, no passengers. Draw/redraw/clear
  routes freely; set home cells (phase 2). Button: RUN (disabled until every card that must run
  has a legal route — reuse the existing >=2-room-stop rule).
- **RUN** — simulation runs. **Route editing is disabled entirely**: no redraw, no clear, no
  relocation, no additions. Speed controls (pause / 1x / 3x) stay live, since watching is now the
  point. Button: ABORT (back to PLAN, counters reset).
- **RESULT** — win or lose overlay with the stats. Buttons: RETRY (back to PLAN with your routes
  intact), NEXT LEVEL (on win), LEVELS.

Consequences to handle:
- **Redeploy is out of the main loop.** The recall/ghost-countdown machinery stays in the code
  (it is still correct, and a future "place-only mid-run" mode may want it) but cannot trigger
  during RUN. Every route commit now happens in PLAN, so every car deploys instantly.
- Watch mode (NAIVE/THESIS/BEST) skips BRIEFING/PLAN and goes straight to RUN, as today.
- The depth tooling already models exactly this (commit a route-set, then simulate), so the
  optimizer and the player now solve the *same* problem. Say so in the report.
- Levels gain explicit `roster` (which cards) and `people` (which passenger types) fields if not
  already implied by existing data; the briefing reads from them so it can never drift.

---

# PHASE 2 — the WIDTH system + acceleration + home floor

## Width: one number, three places

**Passengers have a width** (how much doorway they need):

| type | width | notes |
|---|---|---|
| visitor / patient / exec | 1 | unchanged |
| couple | 2 | two people who will only travel together |
| gurney | 2 | existing type, re-expressed as width |
| delivery | 2 | courier + 1 crate |
| big delivery | 3 | courier + 2 crates |

**Elevators have a width**, and **capacity = 2 x width**, counted in width-units:

| car | width | capacity | character |
|---|---|---|---|
| pod | 1 | 2 | fastest, sharpest acceleration; **width-1 passengers only** |
| standard | 2 | 4 | the workhorse |
| cargo | 3 | 6 | slowest, worst acceleration; the only car that takes big deliveries |

- A passenger may board only if `passenger.width <= car.width`.
- A passenger consumes `passenger.width` capacity units. So a standard car holds 4 ordinary
  people, or 2 couples, or 1 couple + 2 ordinary.
- Speed and acceleration are SEPARATE axes from width — an express is a fast width-2 car, not a
  different width. Keep them independent so they can be ablated separately.

**Corridors have a width** (`gate` cells gain a width number):

- A car may enter only if `car.width <= corridor.width`.
- Cars may share a corridor while the **sum of widths inside is <= corridor.width**.
- So a width-3 corridor takes 3 pods, or 1 cargo, or 1 pod + 1 standard.
- **Default corridor width is 2**, which reproduces today's behaviour exactly (every current car
  is width 2, and 2+2 > 2, so it stays a one-car mutex) — existing levels must not change.
  Verify this with the fingerprint check, not by argument.
- A width-1 corridor is therefore a pod-only passage; a width-2 corridor bars the cargo car.
  That IS mechanic #17, falling out of the same number.

## Acceleration (#24)

Cars gain `accel` (and matching decel) instead of instant speed changes:
- The car ramps toward its max speed and must decelerate to arrive stopped at a stop cell, at a
  blocked gate, or at the end of a ping-pong line.
- Wider/heavier cars accelerate worse: pod sharp, standard medium, cargo sluggish.
- **The design point:** every stop now costs momentum, not just door time. Long uninterrupted
  runs are where a heavy car wins; stop-heavy milk runs are actively wrong for it. Express vs
  local becomes physical rather than a door-time technicality.
- Queueing at a gate now also costs momentum — that is intended, and makes contention bite.
- Must stay deterministic under the fixed-step `advance(dt)`; sub-step accuracy matters, so
  integrate carefully (do not let large dt overshoot a stop). Prove determinism as usual.
- Pathfinding: `Route3.ride_dist` currently prices distance/speed. With acceleration, a many-stop
  leg is genuinely slower than distance implies. Improve the cost estimate to account for stops
  between two points (a per-stop time penalty is enough — do NOT simulate inside the planner),
  and report what that does to transfer behaviour.

## Home floor (#29)

- In PLAN, with a card selected, the player may set a **home cell** on that card's route (tap a
  cell of the route to toggle it as home; tapping the current home clears it).
- An idle EMPTY car with a home set deadheads there and waits; without one it parks where it is
  (today's behaviour). `Car3.home_cell` and `set_home_cell()` already exist.
- Draw it clearly: a small house/anchor marker on the route cell, in the card's colour.

## Axiomatic levels — one per mechanic

Each new mechanic gets its own level proving it earns its place, held to the CURRENT bar:
- thesis WINS >= 15/16 held-out seeds, naive LOSES >= 15/16,
- uniform-random route-set win rate <= 5%,
- tuned only against `SEEDS_TUNE`, asserted on `SEEDS_ASSERT`,
- every room has demand and the thesis covers every room.

1. **W-1 "Freight"** (#1 delivery + width): big deliveries (width 3) spawn at one end and must
   reach the far end; only the cargo car can carry them. *Naive:* three general-purpose routes
   that cover everything and strand the deliveries. *Thesis:* dedicate the cargo car to a freight
   shuttle and cover the rest with the others.
2. **W-2 "Narrows"** (#17 via width): the short path is a width-1 corridor (pods only); the cargo
   route must take a long way around. *Naive:* route everything down the short path, which the
   wide cars cannot use. *Thesis:* pods through the narrows, wide cars around.
3. **W-3 "Momentum"** (#24 acceleration): long uninterrupted runs vs stop-heavy alternatives.
   *Naive:* one stop-everywhere line per card. *Thesis:* the heavy car runs a long express leg,
   the pod does the local hops.
4. **W-4 "Home"** (#29): demand that arrives in predictable bursts at a known room, so
   pre-positioning an idle car beats reacting. *Naive:* correct routes, no home set. *Thesis:*
   same routes plus a home cell. **This level is the honest test of #29** — if it can't clear the
   bar, the mechanic is chrome and we should say so rather than ship it.

## Ablation (the reason we built the depth tools)

After the levels exist, run restricted play to answer, with numbers:
- Does **capacity** add anything once acceleration exists, or is it chrome? (My prediction on
  record: acceleration carries most of the depth, exclusivity/width adds a real second
  constraint, capacity-alone measures as chrome.)
- Does **#29 home floor** beat "no home" on any level other than W-4?
- **Express acceleration model: accel-by-width vs accel-by-speed-class.** Today ramp is a
  function of width alone, so a 520 px/s express and a 260 px/s standard share a ramp and are
  identical over one cell — which pushed L2 off its corridor thesis onto cabin size. Implement an
  alternative where a car's acceleration derives from its top speed (faster car = it also takes
  longer to reach that speed, OR the opposite — try both framings) as a config flag, and measure
  both models across all levels: which gives express a more legible, on-thesis identity, and which
  produces higher skill_gap / more distinct winning strategies. Pick the winner by the numbers and
  say why; if it's close, keep accel-by-width (simpler) and record that.
Report each as best-achievable-score with the mechanic available vs forbidden.

## Corridor-rejection UX (ship before W-2)

Committing a route that sends a car down a corridor narrower than the car is currently refused
silently (the card just stays unrouted). Before W-2 "Narrows" ships:
- On a rejected commit, show the reason on the existing hint line (e.g. "cargo can't fit that
  corridor — it needs width 3"), in the card's colour, for a few seconds.
- Ideally telegraph it DURING drawing: while dragging a too-wide car's stroke into a narrower
  corridor cell, treat that cell like a wall (the magnetic head won't enter it), so the rejection
  is felt as resistance rather than as a silent commit failure. If that's cheap, prefer it; the
  hint line is the fallback for the fast-drag / straight-fill path that reaches the cell anyway.

## Retuning warning

Acceleration changes every car's effective speed, so **every existing level will need retuning**
to hold its axioms. Budget for that; do not weaken assertions to accommodate it.
