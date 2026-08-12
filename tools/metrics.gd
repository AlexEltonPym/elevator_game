extends RefCounted
## Per-level depth measurement (docs/depth-tools-spec.md §5).
##
## Phase 1 SEARCHES on the TRAIN seeds at the coarse step. Phase 2 re-scores
## every finalist on the disjoint TEST seeds at STEP 0.1 — the step every
## balance number in the game is tuned at. Every number this file reports is a
## median over TEST seeds. The gap between the two is reported as
## `seed_fragility`, because a search that memorised the arrival schedule
## produces numbers no human could reproduce (docs/autodesign-research.md §6.2).

const RG = preload("res://tools/routegen.gd")
const Opt = preload("res://tools/optimizers.gd")
const SimApi = preload("res://tools/sim_api.gd")
const NEG_INF := -1.0e18


static func default_cfg(quick: bool) -> Dictionary:
	if quick:
		return {
			"quick": true,
			"seeds_train": SimApi.SEEDS_TRAIN.slice(0, 2),
			"seeds_test": SimApi.SEEDS_TEST.slice(0, 2),
			"checkpoints": [50, 100, 200, 400],
			"budget_random": 400, "budget_greedy": 200, "budget_ea": 400,
			"n_perturb": 3, "n_rank": 8, "search_seed": 90210,
		}
	return {
		"quick": false,
		"seeds_train": SimApi.SEEDS_TRAIN,
		"seeds_test": SimApi.SEEDS_TEST,
		"checkpoints": [100, 400, 1600, 6400],
		"budget_random": 6400, "budget_greedy": 1600, "budget_ea": 6400,
		"n_perturb": 8, "n_rank": 30, "search_seed": 90210,
	}


## Everything for one level. `sim` is a fresh tools/sim_api.gd instance.
static func run_level(sim, level_index: int, cfg: Dictionary) -> Dictionary:
	var lv: Dictionary = Levels3.get_level(level_index)
	SimApi.load_maze(lv)
	var t0 := Time.get_ticks_msec()
	var opt = Opt.new()
	opt.setup(sim, level_index, lv, cfg.seeds_train, SimApi.STEP_COARSE, cfg.search_seed)

	# ---- phase 1: search (TRAIN seeds, coarse step)
	var r_random: Dictionary = opt.run_random(cfg.budget_random, cfg.checkpoints)
	print("    random  done: best %.2f (%d runs, %d/%d proposals undecodable)" % [
			r_random.best_score, r_random.runs_used,
			int(r_random.diag.undecodable), int(r_random.diag.proposed)])
	var r_greedy: Dictionary = opt.run_greedy(cfg.budget_greedy, cfg.checkpoints)
	print("    greedy  done: best %.2f (%d runs)" % [r_greedy.best_score, r_greedy.runs_used])
	var r_ea: Dictionary = opt.run_ea(cfg.budget_ea, cfg.checkpoints)
	var ed: Dictionary = r_ea.diag
	print("    ea      done: best %.2f (%d runs, %d generations, %d children, %.1f%% undecodable, %.1f%% cached, stop=%s)" % [
			r_ea.best_score, r_ea.runs_used, int(ed.generations), int(ed.children),
			100.0 * float(ed.undecodable) / maxf(1.0, float(ed.children)),
			100.0 * float(ed.cached) / maxf(1.0, float(ed.children)), ed.stopped])
	for opname in ed.ops:
		var o: Dictionary = ed.ops[opname]
		if int(o.compared) == 0:
			print("      op %-10s n=%-5d (no parent to compare against)" % [opname, int(o.n)])
			continue
		var den: float = float(o.compared)
		print("      op %-10s n=%-5d compared %-5d changed %.0f%%  improved %.0f%%  mean |dscore| %.2f" % [
				opname, int(o.n), int(o.compared), 100.0 * float(o.changed) / den,
				100.0 * float(o.improved) / den, float(o.sum_abs) / den])

	# ---- phase 2: report (TEST seeds, fine step)
	var out := {
		"id": lv.id, "name": lv.name, "level_index": level_index,
		"quick": cfg.quick, "rooms": Grid3.rooms().size(),
		"cards": lv.cards.size(), "thesis_text": lv.thesis,
		"seeds_train": cfg.seeds_train, "seeds_test": cfg.seeds_test,
		"budgets": {"random": r_random.runs_used, "greedy": r_greedy.runs_used,
				"ea": r_ea.runs_used},
		"diag_random": r_random.diag, "diag_ea": r_ea.diag,
		"entries": {}, "ladder": [], "notes": [],
	}
	var scen_thesis := _scenario_routes(lv.id, "thesis")
	var scen_naive := _scenario_routes(lv.id, "naive")
	if not scen_thesis.is_empty():
		out.entries["thesis"] = _score_entry(sim, level_index, scen_thesis, cfg)
	if not scen_naive.is_empty():
		out.entries["naive"] = _score_entry(sim, level_index, scen_naive, cfg)
	out.entries["random"] = _score_genome(sim, level_index, r_random.best_genome, cfg)
	out.entries["greedy"] = _score_genome(sim, level_index, r_greedy.best_genome, cfg)
	for pt in r_ea.curve:
		out.entries["ea@%d" % pt.budget] = _score_genome(sim, level_index, pt.genome, cfg)
	for pt in r_random.curve:
		out.entries["random@%d" % pt.budget] = _score_genome(sim, level_index, pt.genome, cfg)

	var top_key: String = "ea@%d" % cfg.checkpoints[cfg.checkpoints.size() - 1]
	var best_entry: Dictionary = out.entries[top_key]
	# The ladder walks the EA's anytime curve; a step is a budget doubling
	# whose median TEST score beats the previous point by more than the seed
	# noise band (Lantz et al.'s step unit X, made concrete).
	var noise := _noise_band(out.entries, cfg.checkpoints)
	var prev := NEG_INF
	var steps := 0
	for b in cfg.checkpoints:
		var e: Dictionary = out.entries["ea@%d" % b]
		var improved: bool = prev > NEG_INF and e.score - prev > noise
		if improved:
			steps += 1
		out.ladder.append({"budget": b, "score": e.score, "step": improved,
				"wins": e.get("wins", 0), "n_seeds": e.get("n_seeds", 0)})
		prev = e.score
	out.noise_band = noise
	out.ladder_steps = steps
	out.skill_gap = best_entry.score - out.entries["random"].score
	out.beat_thesis = (best_entry.score - out.entries.thesis.score) \
			if out.entries.has("thesis") else 0.0
	# seed_fragility: same route-set, same step, TRAIN vs TEST seeds.
	var train_fine: Dictionary = sim.score_seeds(level_index, best_entry.routes,
			cfg.seeds_train, SimApi.STEP_FINE)
	out.train_score = train_fine.score
	out.seed_fragility = train_fine.score - best_entry.score
	out.structural_distance = RG.structural_distance(best_entry.routes, scen_thesis) \
			if not scen_thesis.is_empty() else 1.0
	out.shape_best = RG.describe(best_entry.routes)
	out.shape_thesis = RG.describe(scen_thesis) if not scen_thesis.is_empty() else {}
	out.plan_fragility = _plan_fragility(sim, level_index, r_ea.best_genome, cfg)
	out.rank_correlation = _rank_correlation(sim, opt, level_index, cfg)
	out.best_routes = best_entry.routes
	out.best_stops = []
	for rt in best_entry.routes:
		out.best_stops.append(RG.stops_of_cells(rt.cells))
	out.best_genome_stops = _genome_stops(r_ea.best_genome)
	out.wall_s = (Time.get_ticks_msec() - t0) / 1000.0
	out.sim_runs = sim.runs
	return out


