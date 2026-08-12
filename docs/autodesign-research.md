# Automated game design, level solvability, and measuring depth

Research notes for the elevator network-planning prototype (Godot, `scripts/v3`, `tests/balance.gd`).
Compiled 2026-08. Every claim is tagged **[established]** (published, replicated, or standard
practice) or **[speculative]** (my adaptation to our game; nobody has published this for a
route-drawing sim).

---

## 0. Recommended approach for this project (read this part first)

**Our player's problem is, formally, the Transit Route Network Design Problem (TRNDP).** A
solution is a set of routes over a graph; the objective is passenger-weighted travel/wait time
under vehicle constraints. That is a 50-year-old NP-hard OR problem with a mature metaheuristic
literature (§2.4). This is the single most useful reframing in this document, because it tells us
what search algorithm to use without inventing one.

**Recommended pipeline**

1. **Change the representation before searching.** Do not search over cell polylines. Search over
   *ordered room-stop sequences*; decode a sequence to cells with a deterministic connector
   (A* between consecutive stops, with a per-route `avoid_gates` / `prefer_gates` bit and a
   `closed` bit). Cell-level search is ~10^20 self-avoiding walks on a 7x10 grid; stop-level search
   is ~`r!·e` per route (10 rooms → ~10^7), which metaheuristics handle. **[established reframing,
   [speculative] for our exact decode]**
2. **Seed with hand-built route primitives**, not random genomes: full-height spine, express
   lobby↔penthouse, two-room shuttle, perimeter ring, closed loop around the ring, hub feeder,
   k-shortest-paths between the top-weighted `trips` group pairs. Primitive-seeded population is
   standard practice in TRNDP ("route generation phase" then "route selection phase").
3. **Run MAP-Elites as the primary optimizer**, not a plain EA. It yields the ceiling *and* the
   diversity-of-viable-strategies archive, which is exactly the "CHOICE" measurement we want, in
   one run (§4.6). Keep a (μ+λ) EA and a greedy beam-search as cheap baselines/agent-ladder rungs.
4. **Never use one seed.** Evaluate every candidate on a fixed set of ≥8 seeds; hold out a second
   disjoint set for reporting. Our sim is deterministic per seed, so a single-seed optimizer will
   exploit the exact pulse schedule (§6.2).
5. **Track this metric set per level** (§5.2): `ceiling`, `skill_gap`, `ladder_steps`,
   `QD_coverage` / `QD_score`, `restricted_play_Δ` per mechanic, `plan_fragility` vs `seed_fragility`.
6. **Answer "does mechanic X add depth?" with a matched-budget ablation plus restricted play**
   (§5.3). The decisive signal is *not* "the ceiling moved" — it is "the archive of distinct
   winning strategies grew". A mechanic that raises the ceiling but shrinks the archive made the
   level *more constrained*, not deeper.
7. **Use the metrics as an early-warning system, never as the objective you tune levels against**
   (§6). Jaffe et al. 2012 explicitly frame their tool this way and it is the right posture.

Highest-value papers to actually read, in order: Lantz et al. 2017 (depth), Jaffe et al. 2012
(restricted play), Nielsen et al. 2015 (relative algorithm performance profiles), Gravina et al.
2019 (QD for PCG), Shaker/Shaker/Togelius 2013 (Ropossum, solver-verified PCG).

---

## 1. Solver-verified PCG: Ropossum and its relatives

### 1.1 Ropossum / Cut the Rope

Two companion AIIDE-2013 papers by Mohammad Shaker, Noor Shaker and Julian Togelius:

- **Ropossum: An Authoring Tool for Designing, Optimizing and Solving Cut the Rope Levels**
  (AIIDE 2013) — https://ojs.aaai.org/index.php/AIIDE/article/view/12611
- **Evolving Playable Content for Cut the Rope through a Simulation-Based Approach**
  (AIIDE 2013) — https://ojs.aaai.org/index.php/AIIDE/article/view/12690

**How it works.** [established]

- Content representation: level layouts (rope anchors, air cushions, bubbles, candy, elastics)
  evolved by **grammatical evolution** — a grammar constrains genotypes to structurally legal levels
  before any simulation runs.
- Evaluation: a **physics engine simulates the level** and an **AI reasoning agent** attempts to
  solve it. The agent is a *deliberative Prolog-based* planner: at each state it enumerates the
  **"sensible" moves only** (cut this rope now, pop that bubble now), which collapses the continuous
  action space enough that a depth-first search over that reduced space terminates.
- Fitness = playability (solvable / not), plus optimization of a partial human design toward
  playability.
- Authoring integration: the designer draws a *partial* level; the system completes it, checks
  solvability online, and offers optimizations. Real-time feedback was an explicit design goal.

**What solvability checking bought them.** [established] It converted "is this generated level any
good?" from a human playtest into a machine predicate, so the evolutionary loop could run unattended.
It also made mixed-initiative authoring viable — the designer gets an immediate red/green on a
half-finished level.

**The crucial caveat for us.** [established, and under-quoted] Their solvability is
*solvability-relative-to-that-agent*. The Prolog agent's "sensible move" filter defines the search
space; a level the agent cannot solve might be solvable by a human doing something the filter
excluded, and vice versa. Any solver-verified pipeline inherits its solver's blind spots. This is
the single most transferable lesson: **our "level is winnable" claim will always mean "winnable by
our optimizer within budget B".** Report it that way.

### 1.2 Similar solver-verified PCG in other domains [established]

| Domain | Work | Verification mechanism |
|---|---|---|
| Sokoban | Taylor & Parberry 2011, *Procedural Generation of Sokoban Levels*; Kartal, Sohre & Guy 2016, *Data-Driven Sokoban Puzzle Generation with MCTS* (AIIDE 2016) — https://motion.cs.umn.edu/pub/SokobanMCTS/DataDrivenSokobanMCTS.pdf | MCTS **generates by simulated play**, so solvability is guaranteed by construction (the solution is the generation trace). Difficulty features fitted to a user study, then used as the MCTS evaluation function. Anytime. |
| Refraction (educational puzzler) | Smith, Butler & Popović 2013, *Quantifying over play: Constraining undesirable solutions in puzzle design* (FDG) | **Answer Set Programming**: the generator does not just guarantee *a* solution, it constrains *unwanted extra* solutions away. Uniqueness-of-solution as a first-class constraint. |
| Grids/mazes/dungeons generally | Smith & Mateas 2011, *Answer Set Programming for PCG: A Design Space Approach* (TCIAIG) | Declarative constraints; the solver enumerates all levels satisfying them. |
| The Witness, Snakebird | Sturtevant & Ota 2018, *Exhaustive and Semi-Exhaustive Procedural Content Generation* (AIIDE) — https://www.cs.du.edu/~sturtevant/papers/sturtevant18epcg.pdf ; project page https://www.movingai.com/epcg.html | **Exhaustive/branch-and-bound enumeration** of the whole content space of a small level, then filter for uniqueness/difficulty. Feasible only because the content space is tiny. |
| Match-3 | Mugrai, de Mesentier Silva, Holmgård & Togelius 2019, *Automated Playtesting of Matching Tile Games* (CoG) — https://arxiv.org/abs/1907.06570 | MCTS agents with **evolved utility functions** (Max Score, Min Score, Max Moves, Min Moves) as playtesters. |
| Angry Birds / physics puzzlers | the Ropossum line, plus the AIBIRDS level-generation track | Simulation + agent play; same solver-relative caveat. |
| PuzzleScript / general puzzles | Khalifa & Fayek 2015, *Automatic Puzzle Level Generation: A General Approach using a Description Language*; Khalifa et al. 2016, *General Video Game Level Generation* (GECCO) | Generic solver agent over a game description language. |

