extends SceneTree
## v5 depth-measurement entry point (docs/v5-transition-spec.md Phase 3).
##
##   & "<godot_console.exe>" --headless --path . --script tools/v5/run_depth5.gd -- --selftest
##   & "<godot_console.exe>" --headless --path . --script tools/v5/run_depth5.gd -- --scorecheck
##   & "<godot_console.exe>" --headless --path . --script tools/v5/run_depth5.gd -- --levels R-6 [--quick]
##   & "<godot_console.exe>" --headless --path . --script tools/v5/run_depth5.gd -- --report
##
## Per-level results land in tools/out/depth5_<ID>.json (Grid5's maze is static,
## so one process measures one level at a time). --report merges them into
## docs/depth-report5.md. --quick uses tiny budgets + 2 seeds for iteration.

const SimApi5 = preload("res://tools/v5/sim_api5.gd")
const Metrics5 = preload("res://tools/v5/metrics5.gd")
const RG = preload("res://tools/v5/routegen5.gd")

const OUT_DIR := "res://tools/out"
const REPORT_PATH := "res://docs/depth-report5.md"

var args: Array = []
var quick := false
var level_ids: Array = []
var queue: Array = []
var t_start := 0
var mode := "search"
var explicit_levels := false


func _init() -> void:
	args = Array(OS.get_cmdline_user_args())
	quick = args.has("--quick")
	if args.has("--report"):
		mode = "report"
	elif args.has("--selftest"):
		mode = "selftest"
	elif args.has("--scorecheck"):
		mode = "scorecheck"
	var i := args.find("--levels")
	if i >= 0 and i + 1 < args.size():
		for s in String(args[i + 1]).split(","):
			level_ids.append(s.strip_edges())
	explicit_levels = not level_ids.is_empty()
	if level_ids.is_empty():
		for lv in Levels5.LEVELS:
			level_ids.append(str(lv.id))
	queue = level_ids.duplicate()
	t_start = Time.get_ticks_msec()


static func index_of(id: String) -> int:
	for i in Levels5.LEVELS.size():
		if str(Levels5.LEVELS[i].id) == id:
			return i
	return -1


func _process(_delta: float) -> bool:
	match mode:
		"report":
			_write_report()
			quit(0)
			return true
		"selftest":
			quit(0 if _selftest() else 1)
			return true
		"scorecheck":
			quit(0 if _scorecheck() else 1)
			return true
	if queue.is_empty():
		print("\nALL LEVELS DONE in %.1f s" % ((Time.get_ticks_msec() - t_start) / 1000.0))
		if explicit_levels:
			print("(shard: run with --report to merge every tools/out/depth5_*.json)")
		else:
			_write_report()
		quit(0)
		return true
	_run_one(queue.pop_front())
	return false


# ---------------------------------------------------------------- search

func _run_one(id: String) -> void:
	var li := index_of(id)
	if li < 0:
		push_error("unknown level id " + id)
		return
	var cfg := Metrics5.default_cfg(quick)
	print("\n=== %s (%s mode) ===" % [id, "quick" if quick else "full"])
	var sim = SimApi5.new(self)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var cache := "%s/runcache5_%s%s.json" % [OUT_DIR, id, "_quick" if quick else ""]
	sim.open_cache(cache)
	var res: Dictionary = Metrics5.run_level(sim, li, cfg)
	sim.flush_cache(true)
	res["sim_cpu_s"] = sim.sim_usec / 1.0e6
	var f := FileAccess.open("%s/depth5_%s.json" % [OUT_DIR, id], FileAccess.WRITE)
	f.store_string(JSON.stringify(_to_json(res), "  "))
	f.close()
	print("    %s -> %s  |  %d runs (%d replayed), %.1f s wall" % [
			id, res.klass, sim.runs, sim.cache_hits, res.wall_s])
	print("    %s" % res.klass_reason)
	DirAccess.remove_absolute(cache)


# ---------------------------------------------------------------- selftest

