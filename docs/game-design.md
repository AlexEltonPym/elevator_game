# Elevator Game — Design Ideation Document

**Working title:** *Uplift* (placeholders considered: "Shaft", "Going Up", "Vertical")
**Platform:** Mobile-first (portrait phone), Godot 4, touch input, 3–8 minute sessions.
**Pitch:** Mini Motorways, but the map is a cutout of a big building and the network you design is elevators. People appear on floors wanting to reach other floors; you decide which shafts exist, which floors each elevator serves, and how it behaves. Special passengers (sumo wrestlers, impatient executives, hospital gurneys) force you to specialize your fleet. Themed buildings (office, hotel, hospital, spaceship) remix the rules.

**Design north star:** The player should feel like a *systems gardener*, not a joystick pilot. The joy of Mini Motorways is watching a system you shaped cope (or fail to cope) with demand you don't control. Everything below is evaluated against that feeling — and against "can we feel it in a rough prototype in a week."

---

## 1. Core Loop Options

Three distinct directions, plus a note on hybrids. Each is written as: minute-by-minute session, win/fail state, why it might feel good, biggest risk.

### Option A — "Network Designer" (drag-to-assign shafts and floor ranges, Mini-Motorways-style)

**One-line:** You never touch an elevator car. You draw and edit the *network* — shafts, the floor ranges they span, and which floors get doors — and the cars run themselves on a simple dispatch AI. Periodic upgrade choices (new car, express permit, bigger cab) are your only other lever.