# ---------------------------------------------------------------- scoring

static func _score_entry(sim, li: int, routes: Array, cfg: Dictionary) -> Dictionary:
	var r: Dictionary = sim.score_seeds(li, routes, cfg.seeds_test, SimApi.STEP_FINE)
	var served := 0.0
	var lost := 0.0
	var wait := 0.0
	for s in r.stats:
		served += s.served
		lost += s.lost
		wait += s.avg_wait
	var wins := 0
	var t_ends: Array = []
	for s2 in r.stats:
		if s2.result == "win":
			wins += 1
		t_ends.append(s2.t_end)
	var n := maxi(1, r.stats.size())
	return {"score": r.score, "per_seed": r.per_seed, "routes": routes,
			"served": served / n, "lost": lost / n, "avg_wait": wait / n,
			"wins": wins, "n_seeds": r.stats.size(),
			"t_win": SimApi.median(t_ends)}


static func _score_genome(sim, li: int, genome: Array, cfg: Dictionary) -> Dictionary:
	if genome.is_empty():
		return _empty_entry()
	var dec := RG.decode_genome(genome)
	if dec.err != "":
		return _empty_entry()
	return _score_entry(sim, li, dec.routes, cfg)


static func _empty_entry() -> Dictionary:
	return {"score": NEG_INF, "per_seed": [], "routes": [], "served": 0.0,
			"lost": 0.0, "avg_wait": 0.0, "wins": 0, "n_seeds": 0, "t_win": 0.0}


static func _scenario_routes(level_id: String, strategy: String) -> Array:
	var rs: Array = Scenarios3.route_set(level_id, strategy)
	var out: Array = []
	for e in rs:
		out.append({"cells": Scenarios3.cells_of(e), "closed": Scenarios3.closed_of(e)})
	return out


