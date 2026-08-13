extends RefCounted
## The agent LADDER (docs/depth-tools-spec.md §4). Three optimizers of very
## different strength, all playing the same game with the same evaluation
## protocol, so the gaps between them are the depth signal
## (Nielsen et al. 2015, relative algorithm performance profiles):
##
##   random  — uniform sampling of decodable route-sets. "Does thinking help?"
##   greedy  — beam search (width 8) growing one card's stop sequence at a
##             time. Short-horizon tactics only.
##   ea      — (mu+lambda) = 12+24 evolutionary search over route genes,
##             seeded from hand-built primitives AND random genomes, with the
##             TRNDP mutation set. Our ceiling estimator.
##
## THE BUDGET CURRENCY IS ONE SIMULATION RUN, not one candidate: a candidate
## costs len(seeds) runs, so "6400" means the same amount of compute for every
## rung. All three record an anytime CHECKPOINT curve (best-so-far at 100 /
## 400 / 1600 / 6400 runs), which is the ladder of docs/autodesign-research.md
## §4.1 with optimizer budget standing in for the paper's CR-level.
##
## OPTIMIZERS SEE TRAIN SEEDS ONLY. Nothing in this file ever touches
## SEEDS_TEST — that is what makes the reported numbers mean anything.

const RG = preload("res://tools/routegen.gd")
const NEG_INF := -1.0e18

var sim # tools/sim_api.gd instance
var level_index := 0
var level: Dictionary = {}
var rooms: Array = []
var n_cards := 3
var seeds: Array = [] # TRAIN seeds only
var step := 0.25
var rng := RandomNumberGenerator.new()

var cache := {} # genome_key -> score (never re-simulated, never re-charged)
var archive := [] # every distinct candidate: {"key", "genome", "routes", "score"}
var log_lines: Array = []
## Set to an open FileAccess to dump every evaluated genome key (debugging a
## crash inside a 6400-run search is otherwise archaeology).
var trace = null


func setup(sim_api, li: int, lv: Dictionary, train_seeds: Array, search_step: float,
		seed_v: int) -> void:
	sim = sim_api
	level_index = li
	level = lv
	rooms = Grid3.rooms().duplicate()
	n_cards = lv.cards.size()
	seeds = train_seeds
	step = search_step
	rng.seed = seed_v


# ---------------------------------------------------------------- evaluation

## Median TRAIN score of a genome. Undecodable genomes score -INF and cost no
## budget (they never reach the simulator). Repeats are served from cache.
func evaluate(genome: Array, use_seeds: Array = []) -> float:
	var sd: Array = seeds if use_seeds.is_empty() else use_seeds
	var key := RG.genome_key(genome) + "#%d" % sd.size()
	if trace != null:
		trace.store_line(key)
		trace.flush()
	if cache.has(key):
		return cache[key]
	var dec := RG.decode_genome(genome)
	if dec.err != "":
		cache[key] = NEG_INF
		return NEG_INF
	var r: Dictionary = sim.score_seeds(level_index, dec.routes, sd, step)
	cache[key] = r.score
	if sd.size() == seeds.size():
		archive.append({"key": key, "genome": RG.clone(genome),
				"routes": dec.routes, "score": r.score})
	return r.score


# ---------------------------------------------------------------- ladder rungs

## Uniform sampling of decodable route-sets: the weakest rung.
##
## NOTE FOR THE REPORT: random-at-budget-B is best-of-B, not one draw. That is
## a genuinely strong baseline, and the only fair comparison against it is the
## EA at the SAME budget — which is what `ea@B` vs `random@B` is.
func run_random(budget: int, checkpoints: Array) -> Dictionary:
	var st := _new_state(checkpoints)
	var tried := 0
	var undecodable := 0
	var stall := 0
	while sim.runs - st.start < budget:
		tried += 1
		var before: int = sim.runs
		var g := RG.random_genome(rng, rooms, n_cards)
		if g.is_empty():
			undecodable += 1
		else:
			_offer(st, g, evaluate(g))
		# The decodable genome space can be SMALLER than the budget: a tiny level
		# (e.g. a 3-room tutorial) has only a handful of distinct decodable route-
		# sets, so once they are all scored every fresh sample is either
		# undecodable or an already-evaluated (cached) genome — neither of which
		# spends budget. `sim.runs` then plateaus below `budget` and the loop
		# would spin forever. Bail when the space is visibly exhausted, mirroring
		# run_ea's `stale` guard. A healthy level resets `stall` every draw.
		if sim.runs == before:
			stall += 1
			if stall >= 20000:
				break
		else:
			stall = 0
	var out := _finish(st)
	out["diag"] = {"proposed": tried, "undecodable": undecodable}
	return out


