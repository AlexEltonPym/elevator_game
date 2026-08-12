extends RefCounted
## Determinism fingerprint of the balance scenarios (PERSISTENT tool).
##
## Runs the exact tests/scenarios3.gd list the same way tests/balance.gd does
## (STEP 0.1, TIMEOUT 900, one scenario per engine frame) and prints, per
## scenario, a hash over:
##   result / served / lost / sim time / gate totals,
##   EVERY log_served + log_lost entry (type, origin, dest, wait to 9 dp, rides),
##   EVERY car's final car_state / idx / seg_t / dir / position (9 dp).
##
## This is the HARD GATE for the perf work in docs/depth-tools-spec.md §0.4:
## capture before optimising, capture after, the hashes must be identical.
##
##   & "<godot_console.exe>" --headless --path . --script tools/run_fingerprint.gd
##
## Deliberately does NOT use Route3.validate or any other refactored entry
## point, so the measurement itself cannot drift with the code under test.

const STEP := 0.1
const TIMEOUT := 900.0

const ScenData = preload("res://tests/scenarios3.gd")

var scenarios: Array = ScenData.scenarios()
var next_i := 0
var lines: Array = []
var tick_ms_total := 0.0


func step(tree: SceneTree) -> bool:
	if next_i < scenarios.size():
		lines.append(_run(tree, scenarios[next_i]))
		next_i += 1
		return false
	print("")
	print("============== v3 SCENARIO FINGERPRINTS (STEP %.2f) ==============" % STEP)
	var all := ""
	for l in lines:
		print(l.line)
		all += l.blob
	print("---------------------------------------------------------------")
	print("FINGERPRINT-ALL  %d  len=%d" % [hash(all), all.length()])
	print("TICK-MS-TOTAL    %.1f" % tick_ms_total)
	tree.quit(0)
	return true


func _run(tree: SceneTree, sc: Dictionary) -> Dictionary:
	Levels3.current = Levels3.index_of(sc.level)
	Levels3.watch_strategy = ""
	var game = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(game)
	game.rng.seed = ScenData.Scen.SEEDS[sc.level] # canonical per-level seed
	game.start_session()
	for i in sc.routes.size():
		game.commit_route(i, ScenData.Scen.cells_of(sc.routes[i]),
				ScenData.Scen.closed_of(sc.routes[i]))
	var t := 0.0
	var t0 := Time.get_ticks_usec()
	while game.state == game.State.PLAYING and t < TIMEOUT:
		game.advance(STEP)
		t += STEP
	var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0
	tick_ms_total += tick_ms
	var res := "TIMEOUT"
	if game.state == game.State.WIN:
		res = "WIN"
	elif game.state == game.State.LOSE:
		res = "LOSE"
	var blob := "%s|%s|%d|%d|%.9f|%.9f|%d\n" % [sc.key, res, game.served, game.lost,
			t, game.gate_wait_total(), game.gate_transit_total()]
	for e in game.log_served:
		blob += "S|%s|%d,%d|%d,%d|%.9f|%d\n" % [e.type, e.origin.x, e.origin.y,
				e.dest.x, e.dest.y, e.wait, e.rides]
	for e in game.log_lost:
		blob += "L|%s|%d,%d|%d,%d|%.9f|%d\n" % [e.type, e.origin.x, e.origin.y,
				e.dest.x, e.dest.y, e.wait, e.rides]
	for i in game.cars.size():
		var c = game.cars[i]
		blob += "C|%d|%d|%d|%.9f|%d|%.9f|%.9f\n" % [i, c.car_state, c.idx,
				c.seg_t, c.dir, c.position.x, c.position.y]
	var line := "%-14s %-8s served=%-4d lost=%-3d  hash=%-12d len=%-6d tick=%.1f ms" % [
			sc.key, res, game.served, game.lost, hash(blob), blob.length(), tick_ms]
	tree.root.remove_child(game)
	game.free()
	return {"blob": blob, "line": line}