**Relevance to us.** Our situation is closest to Sturtevant's Snakebird/Witness work in one respect
(our grids are tiny: 5×10 to 8×10, 6–13 rooms) and closest to Ropossum in another (our evaluation is
a *continuous-time simulation*, not a discrete solver). Full exhaustive search over route-sets is
out (§5.1), but **exhaustive search over stop-sequences for a single route on a 6-room level is
tractable** and worth doing once, as ground truth to calibrate the metaheuristic.

---

## 2. Simulation-based and search-based PCG

### 2.1 The taxonomy [established]

**Togelius, Yannakakis, Stanley & Browne 2011, "Search-Based Procedural Content Generation: A
Taxonomy and Survey", IEEE TCIAIG 3(3):172–186** — DOI 10.1109/TCIAIG.2011.2148116,
https://nyuscholars.nyu.edu/en/publications/search-based-procedural-content-generation-a-taxonomy-and-survey

The taxonomy axes that matter for us:

- **Constructive vs generate-and-test vs search-based.** Constructive = build it right the first
  time (grammars, WFC, cellular automata), no evaluation loop. Generate-and-test = generate, test,
  discard failures. Search-based = generate-and-test where the test returns a *graded* fitness that
  steers the next generation. We want search-based, because our sim naturally returns a graded score
  (served / lost / wait), not a boolean.
- **Direct vs indirect representation.** Direct = the genome *is* the content (cell grid).
  Indirect = the genome is a recipe decoded into content (a seed for a constructive algorithm).
  Indirect representations shrink the search space and guarantee structural validity. **Our
  stop-sequence-plus-connector representation is exactly an indirect representation**, and this is
  the standard argument for why it will beat cell-level search.
- **Direct vs simulation-based vs interactive fitness.** *Direct* fitness reads features off the
  artifact (e.g. "how many rooms are on a route"). *Simulation-based* fitness runs an agent and
  scores the play trace. *Simulation-based* splits further into **static** (agent behaviour is fixed
  and hand-coded) and **dynamic** (agent learns/adapts during evaluation). Our harness gives us
  simulation-based/static evaluation for free — this is the expensive-but-honest branch.

### 2.2 Fitness from simulated play [established]

The canonical pattern: run an agent, derive scalar features from the trace, combine into fitness.
Examples in the literature: completion time, deaths, jumps, backtracking (Mario); rope cuts and
solution length (Cut the Rope); box pushes and dead-end count (Sokoban). Our `tests/balance.gd`
already computes the right family of features — `served`, `lost`, `avg_wait`, `p90_wait`,
`avg_transfers`, `gate_wait`, `gate_transits` — so the fitness plumbing is done.

### 2.3 Expressive range analysis [established] — the standard tool for evaluating *generators*

- **Smith & Whitehead 2010, "Analyzing the expressive range of a level generator"** (PCG Workshop @
  FDG) — https://dl.acm.org/doi/10.1145/1814256.1814260. Pick 2 metrics (they used *linearity* and
  *leniency*), generate thousands of levels, plot the 2D histogram. Reveals generator bias and holes.
- **Cook, Gow & Colton 2016, "Danesh: Helping Bridge The Gap Between Procedural Generators And Their
  Output"** — https://mkremins.github.io/refs/Danesh.pdf — a Unity tool that does expressive-range
  visualisation and parameter tuning for any generator function.

When we get to auto-*generating* levels (goal (c)), expressive range is the evaluation to run.
Note the recent critique: **"The Right Variety: Improving Expressive Range Analysis with Metric
Selection Methods"** (2023) — https://arxiv.org/pdf/2304.02366 — arbitrary metric choice makes ERA
plots uninformative; choose metrics that are decorrelated.

### 2.4 The OR literature we should be borrowing from [established]

Our route-set search is the **Transit Route Network Design Problem** / Urban Transit Routing
Problem, sometimes with Frequency Setting (TNDFSP). It is NP-hard; the benchmark is **Mandl's Swiss
network** (Mandl 1980). The dominant architecture in that literature is **two-phase**:

1. **Route-set generation**: build a large pool of candidate routes by k-shortest-paths between
   high-demand node pairs, terminal-pair enumeration, or greedy demand-coverage heuristics.
2. **Route-set selection/improvement**: a metaheuristic (GA with elitism, NSGA-II for the
   passenger-cost / operator-cost Pareto front, simulated annealing, bee colony) mutates and
   recombines *sets* of routes; each candidate is scored by a **passenger assignment simulation**.

Representative: *Transit network design by genetic algorithm with elitism* (Nikolić & Teodorović);
*A multi-objective meta-heuristic approach for transit network design and frequency setting*
(Comp. & Ind. Eng. 2019) — https://www.sciencedirect.com/science/article/abs/pii/S0360835219301111;
*Genetic Algorithm for Biobjective Urban Transit Routing Problem* (J. Applied Math. 2013) —
https://projecteuclid.org/journals/journal-of-applied-mathematics/volume-2013/issue-none/Genetic-Algorithm-for-Biobjective-Urban-Transit-Routing-Problem/10.1155/2013/698645.pdf

**Direct transfer to us:** their mutation operators are exactly what we need and are non-obvious —
*add a terminal*, *delete a terminal*, *swap a route segment*, *merge two routes*, *split a route*,
*exchange a stop between two routes of the set*. Steal these wholesale. Their repair operators (fix
a route that became disconnected or that dropped the last coverage of a stop) map onto our
`_route_error` legality checks in `tests/balance.gd:124`.

---

## 3. Agents as evaluators

### 3.1 Procedural personas [established]

- **Holmgård, Green, Liapis & Togelius 2019, "Automated Playtesting With Procedural Personas Through
  MCTS With Evolved Heuristics", IEEE Trans. on Games** — https://arxiv.org/abs/1802.06881
- Earlier: Holmgård, Liapis, Togelius & Yannakakis 2014, *Evolving Personas for Player Decision
  Modeling* (CIG); *Monte-Carlo Tree Search for Persona Based Player Modeling* (AIIDE 2015) —
  https://cdn.aaai.org/ojs/12849/12849-52-16365-1-2-20201228.pdf

The idea: a *procedural persona* is an archetypal player model realised as an agent whose **utility
function** encodes an archetype (Runner, Monster Killer, Treasure Collector, Completionist). They
replace MCTS's UCB1 selection criterion with an **evolved** node-selection expression, so different
personas genuinely explore differently rather than just re-weighting a shared search.

Used for level evaluation: a *baseline* persona answers "is this level playable at all"; the
archetype personas then answer "what kind of level is it" — and the same generated dungeon gets
different difficulty and tactical readings from different personas. In the dungeon-generation
experiments, which persona drove the fitness **changed the layout and the tactical depth** of what
was generated.

**Transfers to us? Yes, with a change of level.** Our "player" makes one big design decision, not a
sequence of tactical moves, so a persona is not a move-selection policy — it is an **objective
function over route-sets**. Natural personas for us: *Throughput* (maximise served), *Punctual*
(minimise p90 wait), *Miser* (win using the fewest cars/shortest total track), *Transfer-averse*
(minimise `avg_transfers` — models a player who dislikes transfer mechanics), *Express-fetishist*
(maximise express utilisation). Each is a separate optimizer run; the *spread* between what they
achieve is itself a level metric.

### 3.2 Agents that are deliberately *not* trying to win [established]

- **Nielsen, Barros, Togelius & Nelson 2015, "General Video Game Evaluation Using Relative Algorithm
  Performance Profiles"** (EvoApplications) —
  https://link.springer.com/chapter/10.1007/978-3-319-16549-3_30 ;
  abstract: https://www.kmjn.org/publications/GVGprofiles_Evostar15-abstract.html
  Seven GVGAI algorithms play hand-designed, mutated and randomly generated VGDL games. **Finding:
  well-designed games show a larger performance gap between strong and weak algorithms than badly
  designed ones.** The evaluation function is literally "good games let good players play better".
  Follow-up: *Evolving Chess-like Games Using Relative Algorithm Performance Profiles* (2016) —
  https://link.springer.com/chapter/10.1007/978-3-319-31204-0_37
