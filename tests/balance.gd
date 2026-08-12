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
var loop_done := false
var loop_checks: Array = [] # filled by the v3.4 loop-mechanics run


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
	if not loop_done:
		loop_done = true
		loop_checks = _loop_mechanics(tree)
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
		game.commit_route(i, ScenData.Scen.cells_of(sc.routes[i]),
				ScenData.Scen.closed_of(sc.routes[i]))
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
## a loop) is legal on the CURRENT level's maze. Closed loops additionally
## need >= 4 cells and the last cell adjacent to the first (the closing link).
func _route_error(entry) -> String:
	var cells: Array = ScenData.Scen.cells_of(entry)
	var closed: bool = ScenData.Scen.closed_of(entry)
	if cells.size() < 2:
		return "fewer than 2 cells"
	if closed and cells.size() < 4:
		return "closed loop with fewer than 4 cells"
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
	if closed:
		var dc: Vector2i = cells[0] - cells[cells.size() - 1]
		if absi(dc.x) + absi(dc.y) != 1:
			return "closing link %s -> %s not adjacent" % [
					str(cells[cells.size() - 1]), str(cells[0])]
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
	for id in ["L1", "L2", "L3", "L4"]:
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
	out.append_array(loop_checks)
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
	# --- Stage A (L1 grid): the minimal 4-cell square + the size guard.
	Levels3.current = Levels3.index_of("L1")
	Levels3.watch_strategy = ""
	var g1 = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g1)
	g1.rng.seed = 11
	g1.auto_spawn = false
	g1.start_session()
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
	# --- Stage B (L4 ring): full closing UX + movement + pathfinding.
	Levels3.current = Levels3.index_of("L4")
	Levels3.watch_strategy = ""
	var g = load("res://scenes/v3_main.tscn").instantiate()
	tree.root.add_child(g)
	g.rng.seed = 777
	g.auto_spawn = false
	g.start_session()
	g.select_card(0)
	var ring: Array = ScenData.Scen.path([Vector2i(0, 0), Vector2i(6, 0),
			Vector2i(6, 6), Vector2i(0, 6), Vector2i(0, 1)])
	g._begin_stroke(Grid3.cell_center(ring[0]))
	for k in range(1, ring.size()):
		g.stroke_try_extend(ring[k])
	out.append(_c("loop: 24-cell ring stroke drawn", g.stroke.size() == 24,
			"size %d" % g.stroke.size()))
	var cl: bool = g.stroke_try_extend(Vector2i(0, 0))
	out.append(_c("loop: ring stroke closes", cl and g.stroke_closed,
			"closed %s" % str(g.stroke_closed)))
	var fwd: bool = g.stroke_try_extend(Vector2i(1, 0))
	out.append(_c("loop: forward drags ignored while closed",
			not fwd and g.stroke_closed and g.stroke.size() == 24,
			"size %d closed %s" % [g.stroke.size(), str(g.stroke_closed)]))
	var retr: bool = g.stroke_try_extend(g.stroke[g.stroke.size() - 2])
	out.append(_c("loop: cannot retract while closed",
			not retr and g.stroke.size() == 24, "size %d" % g.stroke.size()))
	var ro: bool = g.stroke_try_extend(Vector2i(0, 1)) # the tail cell
	out.append(_c("loop: reversing onto the tail reopens",
			ro and not g.stroke_closed and g.stroke.size() == 24,
			"closed %s size %d" % [str(g.stroke_closed), g.stroke.size()]))
	var back: bool = g.stroke_try_extend(Vector2i(0, 2)) # normal backtrack resumes
	out.append(_c("loop: backtrack retracts after reopening",
			back and g.stroke.size() == 23, "size %d" % g.stroke.size()))
	g.stroke_try_extend(Vector2i(0, 1)) # redraw the tail...
	g.stroke_try_extend(Vector2i(0, 0)) # ...close again...
	g._end_stroke() # ...and commit (session-start: deploys instantly)
	var r0 = g.routes[0]
	out.append(_c("loop: committed ring is a closed 10-stop loop",
			r0 != null and r0.closed and r0.cells.size() == 24
			and r0.stop_cells().size() == 10,
			"null" if r0 == null else "closed %s stops %d" % [
					str(r0.closed), r0.stop_cells().size()]))
	# Directional ride_dist: forward short, and a->b + b->a == n for ALL
	# distinct stop pairs.
	var n: int = r0.cells.size()
	out.append(_c("loop: ride_dist forward-only ((ib-ia) mod n)",
			is_equal_approx(r0.ride_dist(Vector2i(0, 0), Vector2i(3, 0)),
					3.0 * Grid3.CELL)
			and is_equal_approx(r0.ride_dist(Vector2i(3, 0), Vector2i(0, 0)),
					21.0 * Grid3.CELL),
			"fwd %.0f bwd %.0f" % [r0.ride_dist(Vector2i(0, 0), Vector2i(3, 0)),
					r0.ride_dist(Vector2i(3, 0), Vector2i(0, 0))]))
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
	var legs = Pathfind3.find_path(Vector2i(3, 0), Vector2i(0, 0), g.cars, -1.0)
	var long_ok: bool = legs != null and not legs.is_empty()
	var legs_dist := 0.0
	if long_ok:
		for leg in legs:
			legs_dist += leg.car.route.ride_dist(leg.board, leg.alight)
		long_ok = legs_dist >= 21.0 * Grid3.CELL - 0.01
	out.append(_c("loop: backward demand priced the long way",
			long_ok, "legs %s dist %.0f" % [
					"none" if legs == null else str(legs.size()), legs_dist]))
	# Closed car wraps forward-only, smoothly across the seam, and actually
	# delivers that backward rider.
	var car = g.cars[0]
	var p = g.spawn_passenger("visitor", Vector2i(3, 0), Vector2i(0, 0))
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
	var p2 = g.spawn_passenger("visitor", Vector2i(6, 0), Vector2i(6, 4))
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
	g.commit_route(0, ScenData.Scen.path([Vector2i(0, 0), Vector2i(3, 0)]))
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


func _c(name: String, ok: bool, detail: String) -> Dictionary:
	return {"name": name, "ok": ok, "detail": detail}
