extends SceneTree
## Depth-measurement entry point (docs/depth-tools-spec.md §6).
##
## ONE COMMAND (all 5 levels, 5 parallel processes, then the report):
##
##   powershell -File tools/run_depth.ps1
##   powershell -File tools/run_depth.ps1 -Quick
##
## Or by hand, one process at a time:
##
##   & "<godot_console.exe>" --headless --path . --script tools/run_depth.gd -- --levels L3
##   & "<godot_console.exe>" --headless --path . --script tools/run_depth.gd -- --report
##
## Flags (after the bare `--`):
##   --levels L1,L3   only these level ids (default: all of Levels3.LEVELS)
##   --quick          small budgets + 2 seeds; finishes in a couple of minutes
##   --report         skip searching: merge tools/out/*.json into
##                    docs/depth-report.md + scripts/v3/discovered3.gd
##   --selftest       batching / determinism / throughput check, no search
##   --scorecheck     score-validity audit: samples random route-sets per level
##                    and reports the win/lose split, the losing-branch spread
##                    and the empirical win-vs-loss separation (docs/depth-
##                    tools-spec.md §1)
##   --tune           LEVEL DESIGN loop: per level, the uniform-random win rate
##                    (is the level trivial?) next to thesis/naive win counts
##                    over Scenarios3.SEEDS_TUNE. Never touches SEEDS_ASSERT.
##   --smoke          headless check that the GAME still works: the level
##                    select builds, every level instantiates and plays, and
##                    every discovered route-set runs under WATCH BEST
##   --lengthsweep    LEVEL-LENGTH experiment: per level, sweep the quota
##                    DOWNWARD (holding geometry + demand shape fixed) and, at
##                    each quota, report thesis WINS / naive LOSES over the seed
##                    set and the uniform-random win rate. Answers "can this
##                    level prove its point with fewer passengers?". Flags:
##                      --quotas 20,25,30,40,50   quota values to try (the
##                                                current quota is always added)
##                      --maxlost N     force this max_lost at every quota
##                                      (default: keep the level's current one)
##                      --seeds tune|assert   which 16-seed set (default tune;
##                                      choose lengths on tune, confirm on assert)
##                      --n 256         uniform-random samples per quota
##                    A quota "holds" if thesis WINS >= 15/16 AND naive LOSES
##                    >= 15/16 AND random win-rate <= 5%. Never edits the table.
##
## Per-level results land in tools/out/depth_<ID>.json so shards can run in
## separate processes (Grid3's maze is static, so one process = one level at a
## time — docs/sim-search-feasibility.md §3).

const SimApi = preload("res://tools/sim_api.gd")
const Metrics = preload("res://tools/metrics.gd")
const RG = preload("res://tools/routegen.gd")

const OUT_DIR := "res://tools/out"
const REPORT_PATH := "res://docs/depth-report.md"
const DISCOVERED_PATH := "res://scripts/v3/discovered3.gd"

var args: Array = []
var quick := false
var level_ids: Array = []
var queue: Array = []
var done: Array = []
var t_start := 0
var mode := "search"
var explicit_levels := false # a shard: leave the merge to the --report pass


func _init() -> void:
	args = Array(OS.get_cmdline_user_args())
	quick = args.has("--quick")
	if args.has("--report"):
		mode = "report"
	elif args.has("--selftest"):
		mode = "selftest"
	elif args.has("--smoke"):
		mode = "smoke"
	elif args.has("--scorecheck"):
		mode = "scorecheck"
	elif args.has("--tune"):
		mode = "tune"
	elif args.has("--lengthsweep"):
		mode = "lengthsweep"
	# Ablation knobs (docs/depth-report.md): swap the acceleration model or
	# restrict a mechanic, so accel-by-width / accel-by-speed and
	# capacity-on / capacity-off can be measured without editing the tables.
	var ai := args.find("--accel")
	if ai >= 0 and ai + 1 < args.size():
		Levels3.accel_model = String(args[ai + 1]).strip_edges()
	var ri := args.find("--restrict")
	if ri >= 0 and ri + 1 < args.size():
		Levels3.restrict = String(args[ri + 1]).strip_edges()
	var i := args.find("--levels")
	if i >= 0 and i + 1 < args.size():
		for s in String(args[i + 1]).split(","):
			level_ids.append(s.strip_edges())
	explicit_levels = not level_ids.is_empty()
	if level_ids.is_empty():
		for lv in Levels3.LEVELS:
			level_ids.append(lv.id)
	queue = level_ids.duplicate()
	t_start = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	match mode:
		"report":
			_write_outputs()
			quit(0)
			return true
		"selftest":
			_selftest()
			quit(0)
			return true
		"smoke":
			quit(0 if _smoke() else 1)
			return true
		"scorecheck":
			quit(0 if _scorecheck() else 1)
			return true
		"tune":
			quit(0 if _tune() else 1)
			return true
		"lengthsweep":
			quit(0 if _lengthsweep() else 1)
			return true
	if queue.is_empty():
		print("\nALL LEVELS DONE in %.1f s" % ((Time.get_ticks_msec() - t_start) / 1000.0))
		if explicit_levels:
			# A shard. Merging here would race the other shards and produce a
			# one-level report; the --report pass does it once, at the end.
			print("(shard: run with --report to merge every tools/out/depth_*.json)")
		else:
			_write_outputs()
		quit(0)
		return true
	var id: String = queue.pop_front()
	_run_one(id)
	return false


# ---------------------------------------------------------------- search

func _run_one(id: String) -> void:
	var li := Levels3.index_of(id)
	if li < 0:
		push_error("unknown level id " + id)
		return
	var cfg := Metrics.default_cfg(quick)
	print("\n=== %s (%s mode) ===" % [id, "quick" if quick else "full"])
	var sim = SimApi.new(self)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Resume support: see the run-cache note in tools/sim_api.gd. A shard that
	# is killed mid-search can simply be relaunched; it replays the identical
	# deterministic trajectory, serving everything it already did from disk.
	var cache := "%s/runcache_%s%s.json" % [OUT_DIR, id, "_quick" if quick else ""]
	sim.open_cache(cache)
	var res: Dictionary = Metrics.run_level(sim, li, cfg)
	sim.flush_cache(true)
	res["sim_cpu_s"] = sim.sim_usec / 1.0e6
	res["sim_game_seconds"] = sim.sim_seconds
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var f := FileAccess.open("%s/depth_%s.json" % [OUT_DIR, id], FileAccess.WRITE)
	f.store_string(JSON.stringify(_to_json(res), "  "))
	f.close()
	print("    %s: %d runs (%d replayed from cache), %.1f s wall (%.0f game-s simulated)" % [
			id, sim.runs, sim.cache_hits, res.wall_s, sim.sim_seconds])
	# The level is finished and its JSON is written; the cache has no further
	# use and is the biggest file we produce.
	DirAccess.remove_absolute(cache)
	done.append(id)


# ---------------------------------------------------------------- selftest