- **Guerrero-Romero, Louis & Perez-Liebana 2017, "Beyond Playing to Win: Diversifying Heuristics for
  GVGAI"** (CIG), and the follow-up **MAP-Elites to Generate a Team of Agents that Elicits Diverse
  Automated Gameplay** (CoG 2021) — https://ieee-cog.org/2021/assets/papers/paper_100.pdf. A *team*
  of agents with distinct goals (win-rate, score, exploration, item collection) characterises a game
  better than one strong agent.
- **Bravi, Perez-Liebana, Lucas & Liu 2018, "Shallow Decision-Making Analysis in General Video Game
  Playing"** (CIG) — https://arxiv.org/abs/1806.01151. Metrics that introspect *decision-making*
  (action distributions, decision agreement between agents) rather than outcome, applicable to any
  agent regardless of algorithm.

### 3.3 Industry [established]

- **Zhao, Borovikov, de Mesentier Silva, et al. (Electronic Arts) 2019/2020, "Winning Isn't
  Everything: Enhancing Game Development with Intelligent Agents"** (IEEE Trans. on Games) —
  https://arxiv.org/abs/1903.10545. Four case studies across *The Sims Mobile* and a battle game.
  Agents (DQN/Rainbow, evolution strategies, imitation) are built to **strike a balance between
  skill and style**, not to maximise score, because a superhuman agent tells you nothing about
  whether the career-progression tuning feels balanced to a human.
- **Gudmundsson et al. (King) 2018, "Human-Like Playtesting with Deep Learning"** (CIG) —
  https://gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf. Supervised
  CNN trained on *human* Candy Crush moves predicts the most human action; used to predict **level
  difficulty** for unreleased content. Beat MCTS on both correlation-with-human-difficulty **and**
  compute cost by a wide margin. This is the strongest evidence in the literature that a
  *human-imitating weak agent* beats a *strong searcher* for difficulty prediction.
- **Roohi, Guckelsberger, Relas, Heiskanen, Takatalo & Hämäläinen 2020, "Predicting Game Difficulty
  and Churn Without Players"** (CHI PLAY) — https://arxiv.org/pdf/2008.12937 ; extended as
  *Predicting Game Difficulty and Engagement Using AI Players* (PACM HCI 2021) —
  https://arxiv.org/abs/2107.12061. DRL agents supply per-level difficulty, which then drives a
  **population simulation** with simple models of player skill, persistence and boredom, predicting
  per-level pass rate *and churn*. DRL+MCTS beat either alone, most on the hardest levels.

### 3.4 So: strong solver or weak/varied agents? [established consensus, applied judgement]

The literature's answer is unambiguous and it is **"varied, not maximal"**:

- A strong solver answers exactly one question — *is there a solution, and how good can it get* —
  and you do need that (Ropossum needs it for solvability; we need it for the ceiling).
- Everything else — difficulty, balance, choice, "is this level interesting" — comes from
  **differences between agents of different strengths or different goals** (Nielsen 2015,
  Guerrero-Romero 2017, EA 2019, King 2018).

**For us:** build an **agent ladder**, not one agent. Concretely: `random-legal` → `greedy`
(chain rooms by demand weight) → `beam(width 20)` → `EA(1k evals)` → `EA/ME(20k evals)`. Every
metric in §5.2 is a function of that ladder. This is cheap — the weak rungs cost almost nothing —
and it is what makes the ladder-step depth metric computable at all.

---

## 4. Depth, choice and challenge metrics

This is the section where the transfer question really bites. Most of this literature is about
**two-player competitive** games, where "win rate between agents" is the universal currency. We have
a **single-player optimisation** game with no opponent, so every metric below needs its currency
swapped from *win rate* to *achieved score margin*, and several of them break when you do that.

### 4.1 Lantz, Isaksen, Jaffe, Nealen & Togelius 2017, "Depth in Strategic Games" (AAAI-17, pp. 967–974)

http://www.nealen.net/papers/Lantz2017Depth.pdf — **the reference definition.** [established as a
model; note the authors themselves state they have not built a system to evaluate it]

**What it says.** Depth `d` = "the capacity of a game to absorb dedicated problem-solving attention
and allow for sustained, long-term learning". They first *rule out* the obvious candidates:

- **State space size is not depth.** Their thought experiment: add a rule letting either player flip
  a token from side A to side B on their turn. State space doubles instantly; depth unchanged.
- **Branching factor is not depth.** Add arbitrarily many "dud" branches that obviously lose.
  Branching factor inflates; depth unchanged.
- **Computational complexity class is not depth.** Too coarse, and "needle in a haystack" problems
  are resource-intensive without being interesting.

**The model: the strategy ladder.** Formalise the human *skill chain* (Robertie's "complexity
number", 1992; Elias, Garfield & Gutschera, *Characteristics of Games*, MIT Press 2012 — a skill
chain is the number of distinct skill ranks where each rank beats the one below significantly more
than half the time) as an algorithmic ladder:

1. Fix the game and a time limit.
2. Fix a language for expressing strategies.
3. Define **CR-levels** (computational resource levels) by weighting/fixing *speed* (ops/sec),
   *algorithm size*, and *working memory*. Suggested: set random-legal play and perfect play as the
   endpoints, divide into ~100 evenly spaced levels.
4. Define **strength**: either **win rate (WR)** against the other strategies at or below its
   CR-level, or **quality of move selection (QM)** — how often its move matches the perfect
   strategy's. They discuss the problems with both and explicitly leave the choice unresolved.
5. Define a **step unit** X (traditional skill chains use ~60–75 % win rate).
6. Let `A(CR_n)` = the best strategy at resource level n. Plot `A(CR_n)` vs `CR_n`.
7. Walk the curve from `A(CR_1)`, counting a **step** each time strength improves by ≥ X over the
   last step point. **`d` = the number of steps.**

The picture (their Fig. 1): a shallow game jumps to near-perfect play immediately and flatlines; a
deep game has a long staircase of intermediate strategies each meaningfully better than the last.

**The secondary model — the entropy curve (their Fig. 2).** Depth is maximised at *intermediate*
entropy of the state space. Two ways to fail: (a) **high entropy / disordered** — no exploitable
regularity, so no heuristics exist and the only strategy is raw search, giving a short ladder;
(b) **low entropy / one strong heuristic** — "one weird trick" solves it, also a short ladder. Deep
games are **semi-ordered**: the shortest description of "how to find the best move" is long and
mixes heuristics with search. They connect this to Kolmogorov complexity of the optimal strategy,
and propose a *Speed-Only vs Size-Only* experiment: a game whose ladder is much longer when you add
*algorithm size* (memory for heuristics) than when you add *speed* (raw search) is a game whose
structure rewards knowledge.

**Stated limitations.** [established] They limit themselves to two-player turn-based games; the full
model needs knowledge of perfect play and its minimal resource cost, so it is "impossible to apply
completely to complex, real-world games"; they endorse only partial application (low CR-levels of
big games, full application to toy games) and had **no implemented system** at publication.

**Does it transfer to us?** Partly, and the parts that don't matter a lot.

- ✅ **The ladder shape transfers directly and is our single best depth metric.** Replace "win rate
  vs other strategies" with "achieved score margin" (see §5.2), and replace "CR-level" with
  **optimizer budget in simulation evaluations** — a clean, monotone, measurable resource axis.
  Anytime search curves are exactly the object the model wants.
- ✅ The dud-branch and state-space critiques transfer verbatim and are a live risk for us: adding
  more grid cells, or a fourth elevator card, inflates our search space without adding depth.
