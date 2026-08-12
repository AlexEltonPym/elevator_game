# Mechanics catalogue — for approval

A menu of candidate mechanics, numbered for picking. Nothing here is built yet.

**The bar every entry must clear.** The depth run showed 27–47% of *uniformly random* route-sets
win our current levels: random plans are accidentally good because generic coverage is enough.
So the question for each mechanic is not "is it flavourful" but **does it punish generic coverage
and create a decision?** Each entry states the decision it forces and the axiom that would prove
it earns its place — a level where a plan ignoring the mechanic reliably LOSES and a plan using it
reliably WINS, across a seed set, with random plans near 0% win rate.

Cost: **S** = a few hours, **M** = a day-ish, **L** = multi-day / touches pathfinding.

---

## A. People — passenger types

Passengers currently differ only in slots, patience, and where they spawn. These add
*routing constraints*, which is what actually shapes a network.

1. **Cargo/sumo passenger (exclusive)** — S. Takes 2–3 slots AND can only ride a car with the
   `freight` flag. *Decision:* one car must be dedicated to serving their rooms; that car's route
   is then unavailable for general coverage. *Axiom:* a level where freight demand is concentrated
   at the far end of the map, so a generic all-cars-everywhere plan strands them.
2. **Hospital bed / gurney (exclusive + slow load)** — S. 2 slots, freight-only, and doubles the
   door exchange time at its stops. *Decision:* freight routes want FEW stops, pushing you toward a
   dedicated shuttle rather than a long milk run.
3. **Group / family (indivisible)** — M. 3 passengers that will only board together; they wait
   until a car arrives with 3 free slots. *Decision:* makes capacity lumpy — a big car earns its
   keep, and heavily-loaded routes starve groups even at high throughput.
4. **VIP with a deadline** — S. Very short patience, but visible from spawn with a countdown ring.
   *Decision:* forces a fast lane you keep clear, not just high average throughput.
5. **Wanderer / low-priority** — S. Enormous patience, no urgency, but counts toward quota.
   *Decision:* filler that rewards a slow milk-run route existing at all; makes "cover everything"
   a legitimate role for one card rather than the default for all three.
6. **Escort pair** — M. Two linked passengers (patient + porter) who must travel together and
   both alight at the destination. Like a group but with a same-destination guarantee.
7. **Transfer-averse passenger** — M. Refuses multi-leg plans; if no direct route exists they wait
   and eventually leave. *Decision:* directly attacks the transfer strategy — you can't hub
   everything. Strong anti-generic-coverage pressure.
8. **Contagious / isolation patient** — M. Must ride ALONE (car takes no other passengers for that
   trip). *Decision:* a throughput tax that makes dedicating a small fast car attractive.
9. **Return-trip passenger** — M. Rides to a destination, waits a fixed dwell, then needs a ride
   back. *Decision:* creates predictable reverse demand and rewards loops with a return leg.

## B. Floors and rooms

10. **Lobby / entrance rooms** — S. Rooms flagged as spawn-heavy sources rather than uniform
    demand. (Partly exists via demand weights; making it explicit and visible is the change.)
11. **Restricted floor (keycard)** — S. A room only certain passenger types may enter or exit.
    *Decision:* forces a route that serves it to be worth the detour for that traffic alone.
12. **Timed floor (shift change)** — M. A room that goes from dormant to a huge burst on a
    schedule telegraphed in the HUD. *Decision:* the mid-game redesign moment — your redeploy
    mechanic finally has a reason to exist. **This is my pick of the section.**
13. **Capacity-limited waiting room** — M. A room holds at most N waiting passengers; beyond that,
    new arrivals leave immediately (counted lost). *Decision:* makes neglect fail fast and loudly
    instead of slowly, and punishes plans that let one room queue forever.
14. **Hazard/service floor** — S. A room that cannot be a stop but is passable — cars may transit,
    never open doors. Shapes geometry without adding demand.
15. **Sky lobby (transfer-only)** — M. A room with no demand of its own that halves the transfer
    wait penalty for passengers changing cars there. *Decision:* makes a deliberate interchange
    point worth building around — SimTower's best idea, made explicit.

## C. Routes, blockages, gates

16. **Mutex-N corridor** — S. Gates that admit N cars at once instead of 1. Trivial generalisation
    of the existing gate group. *Decision:* tunes congestion from hard block to soft friction.
17. **Type-restricted corridor** — S. A corridor only certain car types may enter (e.g. too narrow
    for the freight car, or express-only). *Decision:* geometry stops being uniform — your car
    types now determine which paths exist for them. Strong pick.
18. **One-way corridor** — S. Traversable in one direction only. *Decision:* forces loop thinking
    even outside ring levels, and makes some networks impossible to run as ping-pong.
19. **Toll / slow corridor** — S. A cell that costs extra transit time. *Decision:* a soft version
    of a blockage; makes the long way genuinely competitive without a hard mutex.
20. **Breakable/maintenance corridor** — M. A corridor that closes for a window mid-level, with
    warning. *Decision:* the strongest argument for building a redundant path — and another
    redeploy trigger.
