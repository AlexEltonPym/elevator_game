extends RefCounted
## The agent LADDER for v5 (docs/v5-transition-spec.md §5.1 "optimizers ports
## nearly unchanged" + the Reading-B outputs). Ports tools/optimizers.gd:
##
##   random  — uniform sampling of decodable route-sets. "Does thinking help?"
##   greedy  — beam search (width 8) growing one card's dock sequence at a time.
##   ea      — (mu+lambda) = 12+24 evolutionary search over dock-sequence genes,
##             seeded from capacity-aware primitives + random genomes.
##
## THE BUDGET CURRENCY IS ONE SIMULATION RUN. All three record an anytime
## best-so-far curve at 100 / 400 / 1600 / 6400 runs. Optimizers see TRAIN seeds
## only. Added for Reading B: `e1` (evals-to-first-WIN) and the winning-niche
## archive that yields `K` (count of structurally-distinct winning route-sets).

const RG = preload("res://tools/v5/routegen5.gd")
const SimApi5 = preload("res://tools/v5/sim_api5.gd")
const NEG_INF := -1.0e18

var sim # tools/v5/sim_api5.gd instance
var level_index := 0
var level: Dictionary = {}
var all_docks: Array = []
var widths: Array = []
var n_cards := 1
var seeds: Array = [] # TRAIN seeds only
var step := 0.25
var rng := RandomNumberGenerator.new()

var cache := {}   # genome_key#nseeds -> score
var archive := [] # every distinct candidate: {"key","genome","routes","score"}
var e1 := -1      # sim.runs at the FIRST winning median-train evaluation (-1 = none)


func setup(sim_api, li: int, lv: Dictionary, train_seeds: Array, search_step: float,
		seed_v: int) -> void:
	sim = sim_api
	level_index = li
	level = lv
	all_docks = RG.docks()
	widths = RG.card_widths(lv)
	n_cards = widths.size()
	seeds = train_seeds
	step = search_step
	rng.seed = seed_v


# ---------------------------------------------------------------- evaluation

func evaluate(genome: Array, use_seeds: Array = []) -> float:
	var sd: Array = seeds if use_seeds.is_empty() else use_seeds
	var key := RG.genome_key(genome) + "#%d" % sd.size()
	if cache.has(key):
		return cache[key]
	var dec := RG.decode_genome(genome, widths)
	if dec.err != "":
		cache[key] = NEG_INF
		return NEG_INF
	var r: Dictionary = sim.score_seeds(level_index, dec.routes, sd, step)
	cache[key] = r.score
	if sd.size() == seeds.size():
		archive.append({"key": key, "genome": RG.clone(genome),
				"routes": dec.routes, "score": r.score})
		if e1 < 0 and r.score >= SimApi5.WIN_BONUS:
			e1 = sim.runs
	return r.score


# ---------------------------------------------------------------- ladder rungs

func run_random(budget: int, checkpoints: Array) -> Dictionary:
	var st := _new_state(checkpoints)
	var tried := 0
	var undecodable := 0
	var stall := 0
	while sim.runs - st.start < budget:
		tried += 1
		var before: int = sim.runs
		var g := RG.random_genome(rng, all_docks, widths)
		if g.is_empty():
			undecodable += 1
		else:
			_offer(st, g, evaluate(g))
		# The decodable genome space can be smaller than the budget on a tiny
		# level; bail when it is visibly exhausted (guards run_random's stagnation
		# bug the v4 tools hit).
		if sim.runs == before:
			stall += 1
			if stall >= 20000:
				break
		else:
			stall = 0
	var out := _finish(st)
	out["diag"] = {"proposed": tried, "undecodable": undecodable}
	return out