func _selftest() -> bool:
	print("=== sim_api5 / routegen5 selftest ===")
	var ok := true
	var sim = SimApi5.new(self)
	# 1. Determinism: R-1 thesis run twice is bit-identical.
	var r1 := index_of("R-1")
	SimApi5.load_maze(Levels5.LEVELS[r1])
	var thesis1 := [{"cells": _c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6]]), "closed": false}]
	var a: Dictionary = sim.run(r1, thesis1, 7101, SimApi5.STEP_COARSE)
	var b: Dictionary = sim.run(r1, thesis1, 7101, SimApi5.STEP_COARSE)
	var det: bool = a.served == b.served and a.lost == b.lost \
			and is_equal_approx(a.avg_wait, b.avg_wait) and is_equal_approx(a.score, b.score)
	ok = _p("R-1 thesis is bit-reproducible on a fixed seed", det,
			"a{served %d score %.4f} b{served %d score %.4f}" % [a.served, a.score, b.served, b.score]) and ok
	print("    R-1 thesis: %s served %d lost %d score %.2f" % [a.result, a.served, a.lost, a.score])
	# 2. A/B/A no state leak across levels.
	var r6 := index_of("R-6")
	SimApi5.load_maze(Levels5.LEVELS[r6])
	var r6split := [{"cells": _c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5]]), "closed": false},
			{"cells": _c([[2,5],[2,6],[2,7],[2,8],[2,9],[2,10]]), "closed": false}]
	var s1: Dictionary = sim.run(r6, r6split, 7101, SimApi5.STEP_COARSE)
	SimApi5.load_maze(Levels5.LEVELS[r1])
	sim.run(r1, thesis1, 7101, SimApi5.STEP_COARSE)
	SimApi5.load_maze(Levels5.LEVELS[r6])
	var s2: Dictionary = sim.run(r6, r6split, 7101, SimApi5.STEP_COARSE)
	ok = _p("A/B/A: R-6 identical either side of an R-1 run (no maze leak)",
			s1.served == s2.served and is_equal_approx(s1.score, s2.score),
			"s1 %d/%.2f s2 %d/%.2f" % [s1.served, s1.score, s2.served, s2.score]) and ok
	# 3. The R-6 cooperative SPLIT is legal and WINS; the full-shaft double is invalid.
	print("    R-6 split: %s served %d lost %d score %.2f" % [s1.result, s1.served, s1.lost, s1.score])
	ok = _p("R-6 cooperative split WINS", s1.result == "win", s1.result) and ok
	var bad := [{"cells": _c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6],[2,7],[2,8],[2,9],[2,10]]), "closed": false},
			{"cells": _c([[2,0],[2,1],[2,2]]), "closed": false}]
	var rbad: Dictionary = sim.run(r6, bad, 7101, SimApi5.STEP_COARSE)
	ok = _p("R-6 full-shaft + overlapping second is rejected (overlap cap)",
			not rbad.valid, "valid=%s err=%s" % [str(rbad.valid), rbad.err]) and ok
	# 4. Decode round-trip + primitive count on every level; R-6 split gene decodes.
	print("--- decode round-trip ---")
	for i in Levels5.LEVELS.size():
		var lv: Dictionary = Levels5.LEVELS[i]
		SimApi5.load_maze(lv)
		var widths := RG.card_widths(lv)
		var dk := RG.docks()
		var prim := RG.primitive_genes(lv)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var found := false
		for _try in 12:
			if not RG.random_genome(rng, dk, widths).is_empty():
				found = true
				break
		print("  %-4s %d docks, %d rooms, %d cards, %d primitives, decodable random genome found: %s" % [
				lv.id, dk.size(), Grid5.room_count(), widths.size(), prim.size(), str(found)])
		ok = _p("%s: has docks and a decodable random genome" % lv.id,
				dk.size() >= 2 and found, "docks %d" % dk.size()) and ok
	# 5. Invalid geometry scores, does not crash.
	SimApi5.load_maze(Levels5.LEVELS[r1])
	var jump := [{"cells": _c([[2,0],[2,6]]), "closed": false}]
	var rj: Dictionary = sim.run(r1, jump, 7101, SimApi5.STEP_COARSE)
	ok = _p("non-adjacent route scored invalid, not crashed", not rj.valid, rj.err) and ok
	print("SELFTEST: %s" % ("ALL PASS" if ok else "FAILURES PRESENT"))
	return ok


# ---------------------------------------------------------------- score audit

