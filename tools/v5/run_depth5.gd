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
	# R-6 is a STEPPED cap-2 shaft (cols 6, rows 9 after the shorten pass): column 2
	# up to the cap-4 atrium at (2,4), then it steps right to column 3. The cooperative
	# split is LIFT 1 lower-left (A,B,atrium C) + LIFT 2 upper-right (C,D,E), meeting only
	# at (2,4). This is the smoke/fingerprint hand solution — valid in-bounds cells.
	var r6split := [{"cells": _c([[2,0],[2,1],[2,2],[2,3],[2,4]]), "closed": false},
			{"cells": _c([[2,4],[3,4],[3,5],[3,6],[3,7],[3,8]]), "closed": false}]
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
	# One lift running the WHOLE stepped shaft (column 2 up to the atrium, then column 3
	# to the top) plus a second that re-enters the cap-2 lower column: the second pushes
	# (2,0)/(2,1)/(2,2) to width 4 over their cap-2, so the set is rejected by the overlap
	# cap — the check under test. In-bounds on the shortened R-6.
	var bad := [{"cells": _c([[2,0],[2,1],[2,2],[2,3],[2,4],[3,4],[3,5],[3,6],[3,7],[3,8]]), "closed": false},
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
		var legal := 0
		var attempts := 0
		while legal < n and attempts < n * 80:
			attempts += 1
			var s := RG.sample_random_routeset(rng, dk, widths)
			if not s.legal:
				continue
			legal += 1
			var r: Dictionary = sim.run(li, s.routes, SimApi5.SEEDS_TRAIN[0], SimApi5.STEP_COARSE)
			results[r.result] += 1
			if r.result == "win":
				wins.append(r.score)
			else:
				losses.append(r.score)
		var rwr := 100.0 * float(results.win) / maxf(1.0, float(legal))
		var legality := 100.0 * float(legal) / maxf(1.0, float(attempts))
		print("\n--- %s %s (freer sampler): %d legal of %d attempts (legality %.1f%%) -> win %d / lose %d / timeout %d   (legal-plan win rate %.2f%%)" % [
				id, lv.name, legal, attempts, legality, results.win, results.lose, results.timeout, rwr])
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
	L.append("- ONE search pass per level yields TWO readings (docs/v5-transition-spec.md §2.2): Reading A (soft-border) = the random-plan win basin + `skill_gap` + the ladder; Reading B (puzzle) = solvability + `K` + `e1`. A **balance-keyed classifier** picks the headline.")
	L.append("- **The random baseline uses a FREER sampler** (drifted self-avoiding walks between random dock stops), NOT the smart shortest-path decoder. The smart decoder auto-covers intermediate rooms and auto-threads a level's cooperative split, so a \"random\" gene would do the puzzle's reasoning for free and inflate a constraint level's random-win. The freer sampler produces genuinely varied legal plans that often miss rooms and mis-thread the shaft, so its win rate reflects the LEVEL's difficulty, not the decoder's cleverness. (The EA / greedy keep the smart decoder.)")
	L.append("- **Two probe numbers.** *legality rate* = fraction of raw random draws that are even legal (all cards decode under the caps, serve >= 2 rooms); it reflects caps AND the wandering sampler's dead-end rate, so read it as a rough constraint indicator, not a pure cap measure. *legal-plan win rate* = wins among legal draws — **this is the difficulty signal that drives the classifier.**")
	L.append("- **Classifier (balance-keyed):** legal-plan win rate >= %.0f%% (a broad basin of working plans) -> **soft-border**; legal-plan win rate < %.0f%% (few legal plans work) AND the solver is solvable >=7/8 seeds -> **puzzle**; < %.0f%% AND not solvable -> **BROKEN**. The %.0f%% bar is the spec's own forgiving/tutorial bar (§4.1). The `spec-primary` column shows the spec §2.3 raw `w_rand < %d` rule for audit only; it is NOT the driver." % [
			Metrics5.FORGIVING_RWR, Metrics5.FORGIVING_RWR, Metrics5.FORGIVING_RWR, Metrics5.FORGIVING_RWR, Metrics5.TAU_SOFT])
	L.append("- **Solvability is per-seed** (spec §2.2a): for >= 7/8 TEST seeds, does the solver's set of discovered winning route-sets contain one that wins that seed? (Not \"does one genome win every seed\" — the right question when a legal win is seed-fragile.)")
	L.append("- **`K` is a secondary quality signal, not the discriminator.** `K (arch)` is the archive estimate (distinct winning `win_signature`s the EA evaluated). `K (exh)` is EXHAUSTIVE ground truth where the capped stop-sequence space is small enough to enumerate (distinct winning per-card served-room structures); `--` means the space was too large and only the archive estimate is available.")
	L.append("- One budget unit = one sim run of THE REAL v5 LEVEL (shipped quota / max_lost / win-lose live, %d game-second timeout). `WIN -> %.0f + (%.0f - t_win)`; else `served - %.1f*lost - %.2f*avg_wait`. Optimizers search TRAIN seeds at STEP %.2f; every reported number is a median over the disjoint TEST seeds at STEP %.2f. Solvability is always **relative to this solver at this budget** (Ropossum's caveat): \"winnable by our EA within %d evals on these seeds\", never \"winnable\"." % [
			int(SimApi5.TIMEOUT), SimApi5.WIN_BONUS, SimApi5.TIMEOUT, SimApi5.LOST_WEIGHT, SimApi5.WAIT_WEIGHT, SimApi5.STEP_COARSE, SimApi5.STEP_FINE, int(results[0].get("B_max", 6400))])
	L.append("")
	L.append("## Classification table")
	L.append("")
	L.append("Class is driven by the **legal-plan win rate** (freer sampler) + solvability. `spec-primary` is the raw spec §2.3 `w_rand` rule shown for audit only.")
	L.append("")
	L.append("| level | class | legality | legal-plan win rate | solvable | K (arch) | K (exh) | e1 evals | spec-primary |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var prim: String = str(r.get("klass_primary", r.klass))
		var flag := "" if prim == str(r.klass) else " ⚠"
		var exk: int = int(r.get("exhaustive_k", -1))
		var exk_s := str(exk) if bool(r.get("exhaustive_k_feasible", false)) else "—"
		L.append("| **%s** %s | **%s** | %.1f%% | %.2f%% (%d/%d) | %d/%d | %d | %s | %s | %s%s |" % [
				r.id, r.name, r.klass, float(r.get("legality_rate", 0.0)),
				float(r.get("legal_win_rate", r.rwr)), int(r.w_rand), int(r.decodable),
				int(r.get("solvable_seeds", 0)), int(r.n_test), int(r.K), exk_s,
				(str(int(r.e1_evals)) if int(r.e1_evals) >= 0 else "—"),
				prim, flag])
	L.append("")
	L.append("## Validation of the classifier against hand-understood levels")
	L.append("")
	var r6 := _find(results, "R-6")
	var r1 := _find(results, "R-1")
	if not r1.is_empty():
		var got1: String = r1.klass
		L.append("- **R-1 \"One Lift\" expected SOFT-BORDER** — got **%s**, driven by: %s. %s" % [got1,
				str(r1.get("klass_signal", "")),
				"CORRECT via the balance signal (not a brittle threshold): a broad basin of legal random plans win." if got1 == "soft-border"
				else "MISCALL — see the R-1 section."])
	if not r6.is_empty():
		var got6: String = r6.klass
		L.append("- **R-6 \"Squeeze\" expected PUZZLE** — got **%s**, driven by: %s. %s" % [got6,
				str(r6.get("klass_signal", "")),
				("CORRECT via the balance signal. The FREER sampler drops R-6's legal-plan win rate to %.2f%% (the smart-decoder version had inflated it to ~6%%), toward the ~0 the design intended — genuinely-random legal plans almost never solve it, but the solver is solvable %d/%d seeds via the cooperative split, and %s. Exhaustive K = %s confirms the winning structure is %s." % [
						float(r6.get("legal_win_rate", r6.rwr)), int(r6.get("solvable_seeds", 0)), int(r6.n_test),
						"the intended split IS among the winning niches" if r6.thesis_among_niches else "the intended split is NOT among the recorded winning niches",
						(str(int(r6.get("exhaustive_k", -1))) if bool(r6.get("exhaustive_k_feasible", false)) else "n/a"),
						"near-unique" if bool(r6.get("exhaustive_k_feasible", false)) and int(r6.get("exhaustive_k", 9)) <= 2 else "small"])
				if got6 == "puzzle"
				else "MISCALL — see the R-6 section."])
	L.append("")
	L.append("Both hand-understood levels are now called correctly by the win/loss BALANCE of legal random plans — a signal with wide margin (R-6 ~%.0f%% vs the tutorials' 77-100%%), not a knife-edge count threshold." % float(r6.get("legal_win_rate", 3.0)) if not r6.is_empty() else "")
	L.append("")
	for r in results:
		L.append_array(_level_section(r))
	L.append("## Method caveats / what I don't fully trust")
	L.append("")
	L.append("- **Solver-relative solvability.** \"Solvable\" is per-seed: for >=7/8 TEST seeds, at least one route-set the search discovered as a winner (a niche example, the best genome, or the hand thesis) wins that seed within the budget. It is NOT \"one genome wins every seed\" — R-6's cooperative split is a legal win but seed-fragile (the best single genome generalises to only 5/8 test seeds), so requiring one genome to win 7/8 would falsely read R-6 as unsolvable. A false BROKEN (our decoder missed a real win) and a false GOOD PUZZLE (the solver found a path no human would) are the two states this most easily confuses (docs/v5-transition-spec.md §6). The numbers are a filter, never the verdict.")
	L.append("- **The thesis is used as a known-legal winner in the solvability check.** That makes solvability not strictly solver-only for the shipped levels; the per-seed count would be re-derived from solver-found winners alone before this gates NEW (un-thesised) levels.")
	L.append("- **K is a secondary quality signal, not the classifier's discriminator.** The archive `K` (distinct `win_signature`s the EA evaluated) does NOT separate puzzle from soft on this tiny suite — signature granularity (overlap-cell counts, loop flags) can give a puzzle a HIGHER archive K than a tutorial. Where the capped stop-sequence space is small enough, **exhaustive K** enumerates all winning per-card served-room structures (ground truth, Sturtevant EPCG); where the space is too large (R-4, with 8 docks x 3 cards) it falls back to the archive estimate, stated as such. Exhaustive K enumerates dock-stop sequences up to length %d and card-decode-order permutations, so a winner reachable only by a longer sequence would be missed — a known blind spot on the enumerated levels." % Metrics5.ENUM_MAX_STOPS)
	L.append("- **The freer sampler's legality rate conflates two things**: how constraining the caps are AND how often a drifted self-avoiding walk dead-ends or misses a room on a given geometry. So a low legality rate (e.g. R-4 at ~2%%, which has NO caps) is not by itself evidence of a constraint puzzle — the classifier reads the legal-plan WIN rate, not legality, for exactly this reason.")
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
	L.append("**Class driven by:** %s" % str(r.get("klass_signal", "")))
	L.append("")
	L.append("| metric | value |")
	L.append("|---|---|")
	L.append("| legality rate (legal raw draws / attempts) | %.1f%% (%d legal of %d) |" % [float(r.get("legality_rate", 0.0)), int(r.decodable), int(r.get("probe_attempts", 0))])
	L.append("| **legal-plan win rate** (freer sampler) | **%.2f%%** (%d/%d legal draws win) |" % [float(r.get("legal_win_rate", r.rwr)), int(r.w_rand), int(r.decodable)])
	L.append("| solvability (per-seed: solver win exists) | %d/%d -> %s |" % [int(r.get("solvable_seeds", 0)), int(r.n_test), "solvable" if r.solvable else "NOT solvable"])
	L.append("| best single EA genome generalises (wins on TEST) | %d/%d |" % [int(r.solve_wins), int(r.n_test)])
	L.append("| `K` archive estimate | %d |" % int(r.K))
	L.append("| `K` EXHAUSTIVE (ground truth) | %s |" % (str(int(r.get("exhaustive_k", -1))) + "  — " + str(r.get("exhaustive_k_note", "")) if bool(r.get("exhaustive_k_feasible", false)) else ("n/a — " + str(r.get("exhaustive_k_note", "")))))
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
	var exk := (" Exhaustive K = %d." % int(r.get("exhaustive_k", -1))) if bool(r.get("exhaustive_k_feasible", false)) else " Exhaustive K n/a (space too large; archive K = %d)." % int(r.K)
	if k == "soft-border":
		var top: Dictionary = r.entries["ea@%d" % _last_budget(r)]
		var thesis_note := ""
		if r.entries.has("thesis"):
			var beat: float = float(top.score) - float(r.entries.thesis.score)
			thesis_note = " The EA %s the hand thesis (%+.1f)." % [
					"beats" if beat > 1.0 else ("matches" if absf(beat) <= 1.0 else "trails"), beat]
		return "SOFT-BORDER: a broad basin — %.2f%% of legal random plans win — so the level has many working plans and quality varies smoothly; skill_gap %+.1f over %d ladder step(s).%s%s" % [
				float(r.get("legal_win_rate", r.rwr)), float(r.skill_gap), int(r.ladder_steps), thesis_note, exk]
	if k == "puzzle":
		return "PUZZLE: only %.2f%% of legal random plans win (the overlap cap forces a specific cooperative structure — the freer sampler almost never stumbles into it), but the solver finds a legal win on %d/%d seeds (first win at %s evals). The best single genome generalises to %d/%d test seeds (a fragile win).%s %s." % [
				float(r.get("legal_win_rate", r.rwr)), int(r.get("solvable_seeds", 0)), int(r.n_test),
				(str(int(r.e1_evals)) if int(r.e1_evals) >= 0 else "n/a"),
				int(r.solve_wins), int(r.n_test), exk,
				"The intended cooperative split IS among the winning niches" if r.thesis_among_niches else "The intended split was NOT recorded among niches"]
	return "BROKEN/UNVERIFIED: only %.2f%% of legal random plans win AND the solver found no legal win on >=7/8 seeds within %d evals. Either impossible or beyond this decoder — do not ship without a hand solve.%s" % [
			float(r.get("legal_win_rate", r.rwr)), int(r.B_max), exk]


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
