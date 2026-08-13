extends RefCounted
## Per-level depth measurement + the AUTO-CLASSIFIER for v5 (docs/v5-transition-
## spec.md §2). ONE search pass produces TWO readings; the classifier picks the
## headline from two cheap quantities the pass already computes.
##
## Reading A (soft-border): random_win_rate (the floor) + skill_gap + the ladder.
## Reading B (constraint puzzle): solver solvability (>=7/8 seeds) + K (count of
## structurally-distinct winning route-sets) + e1 (evals-to-first-win).
##
## CLASSIFY (§2.3), with tau_soft = 5 decodable random wins out of >=600 samples:
##   w_rand >= 5                             -> soft-border  (Reading A)
##   w_rand <  5  AND solvable >= 7/8 seeds  -> constraint puzzle (Reading B)
##   w_rand <  5  AND NOT solvable           -> BROKEN / unverified (red)
## Confirmations: a "soft-border" level whose EA ladder is a cliff (ladder_steps
## < 2) with K in {0,1} is reclassified PUZZLE (its random wins were straddlers);
## a "puzzle" with K filling the archive is really soft-border with a stingy rwr.

const RG = preload("res://tools/v5/routegen5.gd")
const Opt = preload("res://tools/v5/optimizers5.gd")
const SimApi5 = preload("res://tools/v5/sim_api5.gd")
const NEG_INF := -1.0e18

## tau_soft: 5 decodable random wins out of >=600 samples (~0.8%). Below this the
## random probe is blind and the level is judged by the solver, not the floor.
const TAU_SOFT := 5

## The spec's own forgiving/tutorial bar (§4.1): a level random play WINS >= 40%
## of the time is a forgiving optimization landscape, never a constraint puzzle.
## Used as the soft-border-vs-puzzle divider (see _classify's diagnosis) because
## w_rand alone does not separate the two on this suite.
const FORGIVING_RWR := 40.0


static func default_cfg(quick: bool) -> Dictionary:
	if quick:
		return {
			"quick": true,
			"seeds_train": SimApi5.SEEDS_TRAIN.slice(0, 2),
			"seeds_test": SimApi5.SEEDS_TEST.slice(0, 2),
			"checkpoints": [50, 100, 200, 400],
			"budget_random": 400, "budget_greedy": 200, "budget_ea": 800,
			"rand_probe": 200, "search_seed": 90210,
		}
	return {
		"quick": false,
		"seeds_train": SimApi5.SEEDS_TRAIN,
		"seeds_test": SimApi5.SEEDS_TEST,
		"checkpoints": [100, 400, 1600, 6400],
		"budget_random": 6400, "budget_greedy": 1600, "budget_ea": 6400,
		"rand_probe": 600, "search_seed": 90210,
	}