func _scorecheck() -> bool:
	var n := 600
	var i := args.find("--n")
	if i >= 0 and i + 1 < args.size():
		n = int(args[i + 1])
	var ok := true
	print("=== v5 score validity audit: %d uniform random route-sets per level ===" % n)
	print("score: WIN -> %.0f + (%.0f - t_win);  else served - %.1f*lost - %.2f*avg_wait" % [
			SimApi5.WIN_BONUS, SimApi5.TIMEOUT, SimApi5.LOST_WEIGHT, SimApi5.WAIT_WEIGHT])
	var sim = SimApi5.new(self)
	var rng := RandomNumberGenerator.new()
	for id in level_ids:
		var li := index_of(id)
		if li < 0:
			continue
		var lv: Dictionary = Levels5.LEVELS[li]
		SimApi5.load_maze(lv)
		var widths := RG.card_widths(lv)
		var dk := RG.docks()
		rng.seed = 4242 + li
		var wins: Array = []
		var losses: Array = []
		var results := {"win": 0, "lose": 0, "timeout": 0}
		var decodable := 0
		for _k in n:
			var g := RG.random_genome(rng, dk, widths)
			if g.is_empty():
				continue
			var dec := RG.decode_genome(g, widths)
			if dec.err != "":
				continue
			decodable += 1
			var r: Dictionary = sim.run(li, dec.routes, SimApi5.SEEDS_TRAIN[0], SimApi5.STEP_COARSE)
			results[r.result] += 1
			if r.result == "win":
				wins.append(r.score)
			else:
				losses.append(r.score)
		var rwr := 100.0 * float(results.win) / maxf(1.0, float(decodable))
		print("\n--- %s %s: %d decodable of %d -> win %d / lose %d / timeout %d   (rwr %.2f%%)" % [
				id, lv.name, decodable, n, results.win, results.lose, results.timeout, rwr])
		if not wins.is_empty():
			print("    win scores  : min %.1f med %.1f max %.1f  (%d wins)" % [
					_amin(wins), SimApi5.median(wins), _amax(wins), wins.size()])
		if not losses.is_empty():
			print("    lose scores : min %.2f med %.2f max %.2f  (%d losers, %d distinct)" % [
					_amin(losses), SimApi5.median(losses), _amax(losses), losses.size(), _n_distinct(losses)])
		if not wins.is_empty() and not losses.is_empty():
			var gap: float = _amin(wins) - _amax(losses)
			ok = _p("%s: every win outranks every loss" % id, gap > 0.0,
					"worst win %.1f vs best loss %.2f" % [_amin(wins), _amax(losses)]) and ok
	print("\nSCORECHECK: %s" % ("ALL PASS" if ok else "FAILURES PRESENT"))
	return ok


# ---------------------------------------------------------------- outputs