## The no-leak batching pattern of docs/sim-search-feasibility.md §3,
## re-verified here: run A, B, A and confirm the two A runs are identical.
## Also times the two step sizes so budgets can be sized honestly.
func _selftest() -> void:
	print("=== sim_api selftest ===")
	var sim = SimApi.new(self)
	var a := Levels3.index_of("L3")
	var b := Levels3.index_of("L1")
	var routes_a := _thesis_routes("L3")
	var routes_b := _thesis_routes("L1")
	var r1: Dictionary = sim.run(a, routes_a, 1101, SimApi.STEP_COARSE)
	var r2: Dictionary = sim.run(b, routes_b, 1101, SimApi.STEP_COARSE)
	var r3: Dictionary = sim.run(a, routes_a, 1101, SimApi.STEP_COARSE)
	var same: bool = r1.served == r3.served and r1.lost == r3.lost \
			and is_equal_approx(r1.avg_wait, r3.avg_wait) \
			and is_equal_approx(r1.score, r3.score)
	print("A: served %d lost %d score %.4f" % [r1.served, r1.lost, r1.score])
	print("B: served %d lost %d score %.4f" % [r2.served, r2.lost, r2.score])
	print("A: served %d lost %d score %.4f" % [r3.served, r3.lost, r3.score])
	print("A/B/A identical: %s" % ("YES" if same else "NO -- STATE LEAK"))
	# Invalid geometry must score, not crash.
	var bad := [{"cells": [Vector2i(3, 0), Vector2i(3, 9)], "closed": false}]
	var rb: Dictionary = sim.run(a, bad, 1101, SimApi.STEP_COARSE)
	print("invalid route rejected: %s (%s)" % [str(not rb.valid), rb.err])
	# Throughput at both steps.
	for st in [SimApi.STEP_COARSE, SimApi.STEP_FINE]:
		for id in ["L1", "L3", "L4"]:
			var li := Levels3.index_of(id)
			var t0 := Time.get_ticks_usec()
			var n := 5
			for _i in n:
				sim.run(li, _thesis_routes(id), 1101, st)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
			print("  step %.2f  %-4s  %6.1f ms/run  %5.1f runs/s" % [
					st, id, ms, 1000.0 / ms])
	# Decode round-trip on every level.
	print("--- gene decode round-trip ---")
	for lv in Levels3.LEVELS:
		SimApi.load_maze(lv)
		var rooms: Array = Grid3.rooms()
		var gene := {"stops": [rooms[0], rooms[rooms.size() - 1]], "closed": false}
		var d := RG.decode(gene)
		var got := RG.stops_of_cells(d.cells)
		print("  %-4s %d rooms, %d primitives, decode err '%s', stops kept %s" % [
				lv.id, rooms.size(), RG.primitive_genes(lv).size(), d.err,
				str(got.has(gene.stops[0]) and got.has(gene.stops[1]))])


# ---------------------------------------------------------------- game smoke

## The game must still be a game. Builds the real level-select scene and every
## level scene headlessly, and plays each discovered route-set under WATCH
## BEST. Prints PASS/FAIL per check; exits nonzero on any failure.
func _smoke() -> bool:
	var ok := true
	print("=== game smoke ===")
	Levels3.headless = false # the smoke test must exercise the REAL game, HUD and all
	# 1. Level select builds as PAGED WORLDS (docs/ui-pass §1): one world at a
	#    time, arrow paging, a full-width PLAY card per level with a compact
	#    N/T/B strip under it. Page through every world and tally: a PLAY card
	#    per level, a B button exactly where a discovered set exists, a T per
	#    level with a thesis and an N per level with a naive set.
	Levels3.watch_strategy = ""
	Levels3.injected = null
	var sel = load("res://scenes/v3_select.tscn").instantiate()
	root.add_child(sel)
	var n_worlds: int = Levels3.WORLDS.size()
	var play_ids := {}
	var b_count := 0
	var t_count := 0
	var n_count := 0
	var worlds_seen: Array = []
	for wi in n_worlds:
		var labels: Array = []
		_collect_buttons(sel, labels)
		worlds_seen.append(String(sel.world_label.text))
		for lbl in labels:
			var s := String(lbl)
			if s == "B":
				b_count += 1
			elif s == "T":
				t_count += 1
			elif s == "N":
				n_count += 1
			elif s.length() >= 2: # a PLAY card: "L1  TOWER\n<thesis>"
				play_ids[s.split(" ")[0]] = true
		if wi == 0:
			ok = _p("select: on the first world the left arrow is disabled, the right is live",
					sel.left_btn.disabled and not sel.right_btn.disabled,
					"left %s right %s" % [str(sel.left_btn.disabled),
							str(sel.right_btn.disabled)]) and ok
		if wi < n_worlds - 1:
			sel.right_btn.pressed.emit() # page to the next world
	var want_t := 0
	var want_n := 0
	for lv in Levels3.LEVELS:
		var sets: Dictionary = Scenarios3.route_sets(lv.id)
		if sets.has("thesis"):
			want_t += 1
		if sets.has("naive"):
			want_n += 1
	ok = _p("select: pages through every world",
			worlds_seen.size() == n_worlds and worlds_seen[0].begins_with("PATH")
			and sel.right_btn.disabled,
			"seen %s right_disabled %s" % [str(worlds_seen), str(sel.right_btn.disabled)]) and ok
	ok = _p("select: a PLAY card for every level across the worlds",
			play_ids.size() == Levels3.LEVELS.size(),
			"%d cards vs %d levels" % [play_ids.size(), Levels3.LEVELS.size()]) and ok
	ok = _p("select: WATCH BEST (B) count matches discovered sets",
			b_count == _n_discovered(), "%d B buttons vs %d sets" % [b_count, _n_discovered()]) and ok
	ok = _p("select: N/T strips match the scenario sets",
			t_count == want_t and n_count == want_n,
			"T %d/%d N %d/%d" % [t_count, want_t, n_count, want_n]) and ok
	root.remove_child(sel)
	sel.free()
	# 2. Every level instantiates and plays THROUGH THE v4 PHASES: a fresh
	#    scene opens on the BRIEFING, PLAN is where routes may be drawn, and
	#    RUN locks them.
	for i in Levels3.LEVELS.size():
		var lv: Dictionary = Levels3.LEVELS[i]
		Levels3.current = i
		Levels3.watch_strategy = ""
		var g = load("res://scenes/v3_main.tscn").instantiate()
		g.headless = true
		root.add_child(g)
		ok = _p("%s: opens on the briefing" % lv.id, g.state == g.State.BRIEFING,
				"state %d" % g.state) and ok
		ok = _hud_layout(g, lv) and ok
		g.rng.seed = 5150
		# Walk the whole loop through the REAL HUD BUTTONS, not the API: a
		# phase machine nothing can press is not a game.
		var to_plan: bool = _press(g, "PLAN")
		ok = _p("%s: the briefing's PLAN button opens the editable phase" % lv.id,
				to_plan and g.state == g.State.PLAN and g.can_edit(),
				"pressed %s state %d" % [str(to_plan), g.state]) and ok
		var rs: Array = Scenarios3.route_set(lv.id, "thesis")
		g.commit_route(0, Scenarios3.cells_of(rs[0]), Scenarios3.closed_of(rs[0]))
		var run_locked: bool = not g.ready_to_run() and not _press(g, "RUN")
		for k in range(1, mini(rs.size(), g.CARDS.size())):
			g.commit_route(k, Scenarios3.cells_of(rs[k]), Scenarios3.closed_of(rs[k]))
		ok = _p("%s: RUN stays disabled until every card is routed" % lv.id,
				run_locked and g.ready_to_run() and g.state == g.State.PLAN,
				"locked %s ready %s" % [str(run_locked), str(g.ready_to_run())]) and ok
		var started: bool = _press(g, "RUN")
		for _t in 300:
			g.advance(0.1)
		ok = _p("%s: plays normally" % lv.id,
				started and g.cars.size() == lv.cards.size()
				and g.state == g.State.PLAYING and g.routes[0] != null
				and not g.can_edit() and g.served > 0,
				"state %d served %d" % [g.state, g.served]) and ok
		var aborted: bool = _press(g, "ABORT - BACK TO PLAN")
		ok = _p("%s: ABORT returns to PLAN with the routes kept" % lv.id,
				aborted and g.state == g.State.PLAN and g.can_edit()
				and g.served == 0 and g.routes[0] != null,
				"pressed %s state %d served %d" % [str(aborted), g.state, g.served]) and ok
		root.remove_child(g)
		g.free()
	# 3. Every WATCH strategy the level select offers actually pre-draws its
	#    routes and plays them (this is the gate on "the shipped scenario data
	#    still fits the shipped geometry" - a route set left behind by a level
	#    redesign is rejected by commit_route and would otherwise only show up
	#    as a car that never appears).
	for i in Levels3.LEVELS.size():
		var lv3: Dictionary = Levels3.LEVELS[i]
		for strat in ["naive", "thesis"]:
			var want: int = Scenarios3.route_set(lv3.id, strat).size()
			if want == 0:
				continue
			Levels3.current = i
			Levels3.watch_strategy = strat
			var g3 = load("res://scenes/v3_main.tscn").instantiate()
			g3.headless = true
			root.add_child(g3)
			var drawn := 0
			for r in g3.routes:
				if r != null:
					drawn += 1
			# Watch mode skips BRIEFING/PLAN: it is already running.
			var started: bool = g3.state == g3.State.PLAYING and not g3.can_edit()
			for _t in 600:
				g3.advance(0.1)
			ok = _p("%s: WATCH %s draws %d routes and runs" % [lv3.id, strat.to_upper(), want],
					drawn == want and g3.served > 0 and started,
					"drew %d/%d, served %d, started %s" % [
							drawn, want, g3.served, str(started)]) and ok
			Levels3.watch_strategy = ""
			root.remove_child(g3)
			g3.free()
	# 4. WATCH BEST actually runs the discovered set.
	for i in Levels3.LEVELS.size():
		var lv2: Dictionary = Levels3.LEVELS[i]
		if not Discovered3.has(lv2.id):
			continue
		Levels3.current = i
		Levels3.watch_strategy = "best"
		var g2 = load("res://scenes/v3_main.tscn").instantiate()
		g2.headless = true
		root.add_child(g2)
		var committed := 0
		for r in g2.routes:
			if r != null:
				committed += 1
		var best_started: bool = g2.state == g2.State.PLAYING
		for _t in 600:
			g2.advance(0.1)
		ok = _p("%s: WATCH BEST commits and runs" % lv2.id,
				committed == Discovered3.route_set(lv2.id).size() and g2.served > 0
				and best_started,
				"%d routes, served %d lost %d" % [committed, g2.served, g2.lost]) and ok
		print("      %s watch-best 60 s: served %d, lost %d" % [lv2.id, g2.served, g2.lost])
		Levels3.watch_strategy = ""
		root.remove_child(g2)
		g2.free()
	print("SMOKE: %s" % ("ALL PASS" if ok else "FAILURES PRESENT"))
	return ok


