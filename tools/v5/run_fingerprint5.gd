extends SceneTree
## Determinism fingerprint of the v5 "Rooms" sim (PERSISTENT tool, Phase 0 of
## docs/v5-transition-spec.md §5.3). The v5 analogue of tools/run_fingerprint.gd:
## it promotes tests/v5_smoke.gd's per-step position/served/lost signature to a
## real, hashable baseline over R-1..R-6.
##
##   & "<godot_console.exe>" --headless --path . --script tools/v5/run_fingerprint5.gd
##
## For each level it instantiates scenes/v5_main.tscn headless, commits the SAME
## hand solution the smoke uses, runs it to WIN/LOSE/timeout at a fixed seed and
## STEP, and hashes, per level:
##   result / served / lost / sim time,
##   EVERY log_served + log_lost entry (type, wait to 9 dp, rides),
##   a per-STEP signature of served/lost + every car's quantised position,
##   EVERY car's final car_state / idx / seg_t / dir / position (9 dp),
##   the total reactivations.
##
## This is the HARD GATE that the v5 tooling (sim_api5 / routegen5 / optimizers5 /
## metrics5) leaves the SIM byte-identical: capture the hash before building the
## tooling, capture it after, they must match. Like the v4 fingerprint, it
## deliberately does NOT route through any tooling entry point, so the
## measurement itself cannot drift with the code under test.
##
## v5 gets its OWN baseline hash; v4's 3552943357 stays the v4 reference until v4
## is deleted (docs/v5-transition-spec.md §5.1).

const STEP := 0.1
const CAP := 600.0 # game-seconds budget per level (matches v5_smoke.CAP)

# Fixed per-level seeds: distinct, stable, and independent of the smoke's so the
# baseline is a property of this tool alone.
const SEEDS := {
	"R-1": 51001, "R-2": 51002, "R-3": 51003,
	"R-4": 51004, "R-5": 51005, "R-6": 51006,
}


func _c(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append(Vector2i(p[0], p[1]))
	return out


## The hand solutions, verbatim from tests/v5_smoke.gd::_solution — the same
## scripted route-sets the smoke drives, so the fingerprint pins the exact
## trajectories the smoke already trusts.
func _solution(id: String) -> Array:
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


func _run(level_index: int, seed_v: int) -> Dictionary:
	Levels5.current = level_index
	Levels5.headless = true
	var lv: Dictionary = Levels5.LEVELS[level_index]
	var node = load("res://scenes/v5_main.tscn").instantiate()
	node.headless = true
	root.add_child(node)   # _ready: loads the maze (headless), builds the cars/HUD
	node.rng.seed = seed_v
	node.to_plan()
	var sol := _solution(str(lv.id))
	for ci in sol.size():
		node.commit_route(ci, sol[ci], false)
	node.start_run()
	var t := 0.0
	var sig := ""
	while t < CAP and node.state == node.State.PLAYING:
		node.advance(STEP)
		t += STEP
		sig += "%d;%d;" % [node.served, node.lost]
		for car in node.cars:
			if car != null:
				sig += "%d,%d|" % [int(round(car.position.x * 1000.0)),
						int(round(car.position.y * 1000.0))]
	var res := "TIMEOUT"
	if node.state == node.State.WIN:
		res = "WIN"
	elif node.state == node.State.LOSE:
		res = "LOSE"
	var blob := "%s|%s|%d|%d|%.9f|%d\n" % [str(lv.id), res, node.served, node.lost,
			t, node.reactivations]
	for e in node.log_served:
		blob += "S|%s|%.9f|%d\n" % [e.type, e.wait, e.rides]
	for e in node.log_lost:
		blob += "L|%s|%.9f|%d\n" % [e.type, e.wait, e.rides]
	for i in node.cars.size():
		var c = node.cars[i]
		blob += "C|%d|%d|%d|%.9f|%d|%.9f|%.9f\n" % [i, c.car_state, c.idx,
				c.seg_t, c.dir, c.position.x, c.position.y]
	blob += "SIG|%d|%d\n" % [hash(sig), sig.length()]
	var line := "%-4s %-8s served=%-3d lost=%-2d t=%6.1f react=%d  hash=%-12d len=%d" % [
			str(lv.id), res, node.served, node.lost, t, node.reactivations,
			hash(blob), blob.length()]
	node.free()
	return {"blob": blob, "line": line}


func _process(_delta: float) -> bool:
	print("============== v5 SIM FINGERPRINTS (STEP %.2f) ==============" % STEP)
	var all := ""
	for i in Levels5.LEVELS.size():
		var lv: Dictionary = Levels5.LEVELS[i]
		var seed_v: int = SEEDS.get(str(lv.id), 51000 + i)
		var r := _run(i, seed_v)
		print(r.line)
		all += r.blob
	print("---------------------------------------------------------------")
	print("FINGERPRINT5-ALL  %d  len=%d" % [hash(all), all.length()])
	quit(0)
	return true
