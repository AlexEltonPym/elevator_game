# Design Critique — Uplift (Elevator Network Game)

**Role:** skeptical playtester + mobile designer. **Docs reviewed:** `game-design.md`, `competitor-research.md`, `asset-research.md`.

**Verdict up front:** Direction A is the right bet, but the design doc is over-confident about *why* it will be fun and under-specified about the two things that will actually decide it: **edit cadence** (how often the player has a real decision to make) and **transfers** (whether the network can ever be more than "one shaft per demand band"). The doc names "is the AI legible?" as the biggest risk. I disagree — that risk is iterable. The structural risk is that A's decision space saturates in the first two minutes and the rest of the run is a screensaver with a countdown.

---

## 1. Loop-by-loop critique

### Option A — "Network Designer"

**Where the fun actually is, moment to moment.** Not in watching cars move — in the *diagnose → edit → payoff* cycle: spot the swelling queue on 7, realize your express skips it, toggle one door, watch the queue drain. That cycle is the whole game. Every design question reduces to: how often does the game hand the player a fresh instance of that cycle, and how legible is the diagnosis step?

**Where it breaks down:**

- **Decision saturation (the big one).** Count the actual decision space in the slice: 3 shafts × 4 column slots × range handles × ~10 door toggles × 3 idle floors. A competent player finishes exploring it in ~2 minutes. After that, the doc's pressure sources are spawn *rate* and *mix* ramps — but a rate ramp does not create new decisions; it just accelerates a static layout toward failure. Mini Motorways forces an edit every 10–20 seconds because new houses/destinations spawn at new *locations*, continuously invalidating your geometry. Uplift's only geometry-invalidator is building growth, which arrives every 1–2 days (90+ seconds). Between growth beats there is nothing to do. That's the dead-time hole, and the doc's own §7 Q3 ("if editing <10%, it's a screensaver") admits it without proposing the fix.
- **Composition ramp is weaker than claimed.** "+10% sumo" is called "a completely different puzzle" — it isn't, in A. The player's response to more sumos is one edit (take the double-wide card, or dedicate a shaft), made once. Mix changes are one-time re-specializations, not continuous pressure.
- **Legibility of the dispatch AI.** "Longest-waiting reachable queue" plus LOOK will regularly produce the single most rage-inducing image in elevators: a car sliding past a packed floor because it's mid-delivery. That is *correct* behavior that *looks* stupid. Next-stop pips help calm players; nobody reads pips while a ring is filling. This risk is real but is the fixable one — it yields to iteration on telegraphing (e.g., a car visibly "claims" a queue with a line/beam the moment it commits, like Mini Motorways' pin-to-car pathing).
- **Visual liveliness.** MM is an ant farm: dozens of agents on player-drawn geometry. Slice-1 Uplift is 3 cars oscillating in 3 straight lines. The "watch your system cope" fantasy needs crowd mass (queues breathing, lobbies pulsing) to carry the watching half of the loop. Budget juice for *passengers*, not cars.
- **Throughput math is a hidden hard cap.** At 1 spawn/1.5s, 3 cars of capacity 4 with ~10s round trips sit at a knife-edge; past a point, no layout survives without the upgrade cards granting raw throughput. That's fine (MM is the same) but it means late-run failure is arithmetic, not skill — pacing must ensure players die *after* an interesting mistake, not at a predetermined wall.

**Failure fairness: currently unfair-feeling as specced.** The 20s overcrowd ring assumes a rescue is possible in 20s. In MM a rescue is a 2-second redraw. In Uplift the correct rescue is often structural — place a shaft, drag a range — which costs budget the player may have spent, and the real fix ("you needed a different layout two minutes ago") is unactionable. Cascades make it worse: freeing floor 7 by cutting doors at 5 just moves the ring to 5. Requirements to make it fair: (1) the ring must *drain* when the queue drops below cap, never latch; (2) a mechanical rescue path under 5 seconds must always exist (instant refund/redraw, no placement animation lockout); (3) rush pulses must be telegraphed with enough lead time to act (10s, per §5 — probably needs 15–20s early on).