## Beam search over stop sequences: start from the heaviest demand pairs, then
## repeatedly append the single best next stop to one card at a time. Cheap on
## purpose (2 train seeds per candidate) — it is a ladder rung, not a
## contender; its elite is re-scored on the TEST seeds like everything else.
func run_greedy(budget: int, checkpoints: Array, beam_w := 8, n_seeds := 2,
		max_grow := 5) -> Dictionary:
	var st := _new_state(checkpoints)
	var gs: Array = seeds.slice(0, mini(n_seeds, seeds.size()))
	var pairs := RG.demand_pairs(level)
	var start: Array = []
	for c in n_cards:
		var p: Dictionary = pairs[mini(c, pairs.size() - 1)]
		start.append({"stops": [p.from, p.to], "closed": false})
	if RG.decode_genome(start).err != "":
		start = RG.random_genome(rng, rooms, n_cards)
		if start.is_empty():
			return _finish(st)
	var beam: Array = [start]
	_offer(st, start, evaluate(start, gs))
	for card in n_cards:
		for _grow in max_grow:
			if sim.runs - st.start >= budget:
				break
			var cands: Array = []
			var seen := {}
			for state in beam:
				for r in rooms:
					if (state[card].stops as Array).has(r):
						continue
					var c1 := RG.clone(state)
					(c1[card].stops as Array).append(r)
					_push_unique(cands, seen, c1)
				var c2 := RG.clone(state)
				c2[card].closed = not c2[card].closed
				_push_unique(cands, seen, c2)
			var scored: Array = []
			for c in cands:
				if sim.runs - st.start >= budget:
					break
				var s := evaluate(c, gs)
				if s > NEG_INF:
					scored.append({"g": c, "s": s})
					_offer(st, c, s)
			if scored.is_empty():
				break
			scored.sort_custom(func(a, b): return a.s > b.s)
			var next_beam: Array = []
			for i in mini(beam_w, scored.size()):
				next_beam.append(scored[i].g)
			beam = next_beam
	return _finish(st)


