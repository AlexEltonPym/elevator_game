# v5 transition — measurement, the 2-max overlap mechanic, the level suite, and killing v4

Design + light-research doc (NOT code). It plans the move of the depth-measurement methodology from
v4 (rooms-as-cells + `tools/*` + `tests/balance.gd`) to v5 ("Rooms": multi-cell rooms, baked docks,
lifts docking beside rooms, walk time, transfer rooms, one-lift corridors, reactivation/itineraries),
the new **2-max tile overlap** constraint that makes some v5 levels genuine puzzles, the level-class
taxonomy that decides how each level is judged, and the safe order to port-then-remove v4.

Grounding: `docs/autodesign-research.md` (methods + citations), `docs/depth-tools-spec.md` (v4
scoring/seeds/metrics), `docs/surrogate-design.md` (learned pre-screen), `docs/ablation-report.md`
(what each v4 mechanic is worth), and the shipped v5 code (`scripts/v5/*`, `tests/v5_smoke.gd`).
Tags as elsewhere: **[established]** = published/standard; **[speculative]** = my adaptation.

---

## 0. Recommendation up front

1. **Do not build two measurement tools. Build one measurement PASS with two READINGS.** Every v5
   level is run through the same machinery (`sim_api5` + the optimizer + a MAP-Elites archive). What
   differs is only the *headline* statistic, chosen automatically from what the pass observes:
   - **soft-border / optimization levels** — headline = random-win-rate (the floor) + `skill_gap` +
     the strategy ladder, exactly as v4. Many legal route-sets, quality varies.
   - **constraint-puzzle levels** — headline = **solver solvability** (Ropossum-style: a real
     optimizer finds ≥1 legal win, not random luck) + **solution scarcity `K`** (count of
     structurally-distinct winning route-sets from the archive; 0 = broken, few = good puzzle,
     many = trivial) + **evals-to-first-solution** as the difficulty x-axis. Random-win-rate here is
     ~0 by construction and is used only to *confirm* the level is puzzle-shaped, never as difficulty.
2. **Auto-classify from two cheap quantities** the pass already produces — the random-win count and
   the solver's evals-to-first-win — with a hard third bucket for **broken/unverified** so an
   *impossible* level can never masquerade as a *hard* one (the exact failure the v4 metric has on
   puzzles). Rule and thresholds in §2.3.
3. **Add the 2-max tile overlap as a HARD drawing cap** (§3). It is the mechanic that *creates* the
   constraint-puzzle level shape (turns routing into a Numberlink-like vertex-disjoint-paths problem),
   and a hard cap is the only version that actually collapses the solution set; a soft penalty just
   re-smooths the landscape back into a soft-border level.
4. **Port, then remove — never lose the green line.** v5 tooling + a v5 balance suite + a v5 level
   suite must all exist and pass *before* v4 is deleted, so at every commit *some* balance suite is
   green. Phase order in §5. v4 stays frozen (fingerprint `3552943357`, balance `182 ALL PASS`) until
   the very last phase.
5. **Own reactivation as a first-class, ENDOGENOUS demand mechanic.** v5 passengers reactivate into a
   fresh trip toward a *network-reachable* room (`main5.gd:520`), so demand depends on the route-set
   the player drew. This breaks v4's static trip-table assumption and is the subtlest port item — it
   is where "the plan is priced against reality" is most likely to quietly become false (§4.4, §6).

Highest-value papers for the new (puzzle) half, in order: Shaker/Shaker/Togelius 2013 (Ropossum,
solver-verified playability + the solver-relative caveat), Smith/Butler/Popović 2013 (uniqueness as a
first-class design constraint), Demaine et al. 2014 (Numberlink NP-completeness; poly-time for *fixed*
pair count — why our tiny rosters stay solvable), Sturtevant & Ota 2018 (exhaustive enumeration on
tiny content spaces, our ground-truth for `K`), Gravina et al. 2019 (QD as the scarcity/diversity
estimator).

---

## 1. What v5 is, in the terms the tooling needs

The tooling only cares about the sim's inputs and outputs, so pinning those down first makes the port
concrete.

- **A route serves a room iff its polyline passes a DOCK cell** of that room (`Grid5.dock_rooms`,
  `Route5.served()`). Rooms are multi-cell and NOT routable (`Grid5.passable` is false on room cells).
  So the search's atom is no longer "which room cells are on the line" (v4) but **which dock cells,
  in what order** — a dock is a `(room_id, cell, dir)` triple, and one open cell flanked by two rooms
  serves both (the "double duty" case, R-2).
