extends RefCounted
## v3 balance harness (PERSISTENT deliverable - keep it green).
##
## Runs every scenario from tests/scenarios3.gd headless at high effective
## speed: each scenario instantiates scenes/v3_main.tscn for its level,
## fixes the game RNG seed, commits the scripted routes, then drives
## main3.advance() with fixed 0.1 s steps until win / lose / timeout.
## Collects served, lost, avg wait, avg transfers, gate wait and gate
## transits, prints a per-scenario table plus PASS/FAIL per assertion, and
## exits nonzero on any failure (note: the mono wrapper may turn even a
## clean exit into code 1 - trust the final "BALANCE: ALL PASS" line).
##
## Beyond the per-level win/lose assertions it also:
## - lints EVERY level for dead rooms (each room must have spawn weight > 0,
##   be a possible destination, and be covered by the thesis route set), and
## - smoke-tests the v3.3 redeploy flow (mid-run redraw with riders aboard
##   recalls + redeploys in ~3 s; session-start commits deploy instantly).
##
## Driven by tests/run_balance.gd (one scenario per engine frame so freed
## nodes flush between runs):
##   & "<godot_console.exe>" --headless --path . --script tests/run_balance.gd
##
## Tuning loop: adjust level spawn/patience numbers in scripts/v3/levels3.gd
## (NOT the assertions here) until everything passes.

const STEP := 0.1 # fixed logic step (game-seconds) - keep constant: results are seed-exact
const TIMEOUT := 900.0 # game-seconds per scenario before declaring TIMEOUT

const ScenData = preload("res://tests/scenarios3.gd")

var scenarios: Array = ScenData.scenarios()
var results := {} # key -> stats dict
var next_i := 0
var redeploy_done := false
var redeploy_checks: Array = [] # filled by the redeploy smoke run


## Run one scenario per call (per engine frame). Returns true when finished
## (after printing the report and requesting quit).
func step(tree: SceneTree) -> bool:
	if next_i < scenarios.size():
		var sc: Dictionary = scenarios[next_i]
		results[sc.key] = _run_scenario(tree, sc)
		next_i += 1
		return false
	if not redeploy_done:
		redeploy_done = true
		redeploy_checks = _redeploy_smoke(tree)
		return false
	var ok := _report()
	tree.quit(0 if ok else 1)
	return true


# ---------------------------------------------------------------- running