# ---------------------------------------------------------------- score audit

## Does the REAL-LEVEL score (docs/depth-tools-spec.md §1) actually have a
## gradient an optimizer can climb? Samples uniform random route-sets per
## level and reports:
##   * how many WIN, and the spread of win scores (are wins distinguishable?)
##   * the spread of LOSING scores (if almost everything loses, the losing
##     branch is the only gradient there is — it had better discriminate)
##   * the empirical gap between the worst win and the best loss, which is the
##     check that WIN_BONUS is big enough on THIS level rather than in theory.
## Also scores the thesis and naive route-sets for scale.
func _scorecheck() -> bool:
	var n := 200
	var i := args.find("--n")
	if i >= 0 and i + 1 < args.size():
		n = int(args[i + 1])
	var ok := true
	print("=== score validity audit: %d uniform random route-sets per level ===" % n)
	print("score: WIN -> %.0f + (%.0f - t_win);  LOSE/TIMEOUT -> served - %.1f*lost - %.2f*avg_wait"
			% [SimApi.WIN_BONUS, SimApi.TIMEOUT, SimApi.LOST_WEIGHT, SimApi.WAIT_WEIGHT])
	var sim = SimApi.new(self)
	var rng := RandomNumberGenerator.new()
	for id in level_ids:
		var li := Levels3.index_of(id)
		if li < 0:
			continue
		var lv: Dictionary = Levels3.LEVELS[li]
		SimApi.load_maze(lv)
		var rooms: Array = Grid3.rooms()
		rng.seed = 4242 + li
		var wins: Array = []
		var losses: Array = []
		var lose_served: Array = []
		var results := {"win": 0, "lose": 0, "timeout": 0}
		var skipped := 0
		for _k in n:
			var g := RG.random_genome(rng, rooms, lv.cards.size())
			if g.is_empty():
				skipped += 1
				continue
			var dec := RG.decode_genome(g)
			if dec.err != "":
				skipped += 1
				continue
			# One seed per sample: this measures the score's SHAPE over the
			# candidate space, not a candidate's seed-robustness.
			var r: Dictionary = sim.run(li, dec.routes, SimApi.SEEDS_TRAIN[0],
					SimApi.STEP_COARSE)
			results[r.result] += 1
			if r.result == "win":
				wins.append(r.score)
			else:
				losses.append(r.score)
				lose_served.append(float(r.served))
		var thesis := _thesis_routes(lv.id)
		var t_score := "n/a"
		if not thesis.is_empty():
			var rt: Dictionary = sim.run(li, thesis, SimApi.SEEDS_TRAIN[0], SimApi.STEP_COARSE)
			t_score = "%s %.2f (served %d, lost %d)" % [rt.result, rt.score, rt.served, rt.lost]
		print("\n--- %s %s: %d valid of %d samples (%d undecodable) -> win %d / lose %d / timeout %d   (thesis: %s)" % [
				lv.id, lv.name, n - skipped, n, skipped,
				results.win, results.lose, results.timeout, t_score])
		if not wins.is_empty():
			print("    win scores    : min %.1f  med %.1f  max %.1f  (spread %.1f over %d)" % [
					_amin(wins), SimApi.median(wins), _amax(wins),
					_amax(wins) - _amin(wins), wins.size()])
		if not losses.is_empty():
			print("    losing scores : min %.2f  med %.2f  max %.2f  (spread %.2f over %d, %d distinct)" % [
					_amin(losses), SimApi.median(losses), _amax(losses),
					_amax(losses) - _amin(losses), losses.size(), _n_distinct(losses)])
			print("    losing served : min %.0f  med %.0f  max %.0f  (quota %d)" % [
					_amin(lose_served), SimApi.median(lose_served), _amax(lose_served),
					int(lv.quota)])
		if not wins.is_empty() and not losses.is_empty():
			var gap: float = _amin(wins) - _amax(losses)
			ok = _p("%s: every win outranks every loss" % lv.id, gap > 0.0,
					"worst win %.1f vs best loss %.2f" % [_amin(wins), _amax(losses)]) and ok
			print("    separation    : %.1f" % gap)
		if not losses.is_empty():
			var distinct := _n_distinct(losses)
			ok = _p("%s: losing branch discriminates (>=10 distinct scores)" % lv.id,
					distinct >= 10 or losses.size() < 10,
					"%d distinct over %d losers" % [distinct, losses.size()]) and ok
	print("\nSCORECHECK: %s" % ("ALL PASS" if ok else "FAILURES PRESENT"))
	return ok


