extends RefCounted
## v3 balance harness (PERSISTENT deliverable - keep it green).
##
## Runs every scenario from tests/scenarios3.gd headless at high effective
## speed: each (scenario, seed) pair instantiates scenes/v3_main.tscn for its
## level, fixes the game RNG seed, commits the scripted routes, then drives
## main3.advance() with fixed 0.1 s steps until win / lose / timeout.
##
## ---------------------------------------------------------------- THE AXIOM
##
## Every core claim is asserted over a SEED SET, never one seed. This is the
## whole point of the v3.5 pass: the old suite asserted "naive LOSES / thesis
## WINS" on one canonical seed per level, and when the depth run
## (docs/depth-report.md) held that claim out on 8 unseen seeds, L3's naive
## strategy WON 6 of them. The axiom had been measuring seed luck.
##
## So: 16 seeds (Scenarios3.SEEDS_ASSERT), and the assertion form is
##   thesis WINS >= 15/16   and   naive LOSES >= 15/16
## per level - one bad seed tolerated, two is a failure. The report prints the
## per-seed win count for every scenario AND names the odd seeds out, so a
## straddle is visible instead of hidden behind a median.
##
## SEEDS_ASSERT is HELD OUT: level geometry and demand were tuned against the
## disjoint Scenarios3.SEEDS_TUNE (via `tools/run_depth.gd -- --tune`), so
## these numbers are a measurement, not a memory. If a level regresses, tune
## on SEEDS_TUNE and re-run this - never tune on the assertion seeds.
##
## RUNTIME. 9 scenarios x 16 seeds = 144 simulated levels, ~40 s wall on an
## 8-core box - so the multi-seed suite IS the default gate and CI runs the
## meaningful thing. `--quick` (one canonical seed per level, ~5 s) exists for
## fast iteration only; it prints a warning that it proves nothing about the
## axioms.
##
## Beyond the per-level win/lose assertions it also:
## - lints EVERY level for dead rooms (each room must have spawn weight > 0,
##   be a possible destination, and be covered by the thesis route set) and
##   for a BRIEFING that names every card, passenger type and goal number,
## - checks the v4 phase machine (briefing -> plan -> run -> result, no
##   editing of any kind during a run, ABORT/RETRY back to PLAN, and no car
##   ever recalling or redeploying mid-run), and
## - smoke-tests the v3.3 redeploy flow, which the player can no longer
##   reach, by driving main3.commit_route_mid_run() directly (mid-run redraw
##   with riders aboard recalls + redeploys in ~3 s; PLAN commits deploy
##   instantly).
##
## Driven by tests/run_balance.gd (one RUN per engine frame so freed nodes
## flush between runs):
##   & "<godot_console.exe>" --headless --path . --script tests/run_balance.gd
##   & "<godot_console.exe>" --headless --path . --script tests/run_balance.gd -- --quick
##
## Tuning loop: adjust level spawn/patience/quota numbers in
## scripts/v3/levels3.gd (NOT the assertions here) until everything passes.

const STEP := 0.1 # fixed logic step (game-seconds) - keep constant: results are seed-exact
const TIMEOUT := 900.0 # game-seconds per scenario before declaring TIMEOUT

## A level's core claim must hold on at least this many of the seed set. One
## tolerated failure keeps the gate from flapping on a single unlucky arrival
## order; two means the level, not the seed, is wrong.
const MIN_HITS := 15

const ScenData = preload("res://tests/scenarios3.gd")

var quick := Array(OS.get_cmdline_user_args()).has("--quick")
var scenarios: Array = ScenData.scenarios()
var jobs: Array = [] # one {sc, seed} per engine frame
var next_job := 0
var results := {} # scenario key -> {"runs": Array of per-seed stats dicts}
var phase_done := false
var phase_checks: Array = [] # filled by the v4 phase-machine run
var redeploy_done := false
var redeploy_checks: Array = [] # filled by the redeploy smoke run
var loop_done := false
var loop_checks: Array = [] # filled by the v3.4 loop-mechanics run
var unit_done := false
var unit_checks: Array = [] # Route3.validate / gene decode / injected level
var v4_done := false
var v4_checks: Array = [] # width / acceleration / home floor (v4 phase 2)


func _init() -> void:
	for sc in scenarios:
		results[sc.key] = {"runs": []}
		for sd in _seeds_for(sc):
			jobs.append({"sc": sc, "seed": sd})


## The seeds a scenario is judged on: the held-out 16 by default, or just the
## level's canonical WATCH seed under --quick.
func _seeds_for(sc: Dictionary) -> Array:
	if quick:
		return [ScenData.Scen.SEEDS[sc.level]]
	return ScenData.Scen.SEEDS_ASSERT


## Run one (scenario, seed) per call (per engine frame). Returns true when
## finished (after printing the report and requesting quit).
func step(tree: SceneTree) -> bool:
	if next_job < jobs.size():
		var j: Dictionary = jobs[next_job]
		results[j.sc.key].runs.append(_run_scenario(tree, j.sc, j.seed))
		next_job += 1
		return false
	if not phase_done:
		phase_done = true
		phase_checks = _phase_checks(tree)
		return false
	if not redeploy_done:
		redeploy_done = true
		redeploy_checks = _redeploy_smoke(tree)
		return false
	if not loop_done:
		loop_done = true
		loop_checks = _loop_mechanics(tree)
		return false
	if not unit_done:
		unit_done = true
		unit_checks = _unit_smoke(tree)
		return false
	if not v4_done:
		v4_done = true
		v4_checks = _v4_mechanics(tree)
		return false
	var ok := _report()
	tree.quit(0 if ok else 1)
	return true


# ---------------------------------------------------------------- running

func _run_scenario(tree: SceneTree, sc: Dictionary, seed_v: int) -> Dictionary:
	var li: int = Levels3.index_of(sc.level)
	assert(li >= 0, "unknown level id " + str(sc.level))
	Levels3.current = li
	Levels3.watch_strategy = "" # harness commits routes itself
	var game = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(game) # _ready loads the level grid
	var r := {
		"key": sc.key, "level": sc.level, "seed": seed_v, "result": "TIMEOUT",
		"served": 0, "lost": 0, "time": 0.0, "avg_wait": 0.0, "p90_wait": 0.0,
		"avg_transfers": 0.0, "gate_wait": 0.0, "gate_transits": 0,
		"quota": game.QUOTA, "max_lost": game.MAX_LOST, "log_served": [],
		"route_error": "",
	}
	for i in sc.routes.size():
		var err := _route_error(sc.routes[i])
		if err != "":
			r.route_error = "route %d: %s" % [i, err]
			push_error("%s %s" % [sc.key, r.route_error])
			game.get_parent().remove_child(game)
			game.free()
			return r
	game.rng.seed = seed_v
	# The v4 loop: commit the route-set in the PLAN phase (a fresh scene opens
	# in BRIEFING, where commits are legal), then start the run. Nothing may
	# change the network after start_run() — see main3.commit_route.
	for i in sc.routes.size():
		game.commit_route(i, ScenData.Scen.cells_of(sc.routes[i]),
				ScenData.Scen.closed_of(sc.routes[i]),
				ScenData.Scen.home_of(sc.routes[i]))
	game.start_run()
	var t := 0.0
	while game.state == game.State.PLAYING and t < TIMEOUT:
		game.advance(STEP)
		t += STEP
	r.time = t
	r.served = game.served
	r.lost = game.lost
	r.gate_wait = game.gate_wait_total()
	r.gate_transits = game.gate_transit_total()
	r.log_served = game.log_served.duplicate(true)
	if game.state == game.State.WIN:
		r.result = "WIN"
	elif game.state == game.State.LOSE:
		r.result = "LOSE"
	if not game.log_served.is_empty():
		var w := 0.0
		var tr := 0.0
		var waits: Array = []
		for e in game.log_served:
			w += e.wait
			tr += maxi(0, e.rides - 1)
			waits.append(e.wait)
		r.avg_wait = w / game.log_served.size()
		r.avg_transfers = tr / game.log_served.size()
		waits.sort()
		r.p90_wait = waits[mini(int(waits.size() * 0.9), waits.size() - 1)]
	tree.root.remove_child(game)
	game.free()
	return r


## "" when the route entry (cell Array, or {"cells", "closed"} Dictionary for
## a loop) is legal on the CURRENT level's maze. The check itself now lives in
## Route3.validate (main3.commit_route and the search tools call the same
## one); this only unwraps the scenario entry shape.
func _route_error(entry) -> String:
	return Route3.validate(ScenData.Scen.cells_of(entry),
			ScenData.Scen.closed_of(entry))