func _run_scenario(tree: SceneTree, sc: Dictionary) -> Dictionary:
	var li: int = Levels3.index_of(sc.level)
	assert(li >= 0, "unknown level id " + str(sc.level))
	Levels3.current = li
	Levels3.watch_strategy = "" # harness commits routes itself
	var game = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(game) # _ready loads the level grid
	var r := {
		"key": sc.key, "level": sc.level, "result": "TIMEOUT",
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
	game.rng.seed = sc.seed
	game.start_session()
	for i in sc.routes.size():
		game.commit_route(i, sc.routes[i])
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


## "" when `cells` is a legal polyline on the CURRENT level's maze.
func _route_error(cells: Array) -> String:
	if cells.size() < 2:
		return "fewer than 2 cells"
	var seen := {}
	for k in cells.size():
		var c: Vector2i = cells[k]
		if not Grid3.passable(c):
			return "cell %s not passable" % str(c)
		if seen.has(c):
			return "cell %s visited twice" % str(c)
		seen[c] = true
		if k > 0:
			var d: Vector2i = c - cells[k - 1]
			if absi(d.x) + absi(d.y) != 1:
				return "cells %s -> %s not adjacent" % [str(cells[k - 1]), str(c)]
	return ""


## Share of served origin-group -> dest-group passengers that used >= 2 legs.
func _transfer_share(r: Dictionary, from_cells: Array, to_cells: Array) -> float:
	var total := 0
	var multi := 0
	for e in r.log_served:
		if e.origin in from_cells and e.dest in to_cells:
			total += 1
			if e.rides >= 2:
				multi += 1
	if total == 0:
		return 0.0
	return float(multi) / float(total)


# ---------------------------------------------------------------- reporting

func _report() -> bool:
	print("")
	print("===================== v3 BALANCE HARNESS =====================")
	print("%-14s %-8s %8s %8s %9s %9s %10s %10s %8s" % [
			"scenario", "result", "served", "lost", "avg wait", "p90 wait",
			"transfers", "gate wait", "transits"])
	for sc in scenarios:
		var r: Dictionary = results[sc.key]
		print("%-14s %-8s %5d/%-3d %5d/%-3d %8.1fs %8.1fs %10.2f %9.1fs %8d" % [
				r.key, r.result, r.served, r.quota, r.lost, r.max_lost,
				r.avg_wait, r.p90_wait, r.avg_transfers, r.gate_wait,
				r.gate_transits])
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
		if results[sc.key].route_error != "":
			out.append({"name": sc.key + " routes valid", "ok": false,
					"detail": results[sc.key].route_error})
	# Every playable level: naive LOSES (hits max_lost before quota) while
	# the intended (thesis) strategy WINS with lost <= 3.
	for id in ["L1", "L2", "L3"]:
		var ri: Dictionary = results["%s_intended" % id]
		var rn: Dictionary = results["%s_naive" % id]
		out.append(_c("%s intended wins quota" % id, ri.result == "WIN",
				"result " + ri.result))
		out.append(_c("%s intended lost <= 3" % id, ri.lost <= 3, "lost %d" % ri.lost))
		out.append(_c("%s naive loses before quota" % id, rn.result == "LOSE",
				"result %s, served %d, lost %d" % [rn.result, rn.served, rn.lost]))
	var l2i: Dictionary = results.L2_intended
	var l2n: Dictionary = results.L2_naive
	out.append(_c("L2 naive gate wait >= 3x intended",
			l2n.gate_wait >= 3.0 * l2i.gate_wait,
			"naive %.1fs vs intended %.1fs" % [l2n.gate_wait, l2i.gate_wait]))
	out.append(_c("L2 intended gate transits >= 10", l2i.gate_transits >= 10,
			"transits %d" % l2i.gate_transits))
	var l3i: Dictionary = results.L3_intended
	var l3_level: Dictionary = Levels3.get_level(Levels3.index_of("L3"))
	var share := _transfer_share(l3i, l3_level.groups.arms, l3_level.groups.pent)
	out.append(_c("L3 arm->penthouse 2-leg share >= 40%", share >= 0.4,
			"share %.0f%%" % (share * 100.0)))
	var x1: Dictionary = results.X1_smoke
	out.append(_c("X-1 winnable by old smoke strategy", x1.result == "WIN",
			"result %s, served %d, lost %d" % [x1.result, x1.served, x1.lost]))
	out.append_array(_lint_levels())
	out.append_array(redeploy_checks)
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
		for row in lv.trips:
			if row.w <= 0.0:
				continue
			for c in lv.groups[row.from]:
				origins[c] = true
			for c in lv.groups[row.to]:
				dests[c] = true
		var covered := {}
		for cells in ScenData.Scen.route_set(lv.id, "thesis"):
			for c in cells:
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
	return out


# ---------------------------------------------------------- redeploy smoke

## Mid-run route replacement with riders aboard must RECALL (drop the riders
## at an old-route room stop, not teleport them), keep the car off the grid
## for a ~3 s ghost countdown at the new start, then resume service there.
## Session-start commits (never-deployed cars) must deploy with no delay.
func _redeploy_smoke(tree: SceneTree) -> Array:
	var out: Array = []
	Levels3.current = Levels3.index_of("L1")
	Levels3.watch_strategy = ""
	var game = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(game)
	game.rng.seed = 4242
	game.auto_spawn = false # only our hand-placed passengers
	game.start_session()
	var old_route: Array = ScenData.Scen.path(
			[Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 5)])
	game.commit_route(0, old_route)
	var car = game.cars[0]
	out.append(_c("redeploy: session-start commit deploys instantly",
			car.car_state == Car3.CarState.RUNNING and car.visible,
			"state %d" % car.car_state))
	# A rider from the lobby up the side column.
	var p = game.spawn_passenger("visitor", Vector2i(2, 0), Vector2i(1, 5))
	var t := 0.0
	while p.riding != car and t < 60.0:
		game.advance(STEP)
		t += STEP
	out.append(_c("redeploy: smoke rider boarded", p.riding == car,
			"riding %s after %.1fs" % [str(p.riding), t]))
	game.advance(3.0) # doors finish (~1.8 s) and the car gets rolling mid-route
	# Mid-run redraw to a DIFFERENT start while the rider is aboard.
	var new_route: Array = ScenData.Scen.path([Vector2i(1, 6), Vector2i(1, 8)])
	game.commit_route(0, new_route)
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
			and car.current_cell() == Vector2i(1, 6),
			"state %d cell %s" % [car.car_state, str(car.current_cell())]))
	# The redeployed route must actually serve someone.
	var p2 = game.spawn_passenger("visitor", Vector2i(1, 6), Vector2i(1, 8))
	t = 0.0
	while is_instance_valid(p2) and p2.active and t < 60.0:
		game.advance(STEP)
		t += STEP
	out.append(_c("redeploy: new route serves a rider",
			not is_instance_valid(p2) or not p2.active, "still waiting after %.1fs" % t))
	tree.root.remove_child(game)
	game.free()
	return out


func _c(name: String, ok: bool, detail: String) -> Dictionary:
	return {"name": name, "ok": ok, "detail": detail}