func _write_report() -> void:
	var results: Array = []
	for id in level_ids:
		var path := "%s/depth5_%s.json" % [OUT_DIR, id]
		if not FileAccess.file_exists(path):
			print("  (no result yet for %s)" % id)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d != null:
			results.append(d)
	if results.is_empty():
		print("no results to report")
		return
	var L: Array = []
	L.append("# v5 depth report — GENERATED by tools/v5/run_depth5.gd")
	L.append("")
	L.append("Do not hand-edit: re-run the depth tool instead. Generated %s%s." % [
			Time.get_datetime_string_from_system(),
			"  **--quick mode: tiny budgets + 2 seeds, indicative only**" if bool(results[0].get("quick", false)) else ""])
	L.append("")
	L.append("## How to read this")
	L.append("")
	L.append("- ONE search pass per level yields TWO readings (docs/v5-transition-spec.md §2.2): Reading A (soft-border) = random-win-rate + `skill_gap` + the ladder; Reading B (puzzle) = solvability + `K` + `e1`. The **auto-classifier** picks the headline.")
	L.append("- **spec-primary** is the spec §2.3 rule applied verbatim: `w_rand >= %d` (>= %d decodable random wins out of >=%d samples, ~0.8%%) -> soft-border; `w_rand < %d` with a solver win on >=7/8 seeds -> puzzle; else BROKEN." % [
			Metrics5.TAU_SOFT, Metrics5.TAU_SOFT, int(results[0].get("rand_probe", 600)), Metrics5.TAU_SOFT])
	L.append("- **class** is the corrected call. The spec-primary rule assumes a puzzle has random-win ~0 (`w_rand < 5`); on this tiny suite that assumption fails for R-6 (see its diagnosis), and `K` cannot rescue it (signature granularity gives R-6 a HIGHER K than the tutorials). The robust divider is the **win/loss balance of LEGAL random plans** against the spec's own forgiving bar (§4.1, rwr >= %.0f%%): random mostly WINS -> **soft-border** (forgiving landscape); random mostly LOSES but the solver reliably wins -> **puzzle** (constraint); random ~never wins and no solver win -> **BROKEN**." % Metrics5.FORGIVING_RWR)
	L.append("- **Solvability is per-seed** (spec §2.2a): for >= 7/8 TEST seeds, does the solver's set of discovered winning route-sets contain one that wins that seed? (Not \"does one genome win every seed\" — the right question when a legal win is seed-fragile.)")
	L.append("- One budget unit = one sim run of THE REAL v5 LEVEL (shipped quota / max_lost / win-lose live, %d game-second timeout). `WIN -> %.0f + (%.0f - t_win)`; else `served - %.1f*lost - %.2f*avg_wait`. Optimizers search TRAIN seeds at STEP %.2f; every reported number is a median over the disjoint TEST seeds at STEP %.2f." % [
			int(SimApi5.TIMEOUT), SimApi5.WIN_BONUS, SimApi5.TIMEOUT, SimApi5.LOST_WEIGHT, SimApi5.WAIT_WEIGHT, SimApi5.STEP_COARSE, SimApi5.STEP_FINE])
	L.append("- Solvability is always **relative to this solver at this budget** (Ropossum's caveat): \"winnable by our EA within %d evals on these seeds\", never \"winnable\"." % int(results[0].get("B_max", 6400)))
	L.append("")
	L.append("## Classification table")
	L.append("")
	L.append("`class` is the corrected call; `spec-primary` is the spec §2.3 w_rand rule applied verbatim. They differ only where the w_rand rule miscalls (see the R-6 diagnosis).")
	L.append("")
	L.append("| level | class | spec-primary | w_rand (rwr) | solvable seeds | K | e1 evals | skill_gap | ladder steps | thesis among niches |")
	L.append("|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var prim: String = str(r.get("klass_primary", r.klass))
		var flag := "" if prim == str(r.klass) else " ⚠"
		L.append("| **%s** %s | **%s** | %s%s | %d (%.2f%%) | %d/%d | %d | %s | %+.1f | %d | %s |" % [
				r.id, r.name, r.klass, prim, flag, int(r.w_rand), float(r.rwr),
				int(r.get("solvable_seeds", 0)), int(r.n_test), int(r.K),
				(str(int(r.e1_evals)) if int(r.e1_evals) >= 0 else "—"),
				float(r.skill_gap), int(r.ladder_steps),
				"yes" if r.thesis_among_niches else "no"])
	L.append("")
	L.append("## Validation of the classifier against hand-understood levels")
	L.append("")
	var r6 := _find(results, "R-6")
	var r1 := _find(results, "R-1")
	if not r1.is_empty():
		var got1: String = r1.klass
		L.append("- **R-1 \"One Lift\" expected SOFT-BORDER** — got **%s**. %s" % [got1,
				"CORRECT: a forgiving tutorial with a real random-win floor." if got1 == "soft-border"
				else "MISCALL — see diagnosis in the R-1 section."])
	if not r6.is_empty():
		var got6: String = r6.klass
		var prim6: String = str(r6.get("klass_primary", got6))
		L.append("- **R-6 \"Squeeze\" expected PUZZLE** — got **%s** (corrected). %s" % [got6,
				("CORRECT. Legal random plans mostly LOSE (rwr %.2f%%) and the solver is solvable %d/%d seeds via the cooperative split, and %s. NOTE: the spec-primary w_rand rule alone says **%s** (a MISCALL) because R-6's random-win is ~%.0f%%, NOT ~0 — the dock/shortest-path decoder auto-covers intermediate rooms and auto-splits at the transfer, and illegal overlaps are filtered as undecodable rather than counted as losses. This is the signal that the w_rand threshold (and K) needs the rwr-balance refinement before gating new puzzles." % [
						float(r6.rwr), int(r6.get("solvable_seeds", 0)), int(r6.n_test),
						"the intended split IS among the winning niches" if r6.thesis_among_niches else "the intended split is NOT among the recorded winning niches",
						prim6, float(r6.rwr)])
				if got6 == "puzzle"
				else "MISCALL — see diagnosis in the R-6 section."])
	L.append("")
	for r in results:
		L.append_array(_level_section(r))
	L.append("## Method caveats / what I don't fully trust")
	L.append("")
	L.append("- **Solver-relative solvability.** \"Solvable\" is per-seed: for >=7/8 TEST seeds, at least one route-set the search discovered as a winner (a niche example, the best genome, or the hand thesis) wins that seed within the budget. It is NOT \"one genome wins every seed\" — R-6's cooperative split is a legal win but seed-fragile (the best single genome generalises to only 5/8 test seeds), so requiring one genome to win 7/8 would falsely read R-6 as unsolvable. A false BROKEN (our decoder missed a real win) and a false GOOD PUZZLE (the solver found a path no human would) are the two states this most easily confuses (docs/v5-transition-spec.md §6). The numbers are a filter, never the verdict.")
	L.append("- **The thesis is used as a known-legal winner in the solvability check.** That makes solvability not strictly solver-only for the shipped levels; the per-seed count would be re-derived from solver-found winners alone before this gates NEW (un-thesised) levels.")
	L.append("- **K is archive-derived, not exhaustive.** K counts distinct `win_signature`s (per-card served-room set + loop/overlap flags) among winning genomes the EA happened to evaluate. It is a lower bound on true solution diversity and only as honest as the search's coverage; a proper ground-truth K needs exhaustive stop-sequence enumeration under the cap (Sturtevant EPCG), not yet built here.")
	L.append("- **e1 is a within-level relative difficulty**, evals-to-first-win for THIS solver — not human difficulty (Sturtevant 2020).")
	L.append("- The decoder is order-dependent under the overlap cap (card 0 claims capacity first); a reorder-cards mutation lets the search rearrange it, but a solution only reachable by a decode order the mutation never tried could read as harder than it is.")
	_store(REPORT_PATH, "\n".join(L) + "\n")
	print("wrote %s (%d levels)" % [REPORT_PATH, results.size()])


func _level_section(r: Dictionary) -> Array:
	var L: Array = []
	L.append("## %s — %s   [%s]" % [r.id, r.name, r.klass])
	L.append("")
	L.append("Thesis: *%s*" % r.get("thesis_text", ""))
	L.append("")
	L.append("**Classifier:** %s" % r.klass_reason)
	L.append("")
	L.append("%d rooms, %d cards, quota %d / max_lost %d. Search cost: %d runs, %.0f s wall." % [
			int(r.rooms), int(r.cards), int(r.quota), int(r.max_lost), int(r.sim_runs), float(r.wall_s)])
	L.append("")
	L.append("| metric | value |")
	L.append("|---|---|")
	L.append("| random-win count `w_rand` | %d of %d decodable (rwr %.2f%%) |" % [int(r.w_rand), int(r.decodable), float(r.rwr)])
	L.append("| solvability (per-seed: solver win exists) | %d/%d -> %s |" % [int(r.get("solvable_seeds", 0)), int(r.n_test), "solvable" if r.solvable else "NOT solvable"])
	L.append("| best single EA genome generalises (wins on TEST) | %d/%d |" % [int(r.solve_wins), int(r.n_test)])
	L.append("| `K` (structurally-distinct winning route-sets) | %d |" % int(r.K))
	L.append("| `e1` (evals to first win) | %s |" % (str(int(r.e1_evals)) if int(r.e1_evals) >= 0 else "no win found"))
	L.append("| `skill_gap` (ea@B - random best) | %+.1f |" % float(r.skill_gap))
	L.append("| ladder steps (budget doublings that beat noise %.2f) | %d |" % [float(r.noise_band), int(r.ladder_steps)])
	L.append("| best-EA vs thesis structural distance | %.2f |" % float(r.structural_distance))
	L.append("| intended solution among winning niches | %s |" % ("yes" if r.thesis_among_niches else "no"))
	L.append("| seed fragility (train - test) | %+.1f |" % float(r.seed_fragility))
	L.append("")
	if r.entries.has("thesis"):
		var te: Dictionary = r.entries.thesis
		L.append("Thesis route-set on TEST seeds: score %.2f, wins %d/%d, served ~%.0f, lost ~%.1f." % [
				float(te.score), int(te.get("wins", 0)), int(te.get("n_seeds", 0)),
				float(te.served), float(te.lost)])
		L.append("")
	L.append("Ladder (median TEST score vs budget): %s -> **%d step(s)**." % [_ladder_str(r), int(r.ladder_steps)])
	L.append("")
	L.append("Best route-set found (served rooms per card):")
	L.append("")
	L.append("```")
	for i in r.best_routes.size():
		var rt: Dictionary = r.best_routes[i]
		L.append("card %d %s %2d cells, serves %s" % [
				i, "LOOP" if rt.get("closed", false) else "line", (rt.cells as Array).size(),
				str(r.best_served_rooms[i]) if i < r.best_served_rooms.size() else "?"])
	L.append("```")
	L.append("")
	L.append("**Verdict.** " + _verdict(r))
	L.append("")
	return L


func _verdict(r: Dictionary) -> String:
	var k: String = r.klass
	if k == "soft-border":
		var top: Dictionary = r.entries["ea@%d" % _last_budget(r)]
		var thesis_note := ""
		if r.entries.has("thesis"):
			var beat: float = float(top.score) - float(r.entries.thesis.score)
			thesis_note = " The EA %s the hand thesis (%+.1f)." % [
					"beats" if beat > 1.0 else ("matches" if absf(beat) <= 1.0 else "trails"), beat]
		return "SOFT-BORDER: %d of %d decodable random plans win (rwr %.2f%%), so the level has a measurable floor and quality varies smoothly; skill_gap %+.1f over %d ladder step(s).%s" % [
				int(r.w_rand), int(r.decodable), float(r.rwr), float(r.skill_gap), int(r.ladder_steps), thesis_note]
	if k == "puzzle":
		return "PUZZLE: legal random plans mostly LOSE (rwr %.2f%%, %d/%d) because the overlap cap forces a specific cooperative structure, but the solver finds a legal win on %d/%d seeds (first win at %s evals). K=%d archive winning-signature(s); the best single genome generalises to %d/%d test seeds (a fragile win). %s." % [
				float(r.rwr), int(r.w_rand), int(r.decodable), int(r.get("solvable_seeds", 0)), int(r.n_test),
				(str(int(r.e1_evals)) if int(r.e1_evals) >= 0 else "n/a"), int(r.K),
				int(r.solve_wins), int(r.n_test),
				"The intended cooperative split IS among the winning niches" if r.thesis_among_niches else "The intended split was NOT recorded among niches"]
	return "BROKEN/UNVERIFIED: random-win ~0 (%d/%d) AND the solver found no legal win on >=7/8 seeds within %d evals. Either impossible or beyond this decoder — do not ship without a hand solve." % [
			int(r.w_rand), int(r.decodable), int(r.B_max)]


# ---------------------------------------------------------------- helpers

func _last_budget(r: Dictionary) -> int:
	var b := 0
	for e in r.ladder:
		b = maxi(b, int(e.budget))
	return b


func _ladder_str(r: Dictionary) -> String:
	var parts: Array = []
	for e in r.ladder:
		parts.append("%d:%.0f%s" % [int(e.budget), float(e.score), "*" if e.step else ""])
	return "  ".join(parts)


func _find(results: Array, id: String) -> Dictionary:
	for r in results:
		if str(r.id) == id:
			return r
	return {}


func _c(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append(Vector2i(p[0], p[1]))
	return out


func _amin(a: Array) -> float:
	var m: float = a[0]
	for x in a:
		m = minf(m, float(x))
	return m


func _amax(a: Array) -> float:
	var m: float = a[0]
	for x in a:
		m = maxf(m, float(x))
	return m


func _n_distinct(a: Array) -> int:
	var d := {}
	for x in a:
		d["%.4f" % float(x)] = true
	return d.size()


func _p(name: String, ok: bool, detail: String) -> bool:
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", name, "" if ok else "  (" + detail + ")"])
	return ok


## JSON-safe: Vector2i cells -> [x,y] arrays.
func _to_json(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[str(k)] = _to_json(v[k])
		return out
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_to_json(e))
		return out
	if v is Vector2i:
		return [v.x, v.y]
	return v


func _store(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
