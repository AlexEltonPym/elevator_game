# Competitor & Prior-Art Research

Research for a 2D mobile-first game: cutout side view of a building, passengers arrive on floors wanting destination floors, and the player designs which elevators serve which floors and how they move. Working pitch: **"Mini Motorways but with elevators."**

Compiled 2026-08-11 from web research (sources linked inline).

---

## 1. Direct elevator-management games

### SimTower (1994) — the deepest elevator sim ever shipped

SimTower literally began as an elevator simulation: Yoot Saito was waiting for an elevator, wondering why the furthest car had to stop at his floor, and built a sim around that question; Maxis bought it and wrapped a tower-building game around the elevator engine ([Everything is bad for you](https://sonatano1.wordpress.com/2023/02/20/simtower-revisited/)). Traffic flow is controlled through the **number, location, and run schedule** of elevators.

How its elevator programming worked ([SimTower wiki](https://simtower.fandom.com/wiki/Elevators), [Relentless Optimizer](https://relentlessoptimizer.com/gaming/2021/03/17/simtower-max-tower/)):

- **Three elevator types**: *regular* (serves any floor, limited span of ~30 floors), *service* (staff/garbage/hotel only — separates back-of-house traffic), and *express* (fastest, largest capacity, but only stops at the ground lobby, sub-levels, and every-15th-floor **sky lobbies**).
- **Zoning via sky lobbies**: the express+local transfer pattern (a real skyscraper technique). Riders take an express to floor 15/30/45, then transfer to a local elevator zoned to that band. Dedicating each express shaft to a single sky lobby (parking + L1 + L15 in one shaft; parking + L1 + L30 in another) was the meta-strategy.
- **Per-car programming**: each car has a **home floor** it returns to when idle, and shafts have schedules tuned to morning up-peak / evening down-peak commuter waves. Getting cars pre-staged where demand will appear is the core skill.
- **Visible stress feedback**: waiting sims change color (black → red) as they get angry; sustained bad service makes tenants leave. The failure signal is *readable on individual people*, not just in a meter.
- **Physical constraint**: shafts consume horizontal floor space, so elevator count fights rentable space — a genuine capacity-vs-real-estate tradeoff.

**Lessons for our game:**
- Elevator gameplay is deep enough to carry a whole game — SimTower proved the loop of *place shafts → watch flow → re-zone → watch again* is compulsive.
- The three big levers are all worth stealing: **which floors a shaft serves** (zoning), **where idle cars wait** (home floors), and **time-of-day demand waves** (up-peak/down-peak).
- Sky-lobby transfers are the single most interesting emergent structure in vertical routing — the direct analogue of Mini Metro's interchange stations. Make transfers a first-class mechanic.
- Per-person visible impatience (color shift) is better feedback than abstract meters — and it's exactly how Mini Motorways shows pin buildup.
- Frustration warning: many players quit SimTower *because* elevator management became "a nightmare" of opaque micro ([Steam thread](https://steamcommunity.com/app/423580/discussions/0/358417461606712182)). The depth must be legible; SimTower buried its scheduling in dialog boxes with almost no explanation.

### Yoot Tower (1998)

The sequel; same DNA, more of a "game" than a toy, with three elevator types each with maximum floor spans, forcing chained elevator networks ([Saving Content](https://www.savingcontent.com/2011/02/08/simtower-yoot-tower-review/), [Wikipedia](https://en.wikipedia.org/wiki/Yoot_Tower)).

**Lessons:** floor-span limits per elevator type are a clean, understandable constraint that *forces* network design (chains and transfers) rather than one-shaft-serves-all solutions. Good candidate for our upgrade/constraint system.

### Elevator Saga (2015, browser)

Free JS programming game: you write real JavaScript against an elevator API; levels impose goals like "move X people in Y seconds" or "max Z moves" ([elevatorsaga.com](https://play.elevatorsaga.com/), [HN thread](https://news.ycombinator.com/item?id=47204504)). Beloved by programmers; still cited a decade later.

**Lessons:**
- The *scheduling problem itself* (which car answers which call, where cars idle, express vs. local) is intrinsically fun — people do it recreationally with no graphics at all.
- Its per-level goal variety (throughput / time limit / move budget) maps directly to a mobile level structure and to "challenge mode" variants.
- Its ceiling is also its floor: requiring literal code excludes almost everyone. Our design goal is Elevator Saga's decision space expressed through **drawn zones and toggles instead of code** — the same translation Mini Metro did to graph theory.

### Project Highrise (2016) & Mad Tower Tycoon (2018)

Project Highrise is a well-reviewed SimTower spiritual successor that deliberately **dropped elevator simulation** — one elevator can serve an 80-story tower; fans call it "a bummer to see such a big feature almost entirely missed" ([Steam discussions](https://steamcommunity.com/app/423580/discussions/0/1290690669218824410/)). Mad Tower Tycoon restored some of it: elevators have realistic floor limits and stairs matter, in a more arcade-style package ([comparison](https://nerdybookahs.wordpress.com/2019/08/25/mad-tower-tycoon-and-project-highrise-whats-the-difference/)).

**Lessons:**
- There is documented, ongoing fan demand for SimTower-style elevator management that the modern tower-sim market has explicitly declined to serve. Multiple Steam threads ask for exactly this.
- Also a cautionary note: Project Highrise cut it because full elevator sim + full economy sim is too much game. We avoid that by cutting the economy instead and making elevators the *whole* game — the Mini Metro move.

### Elevator Action (1983 / Returns)

Arcade action-platformer — you're a spy riding elevators and shooting enemies. No management or routing content. **Lesson:** nothing mechanical to borrow; only relevance is that "elevator game" searches surface it, so naming/ASO should avoid confusion with action games.

### Existing mobile elevator games

Survey of iOS/Android ([Pocket Gamer](https://www.pocketgamer.com/going-up/coming-to-android/), [App Store](https://apps.apple.com/us/app/elevator-sorting/id1640717308), etc.):

- **Going Up** — small paid elevator puzzler.
- **One Way: The Elevator** — narrative point-and-click puzzle; elevator is a framing device.
- **Elevator Sorting** — casual color-matching: pick up / drop off matching avatars. Hypercasual depth.
- **Elevator The Game / Elevator Manager** — retro time-management: *you drive one elevator* tapping floors. Reflex, not design.
- **Morning Rush** (itch.io, GameOff 2023 jam) — monochrome elevator-passenger management jam game; closest in spirit, but a one-month jam build, not a polished commercial product.

**Lessons:** every existing mobile elevator game is either (a) you *piloting* a single car in real time, or (b) a puzzle skin. **None is a systems/flow game where you design a network and watch it run.** The player fantasy of "elevator system architect" is unclaimed on mobile.

---

## 2. The Mini Metro / Mini Motorways design DNA

Sources: [Mini Metro postmortem](https://www.gamedeveloper.com/audio/postmortem-dinosaur-polo-club-s-i-mini-metro-i-), [Game Developer feature on Mini Motorways](https://www.gamedeveloper.com/audio/-i-mini-motorways-i-and-the-delicate-art-of-marrying-complexity-and-minimalism), [Elegant Constraint Optimization](https://medium.com/gaming-is-good/mini-metro-and-mini-motorways-the-art-of-elegant-constraint-optimization-2571a32fdfe2).

Why the loop works:

1. **Abstract to nodes and edges.** Mini Metro was designed "in purely abstract terms — nodes and edges instead of stations and lines." Shapes = demand types; everything readable at a glance.
2. **Relentless demand growth against limited supply.** New stations/houses spawn procedurally on a designer-controlled schedule; your network is never finished, only currently-coping.
3. **The weekly upgrade choice.** End of each in-game week: pick one of two random resource bundles (e.g. 30 road tiles vs. 20 tiles + a roundabout). This is the *only* economy — one meaningful strategic decision on a steady drumbeat, which also acts as the difficulty valve.
4. **A soft, legible failure state.** One overcrowded station / one building's pin backlog starts a visible countdown; you can rescue it. Failure is always local, diagnosable, and your fault in a way you can see.
5. **Redraw freely.** Lines/roads can be erased and redrawn at low or no cost — the game is continuous re-planning, not permanent commitment. (Freeways' biggest complaint was *lacking* undo — see §3.)
6. **Calm aesthetic as strategy.** Novelty-map visuals, no text, procedural reactive score (Disasterpeace) driven by game data. "Seemingly-simple systems that are complex in unintuitive ways."
7. **Sessions are short, runs are score-chases, maps are content.** Cities-as-levels segment content and give each map one signature constraint (rivers → bridges, mountains → tunnels).

Critically, the two games differ on the axis that matters to us: **Mini Metro is a *frequency* game** (long lines = infrequent trains = wait time) while **Mini Motorways is a *capacity* game** (roads occupy space; congestion at intersections). An elevator shaft is *both at once* — a car serving many floors comes rarely (frequency) and shafts/cars have finite size (capacity) — which is exactly why the domain is rich.

**What translates to elevators:**
- Demand growth: new floors open, new passenger sources appear, buildings grow taller mid-run.
- Weekly choice: "+1 shaft" vs. "+1 car in an existing shaft" vs. special pieces (express car, double-size car, escalator connecting 2 floors, sky-lobby transfer floor).
- Failure state: a floor's waiting crowd overflows → countdown. Local, visible, rescuable.
- Redraw: dragging a shaft's service range up/down, re-zoning stops — cheap, continuous.
- Color/shape-coded demand: passenger types as shapes (the sumo/businessman idea is the Mini Metro shapes system with personality on top).
- Calm-but-tense audio-reactive presentation; door dings and car whooshes are a gift for procedural audio.

**What doesn't translate directly (design problems to solve):**
- **Topology is 1D.** A building's floors are a line, not a 2D plane — you can't get Mini Metro's spatial variety from geometry alone. Variety must come from *demand patterns, zoning, floor-span limits, and themed constraints* (the hospital/spaceship themes, horizontal moves, sky lobbies) instead of map shape. This is the central design risk.
- **No river/mountain analogue for free** — but themed obstacles work: locked floors, quarantine wards (hospital), depressurized decks (spaceship), maintenance outages.
- **Cars move on their own schedule**, unlike drawn roads where agents route themselves; we're designing *both* the network and its timetable. That's closer to Train Valley than Mini Motorways — keep the timetable side nearly automatic with a few toggles (express, home floor, up-peak) or it becomes homework.

---

## 3. Adjacent flow-management games

### Freeways (2017, Captain Games)

Finger-draw freeway interchanges; gridlock = failure; 160 levels ([Steam](https://store.steampowered.com/app/780210/Freeways/), [Wikipedia](https://en.wikipedia.org/wiki/Freeways_(video_game))). 90% positive.
**Lessons:** (1) tactile "draw the infrastructure" input is joyful on touch — our shaft-range drag should feel like finger-painting; (2) its most-demanded feature for years was **Undo** — experimentation without penalty is non-negotiable; (3) discrete levels with efficiency grades are a valid alternative to endless runs, good for a mobile level map.

### Traffix / hypercasual traffic tappers

Tap-to-release traffic control; pure timing, one-lever interaction. **Lessons:** proves a big casual audience for "watch flow, prevent collisions/jams" on mobile, but one-lever games burn out fast; we should sit one tier deeper (design, not reflexes) while keeping one-thumb input.

### Thronefall (2023)

Strategy stripped to a few levers per run; "depth rather than breadth," gets to core gameplay in seconds ([design analysis](https://donatvatoci1.medium.com/thronefall-a-take-on-minimalism-trimming-the-fat-from-strategy-b76b2413a10c)).
**Lessons:** per-run loadout choices (pick 2–3 perks before a run) is a proven way to add strategic replay depth to a minimalist game without bloating the in-run UI — ideal for passenger-type modifiers and elevator perk builds.

### Overcrowd: A Commute 'Em Up (2020)

Isometric subway-station sim: crowd flow managed via layout, signage, and staff; commuters have needs (patience, thirst, cleanliness); builds 4 floors deep with stairs/escalators/lifts ([Steam](https://store.steampowered.com/app/726110/Overcrowd_A_Commute_Em_Up/), [3rd-strike review](https://3rd-strike.com/overcrowd-a-commute-em-up-review/)).
**Lessons:** *vertical* people-routing (entrances → platforms via stairs/escalators/lifts) is engaging; per-commuter needs create texture — but its staff/needs/inventory layers show how fast scope creeps. Take the patience need only; skip the rest.

### STATIONflow (2020)

Manage passenger flow through a 3D underground station via corridors and **signage**; minimalist look, praised for "the zen of management gameplay," criticized for shallow economy and mediocre AI ([Gamecritics](https://gamecritics.com/daniel-weissenberger/stationflow-review/), [OpenCritic](https://opencritic.com/game/9329/stationflow)).
**Lessons:** guiding flow by adjusting infrastructure while watching hundreds of dots stream through is inherently satisfying; a weak economy is *fine* if the flow puzzle is the game. Also: passenger pathfinding must be excellent — flow games live and die on believable agent behavior.

### Train Valley 1/2 (2015/2019)

Build track + switches, schedule trains, avoid collisions; puzzle-tycoon hybrid, low-poly minimalist look ([Save or Quit review](https://saveorquit.com/2019/04/19/review-train-valley-2/)).
**Lessons:** closest existing analogue to "design network *and* movement rules." Its key tension — dead time vs. collision risk when vehicles share track — maps to multiple cars per shaft. Its level-based goal structure (deliver N of each type) fits themed levels like our hospital.

---

## 4. Market gap & differentiation

### Is there a polished minimalist elevator-flow game on mobile?

**No.** Searches for the concept surface only: jam prototypes (Morning Rush), hypercasual single-car tappers (Elevator The Game, Elevator Manager), puzzle skins (Going Up, One Way, Elevator Sorting), and full tower sims where elevators are one subsystem (SimTower is abandonware; Project Highrise dropped elevator sim entirely; Mad Tower Tycoon is desktop-first and niche). Dinosaur Polo Club has covered subways and roads but nothing vertical. The specific fantasy — *design an elevator system, watch it cope, re-zone under pressure* — is unshipped as a polished mobile product.

### Evidence the demand exists

- SimTower/Yoot Tower nostalgia threads recur constantly; Project Highrise forums explicitly mourn the missing elevator management.
- Elevator Saga went viral twice (2015 and again on HN in 2025) with zero graphics — the scheduling problem alone is magnetic to a technical audience.
- Mini Metro/Mini Motorways have proven the "real-world flow problem, abstracted beautifully, on phones" market repeatedly, including on Apple Arcade.

### Differentiation for our concept

1. **Unowned theme in a proven genre.** We inherit the Mini Motorways audience's mental model (shapes = demand, draw = infrastructure, weekly choice, overflow = fail) applied to a domain nobody has claimed. Pitchable in one sentence.
2. **Frequency *and* capacity in one system.** The elevator domain naturally fuses Mini Metro's frequency tension with Mini Motorways' capacity tension (span vs. wait time; car size vs. shaft width). That's a genuinely new core sim, not a reskin.
3. **Passenger types as constraints with personality** (sumo = capacity constraint, impatient businessman = latency constraint, hospital gurney = needs the wide service elevator, spans two "slots"). Mini Metro's shapes never had *character*; ours are the marketing hook and the tutorialization device in one.
4. **Transfers as the skill ceiling.** Sky-lobby express/local architecture (validated by SimTower and real skyscraper engineering) gives the same "aha" as interchange stations in Mini Metro.
5. **Themed levels solve the 1D-topology problem.** Hospital (triage priority, gurneys, quarantine floors), spaceship (horizontal + vertical car movement — a true 2D elevator graph, which no game has done), hotel (day/night demand inversion), office tower (rush-hour waves). Each theme changes the *demand structure*, which is where this genre's variety must come from.
6. **Design, don't drive.** Every mobile competitor makes you pilot the car. We are the only "architect view" — which is exactly the calmer, deeper positioning that made Mini Metro premium-viable rather than hypercasual-disposable.

### Risks to carry into design

- 1D topology monotony if demand-pattern variety is underinvested (see §2).
- SimTower's cautionary tale: scheduling depth without legibility becomes a nightmare — every zoning rule must be visible on the building itself.
- Timetable micromanagement creep (Train Valley's stress) — keep car behavior automatic with at most 2–3 toggles per shaft.
- Undo/redraw must be free and instant (Freeways' hardest-learned lesson).

### Key sources

- SimTower elevators: https://simtower.fandom.com/wiki/Elevators · https://relentlessoptimizer.com/gaming/2021/03/17/simtower-max-tower/ · https://sonatano1.wordpress.com/2023/02/20/simtower-revisited/
- Elevator Saga: https://play.elevatorsaga.com/ · https://news.ycombinator.com/item?id=47204504
- Project Highrise elevator complaints: https://steamcommunity.com/app/423580/discussions/0/1290690669218824410/
- Mad Tower Tycoon vs Project Highrise: https://nerdybookahs.wordpress.com/2019/08/25/mad-tower-tycoon-and-project-highrise-whats-the-difference/
- Mini Metro postmortem: https://www.gamedeveloper.com/audio/postmortem-dinosaur-polo-club-s-i-mini-metro-i-
- Mini Motorways complexity/minimalism: https://www.gamedeveloper.com/audio/-i-mini-motorways-i-and-the-delicate-art-of-marrying-complexity-and-minimalism
- Constraint-optimization analysis: https://medium.com/gaming-is-good/mini-metro-and-mini-motorways-the-art-of-elegant-constraint-optimization-2571a32fdfe2
- Freeways: https://store.steampowered.com/app/780210/Freeways/ · https://en.wikipedia.org/wiki/Freeways_(video_game)
- STATIONflow: https://gamecritics.com/daniel-weissenberger/stationflow-review/
- Overcrowd: https://store.steampowered.com/app/726110/Overcrowd_A_Commute_Em_Up/
- Train Valley 2: https://saveorquit.com/2019/04/19/review-train-valley-2/
- Thronefall minimalism: https://donatvatoci1.medium.com/thronefall-a-take-on-minimalism-trimming-the-fat-from-strategy-b76b2413a10c
- Mobile elevator games: https://www.pocketgamer.com/going-up/coming-to-android/ · https://apps.apple.com/us/app/elevator-sorting/id1640717308 · https://team-sparrow.itch.io/morning-rush
