extends RefCounted
## v3 balance harness (PERSISTENT deliverable - keep it green).
##
## Runs every scenario from tests/scenarios3.gd headless at high effective
## speed: each scenario instantiates scenes/v3_main.tscn for its level,
## fixes the game RNG seed, commits the scripted routes, then drives
## main3.advance() with fixed 0.1 s steps until win / lose / timeout.
## Collects served, lost, avg wait, avg transfers and gate wait, prints a
## per-scenario table plus PASS/FAIL per assertion, and exits nonzero on any
## failure (note: the mono wrapper may turn even a clean exit into code 1 -
## trust the final "BALANCE: ALL PASS" line).
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


## Run one scenario per call (per engine frame). Returns true when finished
## (after printing the report and requesting quit).
func step(tree: SceneTree) -> bool:
	if next_i < scenarios.size():
		var sc: Dictionary = scenarios[next_i]
		results[sc.key] = _run_scenario(tree, sc)
		next_i += 1
		return false
	var ok := _report()
	tree.quit(0 if ok else 1)
	return true


# ---------------------------------------------------------------- running

func _run_scenario(tree: SceneTree, sc: Dictionary) -> Dictionary:
	var li: int = Levels3.index_of(sc.level)
	assert(li >= 0, "unknown level id " + str(sc.level))
	Levels3.current = li
	var game = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(game) # _ready loads the level grid
	var r := {
		"key": sc.key, "level": sc.level, "result": "TIMEOUT",
		"served": 0, "lost": 0, "time": 0.0, "avg_wait": 0.0, "p90_wait": 0.0,
		"avg_transfers": 0.0, "gate_wait": 0.0, "quota": game.QUOTA,
		"max_lost": game.MAX_LOST, "log_served": [], "route_error": "",
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
	print("================ v3 BALANCE HARNESS ================")
	print("%-14s %-8s %8s %8s %9s %9s %10s %10s" % [
			"scenario", "result", "served", "lost", "avg wait", "p90 wait",
			"transfers", "gate wait"])
	for sc in scenarios:
		var r: Dictionary = results[sc.key]
		print("%-14s %-8s %5d/%-3d %5d/%-3d %8.1fs %8.1fs %10.2f %9.1fs" % [
				r.key, r.result, r.served, r.quota, r.lost, r.max_lost,
				r.avg_wait, r.p90_wait, r.avg_transfers, r.gate_wait])
	print("----------------------------------------------------")
	var checks := _checks()
	var ok := true
	for c in checks:
		var mark: String = "PASS" if c.ok else "FAIL"
		print("[%s] %s%s" % [mark, c.name, "" if c.ok else "  (" + c.detail + ")"])
		ok = ok and c.ok
	print("----------------------------------------------------")
	print("BALANCE: ALL PASS" if ok else "BALANCE: FAILURES PRESENT")
	return ok


func _checks() -> Array:
	var out: Array = []
	for sc in scenarios:
		if results[sc.key].route_error != "":
			out.append({"name": sc.key + " routes valid", "ok": false,
					"detail": results[sc.key].route_error})
	var l1i: Dictionary = results.L1_intended
	var l1n: Dictionary = results.L1_naive
	out.append(_c("L1 intended wins quota", l1i.result == "WIN",
			"result " + l1i.result))
	out.append(_c("L1 intended lost <= 2", l1i.lost <= 2, "lost %d" % l1i.lost))
	out.append(_c("L1 naive loses before quota", l1n.result == "LOSE",
			"result %s, served %d, lost %d" % [l1n.result, l1n.served, l1n.lost]))
	var l2i: Dictionary = results.L2_intended
	var l2n: Dictionary = results.L2_naive
	out.append(_c("L2 intended wins quota", l2i.result == "WIN",
			"result " + l2i.result))
	out.append(_c("L2 intended lost <= 3", l2i.lost <= 3, "lost %d" % l2i.lost))
	out.append(_c("L2 naive lost >= 2x intended (or loses)",
			l2n.result == "LOSE" or l2n.lost >= 2 * l2i.lost,
			"naive %d vs intended %d" % [l2n.lost, l2i.lost]))
	out.append(_c("L2 naive gate wait >= 2x intended",
			l2n.gate_wait >= 2.0 * l2i.gate_wait,
			"naive %.1fs vs intended %.1fs" % [l2n.gate_wait, l2i.gate_wait]))
	var l3i: Dictionary = results.L3_intended
	var l3n: Dictionary = results.L3_naive
	var l3_level: Dictionary = Levels3.get_level(Levels3.index_of("L3"))
	var share := _transfer_share(l3i, l3_level.groups.arms, l3_level.groups.pent)
	out.append(_c("L3 intended wins quota", l3i.result == "WIN",
			"result " + l3i.result))
	out.append(_c("L3 intended lost <= 3", l3i.lost <= 3, "lost %d" % l3i.lost))
	out.append(_c("L3 arm->penthouse 2-leg share >= 40%", share >= 0.4,
			"share %.0f%%" % (share * 100.0)))
	out.append(_c("L3 naive worse on lost count", l3n.lost > l3i.lost,
			"naive %d vs intended %d" % [l3n.lost, l3i.lost]))
	var x1: Dictionary = results.X1_smoke
	out.append(_c("X-1 winnable by old smoke strategy", x1.result == "WIN",
			"result %s, served %d, lost %d" % [x1.result, x1.served, x1.lost]))
	return out


func _c(name: String, ok: bool, detail: String) -> Dictionary:
	return {"name": name, "ok": ok, "detail": detail}