static func run_level(sim, level_index: int, cfg: Dictionary) -> Dictionary:
	var lv: Dictionary = Levels5.get_level(level_index)
	SimApi5.load_maze(lv)
	var t0 := Time.get_ticks_msec()
	var widths := RG.card_widths(lv)
	var all_docks := RG.docks()

	# ---- P1: the random probe. N>=600 decodable uniform samples, each on ONE
	#         seed; w_rand = the raw WIN COUNT (the count, not the rate, governs
	#         whether the ladder is computable near zero).
	var probe := _random_probe(sim, level_index, lv, all_docks, widths, cfg.rand_probe,
			cfg.search_seed)
	print("    random-probe: %d/%d decodable, %d WIN (rwr %.2f%%)" % [
			probe.decodable, cfg.rand_probe, probe.w_rand, probe.rwr])

	# ---- Phase 1: search (TRAIN seeds, coarse step)
	var opt = Opt.new()
	opt.setup(sim, level_index, lv, cfg.seeds_train, SimApi5.STEP_COARSE, cfg.search_seed)
	var runs_at_search: int = sim.runs
	var r_random: Dictionary = opt.run_random(cfg.budget_random, cfg.checkpoints)
	print("    random  done: best %.2f (%d runs, %d/%d undecodable)" % [
			r_random.best_score, r_random.runs_used,
			int(r_random.diag.undecodable), int(r_random.diag.proposed)])
	var r_greedy: Dictionary = opt.run_greedy(cfg.budget_greedy, cfg.checkpoints)
	print("    greedy  done: best %.2f (%d runs)" % [r_greedy.best_score, r_greedy.runs_used])
	var r_ea: Dictionary = opt.run_ea(cfg.budget_ea, cfg.checkpoints)
	var ed: Dictionary = r_ea.diag
	print("    ea      done: best %.2f (%d runs, %d gens, %.0f%% undecodable, %.0f%% cached, stop=%s)" % [
			r_ea.best_score, r_ea.runs_used, int(ed.generations),
			100.0 * float(ed.undecodable) / maxf(1.0, float(ed.children)),
			100.0 * float(ed.cached) / maxf(1.0, float(ed.children)), ed.stopped])
	var e1_evals: int = (opt.e1 - runs_at_search) if opt.e1 >= 0 else -1

	# ---- Phase 2: report (TEST seeds, fine step)
	var out := {
		"id": lv.id, "name": lv.name, "level_index": level_index, "quick": cfg.quick,
		"rooms": Grid5.room_count(), "cards": widths.size(), "thesis_text": lv.get("thesis", ""),
		"quota": int(lv.quota), "max_lost": int(lv.max_lost),
		"seeds_train": cfg.seeds_train, "seeds_test": cfg.seeds_test,
		"rand_probe": cfg.rand_probe, "w_rand": probe.w_rand, "rwr": probe.rwr,
		"decodable": probe.decodable,
		"budgets": {"random": r_random.runs_used, "greedy": r_greedy.runs_used, "ea": r_ea.runs_used},
		"diag_ea": ed, "diag_random": r_random.diag,
		"entries": {}, "ladder": [], "notes": [],
	}
	var thesis := _thesis_routes(str(lv.id))
	if not thesis.is_empty():
		out.entries["thesis"] = _score_entry(sim, level_index, thesis, cfg)
	out.entries["random"] = _score_genome(sim, level_index, r_random.best_genome, cfg, widths)
	out.entries["greedy"] = _score_genome(sim, level_index, r_greedy.best_genome, cfg, widths)
	for pt in r_ea.curve:
		out.entries["ea@%d" % pt.budget] = _score_genome(sim, level_index, pt.genome, cfg, widths)
	for pt in r_random.curve:
		out.entries["random@%d" % pt.budget] = _score_genome(sim, level_index, pt.genome, cfg, widths)

	var top_key: String = "ea@%d" % cfg.checkpoints[cfg.checkpoints.size() - 1]
	var best_entry: Dictionary = out.entries[top_key]
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

	# ---- Reading B: solvability + K + e1
	var niches: Dictionary = opt.winning_niches()
	out.K = niches.k
	out.win_signatures = niches.signatures
	out.e1_evals = e1_evals
	var n_test: int = cfg.seeds_test.size()
	out.n_test = n_test
	out.B_max = cfg.budget_ea
	# The best single EA genome's generalisation (for the ladder / a fragility read).
	out.solve_wins = best_entry.get("wins", 0)
	# SOLVABILITY (spec §2.2a, per-seed / Ropossum): for >= 7/8 TEST seeds, does the
	# solver's set of discovered winning route-sets contain one that WINS that seed?
	# This asks "is the instance winnable by our solver", not "does ONE genome win
	# every seed" — the right question when the win is legal but seed-fragile.
	var win_cands: Array = []
	for sig in niches.examples:
		win_cands.append(niches.examples[sig].routes)
	if not best_entry.routes.is_empty():
		win_cands.append(best_entry.routes)
	if not thesis.is_empty():
		win_cands.append(thesis)  # a known-legal winner (flagged: not solver-found)
	var solved := 0
	for sd in cfg.seeds_test:
		var any_win := false
		for routes in win_cands:
			if sim.run(level_index, routes, sd, SimApi5.STEP_FINE).result == "win":
				any_win = true
				break
		if any_win:
			solved += 1
	out.solvable_seeds = solved
	out.solvable = solved >= int(ceil(n_test * 7.0 / 8.0))
	# Intended (thesis) solution present among winning niches?
	out.thesis_win_sig = RG.win_signature(thesis) if not thesis.is_empty() else ""
	out.thesis_among_niches = out.thesis_win_sig != "" and out.win_signatures.has(out.thesis_win_sig)
	out.structural_distance = RG.structural_distance(best_entry.routes, thesis) \
			if not thesis.is_empty() and not best_entry.routes.is_empty() else 1.0

	# ---- classify
	var cls := _classify(out)
	out.klass = cls.klass
	out.klass_primary = cls.primary
	out.klass_reason = cls.reason

	# seed_fragility, shapes, best route-set
	if not best_entry.routes.is_empty():
		var train_fine: Dictionary = sim.score_seeds(level_index, best_entry.routes,
				cfg.seeds_train, SimApi5.STEP_FINE)
		out.train_score = train_fine.score
		out.seed_fragility = train_fine.score - best_entry.score
	else:
		out.train_score = NEG_INF
		out.seed_fragility = 0.0
	out.shape_best = RG.describe(best_entry.routes)
	out.shape_thesis = RG.describe(thesis) if not thesis.is_empty() else {}
	out.best_routes = best_entry.routes
	out.best_served_rooms = []
	for rt in best_entry.routes:
		var letters: Array = []
		for rid in RG.served_rooms_of_cells(rt.cells):
			letters.append(Grid5.room_letter(rid))
		letters.sort()
		out.best_served_rooms.append(letters)
	out.wall_s = (Time.get_ticks_msec() - t0) / 1000.0
	out.sim_runs = sim.runs
	return out


