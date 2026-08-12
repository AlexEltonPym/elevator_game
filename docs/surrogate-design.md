# A learned surrogate for elevator-network level testing and generation

Research + design doc. Audience: ML. Compiled 2026-08. The system it plugs into is
`docs/depth-tools-spec.md` (the route optimizer + difficulty metrics) and `tools/sim_api.gd`
(the deterministic labeler). Nothing here is trained yet; this is the plan and the papers.

Tagging as elsewhere in `docs/`: **[established]** = published/standard; **[speculative]** = my
adaptation to this game.

---

## 0. Recommendation (read this first)

**Build the outcome surrogate (altitude a), amortized across levels, and build it *after* the
raw-sim route optimizer (agents A/B) lands — but ship the training-data exporter now so A/B's
runs are logged as labels from day one.** The surrogate is trained on the optimizer's output
distribution; without the EA/MAP-Elites elites you have no data near the win boundary, which is
the only region where a route pre-screen has to be accurate. And the surrogate's success bar is
defined *relative to* the raw EA ("reach the same ceiling with fewer true sims"), so you cannot
even measure its value before A/B exist. The one thing to do immediately is the exporter (§6.4),
because retrofitting logging loses the compute A/B will already have spent.

**The single most relevant paper is DSAGE** — *Deep Surrogate Assisted Generation of Environments*
(Bhatt, Tjanaka, Fontaine, Nikolaidis, NeurIPS 2022), [arXiv:2206.04199](https://arxiv.org/abs/2206.04199),
[code](https://github.com/icaros-usc/dsage). It is our problem with the nouns changed: a deep
surrogate predicts *agent behaviour in a generated environment*, MAP-Elites searches the
environment space using the surrogate, and a **downsampled** batch of the surrogate's archive is
verified on the true simulator each iteration and appended to the training set. Our
`(level, route_set) -> outcome` is their `(environment) -> agent behaviour`; our route optimizer
is their inner agent; our `sim_api` is their true simulator. Read it, then
[DSA-ME](https://arxiv.org/abs/2112.03534) (the same team's Hearthstone deckbuilder, which is
combinatorial-loadout-shaped exactly like a route_set), then Jin's surrogate-EC surveys for the
model-management vocabulary.

**Recommended first architecture (altitude a):** a **set-of-sequences encoder conditioned on a
level encoding**, with a win-fraction head plus dense auxiliary outcome heads.
- level -> a small **GNN over the room graph** (or, cheaper first cut, a CNN over the maze tensor);
- each route -> a **sequence encoder** (GRU/Transformer) over its stop embeddings, where a stop
  embedding is the room node's embedding; the `closed` and `home` bits are route-level globals;
- the ≤3 routes are pooled **permutation-invariantly** (Deep Sets / Set Transformer) with the card
  features (width/cap/speed/accel) attached — a route_set is a *set of loadouts*, the same shape
  as a Smogon team or a Hearthstone deck;
- **heads:** primary = win-fraction over the seed set ∈ [0,1] (regression); auxiliary = served,
  lost, avg_wait, gate_wait, transfers, and per-type served/lost — the DSAGE "predict the ancillary
  behaviour, not just the objective" trick, because those quantities are causally upstream of WIN
  and give dense supervision (§2.3). Time-to-quota is a censored regression (winners only).
- **Baseline it must beat:** gradient-boosted trees on hand-engineered structural features
  (per-route demand coverage, ride distances, transfer/gate counts, stop counts, loop bits — most
  already computed in `routegen.gd`/`metrics.gd`). If GBT already screens well, you may not need a
  net for the pre-screen at all, and that is a real finding, not a failure.

**Training-data plan in one line:** label a mixture of uniform-random route_sets (free — it is
already how difficulty is measured), EA-elites + their mutation neighbourhoods, and MAP-Elites
archive members, each over the 8 train seeds, then run the DSAGE loop (surrogate-guide → downsample
→ true-sim-verify → append → retrain) so the training set tracks the generator into novel regions.

**Biggest risk:** Goodhart. A generator that maximizes *surrogate-predicted* difficulty will find
levels/route_sets that exploit the surrogate's blind spots (predicted-hard, actually trivial). The
defence is structural and non-negotiable (§5): the surrogate only ever **screens and ranks**; every
shipped claim ("random-win-rate ≤ 5%", "thesis wins ≥15/16", "mechanic X adds depth") is re-derived
on the true sim on held-out seeds, and the DSAGE downsample+verify step keeps ground truth in the
loop.

### Recommended first experiment, in brief (full spec §6)

Fix one hard level (**L3 Junction** — it could not be length-shortened, its naive strategy won 6/8
held-out seeds, so it has the richest gradient near the boundary). Predict, from a route_set:
win-fraction over the 8 train seeds, the continuous score, and served/lost. Train the set-of-
sequences net and the GBT baseline on ~50–150k labeled route_sets (≈3–8 h of the existing 8-core
harness). Evaluate on held-out route_sets **and held-out seeds**: Spearman ρ of predicted vs true
score, win/lose AUC, and — the number that matters — **precision@k for "truly winning"** and
whether a surrogate-screened EA reaches ≥95% of the raw EA's ceiling at ≤¼ the true-sim budget.
Ship the export schema in §6.4 first so this is a well-defined next task.

---

## 1. Surrogate-assisted search & generation, through the optimization lens

The frame that matters: we have an expensive deterministic oracle `sim(level, route_set, seed)` and
we run it inside two nested search loops — an inner route search per level, and (eventually) an
outer level search. This is the textbook setting for **surrogate-assisted / model-based
optimization**, and the relevant literature splits into (i) the general SAEA model-management
theory, (ii) the QD-specific instantiations that match us almost exactly, and (iii) the games
"learned playtester / difficulty predictor" line that validates the *level*-altitude target.

### 1.1 DSAGE — the direct template  [established]

*Deep Surrogate Assisted Generation of Environments*, NeurIPS 2022. What it actually does, at the
level of detail we need to copy:

- **What it predicts.** A two-stage CNN. Stage 1 predicts an **ancillary occupancy grid** (expected
  agent tile-visitation) from the one-hot environment image. Stage 2 concatenates that predicted
  occupancy with the environment image and predicts the **objective** (solvable / completion rate)
  and the **QD measures** (wall count & mean path length in the Maze domain; sky tiles & jump count
  in Mario). The occupancy grid is *intermediate supervision*: it forces the model to represent the
  agent's trajectory before predicting the high-level behaviour that depends on it.
- **The loop.** Three phases per iteration. (1) *Model exploitation*: run MAP-Elites/CMA-ME for many
  generations using **surrogate predictions only** — no true sim — to fill a "surrogate archive."
  (2) *Agent simulation*: **downsample** the surrogate archive by partitioning it into a coarse grid
  of regions and drawing one solution per region (~25 environments), and evaluate *those* on the
  true simulator, yielding ground-truth objective/measures/occupancy. (3) *Model improvement*:
  retrain on the most recent ~20k samples. Only the ~25 downsampled environments per iteration cost
  a true (expensive) evaluation.
- **Why downsampling.** Evaluating the surrogate's whole archive would pour the true-sim budget onto
  wherever the surrogate is most optimistic — i.e. straight into its blind spots. One-per-region
  sampling spreads verification across behaviour space and is the mechanism that keeps the loop
  honest. This is the anti-Goodhart move, and it is cheap.
- **Ablation.** DSAGE (occupancy + downsample) beats DSAGE-Basic (neither): Maze path-length
  prediction MAE 96.6 vs 157.7; in Mario the ancillary occupancy helped less (jump-count is temporal,
  not spatial) but downsampling's iterative error-correction dominated. Headline: DSAGE reached the
  plain-MAP-Elites QD-score in ~34k evals vs 100k (Maze), and ~2.5k vs 10k (Mario) — a **3–4×
  sample-efficiency** win.

**Transfers to us:** all of it. Our stage-1 ancillary target is not an occupancy grid but the rich
outcome vector the sim already emits (served/lost/waits/gate stats, ideally per passenger type);
our stage-2 objective is win-fraction; our "measures" are whatever behavioural descriptors the
MAP-Elites archive uses (transfers, express utilisation, gate transits, route length). The loop,
the downsample-verify discipline, and the retrain-on-recent-window all copy over unchanged.

### 1.2 DSA-ME — the combinatorial-loadout instantiation  [established]

*Deep Surrogate Assisted MAP-Elites for Automated Hearthstone Deckbuilding*, GECCO 2022,
[arXiv:2112.03534](https://arxiv.org/abs/2112.03534), [code](https://github.com/icaros-usc/evostone2).
A deep surrogate predicts a deck's win rate; MAP-Elites over decks generates a diverse dataset that
improves the surrogate **online**, and the surrogate steers MAP-Elites toward promising decks. It
beats (a) a deep model trained *offline on random decks* and (b) a *linear* surrogate — i.e. the two
lessons are "train online, in the loop" and "the response surface is nonlinear enough to need depth."
The deck is a multiset of cards; a route_set is a set of ≤3 stop-sequences. The user has just built
the isomorphic thing for Smogon (team → battle win rate); this is the same object with a graph-
structured item space instead of a card catalogue. **This is the paper to mirror for the *set*
encoder and the online-training decision.**

### 1.3 General surrogate-assisted EC — the model-management vocabulary  [established]

Jin's surveys are the reference for *how much to trust the model and when*:
- Jin, *A comprehensive survey of fitness approximation in evolutionary computation*, 2005.
- Jin, *Surrogate-assisted evolutionary computation: Recent advances and future challenges*,
  Swarm & Evolutionary Computation 2011.
- Tong, Huang, et al. / Jin, *Surrogate-assisted EAs for expensive optimization: a survey*,
  Journal of Membrane Computing 2024, [link](https://link.springer.com/article/10.1007/s41965-024-00165-w);
  combinatorial-specific survey: Complex & Intelligent Systems 2024,
  [link](https://link.springer.com/article/10.1007/s40747-024-01465-5).

The transferable concepts: **individual- vs generation-based model management** (verify the best
predicted individual each generation, vs re-verify a whole generation periodically); **infill
criteria** — don't evaluate the surrogate's argmax, evaluate the point that best trades predicted
value against predicted *uncertainty* (LCB / expected improvement), which is exactly how you keep an
online surrogate from collapsing onto one exploit; and the warning that surrogate error can
**misdirect** the search, so uncertainty-gated fallback to the true oracle is mandatory, not
optional (§4.4, §5).

### 1.4 Bayesian optimization / GP surrogates  [established, but not our primary tool]

The classical expensive-black-box design toolkit — Shahriari, Swersky, Wang, Adams, de Freitas,
*Taking the Human Out of the Loop: A Review of Bayesian Optimization*, Proc. IEEE 2016,
[link](https://ieeexplore.ieee.org/document/7352306) — fits a GP per problem instance and uses an
acquisition function. **Why it is not the primary recommendation:** GP-BO is *per-instance* (re-fit
per level) and scales poorly past a few thousand points and modest dimension; we want an
**amortized** surrogate — one model that generalizes across levels and route_sets, trained once on
a large offline+online corpus — which is why DSAGE/DSA-ME use deep nets, not GPs. GP-BO remains
worth keeping in mind for the *outer* level search if that stays low-data (dozens–hundreds of fully
verified levels), where its calibrated uncertainty is a genuine asset. QD ancestry we build on:
Mouret & Clune, *Illuminating search spaces by mapping elites*, 2015,
[arXiv:1504.04909](https://arxiv.org/abs/1504.04909); Fontaine & Nikolaidis, **CMA-MAE**, 2023,
[arXiv:2205.10752](https://arxiv.org/abs/2205.10752) — the current archive optimizer to pair the
surrogate with; Gravina et al., *PCG through Quality Diversity*, IEEE CoG 2019,
[arXiv:1907.04053](https://arxiv.org/abs/1907.04053).

### 1.5 Learned playtesters and difficulty predictors — the *level*-altitude precedent  [established]

The evidence that a learned model can predict a level's difficulty *without a full search*:
- Gudmundsson et al. (King), *Human-Like Playtesting with Deep Learning*, CIG 2018,
  [pdf](https://gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf). A
  supervised CNN trained on human Candy Crush moves predicts the most human action; the resulting
  agent's pass-rate **predicts level difficulty for unreleased content**, beating MCTS on both
  correlation-with-humans and compute. The strongest existence proof that a cheap learned evaluator
  beats an expensive searcher for difficulty screening.
- Roohi et al., *Predicting Game Difficulty and Churn Without Players*, CHI PLAY 2020,
  [arXiv:2008.12937](https://arxiv.org/abs/2008.12937); extended PACM HCI 2021,
  [arXiv:2107.12061](https://arxiv.org/abs/2107.12061). DRL difficulty feeds a population model.
- Procedural personas as learned evaluators: Holmgård, Green, Liapis, Togelius, *Automated
  Playtesting With Procedural Personas Through MCTS With Evolved Heuristics*, IEEE ToG 2019,
  [arXiv:1802.06881](https://arxiv.org/abs/1802.06881). Framing that matters for us: our surrogate
  *is* an amortized procedural playtester — it answers "how does the optimizer-persona do on this
  level" in one forward pass instead of a search.

For transit-network structure specifically there is a small deep-learning-for-TNDP line (GNN/RL
over the route-design graph, e.g. RL agents that emit transit routes to satisfy demand). It informs
the *representation* (graph over stops/rooms) more than the *method*; we are not learning a policy
that draws routes, we are learning a value model that scores route_sets.

---

## 2. Representation of `(level, route_set)`

The level is a tiny graph (5×10–8×11 grid, 6–13 room cells, gate corridors with a width, per-room
demand, a passenger-type mix, and 3 typed cards). A route_set is ≤3 routes; each route is an ordered
sequence of room-stops plus a `closed` bit and optional `home` cell (the gene in `routegen.gd`;
decoded to a grid polyline by BFS). The representation question is how to feed both to a net.

### 2.1 The options

| Option | Level as | Route_set as | Captures order / one-way loop / transfers | Data hunger | Verdict |
|---|---|---|---|---|---|
| **A. Hand-features + GBT** | scalar demand/geometry features | per-route coverage, ride-dist, transfer & gate counts, stop counts, loop bits (mostly already in `routegen`/`metrics`) | only what you engineer; loops/transfers need explicit features | low | **the mandatory baseline**; may suffice for the pre-screen |
| **B. CNN, routes as grid channels** | one-hot maze tensor (H×W×classes) + demand channels | rasterize each decoded polyline as a channel (visit-order scalar + stop mask + loop/home globals) | order via a scalar channel is weak; loop direction & transfers are lossy | medium | DSAGE-native, reuses their code, good first cut; loses network structure |
| **C. GNN over the room graph** | nodes = rooms (demand in/out, type flags, coords), edges = grid adjacency / shortest-path dist / gate-crossing | routes as edge features / per-node "visited by car i in position p" | good on network structure; ordering needs positional edge features | medium | best *level* encoder; pair with C or D for routes |
| **D. Set-of-sequences transformer** | pooled GNN/CNN level embedding as context | per-route seq encoder (GRU/Transformer over stop embeddings) → **permutation-invariant pool** over ≤3 routes + card features | native: sequence = order, a flag = loop, shared stops across routes = transfer sites | medium–high | **recommended target**; the deck/team shape the user already knows |
| **E. Hybrid GNN(level) × Set-of-seq(routes)** | C | D, with stop embeddings = the GNN's room-node embeddings | best of both | high | the ceiling; go here once data supports it |

### 2.2 Recommended architecture

Start at **D with a CNN level context** for the first experiment (least infrastructure, and the maze
is genuinely image-like), then graduate to **E** (GNN level context feeding the stop embeddings) once
the online loop is producing enough cross-level data to justify it. Rationale:

- The route_set is fundamentally a *set of variable-length sequences over a shared node set*.
  Deep Sets (Zaheer et al., 2017, [arXiv:1703.06114](https://arxiv.org/abs/1703.06114)) and Set
  Transformer (Lee et al., 2019, [arXiv:1810.00825](https://arxiv.org/abs/1810.00825)) give the
  permutation-invariant pooling over the ≤3 routes for free — and the routes *are* exchangeable
  except through their bound card, so attach card features to each route token and pool. This is the
  exact inductive bias of a Smogon-team or Hearthstone-deck encoder.
- Transfers are the subtle interaction: two routes that share a room stop create a transfer hub, and
  outcome depends on it. A set encoder with attention across route tokens can represent
  "these two routes share stop X" if stop identities are shared embeddings; a CNN with separate
  channels cannot without help. This is the single strongest argument for D/E over B.
- The one-way `closed` loop makes ride distance *direction-dependent* (`Route3.ride_dist`), so the
  sequence encoder must be order-sensitive (not a bag-of-stops) and must see the loop bit.

### 2.3 Output heads and the seed question

**Heads.** Predict the whole outcome vector, DSAGE-style, not just WIN:
- **Primary:** `win_fraction ∈ [0,1]` over the seed set (regression, sigmoid). Because the sim is
  *deterministic per seed*, the seed is a nuisance input that is fully integrated out by
  `win_count / n_seeds`; that fraction is smooth in the route_set and is *exactly what the difficulty
  metric consumes* (the random-win-rate target is a win-fraction). This is your Smogon/Hearthstone
  win-rate head.
- **Auxiliary (dense supervision):** `served`, `lost`, `avg_wait`, `p90_wait`, `avg_transfers`,
  `gate_wait`, `gate_transits`, and **per-passenger-type served/lost** (needs a small addition to
  `_harvest`, §6.4). These are causally upstream of WIN and regularize the primary head; this is the
  direct analogue of DSAGE's ancillary occupancy grid.
- **Time-to-quota:** censored regression — only defined for winners; model as "P(reach quota)" gate
  × "time | reached" (a survival/Tobit head), or simply mask the loss on non-winners.

**The seed aspect — three ways, ranked:**
1. **Predict the aggregate `win_fraction` and mean outcome directly (recommended).** Smoothest
   target, matches what the metrics need, cheapest. The label is the mean over the fixed seed set.
2. **Per-seed prediction with a seed embedding.** Only if you need the *shape* of the outcome
   distribution (e.g. seed_fragility σ/μ). Because seeds are exchangeable draws from the spawn RNG,
   a learned seed embedding is honest but adds variance for little metric value in v1. Consider it a
   phase-2 head, not the starting point.
3. **Predict the full outcome distribution (quantiles / a small mixture).** Overkill until (1) is
   solid; revisit if the win boundary turns out bimodal across seeds (the L3 "naive won 6/8" pattern
   suggests some levels *are* near-bimodal, which is an argument to eventually model spread).

Do **not** feed a single seed as a one-hot and predict that seed's WIN as the primary target: it
throws away the marginalization that makes the target smooth and makes the surrogate memorize spawn
schedules — the exact seed-overfitting pitfall the depth tools already guard against.

---

## 3. Two surrogate altitudes, and which is which

**(a) Outcome surrogate — `sim_hat(level, route_set) -> outcome`.** Replaces individual `sim_api.run`
calls *inside* the route optimizer. Screens which route_sets are worth truly simulating. This is
DSAGE's stage-2 model. Build this first.

**(b) Level-difficulty surrogate — `diff_hat(level) -> {random_win_rate, skill_gap, ...}`.** Predicts
a level's difficulty metrics *from the level alone, without running a route search*. This is the real
PCG accelerator: generate level → predict metrics → keep the promising few → verify with a real
search. It is the expensive one to *label*, because each ground-truth label is a full inner
optimizer run (thousands of sims).

**(b) is built on (a), two ways:**
- **Derived, no extra model.** If `sim_hat` is accurate, the difficulty metrics are just *functionals
  of its predictions*. `random_win_rate(level)` = Monte-Carlo sample route_sets and average
  `sim_hat`'s predicted win-fraction — no true sim. `ceiling`/`skill_gap` = run a **surrogate-only
  EA/MAP-Elites** (the inner optimizer with `sim_hat` in place of `sim_api.run`) and read the best
  predicted score minus the predicted random score. This is the cheapest (b): it is (a) plus an
  aggregation loop, and it is exactly DSAGE's "model exploitation" phase producing a difficulty
  estimate as a by-product.
- **Distilled, a second model.** Once you have a corpus of `(level, true difficulty metrics)` pairs
  (each label = one real inner search), train `diff_hat` to regress them directly from the level
  encoder. Faster at PCG scale (one forward pass vs a surrogate-EA per level) and it can learn
  systematic corrections to the derived estimate. Distill the derived (a)-based estimate into
  `diff_hat` and fine-tune on the true labels.

**Data each needs.** (a): `(level, route_set, seed) -> outcome` tuples — cheap, one sim each.
(b)-derived: nothing beyond (a). (b)-distilled: `(level, verified difficulty metrics)` — expensive,
one inner search each, so you get few of these and they must come from the *outer* generate-verify
loop, not be manufactured up front.

---

## 4. Training data and the active-learning pipeline

The deterministic sim is a *perfect labeler* — no label noise, bit-reproducible — which removes the
usual "is this label right" worry and lets us treat data purely as a coverage problem.

### 4.1 The training distribution is the whole game

A surrogate is only trustworthy where its training data lives, and the two loops operate in very
different regions, so **the mixture matters more than the count**:
- **Uniform-random route_sets (free).** This is already how difficulty is measured
  (`run_depth.gd --scorecheck`), and the labels already exist. But note the measured base rates:
  uniform-random *wins* 0.3–3.1% of the time (`depth-tools-spec.md`). A surrogate trained only on
  this is accurate at predicting "loses" and useless at the win boundary — where the optimizer and
  every interesting decision live. Necessary, not sufficient.
- **EA-elites + their 1-mutation neighbourhoods.** The winning/near-winning region uniform-random
  never reaches. `routegen.mutate` already generates the neighbourhood; label the elites and their
  mutants to teach the surrogate the *shape of the boundary*, which is the only place ranking has to
  be right.
- **MAP-Elites archive members.** Behavioural spread (the archive descriptors) so the surrogate sees
  structurally diverse route_sets, not just the EA's single basin — this is what makes it generalize
  to a generator that later explores new behaviours.
- **Held-out seeds.** Always label over the 8 train seeds; keep the 8 test seeds for evaluating the
  surrogate, so "generalizes to unseen spawn schedules" is measured, not assumed.

### 4.2 The DSAGE loop, mapped

Per outer iteration (per level for altitude a; per level *population* for the eventual b):
1. **Model exploitation.** Run the inner MAP-Elites/EA using `sim_hat` only → a surrogate archive of
   predicted-elite route_sets. Cost: forward passes, negligible.
2. **Downsample.** Partition the surrogate archive by behaviour region; draw one route_set per region
   → a batch of ~25–50. (Downsampling, not top-k, is what stops the batch from piling onto the
   surrogate's favourite exploit.)
3. **Verify on the true sim.** `sim_api.score_seeds` on the batch over the 8 train seeds. This is the
   only expensive step; at ~40 evals/s, a 40-route_set batch × 8 seeds = 320 sims ≈ 8 s.
4. **Append + retrain.** Add the verified tuples to the corpus; retrain (or fine-tune) on the recent
   window. Repeat.

### 4.3 Distribution shift

The generator will keep finding route_sets/levels the surrogate has never seen — that is its job, and
it is precisely what breaks an offline surrogate (DSA-ME's "offline-on-random" baseline). Two
defences, both from the SAEA literature:
- **The verify step is the correction.** Every downsampled batch is ground-truthed and appended, so
  the training set *follows the generator* into new regions. Novelty is self-correcting on a lag of
  one iteration.
- **Uncertainty as an OOD alarm.** Train a small **deep ensemble** (3–5 nets, different seeds/inits;
  Lakshminarayanan et al., 2017, [arXiv:1612.01474](https://arxiv.org/abs/1612.01474)) or use
  MC-dropout (Gal & Ghahramani, 2016, [arXiv:1506.02142](https://arxiv.org/abs/1506.02142)).
  Disagreement flags a route_set the ensemble is guessing on → force a true sim and demote it in the
  ranking. Deep ensembles are the more reliable uncertainty signal and the ≤5-model cost is trivial
  here. Use an LCB/uncertainty-aware infill (§1.3): among predicted-good candidates, prefer the
  uncertain ones for verification, so the loop learns where it is weak.

### 4.4 When to fall back to the true sim

- **Screening (surrogate leads):** rank all candidates by `sim_hat`, truly simulate only the top
  fraction and the high-uncertainty fraction. Wrong rankings cost wasted sims, never wrong claims.
- **Boundary (uncertainty-gated):** any candidate near a decision threshold (win_fraction near the
  quota, or near a metric cutoff like the 5% random-win-rate line) with non-trivial ensemble
  variance → true sim. The threshold is where surrogate error changes a *decision*, so spend there.
- **Certification (surrogate excluded):** any number that gets reported or shipped — §5.

---

## 5. The trust boundary

**Correctness never depends on the surrogate.** It is a search accelerator, full stop. The same
find-then-adversarially-verify discipline the depth tools already run (`SEEDS_TRAIN` to search,
`SEEDS_TEST` to report; `SEEDS_ASSERT` held out from tuning) extends cleanly: the surrogate lives
entirely on the *find* side.

**Where the surrogate is allowed to be wrong:**
- Ranking route_sets for the pre-screen (a mis-rank wastes a true sim).
- Guiding the inner MAP-Elites toward promising regions (a bad steer wastes exploration).
- Pre-filtering generated levels before the expensive verification search (a false positive wastes
  one verification; a false negative discards one candidate level, of which there are thousands).

**Where it is never allowed to be wrong — these come only from the true sim on held-out seeds:**
- "random-win-rate ≤ 5%" (the difficulty gate).
- "thesis WINS ≥ 15/16, naive LOSES ≥ 15/16" (the balance axioms).
- "this level is winnable / deep / has skill-gap X" (any shipped metric).
- "mechanic X adds depth" (the ablation verdict).
- The route_set written to `discovered3.gd` and shown in WATCH BEST — a real elite, re-verified.

**Goodhart, concretely.** The failure mode is a level generator that maximizes
`diff_hat(level).skill_gap` and finds levels that score high *because the surrogate is wrong on
them*, not because they are deep — the generator is an adversary actively searching the surrogate's
error surface (cf. Volz et al., *Evolving Mario Levels in the Latent Space of a DCGAN*, GECCO 2018,
[arXiv:1805.00728](https://arxiv.org/abs/1805.00728), where levels evolved against an agent exploit
that agent). Defences, in order of importance:
1. **The true sim always has the last word.** Every *kept* level is verified by a real inner search
   before it counts. The surrogate chooses *what to verify*, never *what is true*. A Goodharted level
   simply fails verification and is discarded — the generator wasted surrogate time, nothing more.
2. **Downsample-and-verify keeps ground truth in the loop** (§4.2), so the surrogate is continuously
   re-grounded in exactly the region the generator is exploiting; the exploit is trained away within
   an iteration or two.
3. **Never optimize the raw surrogate output as the acceptance objective.** Generate against
   `diff_hat`, but *accept* against the true-sim metric. The surrogate is a proposal distribution,
   not a fitness function of record.
4. **Ensemble disagreement demotes OOD candidates** (§4.3) — a level the ensemble disagrees on is by
   definition one the generator may be exploiting.
5. **The existing anti-Goodhart guards still apply and double as surrogate sanity checks:**
   `plan_fragility`, `seed_fragility`, and hand-watching the elites in WATCH mode. A level the
   surrogate loves but whose verified elites are fragile or look identical is a red flag on both the
   level *and* the surrogate.

---

## 6. Recommended first experiment (full spec)

The smallest surrogate that proves value, and the exporter to feed it.

### 6.1 What it predicts

Fix **L3 Junction** (index via `Levels3.index_of("L3")`). Chosen because it could not be
length-shortened, its naive strategy won 6/8 held-out seeds, and its random-win-rate is the highest
in the table (2.7%) — the richest gradient and the most interesting boundary. Predict, from a
route_set (the 3 genes / decoded routes):
- `win_fraction` over `SEEDS_TRAIN` (8 seeds) — primary;
- `score` (the continuous `sim_api.score_of` value, on the losing branch it is the dense signal);
- `served`, `lost` — auxiliary.

Single-level first deliberately isolates "can the representation learn the response surface" from
"does it generalize across levels." If it can't clear the bar on one level, the cross-level version
won't either.

### 6.2 Representation

Set-of-sequences net (§2.2 option D) with a CNN level context, **plus** the GBT-on-hand-features
baseline (§2.1 option A) it must beat. For a single fixed level the CNN context is a constant, so v1
effectively tests the *route_set* encoder — which is the part that has to be right for a pre-screen.
Keep the level encoder in the code path so the identical model extends to multi-level in phase 2.

### 6.3 Data volume, eval, success bar

- **Volume.** ~50–150k labeled route_sets over 8 seeds. At the measured ~40 evals/s (8 cores),
  100k route_sets × 8 seeds = 800k sims ≈ **5.5 h** — one overnight run. Sample the mixture of §4.1
  (uniform-random : EA-elites+mutants : MAP-Elites members ≈ 40:40:20). Reuse the existing
  `runcache_<ID>.json` so a killed shard resumes.
- **Eval — held out on BOTH axes.** Disjoint held-out route_sets, and predict `SEEDS_TEST` outcomes
  (unseen spawn schedules). Report:
  - **Spearman ρ** of predicted vs true `score` (overall, and *within the losing branch* — the
    branch carries the search gradient; a screener that only separates wins from losses but can't
    rank losers can't climb).
  - **Win/lose AUC** and win_fraction **MAE**.
  - **precision@k for "truly winning"** (k = 50, 100) — the pre-screen's actual job; against a
    ~1–3% base rate this is the number with real lift.
  - **Downstream:** a surrogate-screened EA that truly-simulates only the top-10% of surrogate-ranked
    proposals vs the raw EA — best score reached vs true-sim budget spent.
- **Success bar.** (i) Spearman ρ ≥ 0.9 within the losing branch and win/lose AUC ≥ 0.95 on held-out
  route_sets *and* seeds; (ii) precision@100 for "truly winning" gives ≥10× lift over base rate;
  (iii) surrogate-screened EA reaches ≥95% of the raw EA's median ceiling at ≤¼ the true-sim budget.
  (iv) It must beat the GBT baseline on (i)–(ii) — if it doesn't, ship the GBT as the pre-screen and
  don't build the net. Report all of this honestly per `depth-tools-spec.md §8`; a surrogate that
  can't clear the bar is a finding, not a fudge.

### 6.4 Export schema (the well-defined next task)

The sim already emits the label vector in `sim_api._harvest` (`out`). The exporter is: for each
`sim_api.run`, write one row. Emit JSONL for the structured fields (portable, the ML side tensorizes)
and let the trainer build tensors; also emit the derived tensors so a consumer can skip re-deriving.

**Add to `_harvest` first (one change):** per-passenger-type `served`/`lost` counts (walk
`log_served`/`log_lost` by `.type`) — the auxiliary heads want them, and they cost nothing.

**Row = one `(level, route_set, seed)` label:**

```jsonc
{
  // --- keys / provenance ---
  "level_id": "L3",
  "level_hash": "<sha1 of level.rows + demand + mix + cards + quota/max_lost>",
  "seed": 1101, "step": 0.25,
  "score_rule": "t420_w1000_l3.0_a0.010_v3",   // sim_api._cache_version(), reject mismatched
  "route_set_key": "<routegen.genome_key>",     // dedupe

  // --- route_set (structured; ML side chooses representation) ---
  "routes": [
    { "card": 0, "type": "standard", "width": 2, "cap": 6, "speed": 260, "accel": 300,
      "stops": [[1,3],[3,3],[3,0]],             // room cells, visit order
      "closed": false, "home": null,
      "cells": [[1,3],[2,3],[3,3],[3,2],[3,1],[3,0]] }, // decoded polyline (optional)
    { "card": 1, ... }, { "card": 2, ... }
  ],

  // --- labels (from _harvest.out) ---
  "result": "lose",                              // win | lose | timeout
  "score": 41.2, "t_end": 173.4,
  "served": 108, "lost": 6,
  "avg_wait": 14.1, "p90_wait": 39.2, "avg_transfers": 0.7,
  "waiting_end": 12, "no_path_end": 0,
  "gate_wait": 22.5, "gate_transits": 31,
  "served_by_type": {"visitor": 52, "patient": 49, "exec": 7},   // NEW
  "lost_by_type":   {"visitor": 1,  "patient": 4,  "exec": 1}    // NEW
}
```

**Level static tensor (written once per level, referenced by `level_hash`), for the CNN/GNN:**
- `grid`: `H×W×C` one-hot over cell classes {open, blocked, room, gate}; a separate channel holds
  gate corridor **width**; a channel holds `gate_group_id` (so the mutex structure is visible).
- `demand`: per-room in-weight and out-weight channels (from `routegen.demand`); per-room
  type-origin / type-dest flags (exec/freight lanes via `exec_*` / `type_rooms`).
- `room_index`: `H×W` map from cell → room-node id (so the set-encoder's stop embeddings and the CNN
  share a room indexing).
- `cards`: `3×F` card feature matrix (width, cap, speed, accel, one-hot type).
- scalars: `quota`, `max_lost`, spawn `{interval_start, interval_end, ramp, burst_min, burst_max,
  gap}`, per-type `patience` and `mix`.

**Route tensor (per row, derived — optional, for the CNN path):** per card, an `H×W` rasterization
of the decoded polyline carrying (normalized visit-order scalar, stop-mask), plus route globals
(`closed`, `home` one-hot). For the set-of-sequences path, the `stops` list + `room_index` is enough;
emit both so the representation choice stays open.

Aggregation to a per-`(level, route_set)` example (win_fraction + mean outcome over the 8 seeds) is a
trivial group-by on `route_set_key` at train time — keep the rows per-seed on disk so the seed-level
distribution stays available for phase-2 heads.

---

## Bibliography

Surrogate-assisted generation / QD (the core):
- Bhatt, Tjanaka, Fontaine, Nikolaidis. *Deep Surrogate Assisted Generation of Environments (DSAGE)*.
  NeurIPS 2022. https://arxiv.org/abs/2206.04199 · code https://github.com/icaros-usc/dsage
- Zhang, Fontaine, Hoover, Nikolaidis. *Deep Surrogate Assisted MAP-Elites for Automated Hearthstone
  Deckbuilding (DSA-ME)*. GECCO 2022. https://arxiv.org/abs/2112.03534 · code
  https://github.com/icaros-usc/evostone2
- Mouret, Clune. *Illuminating search spaces by mapping elites*. 2015. https://arxiv.org/abs/1504.04909
- Fontaine, Nikolaidis. *Covariance Matrix Adaptation MAP-Annealing (CMA-MAE)*. GECCO 2023.
  https://arxiv.org/abs/2205.10752
- Gravina, Khalifa, Liapis, Togelius, Yannakakis. *PCG through Quality Diversity*. IEEE CoG 2019.
  https://arxiv.org/abs/1907.04053
- Fontaine et al. *Mapping Hearthstone Deck Spaces through MAP-Elites with Sliding Boundaries*.
  GECCO 2019. https://arxiv.org/abs/1904.10656

Surrogate-assisted EC theory / model management:
- Jin. *Surrogate-assisted evolutionary computation: recent advances and future challenges*. Swarm &
  Evolutionary Computation, 2011.
- Jin. *A comprehensive survey of fitness approximation in evolutionary computation*. Soft Computing,
  2005.
- *Surrogate-assisted EAs for expensive optimization: a survey*. J. Membrane Computing, 2024.
  https://link.springer.com/article/10.1007/s41965-024-00165-w
- *Surrogate-assisted EAs for expensive combinatorial optimization: a survey*. Complex & Intelligent
  Systems, 2024. https://link.springer.com/article/10.1007/s40747-024-01465-5
- Shahriari, Swersky, Wang, Adams, de Freitas. *Taking the Human Out of the Loop: A Review of
  Bayesian Optimization*. Proc. IEEE 2016. https://ieeexplore.ieee.org/document/7352306

Representation:
- Zaheer et al. *Deep Sets*. NeurIPS 2017. https://arxiv.org/abs/1703.06114
- Lee et al. *Set Transformer*. ICML 2019. https://arxiv.org/abs/1810.00825

Uncertainty:
- Lakshminarayanan, Pritzel, Blundell. *Simple and Scalable Predictive Uncertainty Estimation using
  Deep Ensembles*. NeurIPS 2017. https://arxiv.org/abs/1612.01474
- Gal, Ghahramani. *Dropout as a Bayesian Approximation (MC-dropout)*. ICML 2016.
  https://arxiv.org/abs/1506.02142

Learned playtesters / difficulty / Goodhart:
- Gudmundsson et al. (King). *Human-Like Playtesting with Deep Learning*. CIG 2018.
  https://gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf
- Roohi et al. *Predicting Game Difficulty and Churn Without Players*. CHI PLAY 2020.
  https://arxiv.org/abs/2008.12937 · PACM HCI 2021 https://arxiv.org/abs/2107.12061
- Holmgård, Green, Liapis, Togelius. *Automated Playtesting With Procedural Personas Through MCTS
  With Evolved Heuristics*. IEEE ToG 2019. https://arxiv.org/abs/1802.06881
- Volz et al. *Evolving Mario Levels in the Latent Space of a DCGAN*. GECCO 2018.
  https://arxiv.org/abs/1805.00728

Prior in-repo context: `docs/autodesign-research.md` (§5.1 the analytical pre-screen this
generalizes, §4.6 QD), `docs/depth-tools-spec.md` (scoring, seeds, the metrics the surrogate must
not certify), `docs/sim-search-feasibility.md` (throughput/determinism — the labeler budget).