- ⚠️ **The entropy/semi-orderedness half is speculative for us.** We have no way to compute
  Kolmogorov complexity of an optimal route-set. But the *qualitative* diagnostic is usable and
  sharp: if one primitive (e.g. "always draw the full-height spine") wins every level, the game is
  in the low-entropy failure mode. Our L1 thesis text ("dedicate the express") should worry us
  slightly on this axis.
- ❌ Win-rate-based strength, intransitivity concerns, and the whole "which strategies does it
  compete against" apparatus do **not** transfer — there is no opponent. This is a *simplification*
  in our favour: our strength measure is a scalar score, which sidesteps the paper's biggest
  unresolved problem.
- ⚠️ **Risk specific to optimisation games:** our ladder may come out *smooth* (continuous
  improvement, no discrete steps) rather than stepped, because route-set quality is a fairly
  continuous function. A smooth ladder is not automatically shallow, but our step-counting will be
  noisy. Mitigation: report the whole curve (log-budget vs best score, with CIs over seeds), not
  just the step count; and use "number of distinct *behaviour niches* that occupy the frontier at
  successive budgets" as a discretisation.

Related: **Silva, Isaksen, Togelius & Nealen 2016, "Generating Heuristics for Novice Players"**
(CIG) — the "toy versions" arm of the same programme.

### 4.2 Jaffe, Miller, Andersen, Liu, Karlin & Popović 2012, "Evaluating Competitive Game Balance with Restricted Play" (AIIDE 2012, Best Student Paper)

https://homes.cs.washington.edu/~zoran/jaffe2012ecg.pdf — **the most directly actionable paper here.**
[established]

**Method.** Take an optimal (or strong) agent A; produce `A_R`, the same agent under a **behaviour
restriction R**; measure the win rate of `A_R` against an unrestricted opponent *who knows about the
restriction and can exploit it*. The **gap** is the quantitative value of the freedom R removed.
Their catalogue of restrictions and the design question each answers:

| Restriction | Notation | Question answered |
|---|---|---|
| Random | `Depth ≤ 0` | how much does thinking help at all? |
| Greedy | `Depth ≤ 1` | short-term tactics vs long-term strategy |
| Depth ≤ k | `Depth ≤ k` | **how much long-term planning does the game require?** |
| Oblivious-until-round-k | | how much must you *react* vs execute a fixed plan? |
| Omit `a` | `\|Plays(a)\| ≤ 0` | **how powerful/essential is action `a`?** |
| Prefer `a` | `\|Plays(a)\| ≥ ∞` | is `a` a trap when overused? |
| Support ≤ k | | how much must you randomise? |
| Avoids-S / Chooses-s | | end-condition and starting-condition fairness |

**Case study.** They balanced *Monsters Divided*, an educational fractions card game, over ~20
design iterations, using the restricted-play numbers to diagnose: "green is too weak" (omitting green
barely hurts), "the ×2/3 power card is self-destructive" (an *omit* restriction performs near
perfectly while a *prefer* restriction performs terribly), "random play is unreasonably effective"
(no depth). They report saving up to 20 rounds of manual playtesting. They frame the tool as an
**"early warning system"** that "illuminates flagrant imbalances upfront", explicitly *not* a
replacement for playtesting.

**Stated limitations.** [established] Anything rooted in human psychology or feel is out of reach;
the prototype only handled perfect-information discrete games with optimal agents; coding a separate
transition function is prohibitive for complex simulations (they suggest using in-game telemetry
instead, which is exactly what our headless harness gives us for free); they flag that using
*heuristic* rather than optimal agents is the necessary next step for complex games.

**Transfer to us: excellent, with one substitution.** [speculative but low-risk] Swap "win rate of
`A_R` vs unrestricted opponent" for **"best score achievable by the optimizer under restriction R,
at matched budget, relative to unrestricted"**. Every restriction in the table has a natural analogue
(§5.3). This is the cleanest available answer to goal (d), "does mechanic X add depth" — it is
literally `Omit a` applied to a mechanic instead of a card.

### 4.3 Skill chains, Elo, and skill differentiation [established, mostly does NOT transfer]

- **Elias, Garfield & Gutschera 2012, *Characteristics of Games*** (MIT Press) — the reference text
  for skill chains, "heuristic vs. analytic" play, and a large taxonomy of game qualities.
- **Robertie 1992** — the original "complexity number".
- Elo-spread / skill-differentiation depth: measure the Elo range a population of players/agents
  spans; deeper games support wider ranges.

❌ **These do not transfer to a single-player optimisation game.** Elo requires pairwise outcomes.
There is no meaningful "our agent beat your agent" in our game. The *underlying intuition* —
"deeper games support more distinguishable levels of ability" — does transfer, but its computable
form for us is the §4.1 ladder and the §3.4 agent-ladder score gap, not Elo.

### 4.4 Relative algorithm performance profiles [established, transfers well]

Covered in §3.2. The operational form for us: `skill_gap = score(strong) − score(weak)`, normalised.
**Weaknesses to know:** (i) it is easily gamed by making the level merely *large* (a bigger maze
means random routes do worse, without any added depth — this is Lantz's dud-branch critique in
another dress); (ii) it saturates once the strong agent hits the quota ceiling — you must measure
*margin above quota* or *time to quota*, not the binary win; (iii) it says nothing about whether the
strong agent's win is unique or one of many.

### 4.5 Game refinement theory [established, weak fit — include for completeness, don't build on it]

Iida et al., from 2003 onward; e.g. *Game Refinement Theory and Its Application to Score Limit
Games*; *A Computational Game Experience Analysis via Game Refinement Theory* (2022) —
https://www.sciencedirect.com/science/article/pii/S2772503022000378

Measures "entertainment" from the **uncertainty of game outcome** over game length. Model the
information about the outcome as `x(t)` over moves `t`, take the second derivative — "informational
acceleration", by analogy with `F = ma`. The empirical claim: sophisticated board games and popular
sports cluster at a refinement value of roughly **0.07–0.08**.

**Known weaknesses:** [established critique] the derivation is an analogy rather than a derivation;
the 0.07–0.08 band is fitted post hoc to games we already knew were good; the "sophistication–
population paradox" required a patch (Springer 2016). ❌ **Does not transfer to us** — outcome
uncertainty over time is meaningless in a game where you commit a plan up front and then watch a
deterministic sim run. Listed because it will come up in any depth-metrics search; skip it.

### 4.6 Quality-Diversity — the best fit for measuring CHOICE [established method, [speculative] application]

- **Gravina, Khalifa, Liapis, Togelius & Yannakakis 2019, "Procedural Content Generation through
  Quality Diversity"** (IEEE CoG) — https://arxiv.org/pdf/1907.04053 ; overview:
  https://antoniosliapis.com/articles/pcgqd.php
- **Mouret & Clune 2015, "Illuminating search spaces by mapping elites"** — the MAP-Elites original.
- **Fontaine, Lee, Soros, de Mesentier Silva, Togelius & Hoover 2019, "Mapping Hearthstone Deck
  Spaces through MAP-Elites with Sliding Boundaries"** (GECCO) — https://arxiv.org/pdf/1904.10656 —
  the closest analogue to our problem in the whole literature: search over *combinatorial
  loadouts* (decks ≈ our route-sets), evaluated by *simulation*, illuminated across behavioural
  axes. **MESB** slides the archive boundaries to cope with unevenly distributed solutions, which
  matters because most random route-sets will cluster in a narrow band of behaviour.
- Follow-ups worth knowing: *Covariance Matrix Adaptation for the Rapid Illumination of Behavior
  Space* (CMA-ME, 2019) — https://arxiv.org/pdf/1912.02400 ; *Deep Surrogate Assisted MAP-Elites for
  Automated Hearthstone Deckbuilding* (GECCO 2022) — https://dl.acm.org/doi/10.1145/3512290.3528718
  (learn a surrogate of the expensive simulation, use it to pre-screen candidates — directly
  relevant to our simulation cost).