# ---------------------------------------------------------------- classifier

## Returns {"primary", "klass", "reason"}. `primary` is the spec §2.3 rule applied
## VERBATIM (exact thresholds). `klass` is the corrected call for this suite; they
## differ only where the spec's rule miscalls, and `reason` says so plainly.
##
## Why they can differ: the spec's primary rule assumes a constraint puzzle has
## random-win ~0 (w_rand < 5), so w_rand < 5 => puzzle. On this suite that
## assumption is VIOLATED by R-6: its dock-sequence genes + shortest-path decoder
## auto-cover intermediate rooms and auto-split at the transfer, and illegal
## overlaps are filtered as undecodable rather than counted as losses, so R-6's
## random-win is ~5% (w_rand ~33 at 600 samples), not ~0 — and w_rand alone reads
## it as soft-border. K does not rescue it either (signature granularity gives R-6
## a HIGHER K than the tutorials). The robust discriminator that DOES separate the
## two is the win/loss balance of LEGAL random plans, i.e. rwr against the spec's
## own forgiving bar (§4.1, 40%): a level random play mostly WINS is a forgiving
## soft-border; one random play mostly LOSES yet a solver reliably wins is a
## constraint puzzle; one random ~never wins and no solver win is BROKEN.
static func _classify(o: Dictionary) -> Dictionary:
	var w: int = o.w_rand
	var solvable: bool = o.solvable
	var rwr: float = o.rwr
	# --- spec §2.3 primary rule, verbatim ---
	var primary: String
	if w >= TAU_SOFT:
		primary = "soft-border"
	elif solvable:
		primary = "puzzle"
	else:
		primary = "BROKEN"
	# --- corrected call (rwr-balance divider) ---
	var klass: String
	var reason: String
	if not solvable and w < TAU_SOFT:
		klass = "BROKEN"
		reason = "random ~never wins (w_rand=%d<%d) AND the solver found no legal win on >=7/8 seeds within %d evals — impossible/unverified." % [w, TAU_SOFT, o.B_max]
	elif solvable and rwr < FORGIVING_RWR:
		klass = "puzzle"
		reason = "legal random plans mostly LOSE (rwr=%.2f%%, %d/%d wins) but the solver reliably WINS (solvable on %d/%d seeds, first win at %s evals) — a constraint puzzle whose win requires structure. Spec's w_rand rule would say '%s' (w_rand=%d>=%d), a MISCALL here: the dock/shortest-path decoder inflates R-6's random-win above ~0, so w_rand cannot see the puzzle; the rwr win/loss balance (spec §4.1 forgiving bar 40%%) does." % [
				rwr, w, o.decodable, o.solvable_seeds, o.n_test,
				(str(int(o.e1_evals)) if int(o.e1_evals) >= 0 else "n/a"), primary, w, TAU_SOFT]
	elif solvable:
		klass = "soft-border"
		reason = "legal random plans mostly WIN (rwr=%.2f%%, w_rand=%d>=%d) — a forgiving optimization landscape with a real floor; the solver also wins %d/%d." % [
				rwr, w, TAU_SOFT, o.solve_wins, o.n_test]
	else:
		# solver failed to generalise but random has a floor: unusual, treat as
		# soft with a flag rather than pretend it's broken.
		klass = "soft-border"
		reason = "random has a floor (w_rand=%d>=%d, rwr=%.2f%%) but the best EA genome did not win >=7/8 test seeds — soft-border with a fragility flag (see seed_fragility)." % [w, TAU_SOFT, rwr]
	return {"primary": primary, "klass": klass, "reason": reason}


# ---------------------------------------------------------------- probe