## Share of served origin-group -> dest-group passengers that used >= 2 legs,
## POOLED over every seed of the scenario (one seed's log is far too small a
## sample to assert a 40 % share on).
func _transfer_share(rs: Array, from_cells: Array, to_cells: Array) -> float:
	var total := 0
	var multi := 0
	for r in rs:
		for e in r.log_served:
			if e.origin in from_cells and e.dest in to_cells:
				total += 1
				if e.rides >= 2:
					multi += 1
	if total == 0:
		return 0.0
	return float(multi) / float(total)


# ------------------------------------------------------------- aggregation

## How many of a scenario's seeds ended in `want` ("WIN" / "LOSE").
func _count(key: String, want: String) -> int:
	var n := 0
	for r in results[key].runs:
		if r.result == want:
			n += 1
	return n


func _n_seeds(key: String) -> int:
	return results[key].runs.size()


## The seeds that did NOT end in `want`, as "9127 WIN" strings - this is what
## makes a straddle visible instead of averaged away.
func _odd_seeds(key: String, want: String) -> Array:
	var out: Array = []
	for r in results[key].runs:
		if r.result != want:
			out.append("%d %s" % [r.seed, r.result])
	return out


## Lower median of one numeric field across a scenario's seeds.
func _med(key: String, field: String) -> float:
	var v: Array = []
	for r in results[key].runs:
		v.append(float(r[field]))
	if v.is_empty():
		return 0.0
	v.sort()
	return v[(v.size() - 1) / 2]


func _worst(key: String, field: String) -> float:
	var m := -1.0e18
	for r in results[key].runs:
		m = maxf(m, float(r[field]))
	return m


## The required hit count for this run: MIN_HITS of 16 normally, but --quick
## only has one seed to look at, so it demands that one.
func _required(key: String) -> int:
	return mini(MIN_HITS, _n_seeds(key))


## One multi-seed axiom: `want` happened on at least _required() seeds.
func _axiom(name: String, key: String, want: String) -> Dictionary:
	var hits := _count(key, want)
	var need := _required(key)
	return _c("%s (%d/%d seeds)" % [name, hits, _n_seeds(key)], hits >= need,
			"needed %d; odd seeds: %s" % [need, str(_odd_seeds(key, want))])


# ---------------------------------------------------------------- reporting

func _report() -> bool:
	print("")
	print("===================== v3 BALANCE HARNESS =====================")
	if quick:
		print("--quick: ONE canonical seed per level. This proves the scenarios")
		print("still run; it proves NOTHING about the multi-seed axioms. Run")
		print("without --quick before believing anything.")
	else:
		print("Asserting over %d HELD-OUT seeds per scenario (Scenarios3.SEEDS_ASSERT)." % 				ScenData.Scen.SEEDS_ASSERT.size())
		print("Levels were tuned on the disjoint SEEDS_TUNE, so these are measurements.")
	print("Medians over seeds; W/L is the per-seed outcome split.")
	print("%-14s %-9s %8s %8s %9s %9s %10s %10s %8s" % [
			"scenario", "W/L/T", "served", "lost", "avg wait", "p90 wait",
			"transfers", "gate wait", "transits"])
	for sc in scenarios:
		var k: String = sc.key
		var n := _n_seeds(k)
		var w := _count(k, "WIN")
		var l := _count(k, "LOSE")
		print("%-14s %2dW/%dL/%dT %5.0f/%-3d %5.0f/%-3d %8.1fs %8.1fs %10.2f %9.1fs %8.0f" % [
				k, w, l, n - w - l, _med(k, "served"), results[k].runs[0].quota,
				_med(k, "lost"), results[k].runs[0].max_lost,
				_med(k, "avg_wait"), _med(k, "p90_wait"), _med(k, "avg_transfers"),
				_med(k, "gate_wait"), _med(k, "gate_transits")])
	# Name every seed that broke ranks, so nothing hides inside the median.
	for sc in scenarios:
		var want: String = "LOSE" if sc.key.ends_with("_naive") else "WIN"
		var odd := _odd_seeds(sc.key, want)
		if not odd.is_empty():
			print("   %-14s expected %s, got: %s" % [sc.key, want, ", ".join(odd)])
	print("--------------------------------------------------------------")
	var checks := _checks()
	var ok := true
	for c in checks:
		var mark: String = "PASS" if c.ok else "FAIL"
		print("[%s] %s%s" % [mark, c.name, "" if c.ok else "  (" + c.detail + ")"])
		ok = ok and c.ok
	print("--------------------------------------------------------------")
	print("BALANCE: ALL PASS" if ok else "BALANCE: FAILURES PRESENT")
	return ok


func _checks() -> Array:
	var out: Array = []
	for sc in scenarios:
		for r in results[sc.key].runs:
			if r.route_error != "":
				out.append({"name": sc.key + " routes valid", "ok": false,
						"detail": r.route_error})
				break
	# THE AXIOMS. Every playable level, over the whole seed set: the intended
	# strategy WINS and the honest-beginner strategy LOSES (hits max_lost
	# before quota). Asserted as a count, reported as a count.
	for id in ["L1", "L2", "L3", "L4", "W-1", "W-2", "W-3"]:
		var ki: String = "%s_intended" % id
		var kn: String = "%s_naive" % id
		out.append(_axiom("%s intended WINS" % id, ki, "WIN"))
		out.append(_c("%s intended median lost <= 3" % id, _med(ki, "lost") <= 3.0,
				"median %.0f, worst %.0f" % [_med(ki, "lost"), _worst(ki, "lost")]))
		out.append(_axiom("%s naive LOSES" % id, kn, "LOSE"))
	# L2's corridor claim, on medians over the seed set rather than one run.
	var l2i_gw := _med("L2_intended", "gate_wait")
	var l2n_gw := _med("L2_naive", "gate_wait")
	out.append(_c("L2 naive gate wait >= 3x intended", l2n_gw >= 3.0 * l2i_gw,
			"naive %.1fs vs intended %.1fs" % [l2n_gw, l2i_gw]))
	out.append(_c("L2 intended gate transits >= 10",
			_med("L2_intended", "gate_transits") >= 10.0,
			"median transits %.0f" % _med("L2_intended", "gate_transits")))
	# L3's transfer claim, pooled across every seed.
	var l3_level: Dictionary = Levels3.get_level(Levels3.index_of("L3"))
	var share := _transfer_share(results.L3_intended.runs, l3_level.groups.arms,
			l3_level.groups.pent)
	out.append(_c("L3 arm->penthouse 2-leg share >= 40%", share >= 0.4,
			"share %.0f%%" % (share * 100.0)))
	out.append(_axiom("X-1 winnable by old smoke strategy", "X1_smoke", "WIN"))
	out.append_array(_lint_levels())
	out.append_array(phase_checks)
	out.append_array(redeploy_checks)
	out.append_array(loop_checks)
	out.append_array(unit_checks)
	out.append_array(v4_checks)
	return out


# ------------------------------------------------------------- global lints

## Every level: every R cell generates demand (spawn weight > 0), every R
## cell is a possible destination, and the level's thesis route set covers
## every room (each room is a cell of some route). No dead/decoy rooms and
## no room the intended strategy abandons - X-1's smoke set included.
func _lint_levels() -> Array:
	var out: Array = []
	for lv in Levels3.LEVELS:
		Grid3.load_level(lv.rows)
		var origins := {}
		var dests := {}
		if lv.mix.get("exec", 0.0) > 0.0:
			for c in lv.exec_origins:
				origins[c] = true
			for c in lv.exec_dests:
				dests[c] = true
		# type_rooms (v4 axiom levels): typed lanes pin their own origin/dest.
		var tr: Dictionary = lv.get("type_rooms", {})
		for t in tr:
			if lv.mix.get(t, 0.0) <= 0.0:
				continue
			for c in tr[t].from:
				origins[c] = true
			for c in tr[t].to:
				dests[c] = true
		for row in lv.trips:
			if row.w <= 0.0:
				continue
			for c in lv.groups[row.from]:
				origins[c] = true
			for c in lv.groups[row.to]:
				dests[c] = true
		var covered := {}
		for entry in ScenData.Scen.route_set(lv.id, "thesis"):
			for c in ScenData.Scen.cells_of(entry):
				covered[c] = true
		var no_spawn: Array = []
		var no_dest: Array = []
		var uncovered: Array = []
		for r in Grid3.rooms():
			if not origins.has(r):
				no_spawn.append(r)
			if not dests.has(r):
				no_dest.append(r)
			if not covered.has(r):
				uncovered.append(r)
		out.append(_c("%s every room spawns and receives" % lv.id,
				no_spawn.is_empty() and no_dest.is_empty(),
				"no spawn %s, no dest %s" % [str(no_spawn), str(no_dest)]))
		out.append(_c("%s thesis routes cover every room" % lv.id,
				uncovered.is_empty(), "uncovered %s" % str(uncovered)))
		out.append(_briefing_check(lv))
	return out