**Why QD is the right frame for "CHOICE".** A single-objective optimizer returns *one* best
route-set and tells you nothing about whether it was the only one. MAP-Elites returns an **archive**:
the best solution found in each cell of a behaviour space. Two derived numbers:

- **coverage** = fraction of archive cells filled (with a *winning* solution) — how many
  behaviourally distinct ways there are to beat the level;
- **QD-score** = sum of fitness over filled cells — quality-weighted diversity.

A level where 40 distinct behaviour niches all win offers real choice. A level where exactly one
niche wins is a puzzle with one answer — which is fine for a tutorial and bad for a "deep" level.
**This distinction is the one our design conversations most need and it is directly computable.**

**Known weaknesses of QD** [established]: the behaviour descriptors are hand-chosen and the result is
entirely at their mercy (choose descriptors that correlate with fitness and coverage becomes
meaningless); archive resolution is arbitrary; coverage is not comparable across levels with
different reachable behaviour ranges unless you normalise; QD runs cost 5–20× a single-objective run.

### 4.7 Auto-balancing literature [established]

- **Volz, Rudolph & Naujoks 2016, "Demonstrating the Feasibility of Automatic Game Balancing"**
  (GECCO) — https://arxiv.org/abs/1603.03795. Multi-objective EA over *Top Trumps* decks, with
  simulation-based objectives expressing **fairness** (win rate ≈ 50 %) and **excitement** (average
  number of tricks / lead changes). Produced decks at least as good as published ones.
- **Browne & Maire 2010, "Evolutionary Game Design"** (IEEE TCIAIG 2(1):1–16) and the Springer brief
  of the same name — the **Ludi** system evolved *rules* for combinatorial games, scored by **57
  aesthetic criteria** computed from self-play, including *drama* (chance of recovering from a bad
  position), *decisiveness* (how sharply the outcome resolves near the end), *uncertainty*, *lead
  change*, and *depth* proxies. Correlated the criteria against human rankings. Produced *Yavalath*,
  a genuinely published board game. **This is the strongest existence proof that simulation-derived
  aesthetic metrics can drive real design** — and also a cautionary tale: 57 metrics, most of which
  turned out to be redundant or weakly predictive.
- **Marks & Hom 2007, "Automatic Design of Balanced Board Games"** (AIIDE) — earlier, simpler:
  self-play win rate as the fairness objective.
- **Isaksen, Gopstein, Togelius & Nealen 2015, "Exploring Game Space Using Survival Analysis"**
  (FDG) — http://www.nealen.net/papers/exploring-game-space-FDG2015.pdf — and *Exploring Game Space
  of Minimal Action Games via Parameter Tuning and Survival Analysis* (TCIAIG 2017) —
  http://www.nealen.net/papers/08030128.pdf ; *Discovering Unique Game Variants* (ICCC 2015). A
  parameterised Flappy Bird; a **human motor-skill player model** (precision, actions per second);
  **survival analysis** of score histograms to get hazard rates and difficulty curves; validated
  against 10⁶ real play sessions and a user study. Techniques: search for a target difficulty,
  visualise game space, cluster to find *unique* variants. **The methodology (parameterise → simulate
  with an explicitly imperfect player model → analyse the distribution, not the mean) is the right
  template for our level tuning.**

Also useful for framing: *What is Game Balancing? — An Examination of Concepts* (2020) —
https://pdfs.semanticscholar.org/f554/89f9e132a1e3e4a87229b87b05a31a25a70b.pdf

### 4.8 Puzzle-difficulty metrics (single-player — the closest genre fit) [established]

- **van Kreveld, Löffler & Mutser 2015, "Automated Puzzle Difficulty Estimation"** (CIG) —
  https://ics-websites.science.uu.nl/docs/vakken/mscip/assignments/CIG2015-AutomatedPuzzleDifficultyEstimation.pdf
  Combine per-level structural aspects (size, and solver-derived quantities such as decision points
  and dead ends) into a difficulty function whose weights are **fitted to a user study**. Tested on
  *Flow*, *Lazors*, *Move*; error ≈ 1 point on a 1–10 scale (≈0.5 on Flow). The important structural
  point: difficulty is a *learned combination of cheap features*, not a single principled quantity.
- **Kartal, Sohre & Guy 2016** (Sokoban, §1.2) — same shape: user study → features → evaluation
  function → generator.
- **"Generalized Entropy and Solution Information for Measuring Puzzle Difficulty"** (AIIDE 2024) —
  https://ojs.aaai.org/index.php/AIIDE/article/download/31872/34039 — a more recent
  information-theoretic take.
- **Sturtevant et al. 2020, "The Unexpected Consequence of Incremental Design Changes"** —
  https://webdocs.cs.ualberta.ca/~nathanst/papers/sturtevant2020incremental.pdf — in Snakebird, tiny
  level edits that barely change the *computer's* search cost drastically change *human* difficulty.
  **The canonical warning that solver-effort ≠ human difficulty.**

---

## 5. Concrete recommendations for this project

### 5.1 (a) Search over route-sets

**Sizing the problem.** Our grids are 5×10 to 8×10 (50–80 cells), with 6–13 room cells and 3 cards.
A route is a self-avoiding walk; the number of SAWs on a 7×10 grid graph is astronomically large
(≫10²⁰), and a solution is an ordered triple of them. **Cell-level search is hopeless and also
wasteful** — most cell-level variation is irrelevant to the sim, because what the simulation
actually consumes is (i) which rooms are stops and in what order, (ii) the travel distance between
consecutive stops, (iii) which gate groups the route crosses, (iv) the `closed` bit.

**Recommended representation** [speculative for our game; standard practice in TRNDP]:

```
RouteGene  = { stops: [RoomId], closed: bool, gate_pref: {avoid|neutral|prefer} }
Genome     = [RouteGene × 3]                       # one per card
decode(g)  -> cells:   A* between consecutive stops on the grid, cost = 1 per cell,
                       gate cells weighted by gate_pref; splice/repair on self-intersection;
                       for closed, additionally connect last->first and require a simple cycle.
```

The decoder must produce something `_route_error()` (`tests/balance.gd:124`) accepts: ≥2 cells, all
passable, no cell twice, orthogonal adjacency, ≥4 cells and head-adjacency if `closed`. Reject-and-
repair inside the decoder, never inside the optimizer.

**Recommended algorithms, in the order I'd build them:**

1. **Greedy / beam over stop sequences** (build first — 1 day, and it is your `weak` and `medium`
   agent-ladder rungs). Grow each route one stop at a time; score marginal `served`/second; beam
   width 20–50. Fast, deterministic, and gives an immediate sanity baseline. Also the cheapest way
   to discover that a level is trivially solvable.
2. **(μ+λ) EA over `Genome`** with TRNDP mutation operators: *add stop*, *delete stop*, *swap two
   stops within a route*, *move a stop between routes*, *reverse a segment*, *toggle `closed`*,
   *toggle `gate_pref`*, *replace a whole route with a primitive*. Crossover: exchange whole routes
   between genomes (route-level crossover is the standard TRNDP choice and preserves meaning).
   This is your **ceiling** estimator.
3. **MAP-Elites over the same genome** — the main workhorse (§4.6). Suggested archive: 3 descriptors,
   ~10 bins each (1000 cells). Descriptor candidates, all already computed by our harness:
   `avg_transfers` (0–2), express-car utilisation share, `gate_transits` (0–max), total route length
   (short/local vs long/spanning), number of `closed` routes (0–3), room-coverage overlap between
   cards. Pick 2–3 that are **decorrelated with fitness** (the ERA-metric-selection critique, §2.3).
   Use **MESB** sliding boundaries if the archive clumps.
4. **Exhaustive stop-sequence enumeration on the smallest level (L2, 6 rooms)** — as ground truth to
   calibrate how far the metaheuristics fall short. This is Sturtevant's EPCG argument and it is
   cheap enough to be worth doing once.