## (mu + lambda) evolutionary search over route-set genes.
##
## INSTRUMENTED (docs/depth-tools-spec.md §5): the returned `diag` carries
## everything needed to tell "this level is shallow" apart from "this EA is
## broken" — how many proposals never decoded, how many generations actually
## ran, the best-so-far and population-diversity curves, and whether the
## mutation/crossover operators move the score at all.
func run_ea(budget: int, checkpoints: Array, mu := 12, lam := 24) -> Dictionary:
	var st := _new_state(checkpoints)
	var diag := {
		"mu": mu, "lam": lam, "generations": 0, "children": 0,
		"undecodable": 0, "cached": 0, "seeded_primitive": 0, "seeded_random": 0,
		"ops": {
			# `compared` is the denominator for changed/improved/sum_abs: only
			# children that have a parent AND decoded can be compared, so
			# immigration (no parent) legitimately reports n/a there.
			"mutate": {"n": 0, "compared": 0, "changed": 0, "sum_abs": 0.0, "improved": 0},
			"crossover": {"n": 0, "compared": 0, "changed": 0, "sum_abs": 0.0, "improved": 0},
			"immigrate": {"n": 0, "compared": 0, "changed": 0, "sum_abs": 0.0, "improved": 0},
		},
		"gen_curve": [], # {gen, runs, best, pop_best, pop_mean, distinct, spread}
		"stopped": "budget",
	}
	var pop: Array = []
	# Seed from hand-built primitives first, then top up with random genomes
	# (docs/autodesign-research.md §0.2: primitive-seeded populations are
	# standard TRNDP practice; pure noise wastes most of the budget).
	for g in RG.primitive_genomes(level, n_cards, rng, mu):
		if pop.size() >= mu:
			break
		pop.append({"g": g, "s": 0.0})
		diag.seeded_primitive += 1
	while pop.size() < mu:
		var rg := RG.random_genome(rng, rooms, n_cards)
		if rg.is_empty():
			break
		pop.append({"g": rg, "s": 0.0})
		diag.seeded_random += 1
	for m in pop:
		m.s = evaluate(m.g)
		_offer(st, m.g, m.s)
	var stale := 0
	while sim.runs - st.start < budget and not pop.is_empty():
		var before: int = sim.runs
		var kids: Array = []
		for _i in lam:
			var child: Array
			var op := "mutate"
			var parent_s := NEG_INF
			if rng.randf() < 0.1:
				# Immigration: a fresh uniform sample every so often. Without it
				# a converged population can spend the rest of the budget
				# re-proposing cached genomes, and the "ceiling" rung ends up
				# WORSE than the random rung it is supposed to dominate.
				op = "immigrate"
				child = RG.random_genome(rng, rooms, n_cards)
				if child.is_empty():
					op = "mutate"
					var pm: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
					parent_s = pm.s
					child = RG.mutate(rng, pm.g, rooms)
			elif pop.size() >= 2 and rng.randf() < 0.3:
				op = "crossover"
				var pa: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
				var pb: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
				parent_s = maxf(pa.s, pb.s)
				child = RG.crossover(rng, pa.g, pb.g)
				if rng.randf() < 0.5:
					child = RG.mutate(rng, child, rooms)
			else:
				var pm2: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
				parent_s = pm2.s
				child = RG.mutate(rng, pm2.g, rooms)
			kids.append({"g": child, "op": op, "ps": parent_s})
		for k in kids:
			if sim.runs - st.start >= budget:
				break
			var child: Array = k.g
			var key := RG.genome_key(child) + "#%d" % seeds.size()
			var was_cached: bool = cache.has(key)
			var s := evaluate(child)
			diag.children += 1
			if was_cached:
				diag.cached += 1
			if s <= NEG_INF:
				diag.undecodable += 1
			_offer(st, child, s)
			# Operator effect: does this operator move the score at all?
			var o: Dictionary = diag.ops[k.op]
			o.n += 1
			if s > NEG_INF and k.ps > NEG_INF:
				o.compared += 1
				var d: float = s - k.ps
				o.sum_abs += absf(d)
				if absf(d) > 0.0001:
					o.changed += 1
				if d > 0.0:
					o.improved += 1
			if s > NEG_INF:
				pop.append({"g": child, "s": s})
		pop = _select_survivors(pop, mu)
		diag.generations += 1
		diag.gen_curve.append(_pop_snapshot(diag.generations, sim.runs - st.start,
				st.best, pop))
		# A generation that spent no budget at all is a fully cached (i.e.
		# converged) population — bail rather than spin forever.
		stale = stale + 1 if sim.runs == before else 0
		if stale >= 50:
			diag.stopped = "converged (50 generations bought no new evaluation)"
			break
	if pop.is_empty():
		diag.stopped = "population died"
	var out := _finish(st)
	out["diag"] = diag
	return out


## (mu+lambda) survivor selection: best `mu`, but **no duplicate genomes**.
##
## Plain truncation is a trap for this score. Many structurally different plans
## finish the level on the very same tick, so they tie exactly; ties then fill
## every mu slot with copies of two or three genomes, every child is a mutation
## of the same parent, and the search stalls. Measured before this fix: mean
## pairwise diversity inside the population hit 0.000 by generation 4 and never
## recovered, only 2-5 of the 12 slots held distinct genomes, and the
## best-so-far was frozen for the last two thirds of the budget.
##
## Keeping only distinct genomes is the minimum honest fix: identical genomes
## carry identical information, so a population of twelve copies of one plan is
## a population of one.
func _select_survivors(pop: Array, mu: int) -> Array:
	pop.sort_custom(func(a, b): return a.s > b.s)
	var out: Array = []
	var seen := {}
	for m in pop:
		var k := RG.genome_key(m.g)
		if seen.has(k):
			continue
		seen[k] = true
		out.append(m)
		if out.size() >= mu:
			break
	return out