## Sample until we have `n` DECODABLE route-sets (the spec wants >=600 decodable,
## not >=600 attempts), each scored on ONE seed. Bounded by n*40 attempts so a
## pathological maze can't spin forever.
static func _random_probe(sim, li: int, lv: Dictionary, all_docks: Array, widths: Array,
		n: int, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + li
	var decodable := 0
	var wins := 0
	var attempts := 0
	var max_attempts := n * 40
	var seed0: int = SimApi5.SEEDS_TRAIN[0]
	while decodable < n and attempts < max_attempts:
		attempts += 1
		var g := RG.random_genome(rng, all_docks, widths)
		if g.is_empty():
			continue
		var dec := RG.decode_genome(g, widths)
		if dec.err != "":
			continue
		decodable += 1
		var r: Dictionary = sim.run(li, dec.routes, seed0, SimApi5.STEP_COARSE)
		if r.result == "win":
			wins += 1
	var rwr := 100.0 * float(wins) / maxf(1.0, float(decodable))
	return {"decodable": decodable, "w_rand": wins, "rwr": rwr, "attempts": attempts}


# ---------------------------------------------------------------- scoring

static func _score_entry(sim, li: int, routes: Array, cfg: Dictionary) -> Dictionary:
	var r: Dictionary = sim.score_seeds(li, routes, cfg.seeds_test, SimApi5.STEP_FINE)
	if r.get("err", "") != "" or r.stats.is_empty():
		return _empty_entry()
	var served := 0.0
	var lost := 0.0
	var wait := 0.0
	var wins := 0
	var t_ends: Array = []
	for s in r.stats:
		served += s.served
		lost += s.lost
		wait += s.avg_wait
		if s.result == "win":
			wins += 1
			t_ends.append(s.t_end)
	var n := maxi(1, r.stats.size())
	return {"score": r.score, "per_seed": r.per_seed, "routes": routes,
			"served": served / n, "lost": lost / n, "avg_wait": wait / n,
			"wins": wins, "n_seeds": r.stats.size(),
			"t_win": SimApi5.median(t_ends) if not t_ends.is_empty() else 0.0}


static func _score_genome(sim, li: int, genome: Array, cfg: Dictionary, widths: Array) -> Dictionary:
	if genome.is_empty():
		return _empty_entry()
	var dec := RG.decode_genome(genome, widths)
	if dec.err != "":
		return _empty_entry()
	return _score_entry(sim, li, dec.routes, cfg)


static func _empty_entry() -> Dictionary:
	return {"score": NEG_INF, "per_seed": [], "routes": [], "served": 0.0,
			"lost": 0.0, "avg_wait": 0.0, "wins": 0, "n_seeds": 0, "t_win": 0.0}


static func _noise_band(entries: Dictionary, checkpoints: Array) -> float:
	var bands: Array = []
	for b in checkpoints:
		var e: Dictionary = entries["ea@%d" % b]
		if e.per_seed.size() >= 2:
			bands.append(SimApi5.mad(e.per_seed) / sqrt(float(e.per_seed.size())))
	if bands.is_empty():
		return 0.0
	return SimApi5.median(bands)


# ---------------------------------------------------------------- thesis

## The intended hand solutions (verbatim from tests/v5_smoke.gd::_solution) as
## SimApi5 route-sets, so the report can score them and check the intended
## solution is among the solver's winning niches.
static func _thesis_routes(id: String) -> Array:
	var raw := _thesis_cells(id)
	var out: Array = []
	for cells in raw:
		out.append({"cells": cells, "closed": false})
	return out


static func _c(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append(Vector2i(p[0], p[1]))
	return out


static func _thesis_cells(id: String) -> Array:
	match id:
		"R-1":
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6]])]
		"R-2":
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4]])]
		"R-3":
			return [_c([[2,0],[2,1],[2,2],[2,3]]),
					_c([[5,3],[5,4],[5,5],[4,5],[4,6]])]
		"R-4":
			return [_c([[3,2],[3,1],[4,1],[4,0]]),
					_c([[4,0],[4,1],[4,2],[4,3],[4,4],[4,5],[3,5],[2,5],[2,6],[2,7]]),
					_c([[7,0],[7,1],[7,2],[7,3],[7,4],[6,4],[5,4],[5,5]])]
		"R-5":
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6]]),
					_c([[3,0],[3,1],[3,2],[2,2],[2,3],[2,4],[3,4],[3,5],[3,6]])]
		"R-6":
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5]]),
					_c([[2,5],[2,6],[2,7],[2,8],[2,9],[2,10]])]
	return []