21. **Shared track segment** — M. A corridor where two cars in the same segment must maintain
    spacing (soft follow rather than mutex). More realistic congestion than an on/off lock.
22. **Diagonal / long-jump link** — M. A special cell pair connecting distant parts of the grid
    (a shortcut shaft). *Decision:* creates genuine topology choices in an otherwise flat maze.

## D. Elevators — the cars themselves

23. **Big slow cargo car** — S–M. *Your idea.* See the design note below; my recommendation is
    the combination version.
24. **Acceleration model** — M. Cars have ramp-up/ramp-down rather than instant speed, so each
    STOP costs momentum, not just door time. *Decision:* this is what finally makes express vs
    local a real physical tradeoff rather than a door-time one. **Strong pick, and it's the
    mechanic that makes #23 interesting.**
25. **Double-decker car** — M. Serves two adjacent floors simultaneously at each stop.
    *Decision:* rewards routes whose rooms are vertically paired; a geometry-sensitive upgrade.
26. **Small fast pod** — S. Capacity 2, very fast, cheap. *Decision:* a genuinely different role —
    good for VIPs/deadlines, useless for bulk. Rounds out the car roster.
27. **Paternoster / continuous chain** — L. A shaft with continuous slow-moving compartments: no
    waiting for a car, but slow and fixed-route. *Decision:* an infrastructure-style option that
    trades flexibility for guaranteed frequency.
28. **Fuel/power budget** — M. Each car has an energy budget per level; long routes and frequent
    stops drain it. *Decision:* adds a resource axis to route design (may fight the chill vibe —
    flagging that risk).

## E. Elevator algorithms — droppable behaviours

Your "return to default floor" idea generalises into a whole card category: behaviour modules you
attach to a car. These are cheap to build, highly visible in watch mode, and each creates a real
decision because the right choice depends on the demand shape.

29. **Return to home floor** — S. *Your original idea.* Idle empty car deadheads to a chosen cell.
    The `Car3.home_cell` hook already exists; this needs UI only. *Decision:* pre-positioning for
    predictable demand vs staying where you last were.
30. **Park at demand centroid** — S. Idle car repositions to the busiest waiting room on its route.
    A smarter, automatic alternative to #29 — good as a later-unlocked upgrade.
31. **Skip-when-full** — S. A full car ignores further pickup stops and runs express to its
    drop-offs. *Decision:* big throughput gain on heavy routes, hurts short-hop passengers.
32. **Priority pickup** — S. Car preferentially serves the most impatient waiter on its route
    rather than the nearest. *Decision:* trades average wait for worst-case wait.
33. **Direction lock / sector service** — M. Car only picks up passengers travelling the same way
    it's already going (classic real elevator logic). *Decision:* reduces thrash on long routes.
34. **Timed departure (headway holding)** — M. Car waits at a terminal until a fixed interval has
    elapsed, guaranteeing even spacing. *Decision:* this is how you fix loop bunching — directly
    addresses the L4 problem where staggered loops drift together over time.
35. **Load-threshold departure** — S. Car waits at a stop until it's N% full or a timeout hits.
    *Decision:* efficiency vs latency, very legible in watch mode.
36. **Zoning (floor range lock)** — S. Car refuses to serve stops outside a chosen band of its
    route. Brings back the v2 door-toggle expressiveness inside the v3 route model.

---

## Design note: the big slow elevator (#23)

You asked whether it should be capacity, acceleration, or an exclusive passenger type. They're
three genuinely different mechanics:

- **Capacity alone is the weakest.** A bigger car with no downside is a strict upgrade, and strict
  upgrades create no decision — you just always place it. If capacity is the only axis, the
  mechanic is chrome.
- **Acceleration (#24) is where the interest is.** If a heavy car takes time to reach speed, then
  every stop costs it momentum, and long uninterrupted runs are where it wins. That single rule
  makes it *naturally* an express/bulk vehicle and makes stop-heavy milk runs actively wrong for
  it — a real decision, emerging from physics rather than a rule.
- **Exclusive passengers (#1/#2) make it mandatory rather than optional.** If sumo wrestlers and
  hospital beds can *only* ride the freight car, its route isn't a preference, it's a constraint
  you must satisfy while still covering everything else.

**My recommendation: build all three as separable flags, then test them separately.** That's
exactly what the depth tooling is for — restricted-play ablation can tell us whether capacity adds
anything once acceleration exists, rather than us guessing. My prediction, on record so it can be
falsified: acceleration carries most of the depth, exclusivity adds a second real constraint, and
capacity-alone measures as chrome.

## Suggested first slice, if you want my pick

**#24 acceleration + #1 exclusive cargo + #17 type-restricted corridors + #29 home floor.**
Together they make car types differ *physically*, differ in *what they may carry*, and differ in
*where they may go* — three independent axes that all punish generic coverage, plus one behaviour
card to test whether the algorithm-module idea is fun before we build ten of them.
Each still gets its own axiomatic level so we measure them one at a time.