## The v4 BRIEFING is generated from the level data (Levels3.briefing_body),
## which is the whole reason it cannot drift: this asserts the generated text
## really does name every elevator card, every passenger type that can spawn,
## and the goal numbers. A level that adds a card or a passenger type and
## forgets to mention it is now impossible rather than merely discouraged.
func _briefing_check(lv: Dictionary) -> Dictionary:
	var body: String = Levels3.briefing_body(lv)
	var missing: Array = []
	for c in lv.cards:
		if body.find(str(c.name)) == -1:
			missing.append(str(c.name))
	for t in lv.mix:
		if float(lv.mix[t]) <= 0.0:
			continue
		# An exec weight with no exec rooms degrades to a visitor at spawn
		# time, so the briefing is right not to advertise it.
		if t == "exec" and (lv.exec_origins.is_empty() or lv.exec_dests.is_empty()):
			continue
		if body.find(str(t)) == -1:
			missing.append(str(t))
	if body.find(str(int(lv.quota))) == -1:
		missing.append("quota %d" % int(lv.quota))
	if body.find(str(int(lv.max_lost))) == -1:
		missing.append("max_lost %d" % int(lv.max_lost))
	return _c("%s briefing names every card, type and goal" % lv.id,
			missing.is_empty() and Levels3.roster_lines(lv).size() == lv.cards.size()
			and Levels3.people_lines(lv).size() > 0, "missing %s" % str(missing))


# -------------------------------------------------------- v4 phase machine

## THE v4 LOOP (docs/v4-spec.md phase 1): design -> commit -> watch -> learn
## -> retry, with NO mid-run editing. Checks, in order:
##   * a fresh level opens on the BRIEFING, and its text is generated from the
##     level data (that part is linted per level in _briefing_checks);
##   * PLAN is editable and RUN is gated on every card having a >= 2-stop
##     route;
##   * during a RUN every editing path refuses - taps, chip selection, CLEAR
##     and commit_route itself - and no car ever enters the recall/redeploy
##     states, because the only commits that happened were PLAN commits;
##   * ABORT returns to PLAN with the routes intact and the counters reset;
##   * a PLAN commit AFTER a run still deploys instantly (the car is
##     ever_deployed by then - this is the check that PLAN bypasses
##     Car3.apply_route rather than relying on a never-deployed car);
##   * RESULT -> RETRY lands back in PLAN;
##   * watch mode skips BRIEFING/PLAN and is already running.
## Runs on the injected 5x5 fixture: this is main3's state machine under test,
## not any level's geometry.
func _phase_checks(tree: SceneTree) -> Array:
	var out: Array = []
	Levels3.injected = _draw_level()
	Levels3.current = 0
	Levels3.watch_strategy = ""
	var g = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g)
	g.rng.seed = 909
	g.auto_spawn = false
	out.append(_c("phase: a fresh level opens on the BRIEFING",
			g.state == g.State.BRIEFING and not g.can_edit(), "state %d" % g.state))
	g.to_plan()
	out.append(_c("phase: PLAN is editable and idle",
			g.state == g.State.PLAN and g.can_edit() and g.active_passengers.is_empty(),
			"state %d can_edit %s" % [g.state, str(g.can_edit())]))
	out.append(_c("phase: RUN is blocked while cards are unrouted",
			not g.ready_to_run() and g.cards_not_ready().size() == 3,
			"not ready: %s" % str(g.cards_not_ready())))
	var lines: Array = [[Vector2i(0, 0), Vector2i(0, 4)],
			[Vector2i(2, 0), Vector2i(2, 4)], [Vector2i(4, 0), Vector2i(4, 4)]]
	for i in 3:
		g.select_card(i)
		g.commit_route(i, ScenData.Scen.path(lines[i]))
	out.append(_c("phase: RUN unlocks when every card has a 2-stop route",
			g.ready_to_run(), "not ready: %s" % str(g.cards_not_ready())))
	# One stop is not enough: the >= 2-room-stop rule gates RUN too.
	g.commit_route(0, [Vector2i(0, 0), Vector2i(1, 0)])
	out.append(_c("phase: a 1-stop route re-blocks RUN",
			not g.ready_to_run() and g.route_warning(0),
			"not ready: %s" % str(g.cards_not_ready())))
	g.commit_route(0, ScenData.Scen.path(lines[0]))
	# --- RUN: the network is frozen.
	g.start_run()
	g.select_card(1)
	var sel_before: int = g.selected_card
	var cells_before: Array = g.routes[1].cells.duplicate()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Grid3.cell_center(Vector2i(2, 2))
	g._unhandled_input(touch)
	g.select_card(2)
	g.clear_route(1)
	var commit_refused: bool = not g.commit_route(1,
			ScenData.Scen.path([Vector2i(2, 0), Vector2i(2, 2)]))
	out.append(_c("phase: RUN state and speed control are live",
			g.state == g.State.PLAYING and not g.can_edit(), "state %d" % g.state))
	out.append(_c("phase: no editing during a RUN (tap / select / clear / commit)",
			not g.drawing and g.selected_card == sel_before and g.routes[1] != null
			and g.routes[1].cells == cells_before and commit_refused,
			"drawing %s sel %d refused %s" % [
					str(g.drawing), g.selected_card, str(commit_refused)]))
	# Run it for real and confirm the recall/redeploy machinery never fires.
	g.spawn_passenger("visitor", Vector2i(0, 0), Vector2i(0, 4))
	g.spawn_passenger("visitor", Vector2i(2, 4), Vector2i(2, 0))
	var only_running := true
	for _t in 400:
		g.advance(STEP)
		for c in g.cars:
			if c.car_state == Car3.CarState.RECALLING \
					or c.car_state == Car3.CarState.REDEPLOYING:
				only_running = false
	out.append(_c("phase: no car ever recalls or redeploys during a RUN",
			only_running, "a car left RUNNING mid-run"))
	out.append(_c("phase: the run actually served somebody", g.served > 0,
			"served %d" % g.served))
	# --- ABORT: back to PLAN, routes intact, counters reset.
	var served_before: int = g.served
	g.abort_run()
	var routed := 0
	for r in g.routes:
		if r != null:
			routed += 1
	out.append(_c("phase: ABORT returns to PLAN with routes intact, counters reset",
			g.state == g.State.PLAN and g.can_edit() and routed == 3
			and g.served == 0 and g.lost == 0 and is_zero_approx(g.elapsed)
			and g.active_passengers.is_empty() and served_before > 0,
			"state %d routed %d served %d" % [g.state, routed, g.served]))
	# --- Re-planning after a run: the cars are ever_deployed now, so this is
	# where the old mid-game redeploy would have fired. It must not.
	g.commit_route(0, ScenData.Scen.path([Vector2i(0, 4), Vector2i(4, 4)]))
	var car0 = g.cars[0]
	out.append(_c("phase: a PLAN commit after a run still deploys instantly",
			car0.ever_deployed and car0.car_state == Car3.CarState.RUNNING
			and car0.current_cell() == Vector2i(0, 4),
			"state %d cell %s" % [car0.car_state, str(car0.current_cell())]))
	# --- RESULT -> RETRY.
	g.start_run()
	g.advance(1.0)
	g._win()
	out.append(_c("phase: the RESULT overlay locks editing",
			g.state == g.State.WIN and not g.can_edit(), "state %d" % g.state))
	g.to_plan() # RETRY
	out.append(_c("phase: RETRY lands back in PLAN with the routes kept",
			g.state == g.State.PLAN and g.can_edit() and g.routes[0] != null,
			"state %d" % g.state))
	tree.root.remove_child(g)
	g.free()
	Levels3.injected = null
	# --- Watch mode skips the briefing entirely (shipped level, real routes).
	Levels3.current = Levels3.index_of("L4")
	Levels3.watch_strategy = "thesis"
	var gw = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(gw)
	var w_routed := 0
	for r in gw.routes:
		if r != null:
			w_routed += 1
	out.append(_c("phase: WATCH skips BRIEFING/PLAN and is already running",
			gw.state == gw.State.PLAYING and not gw.can_edit() and w_routed > 0,
			"state %d routed %d" % [gw.state, w_routed]))
	Levels3.watch_strategy = ""
	tree.root.remove_child(gw)
	gw.free()
	return out