func run_greedy(budget: int, checkpoints: Array, beam_w := 8, n_seeds := 2,
		max_grow := 5) -> Dictionary:
	var st := _new_state(checkpoints)
	var gs: Array = seeds.slice(0, mini(n_seeds, seeds.size()))
	var rdocks := RG.room_docks()
	var pairs := RG.demand_pairs(level)
	var start: Array = []
	for c in n_cards:
		var p: Dictionary = pairs[mini(c, pairs.size() - 1)] if not pairs.is_empty() else {}
		if p.has("from") and rdocks.has(p.from) and rdocks.has(p.to):
			start.append({"stops": [rdocks[p.from][0], rdocks[p.to][0]], "closed": false})
		else:
			start.append(RG.random_gene(rng, all_docks))
	if RG.decode_genome(start, widths).err != "":
		start = RG.random_genome(rng, all_docks, widths)
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
				for d in all_docks:
					if (state[card].stops as Array).has(d):
						continue
					var c1 := RG.clone(state)
					(c1[card].stops as Array).append(d)
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


func run_ea(budget: int, checkpoints: Array, mu := 12, lam := 24) -> Dictionary:
	var st := _new_state(checkpoints)
	var diag := {
		"mu": mu, "lam": lam, "generations": 0, "children": 0,
		"undecodable": 0, "cached": 0, "seeded_primitive": 0, "seeded_random": 0,
		"ops": {
			"mutate": {"n": 0, "compared": 0, "changed": 0, "sum_abs": 0.0, "improved": 0},
			"crossover": {"n": 0, "compared": 0, "changed": 0, "sum_abs": 0.0, "improved": 0},
			"immigrate": {"n": 0, "compared": 0, "changed": 0, "sum_abs": 0.0, "improved": 0},
		},
		"gen_curve": [], "stopped": "budget",
	}
	var pop: Array = []
	for g in RG.primitive_genomes(level, widths, rng, mu):
		if pop.size() >= mu:
			break
		pop.append({"g": g, "s": 0.0})
		diag.seeded_primitive += 1
	while pop.size() < mu:
		var rg := RG.random_genome(rng, all_docks, widths)
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
				op = "immigrate"
				child = RG.random_genome(rng, all_docks, widths)
				if child.is_empty():
					op = "mutate"
					var pm: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
					parent_s = pm.s
					child = RG.mutate(rng, pm.g, all_docks)
			elif pop.size() >= 2 and rng.randf() < 0.3:
				op = "crossover"
				var pa: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
				var pb: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
				parent_s = maxf(pa.s, pb.s)
				child = RG.crossover(rng, pa.g, pb.g)
				if rng.randf() < 0.5:
					child = RG.mutate(rng, child, all_docks)
			else:
				var pm2: Dictionary = pop[rng.randi_range(0, pop.size() - 1)]
				parent_s = pm2.s
				child = RG.mutate(rng, pm2.g, all_docks)
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
		diag.gen_curve.append(_pop_snapshot(diag.generations, sim.runs - st.start, st.best, pop))
		stale = stale + 1 if sim.runs == before else 0
		if stale >= 50:
			diag.stopped = "converged (50 generations bought no new evaluation)"
			break
	if pop.is_empty():
		diag.stopped = "population died"
	var out := _finish(st)
	out["diag"] = diag
	return out


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
		var d := RG.decode_genome(m.g, widths)
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


# ---------------------------------------------------------------- Reading B

## Count of structurally-distinct WINNING route-sets in the archive (docs/
## v5-transition-spec.md §2.2b): a winning genome (median-train score >= WIN_BONUS)
## counts once per distinct win_signature (per-card served-room set + loop/overlap
## flags). K = 0 broken, few = tight puzzle, many = trivial/soft-border. Returns
## {"k", "signatures", "examples"}.
func winning_niches() -> Dictionary:
	var sigs := {}
	for e in archive:
		if e.score < SimApi5.WIN_BONUS:
			continue
		var sig := RG.win_signature(e.routes)
		if not sigs.has(sig):
			sigs[sig] = {"genome": e.genome, "routes": e.routes, "score": e.score}
	return {"k": sigs.size(), "signatures": sigs.keys(), "examples": sigs}


# ---------------------------------------------------------------- bookkeeping

func _new_state(checkpoints: Array) -> Dictionary:
	return {"start": sim.runs, "best": NEG_INF, "genome": [], "checkpoints": checkpoints,
			"next_cp": 0, "curve": []}


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