**Not recommended:**

- **MCTS** — our decision is a one-shot combinatorial design, not a sequential game. You *can* frame
  route construction as a sequence of "add stop" moves and run MCTS over it (this is exactly what
  Kartal/Sohre/Guy do for Sokoban), and if you want a solvability-by-construction generator later,
  do that. But as a *route-set optimizer* it buys nothing over EA/QD and costs more engineering.
- **RL** — the state/action space is bespoke per level, training would dwarf the eval budget, and
  the EA/King results (§3.3) suggest we would not gain accuracy for the cost.

**Compute budget.** One eval = up to 900 game-seconds at `STEP = 0.1` = 9000 `advance()` calls.
Measure this first; if it is ~0.1 s in headless GDScript, a 20 000-eval MAP-Elites run per level is
~35 minutes, which is fine overnight for 5 levels × 8 seeds. To speed it up:

- **Early termination**: abort the moment `lost > max_lost` (already a LOSE) or `served ≥ quota`.
  Our harness already stops on state change; make sure the optimizer exploits it.
- **Analytical pre-screen (surrogate)**: score a candidate cheaply by summing demand-weighted
  expected journey time over the route network (shortest path over `Route3.ride_dist` + a fixed
  transfer penalty + headway/2 wait), *ignoring* capacity, doors and gate contention. Simulate only
  the top ~10 %. This is the Deep-Surrogate-MAP-Elites idea in its cheapest form and it should be a
  strong predictor on our uncongested levels.
- Consider raising `STEP` for search (0.25 s) and re-verifying finalists at 0.1 s — but **check
  first** that results are step-invariant; the harness comment warns results are seed-exact.

### 5.2 (b) Metrics to implement and track per level

Six, ordered by build cost. All are computed over a **fixed seed set S (|S| ≥ 8)**, reporting
median and IQR; keep a disjoint held-out set S' for reporting.