# ---------------------------------------------------------- redeploy smoke

## Mid-run route replacement with riders aboard must RECALL (drop the riders
## at an old-route room stop, not teleport them), keep the car off the grid
## for a ~3 s ghost countdown at the new start, then resume service there.
## PLAN-phase commits (the only kind the v4 player flow produces) must deploy
## with no delay.
##
## v4 NOTE. The player can no longer reach this: every commit happens in PLAN,
## so main3.commit_route refuses once a run is on and deploys instantly before
## it. The machinery is still correct and a future place-only mid-run mode
## wants it, so this check drives it DIRECTLY through
## main3.commit_route_mid_run() — the one entry point into Car3.apply_route.
## Deleting the check, or letting it quietly assert nothing because the player
## path vanished, is exactly the rot the header note below warns about.
##
## Runs on the injected 5x5 fixture, not a shipped level, for the same reason
## Stage A of the loop checks does: this tests Car3's state machine, and it
## used to silently rot into a no-op the moment L1's rooms moved (the hand
## placed passengers landed on cells that were no longer rooms).
func _redeploy_smoke(tree: SceneTree) -> Array:
	var out: Array = []
	Levels3.injected = _draw_level()
	Levels3.current = 0
	Levels3.watch_strategy = ""
	var game = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(game)
	game.rng.seed = 4242
	game.auto_spawn = false # only our hand-placed passengers
	game.to_plan()
	var old_route: Array = ScenData.Scen.path([Vector2i(0, 0), Vector2i(4, 0)])
	game.commit_route(0, old_route)
	var car = game.cars[0]
	out.append(_c("redeploy: PLAN commit deploys instantly",
			car.car_state == Car3.CarState.RUNNING and car.visible,
			"state %d" % car.car_state))
	game.start_run()
	# A rider along the bottom row.
	var p = game.spawn_passenger("visitor", Vector2i(0, 0), Vector2i(4, 0))
	var t := 0.0
	while p.riding != car and t < 60.0:
		game.advance(STEP)
		t += STEP
	out.append(_c("redeploy: smoke rider boarded", p.riding == car,
			"riding %s after %.1fs" % [str(p.riding), t]))
	game.advance(3.0) # doors finish (~1.8 s) and the car gets rolling mid-route
	# The player path is closed during a run: commit_route must REFUSE and
	# change nothing. (This is the v4 rule under test; the recall machinery
	# below is then driven through the explicit mid-run entry point.)
	var refused: bool = not game.commit_route(0,
			ScenData.Scen.path([Vector2i(0, 2), Vector2i(4, 2)]))
	out.append(_c("redeploy: commit_route refused during a run",
			refused and game.routes[0].cells == old_route
			and car.car_state == Car3.CarState.RUNNING,
			"refused %s state %d" % [str(refused), car.car_state]))
	# Mid-run redraw to a DIFFERENT start while the rider is aboard.
	var new_route: Array = ScenData.Scen.path([Vector2i(0, 4), Vector2i(4, 4)])
	game.commit_route_mid_run(0, new_route)
	out.append(_c("redeploy: commit with riders aboard recalls first",
			car.car_state == Car3.CarState.RECALLING,
			"state %d" % car.car_state))
	t = 0.0
	while car.car_state == Car3.CarState.RECALLING and t < 60.0:
		game.advance(STEP)
		t += STEP
	var old_stops: Array = []
	for c in old_route:
		if Grid3.is_room(c):
			old_stops.append(c)
	var dropped: bool = (not is_instance_valid(p)) \
			or (p.riding == null and old_stops.has(p.cur_cell))
	out.append(_c("redeploy: rider dropped at an old-route room", dropped,
			"cur_cell %s" % (str(p.cur_cell) if is_instance_valid(p) else "served")))
	out.append(_c("redeploy: car absent from grid during countdown",
			car.car_state == Car3.CarState.REDEPLOYING and not car.on_grid()
			and car.current_cell() == Vector2i(-1, -1),
			"state %d" % car.car_state))
	t = 0.0
	while car.car_state == Car3.CarState.REDEPLOYING and t < 10.0:
		game.advance(STEP)
		t += STEP
	out.append(_c("redeploy: countdown lasts ~3 s", t >= 2.8 and t <= 3.4,
			"%.1fs" % t))
	out.append(_c("redeploy: service resumes from the new start",
			car.car_state == Car3.CarState.RUNNING
			and car.current_cell() == Vector2i(0, 4),
			"state %d cell %s" % [car.car_state, str(car.current_cell())]))
	# The redeployed route must actually serve someone.
	var p2 = game.spawn_passenger("visitor", Vector2i(0, 4), Vector2i(4, 4))
	t = 0.0
	while is_instance_valid(p2) and p2.active and t < 60.0:
		game.advance(STEP)
		t += STEP
	out.append(_c("redeploy: new route serves a rider",
			not is_instance_valid(p2) or not p2.active, "still waiting after %.1fs" % t))
	tree.root.remove_child(game)
	game.free()
	Levels3.injected = null
	return out


# ---------------------------------------------------------- v3.4 loop checks