- **Node = room id; edge = a car that serves both endpoints**, cost = ride time + intermediate dock
  stops × `stop_penalty` + `LEG_WAIT` + **real walk** (`Grid5.WALK_PER_TILE` × Manhattan from queue
  tile to board dock, and alight dock to queue tile) (`Pathfind5.find_path`). A room served by 2+ cars
  is a transfer room, emergent.
- **One-lift corridors** are routable open cells carrying a width; contiguous cells form one FIFO
  mutex group; a car enters iff `car.width ≤ group.width` and the sum of widths inside stays
  ≤ width (`Grid5.corridor_*`, `main5.gd:615`). Default width 2 = one normal (width-2) lift at a time.
  This is a **runtime** constraint on simultaneous cars.
- **RUN gate** = every *provided* card has a legal route (variable roster, 1–3), not v4's "every card
  must be routed."
- **Reactivation** (`main5.gd:517`, `passenger5.reactivate`): on arrival, with prob `level.reactivate`
  (default 0.25), a passenger picks a new destination *reachable on the current network* and starts a
  fresh trip from where it is. Endogenous demand.
- **Determinism** is already proven headless: `tests/v5_smoke.gd` instantiates `v5_main.tscn`, commits
  a hand solution, `advance(0.1)`s to win/lose, and asserts a per-step position/served/lost signature
  is bit-identical across two runs. That signature is the seed of `fingerprint5`.

The good news for the port: the expensive, bug-prone half of `sim_api.gd` — the headless discipline
(HUD builds nothing; node leaves the tree after `_ready` so the MessageQueue never fills) — has a v5
equivalent already working in `v5_smoke.gd` (`Levels5.headless`, `node.headless`, the
instantiate/commit/`advance` loop). sim_api5 is largely that loop with the batch/cache/scoring
wrapper from `sim_api.gd` bolted on.

---

## 2. The dual measurement problem (the crux)

### 2.1 Why the single v4 metric can't cover both

v4's headline is **random-win-rate**, and `docs/depth-tools-spec.md §1` is explicit that *"the random
win rate IS the difficulty metric"* — it answers "does the level have a floor at all," targeted ≤ 5 %.
`skill_gap = ea@6400 − random@6400` and the ladder then say *how much search buys you*. This is the
right instrument for an **optimization landscape**: a level where many route-sets are legal, a small
fraction win, and quality varies smoothly, so uniform-random sampling lands a measurable handful of
wins (v4 measured 0.3–3.1 %) and the losing branch carries a dense gradient (250–546 distinct scores
per level).

On a **constraint puzzle** — snake-like, few legal winning configurations — this instrument
degenerates:

- random-win-rate is **~0 trivially**, because the legal-winning set is a measure-zero speck in
  route-set space. So it cannot separate **hard-but-solvable** from **impossible** — both read 0.
- `skill_gap` is **0 or a cliff**: random gets 0; the EA either also gets 0 (→ gap 0, looks shallow
  *and* looks like the random-win-rate says "impossibly hard") or finds the one answer (→ gap = the
  whole WIN_BONUS in a single budget doubling, a step function, not a staircase).
- the ladder is a **cliff, not a ladder** — no intermediate rungs, because there is no continuum of
  "better" partial plans, just legal/illegal.

A level can be an excellent tight puzzle and score identically, on every v4 number, to a broken
unsolvable one. That is the problem to solve.

### 2.2 The two readings

Both readings come out of **one** pass (search + archive) so the machinery, seeds, and cache are
shared; only the summary changes.

**Reading A — soft-border (optimization).** Unchanged from v4. Report, all medians over the held-out
test seeds:
- `random_win_rate` (the floor; the difficulty metric). Lower bound τ_soft below → meaningful.
- `skill_gap = margin(ea@B) − margin(random@B)` at matched budget.
- the ladder: `margin` vs log-budget, and `ladder_steps` (Lantz et al.'s strategy ladder, currency
  swapped from win-rate to score-margin, resource axis = optimizer evals — as `autodesign-research.md
  §4.1` already establishes for v4). **[established, adapted]**
- `K` (below) as a *secondary* "is there choice" check.