| # | Metric | Definition | Measures | Cost |
|---|---|---|---|---|
| M1 | **`margin`** (ceiling) | best over the optimizer's archive of `score = served_at_quota_time` or, better, a continuous surrogate: `(quota_reached ? −time_to_quota : served − quota) + λ·(max_lost − lost)`. Needs to be **continuous and unsaturating**, unlike the binary WIN. | CHALLENGE (is it winnable, and how tightly) | low |
| M2 | **`skill_gap`** | `margin(EA-20k) − margin(random-legal)`, normalised by `margin(EA-20k) − margin(worst-legal)`. Also report `margin(greedy)` in between. | CHALLENGE + "does thinking help" (Nielsen 2015; Jaffe's `Depth ≤ 0`) | low |
| M3 | **`ladder`** | run the optimizer at budgets `{10, 30, 100, 300, 1k, 3k, 10k, 30k}` evals × ≥8 seeds; plot median `margin` vs log-budget. Report the **curve**, plus `ladder_steps` = number of budget points where median margin improves by ≥ X (pick X ≈ 5 % of the M2 range, and *fix X before looking at the data*). | **DEPTH** (Lantz et al., adapted) | medium |
| M4 | **`QD_coverage` / `QD_score`** | fraction of MAP-Elites archive cells containing a *winning* route-set; and Σ fitness over filled cells. Also `n_niches_winning`. | **CHOICE** (Gravina et al.) | medium (free once ME runs) |
| M5 | **`restrict_Δ[R]`** | for each restriction R: `margin_unrestricted − margin_R` at matched budget. Report as a vector, one entry per restriction. | which affordances/mechanics carry weight (Jaffe et al.) | medium (one EA run per R) |
| M6 | **`plan_fragility` vs `seed_fragility`** | *plan*: take the elite route-set; apply every 1-step mutation (move one stop, drop one stop, toggle `closed`); report the distribution of margin loss. *seed*: hold the route-set fixed, re-evaluate over 32 fresh seeds; report σ/μ. | precision vs **chaos** — the anti-Goodhart guard | low |

**Reading them together** (this is where the design judgement lives) [speculative]:

- High M2, low M4 → hard but **only one answer**: a puzzle, not a strategy level.
- High M4, low M2 → lots of options, none of them matter: **noise**, not choice.
- High M3 *and* high M4 → what we actually want: many viable strategies, arranged in a ladder of
  increasing quality that rewards continued thought.
- High M6-seed relative to M6-plan → the level is a **coin flip**; tune spawns down or patience up.
- High M6-plan with sharp cliffs → the level rewards **fiddly precision** rather than insight; this
  reads as unfair to players (Sturtevant 2020).

Wire M1, M2 and M6-seed into `tests/balance.gd` as regression assertions immediately — they are
cheap and they will catch balance regressions when levels are re-tuned. M3–M5 belong in a separate,
slower `tools/autodesign.gd` batch run, not in the green-keeping harness.

### 5.3 (c) Methodology for "does mechanic X add depth?"

The proposed candidates — big slow cargo elevator, lift-type-restricted corridors, gates with max
occupancy 2 — are all *additions to the affordance set*. Here is the protocol. [speculative
synthesis of Jaffe 2012 + Nielsen 2015 + Gravina 2019 — but each ingredient is established]

**Step 0 — preregister.** Before running anything, write down: the levels, the seed set, the eval
budget, the archive descriptors, the step unit X, and **what result would make you cut the
mechanic**. Otherwise you will rationalise whatever comes out. This is not ceremony; it is the only
defence against the Goodhart failure in §6.4.

**Step 1 — matched-budget ablation.** Build level pairs `L` and `L_noX`, identical except the
mechanic is neutralised (gate mutex disabled → gate becomes plain corridor; cargo car replaced by a
standard car; type-restricted corridor made universal). Run the *same* optimizer with the *same*
budget and seed set on both. Compare M1–M4.

**Step 2 — restricted play on X.** On `L` (mechanic present), run the optimizer under
`R = "never route any car through X"` (Jaffe's `Omit a`) and `R = "route every car through X"`
(`Prefer a`). Compute `restrict_Δ[omit-X]` and `restrict_Δ[prefer-X]`.

**Step 3 — read the outcome table.**

| Observation | Verdict |
|---|---|
| `restrict_Δ[omit-X] ≈ 0` | **X is decorative.** Nobody needs it. Cut or buff. |
| `restrict_Δ[omit-X]` huge **and** `QD_coverage` unchanged or *down* | **X is a constraint, not a choice.** It gates the solution instead of opening options. This is the trap for "gate with max occupancy 2" — it may just be a softer wall. |
| `restrict_Δ[prefer-X]` huge (forced use is punished) **and** `restrict_Δ[omit-X]` moderate | **X is a real trade-off.** Good sign — this is the profile of a genuinely interesting mechanic (it is exactly how Jaffe et al. identified a well-tuned power card). |
| `QD_coverage(L) > QD_coverage(L_noX)` with `margin` roughly unchanged | **X added choice without changing difficulty.** The best possible result. |
| `ladder_steps(L) > ladder_steps(L_noX)` | **X added depth**: there are now more distinct rungs of increasingly good play. |
| `margin` up, `QD_coverage` down, `ladder_steps` flat | **X made it easier and narrower.** Cut. |
| M6-seed up sharply | **X added variance, not depth** — the classic "chaos masquerading as depth" outcome. Suspect this for anything that adds contention (occupancy-2 gates especially). |

**Step 4 — inspect the elites by hand.** Pull the top elite from 6–8 different archive niches on `L`
and *watch them* in the existing watch mode. If they look like the same strategy with cosmetic
differences, your descriptors are lying to you and the coverage number is worthless. This step is
non-negotiable; QD coverage is only as honest as the behaviour space.

**Step 5 — one human playtest** on the two most different elites. The literature is unanimous
(Jaffe, EA, King, Sturtevant 2020) that the automated numbers are a filter, not a verdict.

**Specific predictions for our three candidate mechanics** [speculative — worth writing down so we
can be wrong on the record]:

- **Big slow cargo elevator** — likely a genuine depth-adder, because it creates a *capacity vs
  latency* trade-off that interacts with `patience` per passenger type, which is a second axis.
  Expect `QD_coverage` up. Watch for it becoming strictly dominant on high-volume levels (L3), in
  which case `restrict_Δ[omit]` will be huge and coverage will *fall*.
- **Type-restricted corridors** — most likely a *constraint*, i.e. a wall that some cars can pass.
  Expect coverage to fall. It may still be valuable as a level-design vocabulary item (it lets you
  author the L3 "only the express climbs the loft" thesis structurally instead of by tuning), but
  don't expect it to score as depth.
- **Gates with max occupancy 2** — highest chaos risk. It softens a hard mutex into a queueing
  system, which will raise seed variance (M6-seed) and may raise `margin` while flattening the
  ladder. This is the one to test first because it is the one most likely to *look* better and
  measure worse.

### 5.4 (d) Where the eventual auto-generation fits

Once M1–M6 exist, level generation is straightforward search-based PCG (§2.1): genome = maze rows +
`trips` weights + `spawn` params + `quota`/`max_lost`; fitness = a target *profile* over M1–M6
("winnable with margin in [a,b], skill_gap > c, QD_coverage > d"); evaluation = the inner optimizer
run. This is an **expensive nested loop** (each level eval = a full optimizer run), so: use the
analytical surrogate for the inner loop, and run MAP-Elites at the *outer* level too, with expressive
range plots (§2.3) as the report. Do not build this until M1–M6 are trusted.

---

## 6. Pitfalls

### 6.1 Overfitting to the agent [established]

Every solver-verified system inherits its solver's blind spots (§1.1). The best-documented case is
**Volz et al. 2018, "Evolving Mario Levels in the Latent Space of a Deep Convolutional GAN"**
(GECCO) — https://arxiv.org/abs/1805.00728 — where levels evolved against an A* agent's behaviour
produce artifacts that specifically exploit that agent. Mitigations for us:

- Never define "winnable" without a budget qualifier. Report "winnable by EA-20k on ≥7/8 seeds".
- Keep the **agent ladder** (§3.4) and treat a level where *only the top rung* wins as suspicious —
  it likely requires machine precision, not insight.
- Periodically hand-play a level that the optimizer says is unwinnable. If a human beats it, the
  representation or decoder is the bug, not the level.

### 6.2 Seed overfitting [established, and our highest-risk item]

Our sim is deterministic per seed, and pulse spawning means the *exact arrival schedule* is
exploitable. A single-seed optimizer will find a route-set timed to that schedule and will report a
margin that no human could reproduce. This will silently corrupt every metric.

- Fitness = **median (not mean — outlier-robust) over a seed set of ≥8**, drawn once and fixed.
- A disjoint **held-out** seed set for reporting; if margin(held-out) ≪ margin(train), you overfit.
- Report `seed_fragility` (M6) as a first-class number, not a footnote. Existing scenarios in
  `tests/scenarios3.gd` use fixed seeds — that is correct for regression testing and wrong for
  design measurement. Keep them separate.

### 6.3 Metrics that reward chaos rather than depth [established critique, our specific exposure]

Lantz et al.'s two critiques apply directly:

- **State-space inflation**: a bigger maze raises `skill_gap` (random does worse) with no added
  depth. Always report `skill_gap` alongside a size control, or normalise by room count.
- **Dud branches**: more elevator cards, or more rooms nobody wants to visit, inflate the search
  space without adding decisions. Our existing `_lint_levels()` dead-room check
  (`tests/balance.gd:234`) is *exactly* the right guard and should be kept and extended (e.g. "every
  gate group must be crossed by some winning elite in the archive" — a dead gate is a dud branch).
- **Contention ≠ depth**: mechanics that add queueing (occupancy-2 gates, more cars per corridor)
  raise outcome variance, which raises `skill_gap` measured naively, because random play gets
  *worse* faster than good play gets better. Guard with M6-seed.

### 6.4 Goodharting the metric set [established as a general principle; specific to our workflow]

The moment we tune levels to maximise `QD_coverage`, coverage stops measuring choice and starts
measuring "how well this level suits our descriptor axes". Concretely:

- Treat M1–M6 as an **early-warning system** (Jaffe et al.'s own framing) — they tell you where to
  look, they don't tell you what to ship.
- Keep **held-out metrics**: compute more metrics than you optimize against, and check that the
  non-optimized ones move sensibly too.
- Do not put M3/M4/M5 in the CI harness as pass/fail gates. Once a number is a gate, it becomes a
  target. M1/M2/M6-seed are safe to gate because they are coarse, well-understood, and already
  effectively what `tests/balance.gd` asserts.
- Keep the human playtest in the loop for every level that ships (§5.3 step 5).

### 6.5 Solver effort ≠ human difficulty [established]

Sturtevant et al. 2020 (§4.8): in Snakebird, incremental level changes that barely moved the
computer's search cost enormously changed human difficulty. Our optimizer's `evals-to-solve` is
therefore a **poor** proxy for how hard a level feels. Use it for the ladder shape (a *relative*,
within-level measure) and not as an absolute difficulty rating. The published route to absolute
difficulty is King's: fit cheap features to *human* data (Gudmundsson 2018; van Kreveld 2015;
Kartal 2016). We can't do that until we have players.

### 6.6 Miscellaneous

- **Simulation step invariance**: verify that results are stable under `STEP` before speeding up
  search, or the optimizer will exploit integration artifacts.
- **Descriptor–fitness correlation**: if a MAP-Elites descriptor correlates strongly with fitness,
  the archive collapses to a diagonal and coverage becomes meaningless. Check correlation before
  committing to descriptors (the ERA metric-selection critique, §2.3).
- **Continuous fitness**: a binary WIN/LOSE fitness gives the EA nothing to climb. Fitness must be
  graded even for losing route-sets (e.g. `served/quota − lost/max_lost`), or the search will be a
  random walk until it stumbles on a win.
- **The thesis-strategy trap**: our levels currently encode a designer-intended "thesis" strategy and
  the harness asserts it wins while a "naive" strategy loses. That is a good *regression* test and a
  **bad depth test** — it is the low-entropy failure mode from §4.1 (one weird trick). The
  interesting question the optimizer should be asked on every level is: *does the search find
  something better than my thesis, and is it recognisably different?* If yes on L1–L4, that's real
  choice. If the search reliably rediscovers the thesis and nothing else, our levels are puzzles
  with one answer.

---

## 7. Bibliography (chronological within topic)

**Solver-verified PCG**
- Taylor & Parberry (2011). *Procedural Generation of Sokoban Levels*. https://www.academia.edu/2600460/Procedural_Generation_of_Sokoban_Levels
- Smith & Mateas (2011). *Answer Set Programming for PCG: A Design Space Approach*. IEEE TCIAIG.
- Shaker, Shaker & Togelius (2013). *Ropossum: An Authoring Tool for Designing, Optimizing and Solving Cut the Rope Levels*. AIIDE. https://ojs.aaai.org/index.php/AIIDE/article/view/12611
- Shaker, Shaker & Togelius (2013). *Evolving Playable Content for Cut the Rope through a Simulation-Based Approach*. AIIDE. https://ojs.aaai.org/index.php/AIIDE/article/view/12690
- Smith, Butler & Popović (2013). *Quantifying Over Play: Constraining Undesirable Solutions in Puzzle Design*. FDG.
- Khalifa & Fayek (2015). *Automatic Puzzle Level Generation: A General Approach using a Description Language*.
- Kartal, Sohre & Guy (2016). *Data-Driven Sokoban Puzzle Generation with MCTS*. AIIDE. https://motion.cs.umn.edu/pub/SokobanMCTS/DataDrivenSokobanMCTS.pdf
- Sturtevant & Ota (2018). *Exhaustive and Semi-Exhaustive Procedural Content Generation*. AIIDE. https://www.cs.du.edu/~sturtevant/papers/sturtevant18epcg.pdf

**Search-based PCG & generator evaluation**
- Smith & Whitehead (2010). *Analyzing the Expressive Range of a Level Generator*. PCG@FDG. https://dl.acm.org/doi/10.1145/1814256.1814260
- Togelius, Yannakakis, Stanley & Browne (2011). *Search-Based PCG: A Taxonomy and Survey*. IEEE TCIAIG 3(3):172–186. DOI 10.1109/TCIAIG.2011.2148116
- Cook, Gow & Colton (2016). *Danesh: Helping Bridge The Gap Between Procedural Generators And Their Output*. https://mkremins.github.io/refs/Danesh.pdf
- Volz, Schrum, Liu, Lucas, Smith & Risi (2018). *Evolving Mario Levels in the Latent Space of a Deep Convolutional GAN*. GECCO. https://arxiv.org/abs/1805.00728
- (2023). *The Right Variety: Improving Expressive Range Analysis with Metric Selection Methods*. https://arxiv.org/pdf/2304.02366

**Agents as evaluators**
- Nielsen, Barros, Togelius & Nelson (2015). *General Video Game Evaluation Using Relative Algorithm Performance Profiles*. EvoApplications. https://link.springer.com/chapter/10.1007/978-3-319-16549-3_30
- Holmgård, Liapis, Togelius & Yannakakis (2015). *Monte-Carlo Tree Search for Persona Based Player Modeling*. AIIDE. https://cdn.aaai.org/ojs/12849/12849-52-16365-1-2-20201228.pdf
- Guerrero-Romero, Louis & Perez-Liebana (2017). *Beyond Playing to Win: Diversifying Heuristics for GVGAI*. CIG.
- Bravi, Perez-Liebana, Lucas & Liu (2018). *Shallow Decision-Making Analysis in General Video Game Playing*. CIG. https://arxiv.org/abs/1806.01151
- Gudmundsson, Eisen, et al. (King) (2018). *Human-Like Playtesting with Deep Learning*. CIG. https://gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf
- Holmgård, Green, Liapis & Togelius (2019). *Automated Playtesting With Procedural Personas Through MCTS With Evolved Heuristics*. IEEE ToG. https://arxiv.org/abs/1802.06881
- Zhao, Borovikov, et al. (EA) (2019/2020). *Winning Isn't Everything: Enhancing Game Development with Intelligent Agents*. IEEE ToG. https://arxiv.org/abs/1903.10545
- Mugrai, de Mesentier Silva, Holmgård & Togelius (2019). *Automated Playtesting of Matching Tile Games*. CoG. https://arxiv.org/abs/1907.06570
- Roohi et al. (2020). *Predicting Game Difficulty and Churn Without Players*. CHI PLAY. https://arxiv.org/pdf/2008.12937
- Guerrero-Romero & Perez-Liebana (2021). *MAP-Elites to Generate a Team of Agents that Elicits Diverse Automated Gameplay*. CoG. https://ieee-cog.org/2021/assets/papers/paper_100.pdf

**Depth, balance & diversity metrics**
- Robertie (1992). *Letters to the Editor*. Inside Backgammon 2(1) — the "complexity number".
- Marks & Hom (2007). *Automatic Design of Balanced Board Games*. AIIDE.
- Browne & Maire (2010). *Evolutionary Game Design*. IEEE TCIAIG 2(1):1–16. (Ludi; 57 aesthetic criteria; Yavalath.)
- Jaffe, Miller, Andersen, Liu, Karlin & Popović (2012). *Evaluating Competitive Game Balance with Restricted Play*. AIIDE. https://homes.cs.washington.edu/~zoran/jaffe2012ecg.pdf
- Elias, Garfield & Gutschera (2012). *Characteristics of Games*. MIT Press.
- Isaksen, Gopstein & Nealen (2015). *Exploring Game Space Using Survival Analysis*. FDG. http://www.nealen.net/papers/exploring-game-space-FDG2015.pdf
- Isaksen, Gopstein, Togelius & Nealen (2015). *Discovering Unique Game Variants*. ICCC.
- van Kreveld, Löffler & Mutser (2015). *Automated Puzzle Difficulty Estimation*. CIG. https://ics-websites.science.uu.nl/docs/vakken/mscip/assignments/CIG2015-AutomatedPuzzleDifficultyEstimation.pdf
- Mouret & Clune (2015). *Illuminating Search Spaces by Mapping Elites*. https://arxiv.org/abs/1504.04909
- Volz, Rudolph & Naujoks (2016). *Demonstrating the Feasibility of Automatic Game Balancing*. GECCO. https://arxiv.org/abs/1603.03795
- Silva, Isaksen, Togelius & Nealen (2016). *Generating Heuristics for Novice Players*. CIG.
- Lantz, Isaksen, Jaffe, Nealen & Togelius (2017). *Depth in Strategic Games*. AAAI-17, 967–974. http://www.nealen.net/papers/Lantz2017Depth.pdf
- Isaksen, Gopstein, Togelius & Nealen (2017). *Exploring Game Space of Minimal Action Games via Parameter Tuning and Survival Analysis*. IEEE TCIAIG. http://www.nealen.net/papers/08030128.pdf
- Fontaine, Lee, Soros, de Mesentier Silva, Togelius & Hoover (2019). *Mapping Hearthstone Deck Spaces through MAP-Elites with Sliding Boundaries*. GECCO. https://arxiv.org/pdf/1904.10656
- Gravina, Khalifa, Liapis, Togelius & Yannakakis (2019). *Procedural Content Generation through Quality Diversity*. IEEE CoG. https://arxiv.org/pdf/1907.04053
- Fontaine, Togelius, Nikolaidis & Hoover (2019). *Covariance Matrix Adaptation for the Rapid Illumination of Behavior Space* (CMA-ME). https://arxiv.org/pdf/1912.02400
- Sturtevant et al. (2020). *The Unexpected Consequence of Incremental Design Changes*. AIIDE. https://webdocs.cs.ualberta.ca/~nathanst/papers/sturtevant2020incremental.pdf
- Bhatt, Fontaine, Nikolaidis, et al. (2022). *Deep Surrogate Assisted MAP-Elites for Automated Hearthstone Deckbuilding*. GECCO. https://dl.acm.org/doi/10.1145/3512290.3528718
- (2024). *Generalized Entropy and Solution Information for Measuring Puzzle Difficulty*. AIIDE. https://ojs.aaai.org/index.php/AIIDE/article/download/31872/34039
- Iida et al. (2003–). Game refinement theory. See *A Computational Game Experience Analysis via Game Refinement Theory* (2022). https://www.sciencedirect.com/science/article/pii/S2772503022000378 (included for completeness; poor fit — see §4.5.)

**Transit network design (the OR framing of our search problem)**
- Mandl (1980). *Evaluation and optimization of urban public transportation networks*. EJOR. (The benchmark network.)
- Nikolić & Teodorović. *Transit network design by genetic algorithm with elitism*. https://www.academia.edu/9567486/Transit_Network_Design_by_Genetic_Algorithm_with_Elitism
- (2013). *Genetic Algorithm for Biobjective Urban Transit Routing Problem*. J. Applied Mathematics. https://projecteuclid.org/journals/journal-of-applied-mathematics/volume-2013/issue-none/Genetic-Algorithm-for-Biobjective-Urban-Transit-Routing-Problem/10.1155/2013/698645.pdf
- (2019). *A multi-objective meta-heuristic approach for transit network design and frequency setting*. Computers & Industrial Engineering. https://www.sciencedirect.com/science/article/abs/pii/S0360835219301111