## Population health at the end of a generation: best/mean score, how many of
## the mu slots hold DISTINCT genomes, and the mean pairwise Jaccard distance
## over per-card stop sets (0 = the population has collapsed onto one plan).
func _pop_snapshot(gen: int, runs_used: int, best: float, pop: Array) -> Dictionary:
	var keys := {}
	var sum := 0.0
	var n := 0
	for m in pop:
		keys[RG.genome_key(m.g)] = true
		if m.s > NEG_INF:
			sum += m.s
			n += 1
	var dec: Array = []
	for m in pop:
		var d := RG.decode_genome(m.g)
		if d.err == "":
			dec.append(d.routes)
	var pairs := 0
	var dist := 0.0
	for i in dec.size():
		for j in range(i + 1, dec.size()):
			dist += RG.structural_distance(dec[i], dec[j])
			pairs += 1
	return {"gen": gen, "runs": runs_used, "best": best,
			"pop_best": pop[0].s if not pop.is_empty() else NEG_INF,
			"pop_mean": sum / maxf(1.0, float(n)),
			"distinct": keys.size(),
			"spread": dist / maxf(1.0, float(pairs))}


# ---------------------------------------------------------------- bookkeeping

func _new_state(checkpoints: Array) -> Dictionary:
	return {"start": sim.runs, "best": NEG_INF, "genome": [], "checkpoints": checkpoints,
			"next_cp": 0, "curve": []}


## Record a candidate and, whenever the run counter passes a checkpoint, snap
## the best-so-far elite for that budget (the anytime ladder curve).
func _offer(st: Dictionary, genome: Array, score: float) -> void:
	if score > st.best:
		st.best = score
		st.genome = RG.clone(genome)
	var used: int = sim.runs - st.start
	while st.next_cp < st.checkpoints.size() and used >= st.checkpoints[st.next_cp]:
		st.curve.append({"budget": st.checkpoints[st.next_cp], "score": st.best,
				"genome": RG.clone(st.genome)})
		st.next_cp += 1


func _finish(st: Dictionary) -> Dictionary:
	var used: int = sim.runs - st.start
	while st.next_cp < st.checkpoints.size():
		st.curve.append({"budget": st.checkpoints[st.next_cp], "score": st.best,
				"genome": RG.clone(st.genome)})
		st.next_cp += 1
	return {"best_score": st.best, "best_genome": st.genome, "curve": st.curve,
			"runs_used": used}


func _push_unique(cands: Array, seen: Dictionary, g: Array) -> void:
	var k := RG.genome_key(g)
	if seen.has(k):
		return
	seen[k] = true
	cands.append(g)


## `n` distinct candidates sampled EVENLY across the whole evaluated score
## range — the honest sample for the coarse-vs-fine rank-correlation check
## (the top of the archive is a near-tie plateau where ranks mean little).
func spread_archive(n: int) -> Array:
	var a: Array = []
	var seen := {}
	for e in archive:
		if e.score <= NEG_INF or seen.has(e.key):
			continue
		seen[e.key] = true
		a.append(e)
	a.sort_custom(func(x, y): return x.score > y.score)
	if a.size() <= n:
		return a
	var out: Array = []
	for i in n:
		out.append(a[int(round(float(i) * (a.size() - 1) / float(n - 1)))])
	return out


## The `n` best distinct candidates ever evaluated (for the coarse-vs-fine
## rank-correlation check).
func top_archive(n: int) -> Array:
	var a := archive.duplicate()
	a.sort_custom(func(x, y): return x.score > y.score)
	var out: Array = []
	var seen := {}
	for e in a:
		if seen.has(e.key) or e.score <= NEG_INF:
			continue
		seen[e.key] = true
		out.append(e)
		if out.size() >= n:
			break
	return out