**Reading B — constraint puzzle (solver-verified).** For levels where random is blind:
- **(a) Solvability** — a real optimizer (beam → EA → MAP-Elites) finds ≥ 1 **legal winning**
  route-set within budget `B_max` on **≥ 7/8 test seeds**. This is Ropossum's move: solvability turned
  from a human playtest into a machine predicate the loop can check unattended. **[established]** With
  Ropossum's non-negotiable caveat: it is *solvability-relative-to-our-solver* — the claim is always
  **"winnable by our optimizer within budget B,"** never "winnable," and it inherits our decoder's
  blind spots (`autodesign-research.md §1.1`). Report the budget qualifier every time.
- **(b) Scarcity / diversity `K`** — the count of **structurally-distinct** winning route-sets, taken
  from the MAP-Elites archive: a winning niche counts once, and two winners are the same solution if
  their `routegen5.structural_distance` (Jaccard over per-card served-room / dock sets, plus loop /
  corridor / overlap-usage flags) is below a fixed threshold. `K = 0` broken, `K` small = good tight
  puzzle, `K` large = trivially many answers. This is the puzzle-PCG **uniqueness-as-quality** signal
  (Smith/Butler/Popović constrain *unwanted extra* solutions away with ASP; Numberlink/Sudoku
  generators prize near-unique instances). **[established transfer]** On the smallest puzzles,
  ground-truth `K` by **exhaustive stop-sequence enumeration** under the overlap cap (Sturtevant &
  Ota's EPCG — feasible because our content space per level is tiny) to calibrate the archive's `K`.
- **(c) Difficulty = search-effort-to-first-solution** — `e1` = median evals until the optimizer's
  first win, the ladder x-axis, **not** random-win-rate. Report alongside solver-derived structural
  features (decision points, dead-ends) à la van Kreveld 2015 / the AIIDE-2024 solution-information
  work. **Caveat [established]:** solver-effort ≠ human difficulty (Sturtevant 2020, Snakebird) — `e1`
  is a *within-level relative* difficulty, never an absolute rating, and must be sanity-checked by
  hand-solving the small ones.

### 2.3 Auto-classification rule (the concrete decision)

Run **both probes on every level** — they are cheap and share the search:
- `P1 = random_win_rate` over N ≥ 600 uniform **decodable** samples (v4's `--scorecheck`), reported as
  the raw win **count** `w_rand` (the count, not the rate, is what governs whether `skill_gap`/ladder
  are computable — a rate of 0.3 % is 1–2 wins and already noisy).
- `P2` = the solver ladder: `e1` (evals-to-first-win), whether solvable within `B_max` on ≥ 7/8 seeds,
  and `K` from the archive.

**Primary rule.** Let τ_soft = **5 decodable random wins out of ≥ 600 samples (≈ 0.8 %)**.

| condition | class | headline suite |
|---|---|---|
| `w_rand ≥ 5` (≈ rwr ≥ 0.8 %) | **soft-border** | Reading A (rwr floor, skill_gap, ladder); K secondary |
| `w_rand < 5` **and** solvable within `B_max` on ≥ 7/8 seeds | **constraint puzzle** | Reading B (solvable, K, e1) |
| `w_rand < 5` **and** NOT solvable within `B_max` | **BROKEN / unverified** | red — do NOT ship |

The **BROKEN bucket is the whole point**: it is exactly the region v4 silently labels "very hard." A
level with rwr ≈ 0 is either a good puzzle *or* impossible, and only the solver probe tells them apart.

**Two confirmations that guard against misclassification** (a leaky puzzle whose few random wins are
lucky straddlers, or a soft-border level the solver happens to crack in one jump):
- **Ladder-shape check.** A true soft-border level improves across *several* budget doublings
  (`ladder_steps ≥ 2`); a puzzle's ladder is a step function (all improvement in one doubling near the
  win boundary). If a level classifies soft-border by `w_rand` but its ladder is a cliff, **reclassify
  as puzzle** — its random wins were straddlers.
- **Scarcity cross-check.** Compute `K` on *both* classes. A "soft-border" level with `K = 1` is a
  puzzle with a slightly leaky border; a "puzzle" with `K` filling most of the archive is really a
  soft-border level with a stingy rwr sample. When `w_rand` and `K` disagree on which regime, trust
  `K` (it is the structural quantity; `w_rand` is a noisy Monte-Carlo estimate near zero).

**`K` bands (both classes read them):** `K = 0` broken; `K ∈ {1,2}` tight/near-unique puzzle (the
Numberlink/Refraction sweet spot — ship only if *intended* to be that tight); `K ∈ [3,12]` a
constraint puzzle with satisfying alternatives, or a lean optimization level; `K` > ~⅓ of archive
cells (or `w_rand` high) → the many-answers / trivial regime.

### 2.4 What transfers, and what doesn't

| source | transfers as | caveat |
|---|---|---|
| Ropossum (Shaker et al. 2013) | solvability as a machine predicate; report "solvable by our optimizer within budget B" | solver-relative; inherits decoder blind spots |
| Numberlink NP-completeness (Demaine et al. 2014) | the 2-max cap makes routing a vertex-disjoint-paths problem → few legal solutions | hardness needs *pairs growing with size*; at our **fixed** ≤3 cards it's poly-time, which is *why* our solver mode is tractable |
| Refraction / "Quantifying over play" (Smith/Butler/Popović 2013) | `K` (solution count) as a first-class quality signal and design target; constrain extra solutions away | uniqueness is a *design intent*, not automatically good |
| EPCG (Sturtevant & Ota 2018) | exhaustive enumeration of winning stop-sequences on small puzzles → ground-truth `K`, calibrates the archive | only tractable because per-level content space is tiny |
| QD / MAP-Elites (Gravina 2019; Mouret & Clune 2015) | the archive that yields `K` and the diversity of solutions | descriptor-dependent; `K` only as honest as the behaviour space (hand-watch elites) |
| Strategy ladder (Lantz et al. 2017) | soft-border DEPTH; also the puzzle `e1` axis | ladder may be smooth (soft) or a cliff (puzzle) — that *is* the classifier signal |
| Restricted play (Jaffe et al. 2012) | the THESIS/ablation bar (§4) for "does mechanic X earn its place" | heuristic-agent version, per `ablation-report.md` |
| Solution-effort / entropy difficulty (van Kreveld 2015; AIIDE 2024) | puzzle difficulty features beside `e1` | solver-effort ≠ human difficulty (Sturtevant 2020) |
| Game-refinement theory (Iida) | — | does NOT transfer (outcome-uncertainty-over-time is meaningless when you commit a plan then watch) |

---

## 3. The 2-max tile overlap constraint

### 3.1 What it is, and what it is NOT

A tile can carry an **`overlap_max`** = the number of distinct elevator ROUTES whose *committed
polyline* may include that tile (default 2). This is a **static, planning-time** cap on how many lines
may be *drawn* through a cell.

It is explicitly **distinct from the one-lift corridor mutex**, which caps the sum of *car widths
physically inside* a corridor group *at runtime* (`main5.gd:615`). They measure different things and
**compose**:

| | 2-max overlap | corridor width mutex |
|---|---|---|
| counts | distinct **routes drawn** through the tile | sum of **car widths present** in the group |
| when | commit / plan time (static) | every sim step (dynamic) |
| authored as | `overlap_max` per cell (default 2) | `width` per corridor (default 2) |
| effect | caps how many *lines* the route-set may thread here | serialises *cars* sharing the choke at runtime |

A cell can be **both** an `overlap_max=2` tile and a width-2 corridor: two routes may legally be drawn
through it (overlap ok), yet their cars still take turns at runtime (corridor mutex). One is about the
*shape of legal route-sets*; the other about *scheduling*.

### 3.2 Hard or soft? — HARD.

**My call: a hard drawing limit, refused at commit, not a penalty.** Reasons:

1. **It is the mechanic whose job is to collapse the solution set.** A soft/penalised overlap just
   adds another smooth term to the objective — the level stays a soft-border optimization landscape
   and would auto-classify (§2.3) as soft-border, which defeats the entire purpose of having it. Only
   a hard cap produces the Numberlink-like *few-legal-configurations* shape that Reading B measures.
   [speculative, but this is the design intent stated plainly]
2. **It is already the game's idiom and it is legible.** `commit_route` already hard-refuses a route
   that is "too wide for that corridor" with an immediate red rejection (`main5.gd:392`). An
   overlap-cap refusal is the same UX: try to commit the 3rd line through a cap-2 tile, get a red
   "no room to thread here." Deterministic, instant, no hidden reward-shaping.
3. **It is a clean legality predicate for the optimizer** — a genome is legal iff every capped tile
   has ≤ `overlap_max` routes crossing it. No gene needs a penalty weight; invalid genomes score −INF
   and cost no budget, exactly as undecodable legs do today.

The **tuning gradient lives in the authoring, not the mechanism**: `overlap_max=1` tiles are
single-line lanes (the Numberlink wire), `=2` tiles are shared trunks exactly two lines may thread,
`=3`/unlimited elsewhere. A designer dials the constraint tightness by *where* the caps go; the
mechanism stays crisply hard.

### 3.3 Authoring, and how it makes a puzzle

- **Per-cell field**, carried in the level data like corridors carry width: an `overlaps` list of
  `{cells:[...], max:int}` (default `max = 2`). Un-annotated open cells are effectively `max = ∞`
  (today's behaviour), so existing v5 levels are unchanged.
- **A channel of `max=1` cells = a single-route lane**; a region of `max=2` = a shared trunk. Add
  enough of them and the set of route-sets that both (i) obey every cap and (ii) still serve all
  required rooms collapses to a handful of **vertex-disjoint (or ≤2-shared) path assignments** — the
  precise structure that makes Numberlink NP-complete in general (Demaine et al. 2014). Because our
  roster is **fixed and tiny (≤3 cards)**, the instance is the poly-time (fixed-pair-count)
  vertex-disjoint-paths case, which is *why* our solver mode terminates and `K` is enumerable on the
  small ones. **[established analogy]** This is the mechanic that *creates the constraint-puzzle level
  shape*.

### 3.4 How route-genes / the optimizer must respect it

- **Decode maintains a shared `cap_left` map.** `routegen5.decode_genome` decodes the cards in a fixed
  order, threading a `cap_left: {cell → remaining}` dict initialised from the level's caps. Each card's
  BFS treats a cell with `cap_left == 0` as **blocked for this route** (same code path as the existing
  `used`/blocked set in `routegen.gd:_bfs`). A leg that can only route through an exhausted cell makes
  the genome **invalid** (−INF, no crash) — identical handling to an undecodable leg today. Determinism
  preserved (fixed neighbour order, fixed card order).
- **This makes genome legality order-dependent in the decoder** (card 0 claims capacity first). That is
  fine for a deterministic search but the optimizer must be able to *rearrange* who gets scarce
  capacity, so add two operators to `routegen5` (both TRNDP-idiomatic):
  - a **reorder-cards** mutation (permute the decode order / card-to-gene binding),
  - a **capacity-repair** operator: when a leg is blocked by an exhausted tile, reroute it around the
    exhausted cells (re-BFS with those cells hard-blocked) before declaring the genome invalid —
    analogous to the TRNDP "fix a disconnected route" repair operators (`autodesign-research.md §2.4`).
- **Primitive seeding must be capacity-aware**: the hand-built primitives (spine, ring, shuttles) are
  decoded through the same `cap_left`, so the seed population is already legal under the caps rather
  than mostly-invalid.
- **RUN gate re-validates the whole set.** Interactive commit refuses the offending 3rd line in commit
  order, but because commit order is a UI artifact, the RUN gate additionally checks the full route-set
  against the caps, so a legal final configuration is always reachable by clear-and-redraw.

**Flag:** a hard cap makes **over-constraint by construction** easy to author — a level can be
*unsatisfiable* (no legal route-set serves all rooms) or satisfiable only by a path our decoder can't
represent. The solvability probe (§2.3) must gate **every** overlap-puzzle level before ship, and the
small ones need exhaustive-enumeration ground truth + a human solve, because "our solver found nothing"
and "no solution exists" are the two states the tooling most easily confuses here (§6).

---

## 4. Level-class taxonomy for v5

Three classes. Each has an **acceptance bar** = which measurement mode + thresholds, and each mechanic
that must justify itself gets a **thesis** level.

### 4.1 Tutorial (the LEARN-style inverse bar)

Ramped, forgiving, one new idea at a time. The bar is the **inverse** of the difficulty gate: a
tutorial *should* be beatable by naive/random play so a first-timer cannot fail by trying.

- **Mode:** soft-border, **bar inverted**. Target **random-win-rate HIGH** (e.g. `rwr ≥ 40 %`), short
  ladder (`ladder_steps ≤ 1`), `K` large (many ways to win). A tutorial is **never** a constraint
  puzzle — if it auto-classifies as puzzle or broken, it is mis-built.
- **Thesis mechanic:** none — it *teaches* one mechanic in isolation, it doesn't *prove* it.
- R-1 "One Lift" and R-2 "Double Duty" are already this shape.

### 4.2 Thesis (proves a mechanic earns its place)

The restricted-play / ablation bar from `docs/ablation-report.md`: neutralise the mechanic and show the
level collapses. A mechanic is **load-bearing** iff `restrict_Δ[omit-mechanic]` is large — concretely,
the hand thesis WINS ≥ 15/16 assert-seeds *with* the mechanic and drops sharply *without* it (the exact
form the v4 ablation used: capacity 16→0, acceleration 16→6 on L3, etc.). For the **new** v5 mechanics
the thesis must additionally show the mechanic adds **depth** (`ladder_steps` up), **choice**
(`QD_coverage`/`K` up), or is an honest **constraint** (a wall some cars pass — coverage *down*, which
is a legitimate design-vocabulary verdict, not a failure).

| mechanic | new in v5? | thesis level naturally… | acceptance bar |
|---|---|---|---|
| rooms / docks (service model) | yes (core) | **soft-border** | many dock-threadings; skill_gap > 0; `K` healthy |
| transfer rooms | yes | **soft-border (structured)** | `QD_coverage` up vs a no-transfer variant; ride-local-then-express is a distinct winning niche |
| walk / dock-distance | yes | **soft-border (latency knob)** | restricted-play: price walk → 0; axiom must weaken (like the accel ablation) |
| one-lift corridor (width mutex) | ported to v5 | **constraint-leaning** | `restrict_Δ[omit]` large; expect coverage *down* (the "wall some cars pass" verdict, per ablation-report) |
| **2-max overlap** | yes | **constraint PUZZLE** | Reading B: solvable ≥7/8; `K ∈ {1..~6}`; the intended solution is among the winning niches; NOT broken |
| reactivation / itineraries | yes | **soft-border (demand)** | restricted-play: set `reactivate → 0`; a plan tuned for base demand must lose under shipped reactivation (proves the between-trip demand is load-bearing) |
| acceleration / express | ported | **soft-border** | re-run the v4 ablation in v5 (real over long legs & gates; keep accel-by-width unless the walk model changes the arithmetic) |
| width / cargo | ported | **constraint / soft hybrid** | restricted-play on width (W-1 freight, W-2 narrows shape); capacity real where throughput-bound |

**The 2-max overlap thesis is the one that is definitively a constraint puzzle** and is measured by
Reading B; the corridor and width theses lean constraint but are usually measured as soft-border with a
strong `restrict_Δ`; everything else is soft-border. R-3 (transfer) and R-4 (big store) are soft-border
today; R-5 (bottleneck) is a mild corridor thesis.

**Port the v4 ablation verdicts, but re-run — don't assume.** `ablation-report.md` concluded capacity
is real, acceleration bites on long legs/gates, home-floor is CHROME (cut). The v5 walk-time and
dock-distance model **changes the per-stop arithmetic** those verdicts rest on (the report's own
door-dwell-vs-momentum calculation), so each ablation must be re-measured under the room model before
its verdict carries over.

### 4.3 Generic (campaign filler)

The standard gate: auto-classify (§2.3) and pass *some* mode cleanly.
- soft-border: `rwr ≤ 5 %` (upper bound — not too easy) **and** `w_rand ≥ 5` (lower bound — rwr is
  meaningful) **and** `skill_gap > 0` **and** ladder not flat.
- puzzle: solvable on ≥ 7/8 seeds **and** `K ∈ [2,12]` **and** not broken **and** `e1` in a sane band.
- The only *failure* is landing in the **BROKEN/ambiguous** zone — `rwr ≈ 0` with no solver solution,
  or `w_rand`/`K`/ladder-shape disagreeing on the class after the §2.3 confirmations.

---

## 5. Port + removal plan (never lose verification)

**Invariant:** at every commit, *some* balance suite is green. v4 stays frozen and fully removable only
after v5's green gate + level suite exist and pass. `sim_api5`, `routegen5`, `optimizers5`, `metrics5`,
`balance5`, `scenarios5`, `fingerprint5` are new files beside the v4 ones (duplicate, don't entangle —
same posture the prototype already took).

### 5.1 What ports vs is rebuilt

| v4 asset | v5 disposition |
|---|---|
| `sim_api.gd` | **ports structurally** → `sim_api5`: same batch loop / run-cache / seed sets / scoring, but loads `v5_main.tscn` + `Grid5`, and `_harvest` reads v5 stats (served/lost, `reactivations`, `gate_wait`, walk-time). The headless discipline is already proven in `v5_smoke.gd`. Re-verify WIN/LOSE score separation per v5 level (`--scorecheck`); v5 quotas/timeouts differ. |
| route-genes `routegen.gd` | **rebuilt representation** → `routegen5`: gene stop = a **dock cell** (not a room cell); decode = BFS between consecutive docks over passable OPEN cells; thread the **overlap `cap_left`** map across cards (§3.4); add reorder-cards + capacity-repair operators. `demand()` re-keyed on room letters/trips; `structural_distance` reuses `Route5.served_rooms()`. **Add reactivation to the demand model (§4.4 below).** |
| `optimizers.gd` | **ports nearly unchanged** (random / beam / EA / MAP-Elites over genomes). Add Reading-B outputs: `e1` (evals-to-first-win), winning-niche dedup → `K`. New archive descriptors for v5 (transfers, corridor transits, walk-time total, dock-overlap usage, express utilisation). |
| `metrics.gd` | **extends**: keep M1–M6; add solvable / `K` / `e1` and the **auto-classifier** (§2.3). |
| `tests/balance.gd` + `scenarios3.gd` | **rebuilt** → `balance5` + `scenarios5`. The 4 disjoint seed roles port verbatim (watch / TUNE / ASSERT / TRAIN+TEST). Soft-border axiom form ports (thesis WINS ≥15/16, naive LOSES ≥15/16); **puzzle axiom form is new**: solvable ≥7/8 AND `K` in band AND the intended solution among winning niches. `v5_smoke.gd` is the seed of `balance5`. |
| seed discipline | **verbatim** — median-over-test, lower-median aggregation, TRAIN never sees TEST/ASSERT. |
| `export.gd` / `export_verify.gd` | **ports + extends**: rows key stops as dock-cell sequences; add `reactivations`, `walk_time`, per-tile overlap usage, corridor transits; level static tensor gains an `overlap_max` channel beside the corridor-width channel. |
| `fingerprint.gd` / `run_fingerprint.gd` | **method ports** → `fingerprint5`: promote `v5_smoke.gd`'s per-step signature to a real fingerprint. v5 gets its **own** baseline hash (v4's `3552943357` stays the v4 reference until v4 is deleted). |

### 5.2 Reactivation as a first-class demand mechanic (the modeling item the port must own)

v4's demand is a **static** trip matrix (`routegen.demand`). v5 reactivation makes demand
**endogenous**: extra trips are generated toward rooms *the drawn network can reach*, so the demand a
plan must serve **depends on the plan**. Consequences the tooling must handle:

- **The analytical pre-screen / Pathfind5 pricing must not silently ignore it.** `Pathfind5` already
  omits reactivation from leg cost — acceptable for in-game planning, but for the surrogate/pre-screen
  it biases the demand estimate. Recommended first-order model **[speculative]**: expected extra trips
  ≈ `p/(1−p)` × the reactivation-destination distribution over network-reachable pairs (a geometric
  expansion), computed as a one-step fixed point on the served-flow estimate. Ship it as an explicit,
  flagged approximation; the **true sim always has the last word** (the surrogate only screens).
- **Balance/axioms must test it:** the reactivation thesis (§4.2) sets `reactivate → 0` as a
  restricted-play knob and shows a base-demand-tuned plan loses under shipped reactivation.

### 5.3 Phase order

- **Phase 0 — freeze + baseline.** Capture `fingerprint5` (promote the smoke signature). v4 frozen
  (`3552943357`, `182 ALL PASS`) as the untouched reference. No deletions.
- **Phase 1 — 2-max overlap in the GAME.** `overlaps` authoring field; hard commit rejection + HUD
  legibility; decode-time `cap_left`. Add 1–2 overlap-puzzle levels. Extend `v5_smoke` (a 3rd line
  through a cap-2 tile is refused; RUN gate re-validates the full set). Game-side must land before the
  tooling can measure it.
- **Phase 2 — `sim_api5` + `routegen5` + scoring, verified.** Prove `--scorecheck` per v5 level
  (WIN/LOSE separation), determinism (repeated headless run bit-identical), coarse-vs-fine rank
  correlation. Gate: the `v5_smoke` hand theses reproduce as wins through `sim_api5`.
- **Phase 3 — `optimizers5` + `metrics5` + auto-classifier.** Implement both headline suites and the
  §2.3 classifier; generate the first v5 depth report classifying every level soft/puzzle/broken. On
  the smallest overlap puzzle, run exhaustive enumeration to ground-truth `K` and calibrate the archive.
- **Phase 4 — `balance5` + `scenarios5` (the green gate).** Per-class axioms (soft-border counts;
  puzzle solvable+K+intended-solution). Wire M1/M2/M6-seed (+ solvable/K for puzzles) as regression
  asserts. v5 now has its own "ALL PASS."
- **Phase 5 — the v5 level suite.** Tutorials (inverse bar), a thesis per mechanic (§4.2), generics —
  each passing its class bar via the tooling. Re-run the v4 ablations under the room model to confirm
  (or revise) the capacity / acceleration / home-floor verdicts.
- **Phase 6 — remove v4, in this order, only once Phases 2–5 are green:** (a) confirm `balance5` +
  `fingerprint5` green and the level suite complete and committed; (b) repoint the level-select /
  campaign so nothing loads a v3 scene; (c) delete `scripts/v3`, `scenes/v3_*`, `tests/balance.gd` +
  `scenarios3.gd`, and repoint or delete the Grid3-bound `tools/*`; (d) **keep the v4 rationale docs**
  (`ablation-report.md`, `autodesign-research.md`, `depth-tools-spec.md`, `surrogate-design.md`) as
  historical reasoning — delete the code, not the argument. Update `MEMORY.md`. The v4 green line is
  only retired in the *same* state where the v5 green line is already passing.

---

## 6. The single biggest risk

**Puzzle-mode solvability is only ever "solvable by our optimizer within budget B" (Ropossum's
solver-relative caveat), and the hard 2-max overlap makes over-constrained levels trivially easy to
author — so the two states our tooling most easily confuses are exactly the two that matter: a *false
BROKEN* (our decoder missed a real solution) and a *false GOOD PUZZLE* (the solver found a path no
human would, or the level is near-unique for the wrong reason).** The auto-classifier's whole value is
the BROKEN bucket, and that bucket's correctness rests entirely on a solver whose blind spots are
unknown. Mitigation is non-negotiable and layered: exhaustive stop-sequence enumeration under the cap
on the small puzzles (ground-truth `K` and true solvability, Sturtevant EPCG), a strong multi-restart
solver with the capacity-repair operator, and a **human solve** of every shipped overlap puzzle before
the tooling's "solvable / K = n" verdict is trusted — the automated numbers are a filter, never the
verdict (Jaffe, King, Sturtevant are unanimous on this).

---

## Sources (new to this doc; the rest are catalogued in `docs/autodesign-research.md` §7)

- Shaker, Shaker & Togelius (2013). *Ropossum: An Authoring Tool for Designing, Optimizing and Solving
  Cut the Rope Levels.* AIIDE. https://ojs.aaai.org/index.php/AIIDE/article/view/12611
- Smith, Butler & Popović (2013). *Quantifying Over Play: Constraining Undesirable Solutions in Puzzle
  Design.* FDG.
- Demaine et al. (2014). *Zig-Zag Numberlink is NP-Complete.* https://arxiv.org/pdf/1410.5845 ·
  https://dspace.mit.edu/bitstream/handle/1721.1/100008/Demaine_Zig-zag.pdf
- Numberlink overview (fixed-pair-count → poly-time vertex-disjoint paths).
  https://en.wikipedia.org/wiki/Numberlink
- Sturtevant & Ota (2018). *Exhaustive and Semi-Exhaustive Procedural Content Generation.* AIIDE.
  https://www.cs.du.edu/~sturtevant/papers/sturtevant18epcg.pdf
- Gravina, Khalifa, Liapis, Togelius & Yannakakis (2019). *PCG through Quality Diversity.* IEEE CoG.
  https://arxiv.org/pdf/1907.04053
- van Kreveld, Löffler & Mutser (2015). *Automated Puzzle Difficulty Estimation.* CIG.
- *Generalized Entropy and Solution Information for Measuring Puzzle Difficulty* (AIIDE 2024).
  https://ojs.aaai.org/index.php/AIIDE/article/download/31872/34039