## Unit + integration checks for closed (loop) routes, all driven through the
## REAL editing path (select_card -> _begin_stroke -> stroke_try_extend ->
## _end_stroke) and real game ticks:
## - closing detection (>= 4 cells + head adjacency; 3-cell strokes cannot
##   close), forward drags ignored while closed, no retract while closed,
##   reopen by reversing onto the tail, backtrack after reopening;
## - a closed car advances forward-only, wraps the n-1 -> 0 seam smoothly;
## - directional ride_dist (a->b short implies b->a = n - short);
## - backward demand priced as almost-a-full-lap;
## - recall on a loop drives FORWARD to the nearest stop.
func _loop_mechanics(tree: SceneTree) -> Array:
	var out: Array = []
	# --- Stage A: the minimal 4-cell square, the size guard and the magnetic
	# head. These test the DRAWING CODE, not any level, so they run on an
	# injected 5x5 open room (Levels3.injected) instead of borrowing whichever
	# shipped level happens to have an open corner this month - level geometry
	# is redesigned far more often than main3's stroke logic.
	Levels3.injected = _draw_level()
	Levels3.current = 0
	Levels3.watch_strategy = ""
	var g1 = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g1)
	g1.rng.seed = 11
	g1.auto_spawn = false
	g1.to_plan() # drawing is a PLAN-phase action in v4
	g1.select_card(0)
	# Size guard: a 3-cell stroke whose last cell touches the head must NOT
	# close (grid parity makes this stroke undrawable, so it is planted
	# directly â€” the guard is what is under test).
	g1.drawing = true
	g1.stroke = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	g1.stroke_closed = false
	var tri: bool = g1.stroke_try_extend(Vector2i(0, 0))
	out.append(_c("loop: 3-cell stroke cannot close",
			not tri and not g1.stroke_closed, "closed %s" % str(g1.stroke_closed)))
	# The smallest legal loop: a 2x2 square drawn through the real path.
	g1._begin_stroke(Grid3.cell_center(Vector2i(0, 0)))
	g1.stroke_try_extend(Vector2i(1, 0))
	g1.stroke_try_extend(Vector2i(1, 1))
	g1.stroke_try_extend(Vector2i(0, 1))
	var sq: bool = g1.stroke_try_extend(Vector2i(0, 0))
	out.append(_c("loop: 4-cell stroke closes onto its head",
			sq and g1.stroke_closed, "closed %s" % str(g1.stroke_closed)))
	g1._end_stroke()
	out.append(_c("loop: release commits the closed flag",
			g1.routes[0] != null and g1.routes[0].closed,
			"route %s" % ("null" if g1.routes[0] == null else "open")))
	# --- Magnetic retract (head slides back along the path to the finger,
	# speed-independent). Strokes planted directly; the retract phase resolves
	# before any passability check, so cases (1),(2),(4),(5) are grid-free.
	g1.drawing = true
	# (1) Straight snap: E->F reversed onto E leaves just E.
	g1.stroke = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	g1.stroke_closed = false
	var snap: bool = g1.stroke_try_extend(Vector2i(0, 0))
	out.append(_c("retract: straight run snaps back to start",
			snap and g1.stroke.size() == 1, "size %d" % g1.stroke.size()))
	# (2) Corner slide: A->E->east, finger to A unwinds round the bend to A.
	g1.stroke = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]
	g1.stroke_closed = false
	var slide: bool = g1.stroke_try_extend(Vector2i(0, 0))
	out.append(_c("retract: corner slides back to start",
			slide and g1.stroke.size() == 1, "size %d" % g1.stroke.size()))
	# (3) T-junction: finger pulls off the last leg back to the junction; the
	# dropped leg's cells are gone and the junction cell remains (extension
	# toward the finger may add fresh cells, so assert on the dropped leg).
	g1.stroke = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
			Vector2i(0, 3), Vector2i(0, 4)]
	g1.stroke_closed = false
	g1.stroke_try_extend(Vector2i(2, 2))
	out.append(_c("retract: reroutes to the junction, dropping the old leg",
			g1.stroke.find(Vector2i(0, 4)) == -1
			and g1.stroke.find(Vector2i(0, 3)) == -1
			and g1.stroke.find(Vector2i(0, 2)) != -1,
			"cells %s" % str(g1.stroke)))
	# (4) Sideways graze of a looped-back path: the head may draw ON toward the
	# finger (that is the forward pull), but it must never EAT the drawn path,
	# and it can never enter the grazed cell itself.
	var looped := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
			Vector2i(2, 1), Vector2i(2, 2), Vector2i(1, 2)]
	g1.stroke = looped.duplicate()
	g1.stroke_closed = false
	g1.stroke_try_extend(Vector2i(0, 0))
	var kept := true
	for i in looped.size():
		if i >= g1.stroke.size() or g1.stroke[i] != looped[i]:
			kept = false
	out.append(_c("graze: sideways pass never eats the drawn path",
			kept and g1.stroke.back() != Vector2i(0, 0),
			"cells %s" % str(g1.stroke)))
	# (5) Plain one-step reverse still retracts.
	g1.stroke = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	g1.stroke_closed = false
	var one: bool = g1.stroke_try_extend(Vector2i(1, 0))
	out.append(_c("retract: single-step reverse still retracts",
			one and g1.stroke.size() == 2, "size %d" % g1.stroke.size()))
	# --- Magnetic EXTEND (the same pull, outbound). L1's grid is fully open,
	# so these exercise the walk itself rather than any level's geometry.
	# (6) Straight skip forward fills the gap cell by cell.
	g1.stroke = [Vector2i(0, 0)]
	g1.stroke_closed = false
	var fill: bool = g1.stroke_try_extend(Vector2i(0, 3))
	out.append(_c("extend: straight skip fills the run",
			fill and g1.stroke == [Vector2i(0, 0), Vector2i(0, 1),
					Vector2i(0, 2), Vector2i(0, 3)], "cells %s" % str(g1.stroke)))
	# (7) Diagonal drag turns a corner on its own, longest axis first.
	g1.stroke = [Vector2i(0, 0)]
	g1.stroke_closed = false
	var lshape: bool = g1.stroke_try_extend(Vector2i(2, 1))
	out.append(_c("extend: diagonal drag turns a corner",
			lshape and g1.stroke == [Vector2i(0, 0), Vector2i(1, 0),
					Vector2i(2, 0), Vector2i(2, 1)], "cells %s" % str(g1.stroke)))
	# (8) The walk never crosses its own body: it stops rather than teleporting.
	g1.stroke = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	g1.stroke_closed = false
	g1.stroke_try_extend(Vector2i(0, 0)) # retracts to the start...
	g1.stroke = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 2)]
	g1.stroke_closed = false
	g1.stroke_try_extend(Vector2i(0, 0)) # ...finger past the far side of the tail
	out.append(_c("extend: walk stops at its own body, never jumps it",
			not g1.stroke.has(Vector2i(0, 0)) or g1.stroke.size() <= 6,
			"cells %s" % str(g1.stroke)))
	tree.root.remove_child(g1)
	g1.free()
	Levels3.injected = null
	# --- Stage B (L4 ring): full closing UX + movement + pathfinding.
	Levels3.current = Levels3.index_of("L4")
	Levels3.watch_strategy = ""
	var g = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g)
	g.rng.seed = 777
	g.auto_spawn = false
	g.to_plan()
	g.select_card(0)
	var ring: Array = ScenData.Scen.path([Vector2i(0, 0), Vector2i(7, 0),
			Vector2i(7, 7), Vector2i(0, 7), Vector2i(0, 1)])
	g._begin_stroke(Grid3.cell_center(ring[0]))
	for k in range(1, ring.size()):
		g.stroke_try_extend(ring[k])
	out.append(_c("loop: 28-cell ring stroke drawn", g.stroke.size() == 28,
			"size %d" % g.stroke.size()))
	var cl: bool = g.stroke_try_extend(Vector2i(0, 0))
	out.append(_c("loop: ring stroke closes", cl and g.stroke_closed,
			"closed %s" % str(g.stroke_closed)))
	var fwd: bool = g.stroke_try_extend(Vector2i(1, 0))
	out.append(_c("loop: forward drags ignored while closed",
			not fwd and g.stroke_closed and g.stroke.size() == 28,
			"size %d closed %s" % [g.stroke.size(), str(g.stroke_closed)]))
	var retr: bool = g.stroke_try_extend(g.stroke[g.stroke.size() - 2])
	out.append(_c("loop: cannot retract while closed",
			not retr and g.stroke.size() == 28, "size %d" % g.stroke.size()))
	var ro: bool = g.stroke_try_extend(Vector2i(0, 1)) # the tail cell
	out.append(_c("loop: reversing onto the tail reopens",
			ro and not g.stroke_closed and g.stroke.size() == 28,
			"closed %s size %d" % [str(g.stroke_closed), g.stroke.size()]))
	var back: bool = g.stroke_try_extend(Vector2i(0, 2)) # normal backtrack resumes
	out.append(_c("loop: backtrack retracts after reopening",
			back and g.stroke.size() == 27, "size %d" % g.stroke.size()))
	g.stroke_try_extend(Vector2i(0, 1)) # redraw the tail...
	g.stroke_try_extend(Vector2i(0, 0)) # ...close again...
	g._end_stroke() # ...and commit (session-start: deploys instantly)
	var r0 = g.routes[0]
	out.append(_c("loop: committed ring is a closed 8-stop loop",
			r0 != null and r0.closed and r0.cells.size() == 28
			and r0.stop_cells().size() == 8,
			"null" if r0 == null else "closed %s stops %d" % [
					str(r0.closed), r0.stop_cells().size()]))
	# Directional ride_dist: forward short, and a->b + b->a == n for ALL
	# distinct stop pairs.
	var n: int = r0.cells.size()
	out.append(_c("loop: ride_dist forward-only ((ib-ia) mod n)",
			is_equal_approx(r0.ride_dist(Vector2i(0, 0), Vector2i(5, 0)),
					5.0 * Grid3.CELL)
			and is_equal_approx(r0.ride_dist(Vector2i(5, 0), Vector2i(0, 0)),
					23.0 * Grid3.CELL),
			"fwd %.0f bwd %.0f" % [r0.ride_dist(Vector2i(0, 0), Vector2i(5, 0)),
					r0.ride_dist(Vector2i(5, 0), Vector2i(0, 0))]))
	var ident := true
	var stops: Array = r0.stop_cells()
	for i in stops.size():
		for j in range(i + 1, stops.size()):
			if not is_equal_approx(r0.ride_dist(stops[i], stops[j])
					+ r0.ride_dist(stops[j], stops[i]), n * Grid3.CELL):
				ident = false
	out.append(_c("loop: ride_dist identity a->b + b->a == n (all stop pairs)",
			ident, "n %d" % n))
	# A passenger with backward demand prices the long way (single loop car:
	# the only plan is the almost-full lap; it must be honest, not |a-b|).
	var legs = Pathfind3.find_path(Vector2i(5, 0), Vector2i(2, 0), g.cars, -1.0)
	var long_ok: bool = legs != null and not legs.is_empty()
	var legs_dist := 0.0
	if long_ok:
		for leg in legs:
			legs_dist += leg.car.route.ride_dist(leg.board, leg.alight)
		long_ok = legs_dist >= 25.0 * Grid3.CELL - 0.01
	out.append(_c("loop: backward demand priced the long way",
			long_ok, "legs %s dist %.0f" % [
					"none" if legs == null else str(legs.size()), legs_dist]))
	# Closed car wraps forward-only, smoothly across the seam, and actually
	# delivers that backward rider. The plan is committed, so RUN it.
	g.start_run()
	var car = g.cars[0]
	var p = g.spawn_passenger("visitor", Vector2i(5, 0), Vector2i(2, 0))
	var prev_idx: int = car.idx
	var prev_pos: Vector2 = car.position
	var wrapped := false
	var fwd_only := true
	var max_step := 0.0
	var t := 0.0
	while is_instance_valid(p) and p.active and t < 120.0:
		g.advance(STEP)
		t += STEP
		if car.dir != 1 or posmod(car.idx - prev_idx, n) > 1:
			fwd_only = false
		if car.idx < prev_idx:
			wrapped = true
		max_step = maxf(max_step, car.position.distance_to(prev_pos))
		prev_idx = car.idx
		prev_pos = car.position
	out.append(_c("loop: closed car advances forward only", fwd_only, ""))
	out.append(_c("loop: closed car wraps the n-1 -> 0 seam", wrapped, ""))
	out.append(_c("loop: glides across the seam (no position snap)",
			max_step <= car.speed * STEP + 1.0,
			"max step %.1f px vs %.1f" % [max_step, car.speed * STEP]))
	out.append(_c("loop: backward rider served the long way around",
			not is_instance_valid(p) or not p.active,
			"still waiting after %.1fs" % t))
	# Recall on a loop drives FORWARD to the nearest stop (never backwards).
	var p2 = g.spawn_passenger("visitor", Vector2i(2, 0), Vector2i(7, 5))
	t = 0.0
	while p2.riding != car and t < 60.0:
		g.advance(STEP)
		t += STEP
	out.append(_c("loop: recall test rider aboard", p2.riding == car,
			"after %.1fs" % t))
	t = 0.0
	while car.seg_t == 0.0 and t < 30.0: # let it get rolling mid-segment
		g.advance(STEP)
		t += STEP
	var old_r = car.route
	var base: int = posmod(car.idx + (1 if car.seg_t > 0.0 else 0), n)
	var exp_stop := -1
	var best := n + 1
	for s in old_r.stop_indices():
		var dd: int = posmod(s - base, n)
		if dd < best:
			best = dd
			exp_stop = s
	# Mid-run redraw: unreachable from the v4 player flow, so driven straight
	# through the explicit entry point (see _redeploy_smoke's note).
	g.commit_route_mid_run(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(4, 0)]))
	out.append(_c("loop: mid-game redraw with riders recalls",
			car.car_state == Car3.CarState.RECALLING, "state %d" % car.car_state))
	out.append(_c("loop: recall targets the forward-nearest stop",
			car.recall_stop_idx == exp_stop,
			"stop %d expected %d (base %d)" % [car.recall_stop_idx, exp_stop, base]))
	var recall_fwd := true
	t = 0.0
	while car.car_state == Car3.CarState.RECALLING and t < 60.0:
		if car.dir != 1:
			recall_fwd = false
		g.advance(STEP)
		t += STEP
	out.append(_c("loop: recall drives forward (never reverses)", recall_fwd, ""))
	var drop_cell: Vector2i = old_r.cells[exp_stop]
	var dropped: bool = (not is_instance_valid(p2)) \
			or (p2.riding == null and p2.cur_cell == drop_cell)
	out.append(_c("loop: recall drops riders at that forward stop", dropped,
			"cur_cell %s expected %s" % [
					str(p2.cur_cell) if is_instance_valid(p2) else "served",
					str(drop_cell)]))
	tree.root.remove_child(g)
	g.free()
	return out