**Minute by minute:**
- **0:00–0:30** — Building fades in: ~8 floors visible, 1 starter shaft already placed spanning floors 1–4. A trickle of passengers (1 every ~6s) appears on floor lobbies with a destination icon over their head. Player watches the starter elevator handle it. Calm.
- **0:30–1:30** — Spawn rate rises; passengers start appearing on floors 5–8, outside the starter shaft's range. Player drags the top of the shaft upward to extend its range (rubber-band gesture, like extending a road). Cost: shaft-meters from a limited budget shown as a simple counter.
- **1:30–3:00** — First special passenger: a **sumo wrestler** (takes 2 of the cab's 4 slots). Queues start forming on busy floors. Player places a **second shaft** on the right side of the building serving only floors 1, 5–8 (tap floors to toggle doors on/off per shaft — this is the key expressive verb: a shaft with doors only at 1 and 8 *is* an express).
- **3:00** — **Upgrade beat** ("end of day"): pick 1 of 3 cards — e.g. *+1 elevator car in an existing shaft*, *Double-wide cab (choose a shaft)*, *+10 shaft-meters*. The game pauses for this. This is the Mini Motorways "new week" moment.
- **3:00–6:00** — Demand doubles, a new wing of the building unlocks (floors 9–12), penthouse VIPs appear demanding <20s trips. Player reshapes: deletes doors on mid floors of shaft 2 to make it a true express, spends saved meters on a stubby local shaft for 9–12. Tension rises as queues visibly lengthen.
- **6:00–7:00** — One floor's queue hits its cap; its "overcrowding" ring starts filling. Player triages — sacrifices a quiet floor's doors to speed a route. Ring fills anyway. **Building over capacity → run ends.** Score: passengers delivered.

**Win/fail:** Endless score-chase per building (Mini Motorways model). Fail = any floor's waiting-queue meter stays full for N seconds ("the fire marshal shuts you down"). Optional finite "scenario mode": survive to day 7 to unlock next building.

**Why it might feel good:**
- Pure Mini-Motorways fantasy: watching your design absorb chaos, the ache of a bad layout, the relief after a fix.
- "Doors per floor per shaft" is a wonderfully compact expressive language — express vs. local emerges from the player's own toggles rather than a menu.
- Fully pause-free but low-APM: ideal for one thumb on a phone.

**Biggest risk:** The dispatch AI carries the whole experience. If cars behave stupidly (ignoring a full floor, bunching like buses), the player feels *robbed* rather than responsible. Mini Motorways cars are dumb-but-predictable; elevator dispatch is genuinely harder (it's a scheduling problem). Mitigation: brutally simple, legible AI (see §2), and let players see each car's next-stops as pips on the shaft.

### Option B — "Rules, Not Hands" (programming-lite: set per-elevator behavior and watch it run)

**One-line:** Shafts are mostly fixed by the level. Your verb is *configuring each car*: which floors it answers, its home/idle floor, its priority class (who it accepts first), when it returns home. Then you press play and watch your policy succeed or fail. Think SpaceChem/Opus Magnum energy at Mini Metro scale.

**Minute by minute:**
- **0:00–0:45** — Level opens *paused*. Building shows 10 floors, 3 empty shafts, forecast icons on floors ("office floors 6–9 get heavy 9am traffic"). Player taps a shaft → a compact rule card slides up: `Serves: [floor chips] · Idle at: [floor] · Priority: [First-come / VIP-first / Nearest]`. Player sets car 1 = local 1–5, car 2 = 1↔6–9 shuttle idling at 1, car 3 = flex.
- **0:45–2:30** — Press play. "Morning rush" wave runs at 2× life speed. Player mostly *watches*, occasionally hot-editing one rule (allowed, with a 3s reconfiguration cooldown while the car finishes its trip). Queues form at floor 7; player sees car 2 wastefully idling at 1 between runs, changes its idle floor to 7. Immediate visible improvement — this is the core dopamine hit.
- **2:30–3:00** — Wave ends. Report card: average wait, longest wait, complaints. Stars (1–3) based on complaint count. Player can retry the same wave with tweaked rules — the puzzle-optimizer loop.
- **3:00–6:00** — Wave 2 introduces a twist passenger (gurney needs the wide car; VIP needs <15s pickup) that invalidates the previous policy. Player re-plans in the pause, runs again.
- **6:00** — Level cleared at 2 stars; player either replays for 3 or moves on.

**Win/fail:** Level-based, not endless. Win = survive all waves under the complaint cap; stars for performance. Fail is soft — you finish the wave with a bad grade and retry.

**Why it might feel good:**
- The "I fixed the system with one rule change and *watched* it heal" moment is extremely satisfying and screenshot-able.
- Deterministic-ish waves make it a real puzzle: mastery = understanding the traffic, not thumb speed. Great for replay/leaderboard ("beat this wave with 2 elevators").
- Very phone-friendly: all interaction happens on a paused or slow board via chunky rule cards; zero precision required.

**Biggest risk:** It can feel like *homework* — filling in forms, then spectating. If the rule vocabulary is too small the answers are obvious (solved in one try, boring); too large and the card UI becomes a settings screen. Also weakest "juice under pressure" of the three: no rising panic. Mitigation: keep exactly 3 rule dimensions at launch; make the watch phase fast (2–4× speed) and highly animated.

### Option C — "Dispatcher" (direct-control hybrid: you fling the cars yourself)

**One-line:** You *are* the dispatch algorithm. Swipe an elevator up/down to send it to a floor; tap a waiting passenger group to promise them a car. The system layer (buying shafts, cab upgrades) exists but is secondary; moment-to-moment is real-time triage under rising load. Closer to Mini Metro's cousin *Overcrowd* or classic *Tower* / Game & Watch feel.

**Minute by minute:**
- **0:00–0:30** — One shaft, one car, 6 floors. Passenger appears on 4 wanting 1. Player drags the car up; it auto-boards anyone whose destination lies in the car's travel direction, auto-opens at destinations. Instant tactile fun.
- **0:30–2:00** — Second car unlocks in shaft 2. Spawns quicken. The core skill emerges: batching — dragging a car to sweep 6→4→1 in one gesture (draw the path through floors, like a mini route). Patience rings over heads tick down; a completed delivery just before the ring empties gives a "close call" bonus.
- **2:00–4:00** — Sumo (fills the cab alone) and executive (ring drains 3× faster) appear. Player is now juggling 3 cars, planning two gestures ahead. Mistakes cascade — a mis-sent car strands a full floor.
- **4:00–5:00** — Short upgrade interstitial every 90s: pick cab size vs. speed vs. new car. Then load rises again. Run ends when 3 passengers storm out (patience fully drained) — **3 strikes**. Score = deliveries; combo multiplier for uninterrupted no-wait streaks.
- Total run: 4–6 minutes of accelerating arcade tension.

**Win/fail:** Endless arcade, 3-strikes fail, score + combo. Daily-challenge friendly.

**Why it might feel good:**
- Immediately, physically fun in a way A and B are not — feel is in your fingers, testable on day one. Flicking a car and watching it swoosh is intrinsically juicy.
- Failure is always *your* fault, never the AI's — sidesteps Option A's biggest risk entirely.
- Shortest path to "is this game fun at all?"

**Biggest risk:** It drifts away from the stated fantasy — this is an action game, not a design game; APM ceiling on a phone is low and late-game may become claw-hand stress rather than strategic pressure. Also weakest long-term depth: content is spawn patterns, not player-built structure. Mitigation if pursued: cap simultaneous cars at 3–4 and push difficulty through passenger mix, not speed.

### Note on hybrids
A and B compose naturally: A's shaft-drawing plus B's per-car idle/priority rules is probably the full game. C composes badly with either (manual control makes rule-setting moot). Treat C as a *feel probe* and a possible "manual override" spice — e.g. one emergency flick per 30s as a limited resource inside Option A — rather than a foundation.

---

## 2. Recommendation: Prototype Option A, with one Option B rule stolen

**Build the Network Designer.** Reasons:

1. It is the fantasy the designer actually described ("you design which elevators go where and how they should move") — B and C are adjacent interpretations.
2. It has the strongest emergent-story engine (queues, cascading congestion, heroic last-second reroutes), which is what makes Mini Motorways clip-able and sticky.
3. Its central risk — "is watching AI elevators satisfying or infuriating?" — is exactly the kind of question that *only a prototype can answer*, which matches the designer's stated goal ("see what we can feel"). Options B and C have risks (boredom, genre drift) you can largely reason about on paper.

Steal from B: each shaft gets ONE rule — its **idle floor** (where empty cars return). It's a single tap, it dramatically improves perceived AI intelligence, and it gives the player a knob to express intent beyond geometry.

Defer from C: no manual car control in slice 1. If the slice feels too passive, add the "emergency flick" (limited manual override) as experiment #2 — it's a one-day add.

### The vertical slice (target: 1–2 weeks in Godot)

**Scope — build exactly this, nothing more:**

- **Building:** one fixed portrait cutout, 10 floors, no scrolling. Flat-color rectangles. Floor height ~90 px at 1080-wide reference (thumb-friendly).
- **Shafts:** player can place up to 3 vertical shafts in 4 predefined shaft columns (no free-form x-positioning — snap to column slots). Per shaft: drag top/bottom handles to set floor range; tap a floor inside the range to toggle its door on/off; tap-hold shaft to set idle floor. Budget: shaft-meters counter, refunded on edit.
- **Cars:** 1 car per shaft, capacity 4 slots. Dispatch AI, deliberately dumb and legible:
  1. If carrying passengers → go to nearest onboard destination in current direction (elevator algorithm / LOOK).
  2. Else → go to the *longest-waiting* reachable queue.
  3. Else → return to idle floor.
  Show the car's next stop as a highlighted door. No inter-car coordination in slice 1.
- **Passengers:** 3 types only — **Regular** (1 slot), **Sumo** (2 slots, spawns rarely, blocks others visually in queue), **Executive** (1 slot, patience drains 3× fast, gold color). Spawn tables ramp over 5 minutes from 1/6s to 1/1.5s. Destination shown as a floor-number chip over the head; patience as a draining colored ring around the sprite.
- **Pressure & fail:** per-floor queue cap of 6 visible sprites; when capped, a red overcrowd ring around that floor fills over 20s; if any ring completes → run over, score screen (passengers delivered, longest survived).
- **One upgrade beat:** at 2:30, pause + 3-card choice (extra car in a shaft / +capacity on one cab / +8 shaft-meters). Hard-coded, no economy behind it.
- **Juice minimum:** car easing (accelerate/decelerate), door-open squash, passenger hop-in animation, tick sound per delivery, heartbeat pulse when any floor is over half queue. Feel lives or dies on these even in graybox.
- **Explicitly out of scope:** themes, horizontal elevators, save/meta, tutorials, monetization, more than 3 passenger types, multi-car shafts beyond the upgrade card, sound design beyond 4 placeholder SFX.

**What the slice must answer (success criteria):**
- Do playtesters *watch* the elevators between edits, or stare at the UI? (Watching = the ant-farm hook is real.)
- When a queue explodes, do players blame themselves ("my layout") or the AI ("stupid elevator skipped them")? Target: ≥70% self-blame in think-aloud tests.
- Does toggling doors to hand-craft an express feel clever? (The moment someone makes a 1↔10 express unprompted and grins, the design language works.)
- Is 10 floors readable and tappable on an actual 6" phone, or do we need per-floor zoom already?

---

## 3. Passenger Taxonomy

Design rules: every type must (a) change what the *player builds*, not just add HP-style difficulty, (b) be identifiable in <0.5s at ~60 px sprite height, (c) be readable by silhouette + one color + one motion, never by fine detail (colorblind-safe: shape is primary channel).

| # | Type | Silhouette / read | Slots | Patience | Mechanics | What it forces you to build |
|---|------|-------------------|-------|----------|-----------|------------------------------|
| 1 | **Regular** (office worker) | Small round body, muted blue; idles calmly | 1 | Normal (60s) | Baseline. Spawns in singles/pairs. | Coverage everywhere. |
| 2 | **Sumo wrestler** | Huge; twice the width of anyone else, wobble-idle | 2 | Normal | Won't board if <2 slots free; visually plugs the queue so people behind him can't be seen boarding past him (queue is FIFO). | Big-cab or freight elevators; keeping one high-capacity route. |
| 3 | **Executive** (impatient businessman) | Tall thin, gold suit, foot-taps rapidly, patience ring drains 3× | 1 | Very low (20s) | Almost always destined for the penthouse/top floors. Storming out costs 2 strikes instead of 1 (or double overcrowd fill). | A true express (few doors, top-range) to keep them off local routes. |
| 4 | **Tour group** | 4 identical small green sprites holding a flag, move as one blob | 4 (indivisible) | High (90s) | Board together or not at all; delivering all 4 gives bonus. | Slack capacity; tempts you to hold a big car for them. |
| 5 | **Hospital gurney** (+nurse) | Horizontal bed sprite — the only *wide/lying* silhouette in the game, white/red cross | 3, and needs a **wide-door** cab | Low-ish (40s), flashing red when critical | Only appears in hospital theme (and rare events elsewhere). Travels floor-to-floor repeatedly (see §5 hospital twist). | Dedicated freight/bed elevator; door-width upgrade suddenly matters. |
| 6 | **Maintenance worker** | Yellow hard hat, carries comically long ladder (sticks out visually) | 2 | Very high (120s) | Slow to board/unboard (3s doors-open each end, blocking the car). | Routing them onto off-peak/freight shafts so they don't gum up the express. |
| 7 | **Child / scout troop** | Tiny sprite, bright red balloon, wanders within the queue | 1 | High | Won't ride unaccompanied: only boards a car that already contains (or co-boards with) an adult passenger. | Mixed-traffic routes; punishes over-segregation of your network. |
| 8 | **Delivery courier** | Magenta, hand-truck with parcel stack, jitters with urgency | 2 | Normal, but parcel has its own 45s freshness timer with visible steam/melt | Two-leg task: lobby → floor X, then reappears returning to lobby. Doubles effective demand. | Freight loop with lobby doors; rewards a down-direction plan (most games only stress "up"). |
| 9 | **VIP celebrity** (rare event) | Sparkling aura, paparazzi crowd of 2 non-riders around them | 1 | Low | Refuses to share the cab with anyone; while they wait, they attract +1 extra spawn/10s on that floor (gawkers). | An interruptible private run — one flexible small shaft pays off. |
| 10 | **Ghost** (hotel theme spice) | Translucent grey, floats, appears only at night phase | 0 (weightless) | Infinite | Harmless, rides randomly, but occupies a *visual* queue slot and spooks one random passenger into +20% patience drain while sharing a cab. | Nothing structural — comedy + soft pressure; teaches players queues are about space, not weight. |

**Phone readability system (applies to all):**
- **Destination chip:** small rounded tag above head with floor number, color-matched to a stripe on the destination floor's edge (number for precision, color for at-a-glance).
- **Patience:** ring around the sprite draining clockwise, green→amber→red; at red the sprite does an angry shake. No numbers.
- **Slots:** body width literally equals slots occupied (1-slot = 1 unit wide, sumo = 2 units, gurney = 3 lying down). Capacity is thus visible geometry, never a stat you look up.
- **Rare types get motion tells** (sparkle, float, balloon-bob) because motion reads at small sizes better than texture.

Slice 1 uses types 1–3 only. Add 4, 8, then 5 next; 7, 9, 10 are content-phase.

---

## 4. Elevator Taxonomy

The player's fleet vocabulary. Same rule as passengers: each machine must change network *shape*, and be readable by cab proportions + color, not labels.

### Cars / shafts

| Machine | Read | Capacity | Speed | Behavior / niche | Unlock |
|---|---|---|---|---|---|
| **Standard cab** | Square cab, steel grey | 4 | 1.0 | The all-rounder; all early levels. | Start |
| **Compact cab** | Narrow cab, zippy bounce anim | 2 | 1.6 | Fast pickups; can't take sumo/gurney/ladder. Great as executive-runner. | Building 2 |
| **Double-wide cab** | Visibly 2 units wide, wide doors | 8, wide-door | 0.8 | Sumo/gurney/group hauler. Slow doors (1.5s). | First sumo-heavy day |
| **Express permit** (shaft modifier, not a cab) | Shaft rails turn red; skipped floors get blanked door outlines | — | Travel ×2 between served floors, but shaft may have ≤3 doors | Formalizes the hand-made express; the constraint (≤3 doors) makes it a real decision. | Building 2 |
| **Freight elevator** | Industrial cage, chain-link texture, yellow chevrons | 10, wide-door | 0.6 | Only boards 2+ slot passengers and couriers (regulars refuse it). Immune to VIP/executive complaints. | Hospital / event |
| **Paternoster** | Open two-lane loop of small cabins moving continuously up one side, down the other | 1 per cabin, ~6 cabins visible | Constant slow crawl, **never stops** | Zero-wait boarding for regulars on its floors; cannot take sumo/gurney/group/child (safety!). A "conveyor belt for singles" that trivializes short local hops but nothing else. Charming, very European, very clip-able. | Hotel theme |
| **Sky-lobby link** (funicular/diagonal) | Diagonal track across the cutout | 4 | 1.0 | Connects exactly two floors in different shaft columns (e.g. lobby ↔ floor 15). A "bridge" piece that breaks pure verticality; late-game puzzle piece. | Building 4 |
| **Horizontal pod** (spaceship theme) | Cab is a capsule, moves along corridor rails L/R; shafts become a grid | 3 | 1.2 | On spaceship maps, some "floors" are corridors: pods travel horizontally and transfer between vertical shafts at junction nodes — the network becomes 2D routing, the true Mini-Motorways endgame. | Spaceship theme |
| **Service robot lift** (spaceship spice) | Tiny tube, only 1 slot | 1 | 2.0 | Only carries couriers/parcels. Frees your main fleet from freight duty. | Spaceship |

### Upgrade / economy model

- **Currency 1 — Shaft-meters** (spatial budget): earned passively per in-game day + per N deliveries. Spent to place/extend shafts. Fully refunded on demolish (Mini Motorways' forgiving-redesign rule — essential; punishing redesign kills the genre's joy).
- **Currency 2 — Upgrade cards** (the "new week" beat): every day-end, pick **1 of 3** drawn from the building's pool: a new car type, +1 car in an existing shaft (multi-car shafts queue vertically and never pass each other — simple to sim, fun to watch), a cab swap, a shaft modifier (express permit, wide doors), or +meters. Rarity-weighted; themed buildings weight their signature machine.
- **No hard currency, no per-item shop in the loop.** Meta-progression between buildings = permanent unlock of new card *types* into the pool (Mini Motorways' city-unlock model). Keeps in-run choices about *this* building's problems.
- **Cap discipline:** max ~5 shafts and ~8 cars per building, ever. The genre's feel depends on a small vocabulary under pressure, not sprawl.

---

## 5. Difficulty & Progression

### Within a run (the demand ramp)
- **Spawn curve:** interval shrinks on a smooth curve (≈ −10%/day) with sinusoidal *rush pulses* — morning-up rush (everyone lobby→up), lunch scramble (inter-floor chaos), evening-down rush (everyone →lobby). Pulses are telegraphed 10s ahead by a subtle clock icon + floor forecast glow, so players plan rather than react.
- **Composition ramp:** difficulty comes primarily from *mix*, not just rate — day 1 is 100% regulars; sumo share rises to 15%, executives to 10%, etc. A day with the same spawn rate but +10% sumo is a completely different puzzle.
- **Spatial ramp:** the building *grows*. Every 1–2 days a new floor band or side-wing slides open with its own demand profile (Mini Motorways' expanding map, verticalized). This is the single most important pressure source: your elegant network becomes wrong, repeatedly.
- **Fail state:** per-floor overcrowd rings as in the slice. One ring completing = run over (endless mode) or big star penalty (scenario mode).

### The "week upgrade" equivalent
**End of day, every ~90 real seconds:** time freezes, night tint, 1-of-3 card pick (see §4), plus a one-line stat ("437 delivered · longest wait 48s"). It's the breathing beat: pride + planning + the only pause. Days per run: 5–8, so runs land at 5–8 minutes even when going well — a deliberate mobile session cap. (Consider Mini Metro's "run continues but scoring week rolls over" only if testing shows players hate run-length caps.)

### Level themes and twists

| Theme | Building shape | Signature machine | Unique twist |
|---|---|---|---|
| **1. Office tower** (tutorial building) | 12–20 floors, single slab | Express permit | Pure rush-hour rhythm: massive directional tides (all-up at 9, all-down at 5). Teaches ranges, doors, express. Executives are the pressure valve you must isolate. |
| **2. Hotel** | Wide low-rise + thin tower; ground floor is a huge lobby hub | Paternoster | Guests check in (lobby→room, with luggage = 2 slots) and generate *return trips on a timer* (spa, restaurant floors at predictable hours). Night phase: low traffic + ghosts + the paternoster's constant motion looks gorgeous. Demand is schedule-shaped rather than pure ramp — players can learn the timetable. |
| **3. Hospital** | Two towers with a shared podium (floors 1–3 span both) | Freight elevator (bed lift) | Patients don't have one destination; they have a **treatment itinerary** (admit → radiology → ward → surgery → ward → lobby), each leg on a timer, moving as gurneys needing the wide-door lift. Miss a leg's timer and the patient escalates to critical (red, priority, bigger penalty). It's a logistics chain, not point-to-point — the "multi-leg" mechanic from the courier, made central. Also: Code Blue events — a random floor demands a gurney run *right now*, testing your slack capacity. |
| **4. Spaceship** | A grid: vertical shafts × horizontal corridor rails, viewed as a cross-section of the hull | Horizontal pods, robot lift | Full 2D routing — passengers may need shaft→corridor→shaft transfers; you place **junction nodes** where pods hand off. Plus a periodic *gravity-flip klaxon*: for 20s, "up" reverses (cars' travel costs invert; down-going traffic becomes expensive) — a rhythm event that forces temporarily rerouting. This is the endgame theme where the game most resembles Mini Motorways proper. |
| *(stretch)* **5. Mine / skyscraper-under-construction** | Floors are *added at the top* continuously; the building literally races upward | Rope-length budget | Your network chases the growing frontier; teaches demolish-and-redeploy as a core skill. |

**Campaign spine:** Office (learn) → Hotel (schedules + paternoster) → Hospital (chains + priority) → Spaceship (2D). Each theme = 3 hand-shaped buildings + 1 endless variant. Meta-unlocks feed the card pool. Daily challenge: fixed seed on a rotating building, one leaderboard.

---

## 6. Touch UX Sketches (portrait, one thumb)

**Global layout:**
- Building cutout occupies the middle ~75% of a portrait screen. 10–14 floors visible at once; taller buildings use **band-scrolling**: vertical swipe on the *left screen edge* (a dedicated 15%-width gutter) pans floors, so panning never collides with gameplay drags. Floor numbers pinned in this gutter.
- Bottom 15%: the **tray** — draggable shaft/car tokens (Mini Motorways-style), meters counter, day clock. Top 10%: score, pause, speed toggle (1×/2×).
- Reference metrics: floor rows ≥ 64 px tall at 360 dp width; all tap targets ≥ 48 dp. If 20+ floors are needed, the building renders slightly zoomed-out but *touch targets stay floor-row-sized* — you tap a floor row, never a passenger.

**Placing a shaft:** drag a shaft token from the tray onto the building; it ghosts into the nearest legal column slot, snapping between the 3–4 fixed columns. Release to place spanning a default 3 floors around the drop point. Invalid = red ghost + haptic buzz. (Fixed column slots exist *specifically* to kill horizontal fat-finger precision.)

**Setting floor range:** the placed shaft shows fat round **handles** (56 dp) at its top and bottom, hanging half-outside the shaft so a thumb doesn't cover the shaft while dragging. Drag a handle; floors snap with a tick sound + haptic per floor; meters counter live-updates green/red. Release to commit; drag to an unaffordable length and it rubber-bands back.

**Toggling doors (the express-making verb):** tap any floor row *within a shaft's span* to toggle that shaft's door there. Doors are big painted rectangles; a disabled door shows as a dimmed outline. Because a tap could be ambiguous (which shaft?) on floors crossed by two shafts: tap targets are the door cells themselves (shaft-column × floor-row grid cells, each ≥48 dp), not the whole row. One tap = one cell = zero ambiguity.
- **Undo everything:** a persistent undo button top-left. Every gesture is 1-step undoable. Genre law: editing must feel free.

**Setting idle floor:** long-press a shaft (300 ms, with a growing ring affordance) → the shaft lifts slightly and its floors glow; tap one → a little "home" pin appears at that door. Long-press again to clear.

**Fat-finger defenses (summary):**
1. **Grid-cell tap model** — the whole interactive surface is a coarse grid (≤4 columns × floor rows); nothing smaller than a cell is ever a tap target. Passengers, rings, chips are display-only.
2. **Handles offset from content** and oversized; drags are axis-locked (shaft handles move only vertically).
3. **Disambiguation by verb, not position:** tap = doors, drag-from-token = build, drag-handle = resize, long-press = idle floor, edge-gutter swipe = pan. Five verbs, no overlapping start conditions.
4. **Tap-slop forgiveness:** taps register on the nearest cell within 12 dp; drags require 8 dp of travel before ownership, so a sloppy tap never becomes an accidental resize.
5. **Peek-zoom (if needed):** holding a finger down on a dense area for 150 ms pops a 1.5× magnifier lens above the finger (above, not under — the finger is the occluder). Prototype without it; add only if tests demand.
6. **Pause is never required but always allowed** — an accessibility and comfort valve; the sim also auto-slows to 0.5× while any drag is active ("bullet-time editing"), which both feels great and hides input latency.

**Readability at small size:** passenger sprites are deliberately abstract (Mini Motorways dots-and-squares energy): color + silhouette + motion only. Queues render as a compact stacked row per floor with a "+3" overflow chip rather than 9 overlapping sprites. Overcrowd ring wraps the entire floor row so it's visible even mid-scroll.

---

## 7. Open Design Questions (to answer with the prototype)

**Feel / core (slice 1 must answer):**
1. **Is watching legible-but-dumb elevator AI satisfying or infuriating?** The genre bet. Measure self-blame vs. AI-blame in think-alouds; iterate the dispatch rule (longest-wait vs. nearest-call) and see which *feels* fairer, not which is optimal.
2. **Is "doors per floor" enough expressive language,** or do players immediately want per-car rules (Option B's card)? Watch for players poking the shaft looking for more controls.
3. **Passive-pressure balance:** in a good run, what % of time is the player editing vs. watching? If editing <10%, the game is a screensaver → pull in Option B rules or C's manual override. If >60%, it's whack-a-mole → slow the composition ramp.
4. **Does the fail state feel fair?** Is per-floor overcrowding readable early enough to act on, or do deaths feel sudden? Tune ring duration before adding any content.

**Structure (slice 2):**
5. **Endless score-chase vs. wave/star levels** — which retains testers? (Ship both cheaply: same sim, two spawn scripts.)
6. **Run length:** is a 5–8 min capped run right for mobile, or do players want Mini Metro-style "run till you die" 20-minute highs?
7. **Do multi-car shafts read?** Two cars in one shaft is simulation-cheap but might be visually confusing at 64 px floors.

**Input (test on real devices, not desktop):**
8. Are 4 column slots × 64 dp rows genuinely fat-finger-proof on a 5.5" phone with a large thumb? Is the peek-zoom lens necessary?
9. Does auto-slow-while-dragging feel like power or like cheating? (Some players may want a hard mode without it.)

**Content bets (later):**
10. Does the sumo/executive/gurney fantasy carry emotionally — do testers *name* the characters unprompted? (If yes, the character angle deserves art investment; if no, lean abstract.)
11. Is the hospital's multi-leg itinerary a highlight or homework? It's the biggest departure from point-to-point — prototype it as a cheap event ("courier" type 8) before building the theme.
12. Horizontal pods turn the game into 2D routing — is that the exciting endgame or a different game entirely? Defer until vertical feel is proven.

---

*Next step: build the §2 vertical slice in Godot graybox. First playtest question on the wall: "Did you watch the elevators?"*