## Seed noise band: the rough standard error of the median TEST score,
## MAD / sqrt(n), taken across the ladder's elites. An improvement smaller
## than this is not distinguishable from which seeds we happened to draw.
static func _noise_band(entries: Dictionary, checkpoints: Array) -> float:
	var bands: Array = []
	for b in checkpoints:
		var e: Dictionary = entries["ea@%d" % b]
		if e.per_seed.size() >= 2:
			bands.append(SimApi.mad(e.per_seed) / sqrt(float(e.per_seed.size())))
	if bands.is_empty():
		return 0.0
	return SimApi.median(bands)


## Median score DROP over single-stop perturbations of the elite: does the
## plan survive a small mistake, or is it fiddly precision work?
static func _plan_fragility(sim, li: int, genome: Array, cfg: Dictionary) -> float:
	if genome.is_empty():
		return 0.0
	var base: Dictionary = _score_genome(sim, li, genome, cfg)
	if base.score <= NEG_INF:
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.search_seed + 7
	var rooms: Array = Grid3.rooms()
	var drops: Array = []
	var tries := 0
	while drops.size() < cfg.n_perturb and tries < cfg.n_perturb * 6:
		tries += 1
		var g := RG.clone(genome)
		var c := rng.randi_range(0, g.size() - 1)
		var stops: Array = g[c].stops
		var free: Array = []
		for r in rooms:
			if not stops.has(r):
				free.append(r)
		if free.is_empty():
			continue
		stops[rng.randi_range(0, stops.size() - 1)] = free[rng.randi_range(0, free.size() - 1)]
		var s: Dictionary = _score_genome(sim, li, g, cfg)
		if s.score <= NEG_INF:
			continue # undecodable perturbation: not a plan-quality signal
		drops.append(base.score - s.score)
	if drops.is_empty():
		return 0.0
	return SimApi.median(drops)


## Spearman rank correlation between the COARSE search score (STEP 0.25) and
## the FINE score (STEP 0.1), both on TRAIN seeds. If it is poor, searching at
## 0.25 is dishonest and the level must be re-searched at 0.1.
##
## Reported TWICE on purpose. `rho` is over the TOP candidates, as the spec
## asks — but the top of a search is a near-tie plateau, so a low rho there can
## just mean "these are all the same score". `rho_spread` re-measures over
## candidates sampled evenly across the WHOLE score range, which is the honest
## test of whether the coarse step preserves ordering at all.
static func _rank_correlation(sim, opt, li: int, cfg: Dictionary) -> Dictionary:
	var top: Array = opt.top_archive(cfg.n_rank)
	var spread: Array = opt.spread_archive(cfg.n_rank)
	var r_top := _rho_of(sim, li, top, cfg)
	var r_spread := _rho_of(sim, li, spread, cfg)
	return {"n": r_top.n, "rho": r_top.rho, "n_spread": r_spread.n,
			"rho_spread": r_spread.rho, "range_spread": r_spread.range}


static func _rho_of(sim, li: int, cands: Array, cfg: Dictionary) -> Dictionary:
	var coarse: Array = []
	var fine: Array = []
	for e in cands:
		var f: Dictionary = sim.score_seeds(li, e.routes, cfg.seeds_train, SimApi.STEP_FINE)
		coarse.append(e.score)
		fine.append(f.score)
	var rng_span := 0.0
	if coarse.size() >= 2:
		var s := coarse.duplicate()
		s.sort()
		rng_span = s[s.size() - 1] - s[0]
	return {"n": coarse.size(), "rho": spearman(coarse, fine), "range": rng_span}


static func spearman(a: Array, b: Array) -> float:
	if a.size() < 3:
		return 0.0
	var ra := _ranks(a)
	var rb := _ranks(b)
	var n := float(a.size())
	var ma := 0.0
	var mb := 0.0
	for i in ra.size():
		ma += ra[i]
		mb += rb[i]
	ma /= n
	mb /= n
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in ra.size():
		num += (ra[i] - ma) * (rb[i] - mb)
		da += pow(ra[i] - ma, 2.0)
		db += pow(rb[i] - mb, 2.0)
	if da <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(da * db)


## Average ranks (ties share the mean rank).
static func _ranks(v: Array) -> Array:
	var idx: Array = []
	for i in v.size():
		idx.append(i)
	idx.sort_custom(func(x, y): return v[x] < v[y])
	var out: Array = []
	out.resize(v.size())
	var i := 0
	while i < idx.size():
		var j := i
		while j + 1 < idx.size() and is_equal_approx(float(v[idx[j + 1]]), float(v[idx[i]])):
			j += 1
		var r := (i + j) / 2.0 + 1.0
		for k in range(i, j + 1):
			out[idx[k]] = r
		i = j + 1
	return out


static func _genome_stops(genome: Array) -> Array:
	var out: Array = []
	for g in genome:
		var s: Array = []
		for c in g.stops:
			s.append([c.x, c.y])
		out.append({"stops": s, "closed": g.closed})
	return out