# ------------------------------------------------- v3.5 depth-tool plumbing

## CHEAP unit checks for the machinery the depth tools (tools/) stand on. The
## heavy search itself lives in tools/ and is run by hand — this file stays
## the fast gate, so only three things are covered here:
##   1. Route3.validate accepts legal geometry and rejects each illegal kind
##      (and main3.commit_route actually refuses the illegal one),
##   2. a route GENE decodes to cells that keep its stops, in order,
##   3. an INJECTED level (Levels3.injected) builds and plays.
func _unit_smoke(tree: SceneTree) -> Array:
	var out: Array = []
	var RG = load("res://tools/routegen.gd")
	# --- 1. validator, on L4's ring (the only level with a legal loop).
	Grid3.load_level(Levels3.get_level(Levels3.index_of("L4")).rows)
	var ring: Array = ScenData.Scen.path([Vector2i(0, 0), Vector2i(7, 0),
			Vector2i(7, 7), Vector2i(0, 7), Vector2i(0, 1)])
	out.append(_c("validate: legal open route accepted",
			Route3.validate(ring, false) == "", Route3.validate(ring, false)))
	out.append(_c("validate: legal closed loop accepted",
			Route3.validate(ring, true) == "", Route3.validate(ring, true)))
	var cases := [
		["1 cell", [Vector2i(0, 0)], false],
		["non-adjacent step", [Vector2i(0, 0), Vector2i(3, 0)], false],
		["duplicate cell", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0)], false],
		["blocked cell", [Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2)], false],
		["3-cell loop", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], true],
		["loop head/tail apart", ring.slice(0, 8), true],
	]
	for c in cases:
		out.append(_c("validate: rejects %s" % c[0],
				Route3.validate(c[1], c[2]) != "", "accepted"))
	# commit_route must refuse the same geometry instead of driving nonsense.
	Levels3.current = Levels3.index_of("L4")
	Levels3.watch_strategy = ""
	var g = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g)
	g.auto_spawn = false
	g.to_plan()
	var refused: bool = not g.commit_route(0, [Vector2i(0, 0), Vector2i(4, 0)])
	out.append(_c("commit_route rejects illegal geometry",
			refused and g.routes[0] == null, "route %s" % str(g.routes[0])))
	out.append(_c("commit_route still accepts legal geometry",
			g.commit_route(0, ring, true) and g.routes[0] != null and g.routes[0].closed,
			"rejected"))
	# --- 2. gene decode round-trip: every stop survives, in order.
	var stops: Array = [Vector2i(2, 0), Vector2i(5, 0), Vector2i(7, 5), Vector2i(0, 5)]
	var dec: Dictionary = RG.decode({"stops": stops, "closed": false})
	var got: Array = RG.stops_of_cells(dec.cells)
	var order_ok := true
	var at := -1
	for s in stops:
		var i: int = got.find(s)
		if i <= at:
			order_ok = false
		at = i
	out.append(_c("gene decode: legal cells + stops kept in order",
			dec.err == "" and order_ok, "err '%s' got %s" % [dec.err, str(got)]))
	var dec_bad: Dictionary = RG.decode({"stops": [Vector2i(0, 0)], "closed": false})
	out.append(_c("gene decode: 1-stop gene is invalid, not a crash",
			dec_bad.err != "", "accepted"))
	tree.root.remove_child(g)
	g.free()
	# --- 3. an injected (generated) level builds and plays.
	Levels3.injected = _injected_level()
	Levels3.current = 0
	var gi = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(gi)
	gi.rng.seed = 31337
	gi.endless = true
	# Commit in the opening phase, then run (to_plan() would clear `endless`).
	gi.commit_route(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(0, 3)]))
	gi.commit_route(1, ScenData.Scen.path([Vector2i(2, 0), Vector2i(2, 3)]))
	gi.start_run()
	for _t in 900:
		gi.advance(0.1)
	out.append(_c("injected level builds and serves",
			gi.level.id == "GEN" and gi.served > 0,
			"id %s served %d" % [str(gi.level.get("id", "?")), gi.served]))
	tree.root.remove_child(gi)
	gi.free()
	Levels3.injected = null
	return out


# ------------------------------------------------- v4 phase 2 mechanics
#
# WIDTH, ACCELERATION and the HOME FLOOR, each checked on a purpose-built
# injected fixture rather than on a shipped level - these are rules of the
# simulation, and they must keep holding while levels are redesigned around
# them. Everything here is deterministic: fixed seeds, no auto-spawn, hand
# placed parties.