**Ergonomics/session:** best of the three. Low-APM, chunky targets, 5–8 min capped runs, pauses allowed. No complaints at the sketch level.

### Option B — "Rules, Not Hands"

**Where the fun is.** One moment, and it is genuinely great: *change one rule, press play, watch the system heal.* The idle-floor fix at floor 7 in the doc's own walkthrough is the entire game's dopamine in one beat.

**Where it breaks down:**

- **It's one note.** Rule-card puzzles live on wave design. Deterministic waves are solvable, and with only 3 rule dimensions the solution is usually visible on the forecast screen before pressing play. Solved-in-one-try levels are the death of the retry loop; the fix (more rule dimensions) turns the card into a settings screen — the doc knows this and the tension has no third option.
- **Content treadmill.** B is level-based; every wave is hand-authored content that burns in minutes. A's procedural endless generates its own content. For a small team this is a decisive economic difference the doc doesn't weigh.
- **Dead time by construction.** The watch phase is 60–90s of spectating at 2×. Hot-editing with a cooldown (the doc's best B idea) partially rescues it — and notably, hot-editing-during-simulation is just… Option A. The good parts of B keep collapsing into A.
- **Homework aroma on a phone.** Floor-chip multi-selects in a slide-up card is form-filling. Mobile sessions start with intent to *play*; B starts every level with configuration.

**Failure fairness:** excellent — soft fail, retry, stars. Fairest of the three, because the player authored every rule. This is worth remembering for kill-criterion #2 below.

### Option C — "Dispatcher"

**Where the fun is.** In your fingers, day one. Flick, swoosh, ding. It needs no argument, which is exactly why it's seductive.

**Where it breaks down:**

- **Thumb occlusion is worst-case.** Vertical drag targets under a vertical thumb: the finger covers the shaft, the floors, and the queue you're aiming at, simultaneously. Path-drawing through floor stops under your own thumb is a known misery on portrait phones.
- **APM ceiling arrives fast.** 3+ cars under accelerating spawns is claw-hand within a run. The difficulty curve has nowhere to go but speed, and speed on touch is the wrong kind of hard.
- **It surrenders the unclaimed lane.** Competitor research is unambiguous: every existing mobile elevator game is pilot-a-car (Elevator The Game, Elevator Manager, the hypercasual tier). C walks out of the empty "architect" positioning and into the crowded one, with a premium production bar it can't out-juice hypercasual competitors on.
- **Failure fairness:** perfect (always your fault) — but fair frustration in a genre with no depth runway is not worth much.

The doc's disposition — C as a one-day feel probe and a possible limited "emergency flick" resource inside A — is exactly right. Endorsed. The emergency flick is, quietly, one of the best ideas in the doc: it converts A's worst moment (watching the AI do the wrong thing) into a player action with a cost.

---

## 2. Stress-testing the recommendation of A

**Is "watching your own network cope" fun on a phone, honestly?** Only when watching is *pregnant* — when you're watching because you just made a change and are hungry for the verdict, or because you can see trouble forming and are deciding where to intervene. MM never gives you pure watching; there is always a nagging suboptimality somewhere on a big 2D map, and new demand lands every few seconds. Watching with nothing to decide is a screensaver, and phones are unforgiving of screensavers — the home button is one thumb-twitch away.

**The honest MM comparison, itemized:**

| MM ingredient | Uplift-A as specced | Gap? |
|---|---|---|
| New demand at new locations every ~10–20s | Spawn rate/mix ramp on fixed floors; geometry changes only at day boundaries | **Yes — the critical gap** |
| Cheap continuous re-draw | Refundable shafts, door toggles | OK on paper; must be instant in feel |
| Weekly 1-of-N choice | 1-of-3 cards per ~90s day | OK, cadence is even better |
| Local, rescuable, legible failure | Overcrowd ring; rescue may be structural/slow | Partial — fix per §1 above |
| Large 2D map = always a suboptimality somewhere | 10 floors, 1D, 3 shafts | **Yes — decision space is tiny** |
| Ant-farm visual density | 3 cars, small queues | Yes — solvable with crowd juice |

**Single biggest fun-risk:** *edit starvation.* After the initial build-out, the player has nothing meaningful to do between day boundaries, and the game degenerates into watching a fixed network drown on a timer. Illegible AI (the doc's named risk) makes players angry; edit starvation makes them *leave*, and it can't be patched with better telegraphing because it's structural.

**The fix to design in now:** give A a continuous demand-geometry drip — the elevator translation of MM's house spawns. Every ~20–30s, a *tenant event* lands on a specific floor with a visible move-in animation: "gym opens on 6 — expect down-traffic bursts," "floor 9 leased to executives," "floor 3 tenant moves out." Each one locally re-shapes the O-D pattern and thereby asks a fresh layout question at MM cadence, without touching spawn rate. This is cheap (a spawn-table patch keyed to a floor plus one banner animation) and it converts the composition ramp from a global slider into a stream of local, legible, *actionable* events. I'd argue it is the missing core mechanic, not a tuning knob.

**How the prototype must be instrumented to test the risk:**

- Log every player input, classified: structural (place/resize shaft), tactical (door toggle, idle floor), cosmetic (taps that change nothing). Chart **meaningful edits per minute** across the run.
- Log **gaze-proxy**: time between last edit and next edit; distribution of intervals >30s ("dead air"). If dead-air intervals grow monotonically after minute 2, that's the screensaver signature.
- Think-aloud blame tagging on every failure: self / AI / RNG. (The doc's ≥70% self-blame target is good; keep it.)
- A/B the tenant-event drip ON vs OFF in the same slice. This is the single most valuable experiment the prototype can run, and it's a spawn-table flag.

**One more structural gap the doc must resolve before the slice: transfers.** Nothing in §1–§4 says whether a passenger can ride shaft 1 to floor 5 and change to shaft 2. This is not a detail — it's the fork between two different games. Without transfers, every O-D pair needs a single shaft serving both endpoints, the express+local sky-lobby pattern (which the competitor doc calls "the most interesting emergent structure in vertical routing" and "the skill ceiling") is *impossible*, and the 1D-topology monotony risk lands at full force. With transfers, pathing, legibility, and passenger AI all get harder. Recommendation: slice 1 ships direct-only (declared, not accidental), and transfer-at-a-marked-floor is the first slice-2 experiment — it is the game's interchange-station moment and the doc currently doesn't know it.

---

## 3. Taxonomy triage

**A prior problem before judging types:** several passenger designs assume a *routing verb the chosen loop doesn't have*. In A the player never assigns passengers to shafts — passengers presumably board whatever serves their trip. So "routing maintenance workers onto off-peak shafts" and "keeping couriers on the freight loop" are not decisions the player can make unless boarding filters exist on *cabs* (freight refuses regulars, compact refuses sumo). The doc implies this in the elevator table but never states the boarding-rule system. Write it down: **passenger-cab compatibility filters are the routing mechanic.** Every type that "forces routing" must be expressible through them, or it's dead weight.

### Passengers

| Type | Verdict | Reasoning |
|---|---|---|
| Regular | **Keep (slice 1)** | Baseline. |
| Sumo | **Keep (slice 1)** | Best type in the doc: capacity constraint, readable at 2-units-wide, FIFO blocking creates visible drama. One warning: queue-blocking will *look* like AI stupidity ("why is nobody boarding?"); blocked passengers need an explicit animation pointing at the sumo, or this becomes an AI-blame generator. |
| Executive | **Keep (slice 1)** | Second-best: latency constraint that motivates the express, the game's signature build. Bug: "costs 2 strikes" — strikes are Option C's fail state; A has rings. Reconcile (e.g., executive storm-out adds a chunk to that floor's ring). |
| Courier | **Promote (slice 2, ahead of tour group)** | Quietly the most valuable mid-tier type: creates *down* traffic (every elevator game over-stresses up), doubles demand without new sprites, and cheaply pilots the hospital's multi-leg itinerary (§7 Q11 says this itself — the roadmap in §3 should match). |
| Tour group | **Defer** | It's sumo-plus (4 indivisible slots vs 2). Same lesson, bigger number. Adds nothing until double-wide cabs exist and are contested. |
| Gurney | **Keep, theme-gated** | Honest lock-and-key for the hospital (needs wide door). Note it's a *requirement*, not a decision — the decision is the itinerary system around it. |
| Maintenance worker | **Defer, redesign** | The 3s door-block is a pure annoyance debuff unless cab filters let the player shunt them; and "carries a ladder, takes 2 slots, very patient" overlaps sumo. Only worth it once freight cabs exist. |
| Child (needs adult) | **Cut** | Player has no lever: whether an adult co-boards is RNG. "Punishes over-segregation" is too indirect to ever be read as a lesson; it will be read as a bug. |
| VIP celebrity | **Cut from plans, park as event** | Refuses-to-share + gawker-spawn is an event script, not a type, and "interruptible private run" needs manual control A doesn't have. Revisit only if the emergency-flick experiment ships. |
| Ghost | **Fine as theme paint, never earlier** | The doc is honest that it's chrome. Agreed; zero priority. |

The doc's own criterion — "must change what the player *builds*" — is correct, and types 7, 9, 10 fail it. The slice-1 pick (1–3) is right.

### Elevators

- **Standard / Compact / Double-wide / Express permit: keep — this is the real game.** Compact's "can't take sumo" and express's "≤3 doors" are exactly the shape-changing constraints the criterion demands. These four plus cab filters could carry the entire first building.
- **Freight:** good hospital signature; also the cleanest demonstration of cab filters ("regulars refuse it").
- **Paternoster:** charming and clip-able, but it *deletes* gameplay on its floors (zero-wait boarding = no scheduling problem) and is a rendering/sim cost. Content phase, as scheduled; be ready to find it's a screenshot feature, not a mechanic.
- **Sky-lobby link:** under-scoped in the doc relative to its importance — this is the transfer mechanic wearing a costume (see §2). Should be slice-2, not Building-4.
- **Horizontal pods:** a different game; the doc's deferral is correct and §7 Q12 is honest about it.
- **Robot lift:** chrome; fine at the bottom of the spaceship pool.
- **Cap discipline (≤5 shafts / ≤8 cars):** correct instinct, genre-literate, keep.

---

## 4. Mobile playability audit

The §6 UX section is unusually strong (grid-cell tap model, verb disambiguation, offset handles, tap-slop rules are all genre-veteran moves). Remaining problems:

1. **Gesture-timing collision (bug in the spec):** peek-zoom triggers at 150ms hold; idle-floor long-press at 300ms; both start from a stationary finger on the building. Every idle-floor attempt will fire the magnifier first. Pick one: move idle-floor to a tap on a dedicated per-shaft chip (better anyway — discoverable), or gate peek-zoom to dense-queue regions only.
2. **Undo is top-left — the least reachable point on a phone for either thumb.** Undo is a high-frequency, mid-panic action; genre law (the doc's own words) says editing must feel free. Put undo in the bottom tray, near the thumb, always. Top corners are for pause and score only.
3. **Left-edge scroll gutter assumes a left thumb or a reach-across.** ~80% of one-handed users are right-thumbed; the top-left of a 6" screen is a stretch zone. Mirror the gutter (both edges pan) or use a bottom-edge horizontal scrub bar mapped to vertical pan. Test on a real 6.7" device in one hand, standing.
4. **Ring soup.** Patience rings on sprites + overcrowd ring on floors + growing-ring long-press affordance + express-red rails + gold executives: at least four competing circular/color alarms. Establish a strict signal budget: red = floor-level danger only; passenger impatience gets a different channel (the asset doc's emote bubbles are right there and read better at 24–32px than draining rings).
5. **Numeric destination chips will fail at density.** Floor numbers over 60px sprites, ×6 queued, ×10 floors = a wall of tiny numerals. The doc's own color-stripe idea should be primary (color = destination band), number secondary on tap/zoom. MM ships zero numerals in the play field; that's not an accident.
6. **10 floors × 64dp rows ≈ 640dp — fine; 14+ floors is not.** Band-scrolling plus overcrowding *off-screen* is a fairness problem: a ring you can't see is a death you didn't watch. Needs an edge "danger bead" (mini-map dot or gutter glow per off-screen floor in trouble) before any building exceeds one screen. This is missing from the spec and required for §5's taller office towers.
7. **Auto-slow-while-dragging: keep, don't ask.** It hides latency and flatters the player; the "is it cheating?" worry (§7 Q9) is over-thought — MM pauses entirely during editing on mobile and nobody calls it cheating.

---

## 5. Prioritized recommendations

### Change in the design doc (before building)

1. **Add the tenant-event demand drip to §1A/§5 as a core mechanic** (local O-D reshaping every 20–30s, visibly announced). This is the anti-screensaver mechanism and the true MM analogue; rate/mix ramps alone are not.
2. **Specify transfer rules explicitly.** Slice 1: direct-only, stated. Slice 2: transfer floors as the first depth experiment. Pull sky-lobby forward from Building 4.
3. **Write down the passenger-cab compatibility filter system** as the routing mechanic; re-audit every passenger type against it (this kills Child and VIP, defers Maintenance).
4. **Fix fail-state fairness rules:** rings drain when rescued; guaranteed <5s mechanical rescue path; longer telegraphs early; off-screen danger indicators.
5. **Fix spec bugs:** executive "2 strikes" vs ring model; 150ms peek vs 300ms long-press collision; undo placement.

### The prototype MUST test first (in order)

1. **Edit cadence** — meaningful edits/minute and dead-air intervals, with the tenant-drip A/B. This is the go/no-go experiment; everything else is tuning.
2. **Blame attribution** on failure (self vs AI), ≥70% self-blame target, iterating car-claim telegraphing between rounds.
3. **The express grin** — does anyone hand-craft an express unprompted, and does it visibly pay off within 30s of building it?
4. Real-device fat-finger pass (one-handed, standing, 6.7" and 5.5") — before any content work.

### Kill criteria (signals to abandon/pivot)

1. **Edit starvation persists:** after minute 2, median tester makes <1 meaningful edit per minute *even with the tenant-event drip enabled*, and dead-air intervals keep growing. The network-designer loop cannot sustain a run; pivot toward B's hot-editable rule layer or fold in C's manual override as a core verb.
2. **Blame won't flip:** after two full iterations on AI telegraphing, self-blame in think-alouds stays under 50%. Legibility is unfixable at this sim fidelity; pivot to B, where failure is self-authored by construction.
3. **No express moment:** across 5+ testers, nobody voluntarily specializes a shaft (express, idle-floor play, door sculpting) — or those who do can't tell it helped. The expressive language is too thin to generate "aha"; either the verb set must deepen (per-car rules) or the direction is a screensaver with extra steps.

A secondary warning sign (not kill, but pivot-informing): testers consistently prefer replaying the *same* day to fix their grade rather than continuing the run — that's B's puzzle-optimizer instinct asserting itself, and the level/star structure should rise in priority.

---

*Bottom line: A is the right prototype, the slice scope is genuinely disciplined, and the UX spec is above par. But as written the doc is betting the game on "watching is fun" without engineering the reason to keep touching the screen. Build the tenant drip, define transfers, wire the telemetry, and let kill-criterion #1 be the first thing the prototype is capable of measuring.*