# ---------------------------------------------------------------- tuning loop

## THE LEVEL-DESIGN LOOP (v3.5 axiom pass). One command, three numbers per
## level — the three the axioms are actually made of:
##
##   random  uniform random route-sets, each scored on one SEEDS_TUNE seed
##           (round robin, so the rate is not an artifact of one arrival
##           sequence). Its WIN RATE is the difficulty signal: a level where
##           random plans win outright is not a level. Target <= 5 %.
##   thesis  how many of the 16 SEEDS_TUNE seeds the intended strategy WINS.
##   naive   how many of the same 16 the honest-beginner strategy LOSES.
##
## It uses SEEDS_TUNE and NEVER SEEDS_ASSERT. Tuning against the seeds you
## then assert on is exactly the overfitting this pass exists to remove; the
## held-out read is tests/run_balance.gd, which is the gate, not this.
##
##   ... --script tools/run_depth.gd -- --tune [--n 200] [--levels L1,L2]
func _tune() -> bool:
	var n := 200
	var i := args.find("--n")
	if i >= 0 and i + 1 < args.size():
		n = int(args[i + 1])
	var seeds: Array = Scenarios3.SEEDS_TUNE
	print("=== level tuning: %d random route-sets + thesis/naive over %d TUNE seeds ===" % [
			n, seeds.size()])
	print("targets: random win rate <= 5 %, thesis WINS >= 15/16, naive LOSES >= 15/16")
	var sim = SimApi.new(self)
	var rng := RandomNumberGenerator.new()
	var ok := true
	for id in level_ids:
		var li := Levels3.index_of(id)
		if li < 0:
			continue
		var lv: Dictionary = Levels3.LEVELS[li]
		SimApi.load_maze(lv)
		var rooms: Array = Grid3.rooms()
		rng.seed = 4242 + li
		var wins := 0
		var valid := 0
		var win_t: Array = []
		var win_lost: Array = []
		var win_shape: Array = []
		for k in n:
			var g := RG.random_genome(rng, rooms, lv.cards.size())
			if g.is_empty():
				continue
			var dec := RG.decode_genome(g)
			if dec.err != "":
				continue
			valid += 1
			var r: Dictionary = sim.run(li, dec.routes, seeds[k % seeds.size()],
					SimApi.STEP_COARSE)
			if r.result == "win":
				wins += 1
				win_t.append(r.t_end)
				win_lost.append(float(r.lost))
				win_shape.append(RG.describe(dec.routes))
		var sp: Dictionary = lv.spawn
		print("
--- %s %s: %d rooms, quota %d, max_lost %d, interval %.2f->%.2f over %.0f s, burst %d-%d" % [
				lv.id, lv.name, rooms.size(), int(lv.quota), int(lv.max_lost),
				sp.interval_start, sp.interval_end, sp.ramp,
				int(sp.burst_min), int(sp.burst_max)])
		var rate := 100.0 * float(wins) / maxf(1.0, float(valid))
		ok = _p("%s: random win rate <= 5%%" % id, rate <= 5.0,
				"%d/%d valid = %.1f%%" % [wins, valid, rate]) and ok
		print("    random : %d/%d valid samples WIN = %.1f %%   (%d of %d undecodable)" % [
				wins, valid, rate, n - valid, n])
		if wins > 0:
			var lp := 0.0
			var cp := 0.0
			var sp2 := 0.0
			for sh in win_shape:
				lp += sh.loops
				cp += sh.cells
				sp2 += sh.stops
			print("      winners: lost med %.0f max %.0f | finish med %.0f s | avg %.1f loop(s), %.0f stops, %.0f cells" % [
					SimApi.median(win_lost), _amax(win_lost), SimApi.median(win_t),
					lp / wins, sp2 / wins, cp / wins])
		for strat in ["thesis", "naive"]:
			var routes := _strategy_routes(id, strat)
			if routes.is_empty():
				continue
			var w := 0
			var odd: Array = []
			var served: Array = []
			var lostv: Array = []
			var fin: Array = []
			var qend: Array = []
			var waitv: Array = []
			for sd in seeds:
				var r: Dictionary = sim.run(li, routes, sd, SimApi.STEP_FINE)
				served.append(float(r.served))
				lostv.append(float(r.lost))
				qend.append(float(r.waiting_end))
				waitv.append(r.avg_wait)
				if r.result == "win":
					w += 1
					fin.append(r.t_end)
					if strat == "naive":
						odd.append("%d WIN" % sd)
				elif strat == "thesis":
					odd.append("%d %s" % [sd, r.result.to_upper()])
			if strat == "thesis":
				print("      thesis worst: lost %.0f, queued@end %.0f, wait %.0f s" % [
						_amax(lostv), _amax(qend), _amax(waitv)])
			var want: int = seeds.size() - 1
			var hit: bool = w >= want if strat == "thesis" else (seeds.size() - w) >= want
			ok = _p("%s: %s %s >= %d/%d" % [id, strat,
					"WINS" if strat == "thesis" else "LOSES", want, seeds.size()],
					hit, "%d/%d won" % [w, seeds.size()]) and ok
			print("    %-7s: %s %d/%d   served ~%.0f  lost ~%.1f  wait ~%.0f s  queued@end ~%.0f  finish ~%.0f s (worst %.0f)%s" % [
					strat, "WIN" if strat == "thesis" else "LOSE",
					w if strat == "thesis" else seeds.size() - w, seeds.size(),
					SimApi.median(served), SimApi.median(lostv),
					SimApi.median(waitv), SimApi.median(qend),
					SimApi.median(fin) if not fin.is_empty() else 0.0,
					_amax(fin) if not fin.is_empty() else 0.0,
					("   ODD: " + ", ".join(odd)) if not odd.is_empty() else ""])
	print("
TUNE: %s" % ("ALL TARGETS MET" if ok else "TARGETS MISSED"))
	return ok


# ---------------------------------------------------------------- length sweep

## THE LEVEL-LENGTH EXPERIMENT (docs/depth-tools-spec.md, this pass). The
## question the designer asked: our quotas are large (75-116), a thesis run is
## ~3 minutes — can each level prove the SAME strategic point (thesis wins,
## naive loses, uniform-random almost never wins) with FEWER passengers?
##
## For every level it sweeps the QUOTA downward while holding geometry, cards,
## demand shape, spawn pace and patience FIXED — only quota (and max_lost)
## change — and reports at each quota the three numbers the axiom bar is made
## of, so the FULL curve of discrimination-vs-length is visible:
##   thesis WINS / 16, naive LOSES / 16   (over the chosen seed set), and
##   uniform-random win rate over --n samples (the difficulty floor).
##
## A quota HOLDS when thesis WINS >= 15/16 AND naive LOSES >= 15/16 AND the
## random win rate <= 5 %. Discrimination is expected to DEGRADE as the level
## gets shorter: a short level gives a bad plan less time to accumulate the
## losses that would disqualify it, so random plans win more often and the
## random-rate floor is usually what breaks first.
##
## Choose lengths on --seeds tune, then CONFIRM on --seeds assert (the held-out
## gate). Never tune against assert — that is the overfitting this pass avoids.
func _lengthsweep() -> bool:
	var n := 256
	var i := args.find("--n")
	if i >= 0 and i + 1 < args.size():
		n = int(args[i + 1])
	var seeds: Array = Scenarios3.SEEDS_TUNE
	var seedset := "tune"
	var si := args.find("--seeds")
	if si >= 0 and si + 1 < args.size() and String(args[si + 1]).strip_edges() == "assert":
		seeds = Scenarios3.SEEDS_ASSERT
		seedset = "assert"
	var forced_ml := -1
	var mi := args.find("--maxlost")
	if mi >= 0 and mi + 1 < args.size():
		forced_ml = int(args[mi + 1])
	var quotas: Array = []
	var qi := args.find("--quotas")
	if qi >= 0 and qi + 1 < args.size():
		for s in String(args[qi + 1]).split(","):
			quotas.append(int(s.strip_edges()))
	if quotas.is_empty():
		quotas = [20, 25, 30, 40, 50]
	print("=== level-length sweep: thesis/naive over %d %s seeds + %d random samples per quota ===" % [
			seeds.size(), seedset.to_upper(), n])
	print("bar: a quota HOLDS iff thesis WINS >= %d/%d AND naive LOSES >= %d/%d AND random win-rate <= 5%%" % [
			seeds.size() - 1, seeds.size(), seeds.size() - 1, seeds.size()])
	print("max_lost: %s" % ("forced to %d" % forced_ml if forced_ml > 0 else "kept at each level's current value"))
	var sim = SimApi.new(self)
	var rng := RandomNumberGenerator.new()
	var ok := true
	for id in level_ids:
		var li := Levels3.index_of(id)
		if li < 0:
			continue
		var lv: Dictionary = Levels3.LEVELS[li]
		SimApi.load_maze(lv)
		var rooms: Array = Grid3.rooms()
		var cur_q := int(lv.quota)
		var cur_ml := int(lv.max_lost)
		var qs: Array = quotas.duplicate()
		if not qs.has(cur_q):
			qs.append(cur_q)
		qs.sort()
		var thesis := _strategy_routes(id, "thesis")
		var naive := _strategy_routes(id, "naive")
		print("\n--- %s %s: %d rooms, CURRENT quota %d / max_lost %d, interval %.2f->%.2f, burst %d-%d" % [
				lv.id, lv.name, rooms.size(), cur_q, cur_ml,
				lv.spawn.interval_start, lv.spawn.interval_end,
				int(lv.spawn.burst_min), int(lv.spawn.burst_max)])
		print("    quota  max_lost  thesis_WINS  naive_LOSES  random_win%   holds?")
		for q in qs:
			var ml: int = forced_ml if forced_ml > 0 else cur_ml
			var inj: Dictionary = lv.duplicate(true)
			inj.quota = q
			inj.max_lost = ml
			var tw := 0
			for sd in seeds:
				var r: Dictionary = sim.run(li, thesis, sd, SimApi.STEP_FINE, inj)
				if r.result == "win":
					tw += 1
			var nl := 0
			var have_naive := not naive.is_empty()
			if have_naive:
				for sd in seeds:
					var r: Dictionary = sim.run(li, naive, sd, SimApi.STEP_FINE, inj)
					if r.result == "lose":
						nl += 1
			rng.seed = 4242 + li
			var wins := 0
			var valid := 0
			for k in n:
				var g := RG.random_genome(rng, rooms, lv.cards.size())
				if g.is_empty():
					continue
				var dec := RG.decode_genome(g)
				if dec.err != "":
					continue
				valid += 1
				var r: Dictionary = sim.run(li, dec.routes, seeds[k % seeds.size()],
						SimApi.STEP_COARSE, inj)
				if r.result == "win":
					wins += 1
			var rate := 100.0 * float(wins) / maxf(1.0, float(valid))
			var need: int = seeds.size() - 1
			var holds: bool = tw >= need and (not have_naive or nl >= need) and rate <= 5.0
			var clean: bool = tw == seeds.size() and (not have_naive or nl == seeds.size()) \
					and rate <= 5.0
			var mark := "CLEAN" if clean else ("holds" if holds else "-")
			print("    %5d  %8d  %8d/%-2d  %8s/%-2d  %8.1f %%   %s%s" % [
					q, ml, tw, seeds.size(),
					("%d" % nl) if have_naive else "n/a", seeds.size(),
					rate, mark, "   <- current" if q == cur_q else ""])
	print("\nLENGTHSWEEP done.")
	return ok


## Route-set for a level + strategy in SimApi shape ([] when there is none).
func _strategy_routes(id: String, strategy: String) -> Array:
	var out: Array = []
	for e in Scenarios3.route_set(id, strategy):
		var r := {"cells": Scenarios3.cells_of(e), "closed": Scenarios3.closed_of(e)}
		var h = Scenarios3.home_of(e)
		if h != null:
			r["home"] = h # a scenario may pin a car's waiting floor (v4 phase 2)
		out.append(r)
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


func _n_discovered() -> int:
	var n := 0
	for lv in Levels3.LEVELS:
		if Discovered3.has(lv.id):
			n += 1
	return n


## The 720x1280 one-thumb rules, checked rather than asserted in a comment:
## every button the HUD builds (panel, top bar and the briefing overlay that is
## open right now) is at least 90 px tall and inside the viewport, and the
## generated briefing text is short enough that its PLAN button still fits on
## screen under the title.
func _hud_layout(g, lv: Dictionary) -> bool:
	var btns: Array = []
	_collect_button_nodes(g.hud, btns)
	var small: Array = []
	var off: Array = []
	for b in btns:
		var label: String = String(b.text).split("\n")[0]
		# Overlay buttons live in a VBox and have no size until a layout pass,
		# so their minimum is the honest number there.
		if maxf(b.size.y, b.custom_minimum_size.y) < 90.0:
			small.append(label)
		if b.size.x > 0.0 and (b.position.x < 0.0 or b.position.y < 0.0
				or b.position.x + b.size.x > 720.0
				or b.position.y + b.size.y > 1280.0):
			off.append(label)
	var lines: int = Levels3.briefing_body(lv).split("\n").size()
	return _p("%s: HUD fits 720x1280, %d buttons >= 90 px, briefing %d lines" % [
			lv.id, btns.size(), lines],
			small.is_empty() and off.is_empty() and btns.size() >= 8 and lines <= 34,
			"short %s offscreen %s" % [str(small), str(off)])


## Press the HUD button whose label starts with `label`, exactly as a thumb
## would. Refreshes the HUD first, because nothing here runs engine frames and
## a button's enabled state is set in refresh_stats(). Returns false when no
## such button exists or it is disabled — which is itself an assertion (RUN
## must be unpressable until the plan is legal).
func _press(g, label: String) -> bool:
	g.hud.refresh_stats()
	g.hud.refresh_cards()
	var btns: Array = []
	_collect_button_nodes(g.hud, btns)
	for b in btns:
		if String(b.text).begins_with(label) and b.visible and not b.disabled:
			b.pressed.emit()
			return true
	return false


func _collect_button_nodes(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(c)
		_collect_button_nodes(c, out)


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Button:
			out.append(c.text)
		_collect_buttons(c, out)


func _p(name: String, ok: bool, detail: String) -> bool:
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", name, "" if ok else "  (" + detail + ")"])
	return ok


func _thesis_routes(id: String) -> Array:
	return _strategy_routes(id, "thesis")


# ---------------------------------------------------------------- outputs

func _write_outputs() -> void:
	var results: Array = []
	for id in level_ids:
		var path := "%s/depth_%s.json" % [OUT_DIR, id]
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
	_write_report(results)
	_write_discovered(results)


func _write_report(results: Array) -> void:
	var L: Array = []
	var quick_run: bool = bool(results[0].get("quick", false))
	L.append("# Depth report — GENERATED by tools/run_depth.gd")
	L.append("")
	L.append("Do not hand-edit: re-run `powershell -File tools/run_depth.ps1` instead.")
	L.append("")
	L.append("Generated %s%s." % [Time.get_datetime_string_from_system(),
			"  **--quick mode: tiny budgets and 2 seeds, indicative only**" if quick_run else ""])
	L.append("")
	L.append("## How to read this")
	L.append("")
	L.append("- One **evaluation budget unit = one simulation run of THE REAL LEVEL** — the shipped quota, max_lost and win/lose checks are live and the run stops the moment the level ends, with a %d game-second timeout." % int(SimApi.TIMEOUT))
	L.append("- `WIN -> score = %.0f + (%.0f - time_to_quota)` (faster wins score higher); `LOSE or TIMEOUT -> score = served - %.1f*lost - %.2f*avg_wait` (partial credit, always far below any win)." % [SimApi.WIN_BONUS, SimApi.TIMEOUT, SimApi.LOST_WEIGHT, SimApi.WAIT_WEIGHT])
	L.append("- So **a score above %.0f is a win** and its distance above %.0f is the game-seconds it had to spare; anything below is a loss, scored on partial credit. This SUPERSEDES the original spec's fixed 240 s endless horizon — see \"Method caveats\"." % [SimApi.WIN_BONUS, SimApi.WIN_BONUS])
	L.append("- Optimizers searched the **TRAIN** seeds `%s` at STEP %.2f." % [str(results[0].seeds_train), SimApi.STEP_COARSE])
	L.append("- Every number below is a **median over the disjoint TEST seeds** `%s` at STEP %.2f." % [str(results[0].seeds_test), SimApi.STEP_FINE])
	L.append("- `ea@B` is the anytime best-so-far of ONE evolutionary run at budget B, re-scored on the test seeds. `random@B` is best-of-B uniform samples at the SAME budget — that is the fair comparison, and it is a genuinely strong baseline, not a straw man.")
	L.append("")
	L.append("## Headline table")
	L.append("")
	L.append("| level | thesis | naive | random@B | greedy | ea@%s | skill_gap | beat_thesis | ladder steps | struct. dist | seed_frag | plan_frag | rho top | rho spread |" % _last_budget(results[0]))
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in results:
		var top: String = "ea@%s" % _last_budget(r)
		L.append("| **%s** %s | %s | %s | %s | %s | %s | %+.1f | %+.1f | %d | %.2f | %+.1f | %.1f | %.2f | %.2f |" % [
				r.id, r.name, _s(r, "thesis"), _s(r, "naive"), _s(r, "random"),
				_s(r, "greedy"), _s(r, top), r.skill_gap, r.beat_thesis,
				int(r.ladder_steps), r.structural_distance, r.seed_fragility,
				r.plan_fragility, r.rank_correlation.rho,
				r.rank_correlation.get("rho_spread", 0.0)])
	L.append("")
	L.append("Scores marked **W** in the per-level tables are wins. Win/loss split per strategy (over %d test seeds):" % results[0].seeds_test.size())
	L.append("")
	L.append("| level | thesis | naive | random@B | greedy | ea@%s |" % _last_budget(results[0]))
	L.append("|---|---|---|---|---|---|")
	for r in results:
		var top2: String = "ea@%s" % _last_budget(r)
		L.append("| **%s** | %s | %s | %s | %s | %s |" % [r.id, _w(r, "thesis"),
				_w(r, "naive"), _w(r, "random"), _w(r, "greedy"), _w(r, top2)])
	L.append("")
	L.append("Seed noise band per level (median MAD/sqrt(n) of the ladder elites' test scores): " +
			_noise_list(results) + ". A ladder step counts only when a budget doubling beats the previous point by more than that.")
	L.append("")
	for r in results:
		L.append_array(_level_section(r))
	L.append("## Method caveats")
	L.append("")
	L.append("- \"Winnable\" here always means **by this optimizer, at this budget, on these seeds**. Every solver-verified claim inherits its solver's blind spots (docs/autodesign-research.md §1.1).")
	L.append("- The EA was seeded with generic primitives (spine, stop-everywhere, angular ring open/closed, per-group shuttles, hub feeders, heaviest-demand direct lines). It was **not** seeded with our thesis route-sets, so `beat_thesis` is not begging the question.")
	L.append("- The ladder is one anytime run per level, not independent restarts per budget; it therefore reads as an upper bound on what each budget achieves.")
	L.append("- `plan_fragility` only counts perturbations that still decode; a perturbation that makes a route undecodable is a representation artifact, not a plan-quality signal.")
	L.append("- **Read `plan_frag` as a yes/no, not a size.** Since the v3.5 level pass the levels have a real difficulty floor, so moving one stop in an elite route-set usually turns a WIN into a LOSS — and that drop is measured across the ~%.0f-point branch gap, which is why the column reads in the thousands. It means \"one stop matters\", not \"the plan is 1200 units worse\". A small plan_frag now means the perturbation stayed on the winning branch." % SimApi.WIN_BONUS)
	L.append("- **Scoring supersedes the original spec.** The first version of this tool scored a fixed 240 s of ENDLESS play (win/lose disabled). That measured a game nobody plays: every level stops at its quota, so most of each evaluation happened in an overload regime the player never faces, and it punished route-sets that win the shipped level comfortably but degrade under an unbounded demand ramp (L4's one-way-loop thesis was the clearest victim) while rewarding coverage-heavy plans. Scores here come from playing the REAL level to its own win/lose conditions.")
	L.append("- **The two branches are different currencies.** Above %.0f the units are game-seconds saved; below it they are passengers. Do not read the arithmetic difference between a win and a loss as meaningful beyond \"the win is better\". Differences WITHIN a branch are meaningful." % SimApi.WIN_BONUS)
	L.append("- A run ends the moment the level does, so a budget unit is no longer a constant amount of simulated time: strong candidates are cheaper to evaluate than weak ones. The budget is still one run, which is what makes the rungs comparable.")
	L.append("- The decoder lays legs down with BFS, not weighted A*: on a unit-cost grid these agree, and BFS with a fixed neighbour order is deterministic. There is no `gate_pref` bit yet — a route crosses a gate corridor only if the BFS shortest path happens to.")
	_store(REPORT_PATH, "\n".join(L) + "\n")


func _level_section(r: Dictionary) -> Array:
	var L: Array = []
	L.append("## %s — %s" % [r.id, r.name])
	L.append("")
	L.append("Thesis: *%s*" % r.thesis_text)
	L.append("")
	L.append("%d rooms, %d cards. Search cost: %d simulation runs in %.0f s wall (random %d + greedy %d + ea %d, plus the test-seed re-scoring)." % [
			int(r.rooms), int(r.cards), int(r.sim_runs), r.wall_s,
			int(r.budgets.random), int(r.budgets.greedy), int(r.budgets.ea)])
	L.append("")
	L.append("| strategy | score | wins | served | lost | avg wait | med. finish |")
	L.append("|---|---|---|---|---|---|---|")
	for k in ["thesis", "naive", "random", "greedy"]:
		if r.entries.has(k):
			L.append(_row(k, r.entries[k]))
	for pt in r.ladder:
		var kr: String = "random@%d" % int(pt.budget)
		if r.entries.has(kr):
			L.append(_row("random@%d" % int(pt.budget), r.entries[kr]))
		L.append(_row("**ea@%d**%s" % [int(pt.budget), "  <- step" if pt.step else ""],
				r.entries["ea@%d" % int(pt.budget)]))
	L.append("")
	L.append("Ladder (median test score vs budget): " + _ladder_str(r) +
			"  →  **%d step(s)** above a noise band of %.2f." % [int(r.ladder_steps), r.noise_band])
	L.append("")
	L.append("Best route-set found (%d loops, %d stops over %d cells, %d gate group(s) crossed) vs thesis (%s): Jaccard distance **%.2f**." % [
			r.shape_best.loops, r.shape_best.stops, r.shape_best.cells,
			r.shape_best.gate_groups, _shape_str(r.shape_thesis), r.structural_distance])
	L.append("")
	L.append("```")
	for i in r.best_routes.size():
		var rt: Dictionary = r.best_routes[i]
		L.append("card %d %s %2d cells, stops: %s" % [
				i, "LOOP" if rt.closed else "line", rt.cells.size(),
				_cells_str(r.best_stops[i])])
	L.append("```")
	L.append("")
	L.append("**Verdict.** " + _verdict(r))
	L.append("")
	L.append_array(_diag_section(r))
	return L


## Is the EA working, or is it just noise wearing a lab coat? Everything here
## is measured, not assumed (docs/depth-tools-spec.md §5).
func _diag_section(r: Dictionary) -> Array:
	var L: Array = []
	if not r.has("diag_ea"):
		return L
	var d: Dictionary = r.diag_ea
	var dr: Dictionary = r.get("diag_random", {})
	var kids: float = maxf(1.0, float(d.children))
	L.append("<details><summary>EA instrumentation (is the optimizer actually working?)</summary>")
	L.append("")
	L.append("- **%d generations** of mu=%d+lambda=%d completed; %d children proposed; stopped because: %s." % [
			int(d.generations), int(d.mu), int(d.lam), int(d.children), d.stopped])
	L.append("- Seeded from %d hand-built primitive genomes + %d random genomes." % [
			int(d.seeded_primitive), int(d.seeded_random)])
	L.append("- **%.1f%% of proposed genes failed to decode** (scored -INF, cost no budget); %.1f%% were cache hits (already evaluated, also free)." % [
			100.0 * float(d.undecodable) / kids, 100.0 * float(d.cached) / kids])
	if not dr.is_empty():
		L.append("- Uniform random needed %d proposals to fill its budget, %d of which never produced a decodable route-set." % [
				int(dr.get("proposed", 0)), int(dr.get("undecodable", 0))])
	L.append("")
	L.append("Operator effect is measured against the PARENT's score; immigration has no parent, so its comparison columns are blank by construction, not because it is broken.")
	L.append("")
	L.append("| operator | children | comparable | changed the score | improved on parent | mean abs. delta |")
	L.append("|---|---|---|---|---|---|")
	for opname in d.ops:
		var o: Dictionary = d.ops[opname]
		if int(o.get("compared", 0)) == 0:
			L.append("| %s | %d | 0 | — | — | — |" % [opname, int(o.n)])
			continue
		var n: float = float(o.compared)
		L.append("| %s | %d | %d | %.0f%% | %.0f%% | %.2f |" % [opname, int(o.n),
				int(o.compared), 100.0 * float(o.changed) / n,
				100.0 * float(o.improved) / n, float(o.sum_abs) / n])
	L.append("")
	L.append("Best-so-far and population diversity by generation (TRAIN seeds, search step) — `spread` is the mean pairwise Jaccard distance inside the population, so 0 means it has collapsed onto one plan:")
	L.append("")
	L.append("```")
	L.append("gen   runs   best      pop_best  pop_mean  distinct  spread")
	for pt in _thin(d.gen_curve, 14):
		L.append("%-5d %-6d %-9.2f %-9.2f %-9.2f %-9d %.3f" % [
				int(pt.gen), int(pt.runs), pt.best, pt.pop_best, pt.pop_mean,
				int(pt.distinct), pt.spread])
	L.append("```")
	L.append("")
	L.append("</details>")
	L.append("")
	return L


## At most `n` evenly spaced points, always including the last.
func _thin(a: Array, n: int) -> Array:
	if a.size() <= n:
		return a
	var out: Array = []
	for i in n:
		out.append(a[int(round(float(i) * (a.size() - 1) / float(n - 1)))])
	return out


## Honest, mechanical prose: every clause is a threshold on a number above.
func _verdict(r: Dictionary) -> String:
	var out: Array = []
	var noise: float = maxf(r.noise_band, 0.001)
	var top: Dictionary = r.entries["ea@%s" % _last_budget(r)]
	var rnd: Dictionary = r.entries["random"]
	var ea_won: bool = top.score >= SimApi.WIN_BONUS
	var rnd_won: bool = rnd.score >= SimApi.WIN_BONUS
	# The headline question first, in the units that actually apply.
	if ea_won and not rnd_won:
		out.append("SEARCH MATTERS: the EA finds a route-set that WINS the level on %d of %d test seeds; best-of-%s uniform random at the same budget does not win at all (best loss %.2f)." % [
				int(top.get("wins", 0)), int(top.get("n_seeds", 0)), _last_budget(r), rnd.score])
	elif ea_won and rnd_won:
		var margin: float = top.score - rnd.score
		if margin <= 2.0 * noise:
			out.append("SHALLOW: uniform random sampling at the same budget also wins, and finishes within noise of the EA (%+.1f game-seconds, noise %.2f) — thinking barely pays here." % [margin, noise])
		else:
			out.append("Both the EA and best-of-%s random win this level; the EA closes it %.0f game-seconds faster." % [_last_budget(r), margin])
	elif rnd_won and not ea_won:
		out.append("WARNING — the EA is BEATEN by uniform random at equal budget: random found a winning route-set and the EA did not. Treat the EA as underpowered on this level, not the level as shallow.")
	else:
		out.append("NOBODY WINS: neither the EA nor best-of-%s random ever met the quota on the test seeds, so every number here is partial credit (served - %.0f*lost). The EA's margin over random is %+.1f." % [
				_last_budget(r), SimApi.LOST_WEIGHT, r.skill_gap])
	if int(r.ladder_steps) <= 1:
		out.append("The ladder is FLAT (%d step): almost all of the achievable score is reached by the smallest budget, which is the 'one weird trick' shape, not depth." % int(r.ladder_steps))
	else:
		out.append("The ladder has %d distinguishable steps, i.e. more search kept buying real score." % int(r.ladder_steps))
	if r.entries.has("thesis"):
		var th: Dictionary = r.entries["thesis"]
		var th_won: bool = th.score >= SimApi.WIN_BONUS
		if ea_won != th_won:
			out.append("Note the branch change: %s wins the level and %s does not, so `beat_thesis` (%+.1f) is not a like-for-like number — read it as \"one wins, one loses\"." % [
					"the EA's plan" if ea_won else "our thesis",
					"our thesis" if ea_won else "the EA's plan", r.beat_thesis])
		elif r.beat_thesis > 2.0 * noise:
			if r.structural_distance >= 0.5:
				out.append("The optimizer BEAT our thesis by %+.1f with a structurally DIFFERENT plan (Jaccard %.2f) — this level has an answer we did not design." % [r.beat_thesis, r.structural_distance])
			else:
				out.append("The optimizer beat our thesis by %+.1f but with much the same shape (Jaccard %.2f) — it found our idea and tuned it." % [r.beat_thesis, r.structural_distance])
		elif r.beat_thesis < -2.0 * noise:
			out.append("Our hand-designed thesis is still ahead of the search by %.1f — either the level's answer is hard to find, or the budget was too small." % absf(r.beat_thesis))
		else:
			out.append("The optimizer matched the thesis (%+.1f, within noise)." % r.beat_thesis)
	if r.seed_fragility > 3.0 * maxf(r.noise_band, 0.001) and r.seed_fragility > 2.0:
		out.append("WARNING: seed_fragility %+.1f — the elite scores materially better on the seeds it was searched against, so treat its margin as optimistic." % r.seed_fragility)
	else:
		out.append("seed_fragility %+.1f: the elite transfers to unseen seeds." % r.seed_fragility)
	var rc: Dictionary = r.rank_correlation
	var rho_spread: float = rc.get("rho_spread", 0.0)
	if rho_spread < 0.7:
		out.append("Coarse-step search looks UNFAITHFUL: rho %.2f over %d candidates spanning %.1f score, so the STEP 0.25 ranking does not survive re-scoring at 0.1 and this level should be re-searched at 0.1." % [rho_spread, int(rc.get("n_spread", 0)), rc.get("range_spread", 0.0)])
	elif rc.rho < 0.6:
		out.append("Coarse-step search is faithful overall (rho_spread %.2f) but the TOP %d candidates re-rank freely at STEP 0.1 (rho %.2f) — they are a near-tie plateau, so which one is 'best' is arbitrary." % [rho_spread, int(rc.n), rc.rho])
	return " ".join(out)


func _write_discovered(results: Array) -> void:
	var L: Array = []
	L.append("class_name Discovered3")
	L.append("extends RefCounted")
	L.append("## GENERATED by tools/run_depth.gd — do not hand-edit.")
	L.append("##")
	L.append("## The best route-set the depth search found per level, in the same shape as")
	L.append("## Scenarios3: a cell polyline per card, or {\"cells\", \"closed\"} for a loop.")
	L.append("## The level select shows a WATCH BEST button for every level listed here, so")
	L.append("## optimizer output gets EYEBALLED rather than trusted numerically")
	L.append("## (docs/autodesign-research.md §5.3 step 4).")
	L.append("")
	L.append("const SETS := {")
	for r in results:
		if r.best_routes.is_empty():
			continue
		L.append("\t\"%s\": {" % r.id)
		L.append("\t\t\"desc\": \"%s\"," % _desc_of(r))
		L.append("\t\t\"score\": %.2f," % r.entries["ea@%s" % _last_budget(r)].score)
		L.append("\t\t\"routes\": [")
		for rt in r.best_routes:
			var cells: Array = []
			for c in rt.cells:
				cells.append("Vector2i(%d, %d)" % [int(c[0]), int(c[1])])
			# A home cell (v4 phase 2) is part of a route-set, so it survives the
			# round trip through JSON and into the watchable table. The search
			# does not choose homes yet, so in practice this stays absent.
			var home = rt.get("home", null)
			var extra := ""
			if home != null:
				extra = ", \"home\": Vector2i(%d, %d)" % [int(home[0]), int(home[1])]
			if rt.closed:
				L.append("\t\t\t{\"closed\": true%s, \"cells\": [%s]}," % [extra,
						", ".join(cells)])
			elif extra != "":
				L.append("\t\t\t{\"closed\": false%s, \"cells\": [%s]}," % [extra,
						", ".join(cells)])
			else:
				L.append("\t\t\t[%s]," % ", ".join(cells))
		L.append("\t\t],")
		L.append("\t},")
	L.append("}")
	L.append("")
	L.append("")
	L.append("static func has(level_id: String) -> bool:")
	L.append("\treturn SETS.has(level_id)")
	L.append("")
	L.append("")
	L.append("## Route entries for a level (same shape Scenarios3.route_set returns).")
	L.append("static func route_set(level_id: String) -> Array:")
	L.append("\treturn SETS.get(level_id, {}).get(\"routes\", [])")
	L.append("")
	L.append("")
	L.append("static func desc(level_id: String) -> String:")
	L.append("\treturn SETS.get(level_id, {}).get(\"desc\", \"\")")
	_store(DISCOVERED_PATH, "\n".join(L) + "\n")


func _desc_of(r: Dictionary) -> String:
	var s: Dictionary = r.shape_best
	return "search elite: %d loop(s), %d stops, %d cells (beat thesis %+.1f)" % [
			s.loops, s.stops, s.cells, r.beat_thesis]


# ---------------------------------------------------------------- helpers

func _store(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return
	f.store_string(text)
	f.close()
	print("wrote " + path)


## One row of a per-level strategy table.
func _row(label: String, e: Dictionary) -> String:
	var win: bool = e.score >= SimApi.WIN_BONUS
	return "| %s | %.2f%s | %d/%d | %.1f | %.1f | %.1f s | %s |" % [
			label, e.score, " **W**" if win else "", int(e.get("wins", 0)),
			int(e.get("n_seeds", 0)), e.served, e.lost, e.avg_wait,
			("%.0f s" % e.get("t_win", 0.0)) if win else "—"]


## "wins/seeds" cell for the headline win-rate table.
func _w(r: Dictionary, key: String) -> String:
	if not r.entries.has(key):
		return "—"
	var e: Dictionary = r.entries[key]
	return "%d/%d" % [int(e.get("wins", 0)), int(e.get("n_seeds", 0))]


func _s(r: Dictionary, key: String) -> String:
	if not r.entries.has(key):
		return "—"
	return "%.1f" % r.entries[key].score


func _last_budget(r: Dictionary) -> String:
	return str(int(r.ladder[r.ladder.size() - 1].budget))


func _ladder_str(r: Dictionary) -> String:
	var parts: Array = []
	for pt in r.ladder:
		parts.append("%d→%.1f (%d/%d won)" % [int(pt.budget), pt.score,
				int(pt.get("wins", 0)), int(pt.get("n_seeds", 0))])
	return "  ".join(parts)


func _noise_list(results: Array) -> String:
	var parts: Array = []
	for r in results:
		parts.append("%s %.2f" % [r.id, r.noise_band])
	return ", ".join(parts)


func _shape_str(s: Dictionary) -> String:
	if s.is_empty():
		return "no thesis"
	return "%d loops, %d stops, %d cells" % [s.loops, s.stops, s.cells]


func _cells_str(cells: Array) -> String:
	var parts: Array = []
	for c in cells:
		parts.append("(%d,%d)" % [int(c[0]), int(c[1])])
	return " ".join(parts)


# JSON cannot hold Vector2i: routes become [[x, y], ...].
func _to_json(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = _to_json(v[k])
		return d
	if v is Array:
		var a := []
		for e in v:
			a.append(_to_json(e))
		return a
	if v is Vector2i:
		return [v.x, v.y]
	return v