## The width fixture: a 7x3 hall with rooms at both ends and a WIDTH-2
## corridor ("22") in the middle, carrying one pod, one standard and one cargo
## car. Wide enough to express every width rule in one level.
func _width_level() -> Dictionary:
	var lv := _injected_level()
	lv.id = "WID"
	lv.rows = ["R.....R", "..22...", "R.....R"]
	lv.cards = [
		{"name": "POD", "type": "pod", "color": Color(0.45, 0.68, 0.95)},
		{"name": "STANDARD", "type": "standard", "color": Color(0.5, 0.88, 0.55)},
		{"name": "CARGO", "type": "cargo", "color": Color(0.98, 0.68, 0.2)},
	]
	lv.groups = {"low": [Vector2i(0, 0), Vector2i(6, 0)],
			"high": [Vector2i(0, 2), Vector2i(6, 2)]}
	return lv


## Width: the boarding rule, the capacity accounting and the corridor algebra.
func _width_checks(tree: SceneTree) -> Array:
	var out: Array = []
	Levels3.injected = _width_level()
	Levels3.current = 0
	Levels3.watch_strategy = ""
	var g = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g)
	g.rng.seed = 8080
	g.auto_spawn = false
	g.to_plan()
	var pod = g.cars[0]
	var std = g.cars[1]
	var cargo = g.cars[2]
	out.append(_c("width: the card table builds pod 1/2, standard 2/4, cargo 3/6",
			pod.width == 1 and pod.capacity == 2 and std.width == 2
			and std.capacity == 4 and cargo.width == 3 and cargo.capacity == 6,
			"%d/%d %d/%d %d/%d" % [pod.width, pod.capacity, std.width,
					std.capacity, cargo.width, cargo.capacity]))
	out.append(_c("width: a width-3 party fits only the cargo car",
			not pod.fits(3) and not std.fits(3) and cargo.fits(3)
			and std.fits(2) and not pod.fits(2) and pod.fits(1),
			"pod %s std %s cargo %s" % [str(pod.fits(3)), str(std.fits(3)),
					str(cargo.fits(3))]))
	# --- The corridor: two pods share a width-2 tunnel; a standard then does
	# not fit beside them; a cargo can never be in it at all.
	var gi := Grid3.gate_group_of(Vector2i(2, 1))
	out.append(_c("width: the '22' corridor is one group of width 2",
			gi == 0 and Grid3.gate_group_width(gi) == 2
			and Grid3.gate_groups()[gi].size() == 2,
			"group %d width %d" % [gi, Grid3.gate_group_width(gi)]))
	var pod_b = Car3.new()
	pod_b.setup(g, 0, Levels3.injected.cards[0])
	out.append(_c("corridor: two pods share a width-2 corridor",
			g.gate_request(pod, gi) and g.gate_request(pod_b, gi)
			and g.gates[gi].used == 2 and g.gates[gi].holders.size() == 2,
			"used %d" % g.gates[gi].used))
	out.append(_c("corridor: a standard cannot squeeze in beside them",
			not g.gate_request(std, gi), "admitted"))
	g.gate_cancel(pod)
	g.gate_cancel(pod_b)
	g.gate_cancel(std)
	out.append(_c("corridor: releasing both pods frees the whole width",
			g.gates[gi].used == 0 and g.gates[gi].holders.is_empty(),
			"used %d" % g.gates[gi].used))
	out.append(_c("corridor: a cargo car never fits a width-2 corridor",
			not g.gate_request(cargo, gi) and not g.gate_free_for(cargo, gi)
			and g.gates[gi].queue.is_empty(), # and does not even queue for it
			"admitted or queued"))
	pod_b.free()
	# ...and a route that would send it there is refused outright, with the
	# geometry-only validator still accepting the same cells.
	var through: Array = ScenData.Scen.path([Vector2i(2, 0), Vector2i(2, 2)])
	out.append(_c("corridor: geometry-only validation ignores width",
			Route3.validate(through, false) == "", Route3.validate(through, false)))
	out.append(_c("corridor: committing the cargo car through it is refused",
			not g.commit_route(2, through) and g.routes[2] == null,
			"accepted"))
	# The refusal is not silent: it parks a reason (naming the width shortfall)
	# that hud3 surfaces on the hint line, and it leaves the card unrouted.
	out.append(_c("corridor: a refused commit surfaces the reason and leaves the card unrouted",
			g.reject_card == 2 and g.reject_msg.findn("width") != -1
			and g.reject_until_ms > Time.get_ticks_msec() - 1 and g.routes[2] == null,
			"card %d msg '%s' route %s" % [g.reject_card, g.reject_msg, str(g.routes[2])]))
	# The magnetic drawing head feels the same corridor as a wall for the cargo
	# car (a too-narrow gate cell is not drawable), but is drawable for the pod.
	g.select_card(2)
	var cargo_blocked: bool = not g._drawable(Vector2i(2, 1))
	g.select_card(2) # deselect
	g.select_card(0)
	var pod_ok: bool = g._drawable(Vector2i(2, 1))
	g.select_card(0) # deselect
	out.append(_c("corridor: the magnetic head walls the cargo out but lets the pod in",
			cargo_blocked and pod_ok,
			"cargo blocked %s pod ok %s" % [str(cargo_blocked), str(pod_ok)]))
	out.append(_c("corridor: the pod may take the same line",
			g.commit_route(0, through) and g.routes[0] != null, "refused"))
	# --- Boarding + capacity, in width-units, through the real planner.
	g.commit_route(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(0, 2)]))
	g.commit_route(1, ScenData.Scen.path([Vector2i(0, 0), Vector2i(0, 2)]))
	g.start_run()
	var big = g.spawn_passenger("big delivery", Vector2i(0, 0), Vector2i(0, 2))
	out.append(_c("width: a width-3 party will not plan onto width-1/2 cars",
			big.legs.is_empty() and big.no_path, "legs %d" % big.legs.size()))
	var pair = g.spawn_passenger("couple", Vector2i(0, 0), Vector2i(0, 2))
	var pair_car = null if pair.legs.is_empty() else pair.legs[0].car
	out.append(_c("width: a width-2 couple plans onto the standard, not the pod",
			pair_car == std, "car %s" % ("none" if pair_car == null else pair_car.card_type)))
	g.abort_run()
	g.commit_route(2, ScenData.Scen.path([Vector2i(0, 0), Vector2i(0, 2)]))
	g.start_run()
	var b2 = g.spawn_passenger("big delivery", Vector2i(0, 0), Vector2i(0, 2))
	var t := 0.0
	while b2.riding == null and t < 60.0:
		g.advance(STEP)
		t += STEP
	out.append(_c("width: the cargo car carries the width-3 party",
			b2.riding == cargo, "riding %s after %.1fs" % [str(b2.riding), t]))
	out.append(_c("capacity: a width-3 rider costs 3 of the cargo's 6 units",
			cargo.used_slots() == 3 and cargo.free_slots() == 3,
			"used %d free %d" % [cargo.used_slots(), cargo.free_slots()]))
	# Fill the rest with a second big delivery, then prove a third cannot fit.
	var b3 = g.spawn_passenger("big delivery", cargo.current_cell(), Vector2i(0, 2))
	t = 0.0
	while b3.riding == null and t < 60.0:
		g.advance(STEP)
		t += STEP
	var full: bool = cargo.used_slots() == 6 and cargo.free_slots() == 0
	out.append(_c("capacity: two width-3 riders fill a cargo car exactly", full,
			"used %d" % cargo.used_slots()))
	tree.root.remove_child(g)
	g.free()
	Levels3.injected = null
	return out


## Acceleration: cars really do ramp and brake, they arrive at their stops AT
## REST, a repeated run is bit-identical, and a coarse `advance(dt)` neither
## overshoots a stop nor changes the answer.
func _accel_checks(tree: SceneTree) -> Array:
	var out: Array = []
	var lv := _injected_level()
	lv.id = "ACC"
	lv.rows = ["...........", "R.........R"] # a long straight: room, ten cells, room
	lv.groups = {"low": [Vector2i(0, 0)], "high": [Vector2i(10, 0)]}
	# The trace: (served, lost, every car's idx/seg_t/vel) at every step.
	var trace := func(step: float, ticks: int) -> String:
		Levels3.injected = lv
		Levels3.current = 0
		Levels3.watch_strategy = ""
		var g = load("res://scenes/v3_main.tscn").instantiate()
		tree.root.add_child(g)
		g.rng.seed = 4711
		g.to_plan()
		g.commit_route(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(10, 0)]))
		g.commit_route(1, ScenData.Scen.path([Vector2i(0, 0), Vector2i(10, 0)]))
		g.commit_route(2, ScenData.Scen.path([Vector2i(0, 0), Vector2i(10, 0)]))
		g.start_run()
		var s := ""
		for _k in ticks:
			g.advance(step)
			for c in g.cars:
				s += "%d|%.6f|%.6f;" % [c.idx, c.seg_t, c.vel]
		s += "S%d L%d" % [g.served, g.lost]
		tree.root.remove_child(g)
		g.free()
		Levels3.injected = null
		return s
	var a: String = trace.call(0.1, 600)
	var b: String = trace.call(0.1, 600)
	out.append(_c("accel: a repeated run is bit-identical", a == b,
			"traces differ (%d vs %d chars)" % [a.length(), b.length()]))
	# Engine frame boundaries must not change the answer: the same 60 s of game
	# time, chopped up four different ways, has to serve the same people.
	var served_of := func(s: String) -> String:
		return s.substr(s.find("S"))
	var fine: String = served_of.call(trace.call(0.05, 1200))
	var coarse: String = served_of.call(trace.call(0.25, 240))
	var chunky: String = served_of.call(trace.call(1.0, 60))
	out.append(_c("accel: the outcome does not depend on the step size",
			served_of.call(a) == fine and fine == coarse and coarse == chunky,
			"0.1 %s / 0.05 %s / 0.25 %s / 1.0 %s" % [
					served_of.call(a), fine, coarse, chunky]))
	# A single car on a two-stop line, watched closely.
	Levels3.injected = lv
	Levels3.current = 0
	Levels3.watch_strategy = ""
	var g2 = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g2)
	g2.rng.seed = 99
	g2.auto_spawn = false
	g2.to_plan()
	g2.commit_route(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(10, 0)]))
	g2.start_run()
	var car = g2.cars[0]
	g2.spawn_passenger("visitor", Vector2i(0, 0), Vector2i(10, 0))
	var top := 0.0
	var ramped := false
	var stopped_at_end := true
	var t := 0.0
	while t < 40.0:
		g2.advance(0.05)
		t += 0.05
		top = maxf(top, car.vel)
		if car.vel > 1.0 and car.vel < car.speed - 1.0:
			ramped = true # caught mid-ramp: it is not a step function
		if car.door_state != Car3.DoorState.CLOSED and car.vel > 0.001:
			stopped_at_end = false # doors open while still rolling
		if car.seg_t < 0.0 or car.seg_t >= Grid3.CELL:
			stopped_at_end = false # overshot a cell boundary
	out.append(_c("accel: the car ramps rather than jumping to top speed",
			ramped and top > 0.0 and top <= car.speed + 0.001,
			"top %.1f of %.1f" % [top, car.speed]))
	out.append(_c("accel: doors only open once the car is at rest",
			stopped_at_end, "doors opened while moving, or a cell was overshot"))
	# The planner has to KNOW about the momentum it now loses: a stop-heavy leg
	# must be priced above bare distance/speed, and a heavier car must pay more
	# per stop than a light one.
	var pen_std: float = g2.cars[0].stop_penalty()
	var pen_fast: float = g2.cars[2].stop_penalty()
	tree.root.remove_child(g2)
	g2.free()
	Levels3.injected = null
	out.append(_c("accel: Pathfind3 prices a stop it has to brake for",
			pen_std > 0.3 and pen_fast > pen_std,
			"standard %.2f s, express %.2f s" % [pen_std, pen_fast]))
	return out


## HOME FLOOR: an idle EMPTY car with a home deadheads to it and waits there;
## without one it parks where it stands. Set and cleared by tapping in PLAN,
## and kept across a RETRY, because it is part of the plan.
func _home_checks(tree: SceneTree) -> Array:
	var out: Array = []
	var lv := _injected_level()
	lv.id = "HOME"
	lv.rows = ["...........", "R.........R"] # a bare gantry over the line
	lv.groups = {"low": [Vector2i(0, 0)], "high": [Vector2i(10, 0)]}
	Levels3.injected = lv
	Levels3.current = 0
	Levels3.watch_strategy = ""
	var g = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g)
	g.rng.seed = 606
	g.auto_spawn = false
	g.to_plan()
	var line: Array = ScenData.Scen.path([Vector2i(0, 0), Vector2i(10, 0)])
	g.commit_route(0, line)
	g.select_card(0)
	var car = g.cars[0]
	out.append(_c("home: a tap off the route sets nothing",
			not g.toggle_home(0, Vector2i(5, 1)) and car.home_cell == null,
			"home %s" % str(car.home_cell)))
	out.append(_c("home: a tap on a route cell sets the home",
			g.toggle_home(0, Vector2i(10, 0)) and car.home_cell == Vector2i(10, 0),
			"home %s" % str(car.home_cell)))
	out.append(_c("home: tapping it again clears it",
			g.toggle_home(0, Vector2i(10, 0)) and car.home_cell == null,
			"home %s" % str(car.home_cell)))
	g.toggle_home(0, Vector2i(10, 0))
	# An idle EMPTY car deadheads home and stays there.
	g.start_run()
	for _k in 600:
		g.advance(0.1)
	out.append(_c("home: an idle empty car deadheads to its home cell",
			car.current_cell() == Vector2i(10, 0) and car.idle,
			"at %s idle %s" % [str(car.current_cell()), str(car.idle)]))
	# RETRY keeps it (it is part of the plan, like the polyline).
	g.abort_run()
	out.append(_c("home: RETRY keeps the home cell",
			car.home_cell == Vector2i(10, 0), "home %s" % str(car.home_cell)))
	# Redrawing somewhere that does not contain it drops it.
	g.commit_route(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(4, 0)]))
	out.append(_c("home: a redraw that strands the home cell clears it",
			car.home_cell == null, "home %s" % str(car.home_cell)))
	# Without a home the car parks wherever it happened to stop.
	g.commit_route(0, line)
	g.start_run()
	for _k in 600:
		g.advance(0.1)
	out.append(_c("home: with no home set the car parks where it is",
			car.current_cell() != Vector2i(10, 0) or car.home_cell == null,
			"at %s" % str(car.current_cell())))
	# Route-set data can carry it, which is how scenarios / watch mode / the
	# depth tools express a home.
	g.abort_run()
	g.commit_route(0, line, false, Vector2i(10, 0))
	out.append(_c("home: commit_route carries a home cell (scenario data)",
			car.home_cell == Vector2i(10, 0), "home %s" % str(car.home_cell)))
	out.append(_c("home: Scenarios3.home_of reads it out of a route entry",
			ScenData.Scen.home_of({"cells": line, "home": Vector2i(3, 0)})
					== Vector2i(3, 0)
			and ScenData.Scen.home_of(line) == null, "home_of disagrees"))
	tree.root.remove_child(g)
	g.free()
	Levels3.injected = null
	return out


func _v4_mechanics(tree: SceneTree) -> Array:
	var out: Array = []
	out.append_array(_width_checks(tree))
	out.append_array(_accel_checks(tree))
	out.append_array(_home_checks(tree))
	return out


## A 5x5 room with nothing in it but four corner rooms: the fixture the
## stroke/magnetic-head checks are drawn on, so they never break when a level
## is redesigned. Rooms only exist so commit_route has something to stop at.
func _draw_level() -> Dictionary:
	var lv := _injected_level()
	lv.id = "DRAW"
	lv.rows = ["R.R.R", ".....", ".....", ".....", "R.R.R"]
	lv.groups = {"low": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0)],
			"high": [Vector2i(0, 4), Vector2i(2, 4), Vector2i(4, 4)]}
	return lv


## A tiny generated level: two shafts joined at top and bottom. Three cards
## because hud3 always builds three chips.
func _injected_level() -> Dictionary:
	return {
		"id": "GEN", "name": "Generated", "thesis": "", "intro": "",
		"rows": ["R.R", ".#.", ".#.", "R.R"],
		"cards": [
			{"name": "A", "type": "standard", "cap": 4, "speed": 260.0,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "B", "type": "standard", "cap": 4, "speed": 260.0,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "C", "type": "express", "cap": 4, "speed": 520.0,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 20, "max_lost": 5,
		"spawn": {"interval_start": 3.0, "interval_end": 2.0, "ramp": 60.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.8},
		"mix": {"visitor": 1.0},
		"exec_origins": [], "exec_dests": [],
		"groups": {"low": [Vector2i(0, 0), Vector2i(2, 0)],
				"high": [Vector2i(0, 3), Vector2i(2, 3)]},
		"trips": [{"w": 0.5, "from": "low", "to": "high"},
				{"w": 0.5, "from": "high", "to": "low"}],
	}


func _c(name: String, ok: bool, detail: String) -> Dictionary:
	return {"name": name, "ok": ok, "detail": detail}
