extends SceneTree
## Headless smoke for the v5 "Rooms" prototype. Drives the REAL input/sim path:
## for each level it instantiates scenes/v5_main.tscn, commits a hand solution,
## starts the run and advances game time until win/lose or a time cap — checking
## that passengers spawn in rooms, board, ride, transfer (R-3) and alight to
## their destination rooms.
##
## v5.1 additions verified here:
##   (a) board/alight now take game-time — a passenger is observed WALKING in the
##       sim (walk_left > 0) before it can board / after it alights.
##   (b) the sim is deterministic — a repeated run with the same seed is
##       bit-identical (a per-step position/served/lost signature matches).
##   (c) the one-lift corridor (R-5) serialises two contending cars — they never
##       co-occupy the corridor group beyond its width, and they DO contend.
##   (d) the serve-count is correct for a known route (the value the HUD chip
##       shows): R-1's lone lift serves 3 rooms; R-5's two lifts serve 2 each.
##
##   godot --headless --path . --script tests/v5_smoke.gd

const STEP := 0.1
const CAP := 600.0 # game-seconds budget per level

var _i := 0
var _fail := 0
var _reacts := 0 # total reactivations seen across levels (must be > 0 overall)


func _c(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append(Vector2i(p[0], p[1]))
	return out


func _solution(id: String) -> Array:
	match id:
		"R-1":
			# One route: A at the bottom, then the top cell (2,4) serves BOTH offices.
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4]])]
		"R-2":
			# Wall splits the towers: BLUE the left (A,B), GREEN the right (C,D).
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5]]),
					_c([[4,0],[4,1],[4,2],[4,3],[4,4],[4,5]])]
		"R-3":
			# BLUE serves apartment A + lobby B; GREEN serves lobby B + office C.
			return [_c([[2,0],[2,1]]),
					_c([[5,0],[5,1]])]
		"R-4":
			# Bottleneck: both lifts thread the width-2 corridor (2,2..2,4).
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6]]),
					_c([[3,0],[3,1],[3,2],[2,2],[2,3],[2,4],[3,4],[3,5],[3,6]])]
		"R-5":
			# Relay: BLUE the left (A,B,atrium C), GREEN the right (C,D,E).
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4]]),
					_c([[5,0],[5,1],[5,2],[5,3],[5,4]])]
		"R-6":
			# Stepped capped shaft: LIFT 1 the lower-left (A,B,C), LIFT 2 the upper-
			# right (C,D,E); they share only the cap-4 atrium C at (2,4) in the bend.
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4]]),
					_c([[2,4],[3,4],[3,5],[3,6],[3,7],[3,8]])]
		"R-7":
			# EXPRESS runs the left channel lobby->penthouse; LOCAL the right office stack.
			return [_c([[1,0],[1,1],[1,2],[1,3],[1,4],[1,5],[1,6],[1,7],[1,8],[1,9],[1,10]]),
					_c([[4,0],[4,1],[4,2],[4,3],[4,4],[4,5],[4,6],[4,7],[4,8]])]
		"R-8":
			# CARGO runs the wide freight shaft (delivery A -> cafe B); LOCAL the narrow
			# people corridor (lobby C, offices D,E, up to cafe B for lunch).
			return [_c([[2,0],[2,1],[2,2],[2,3],[2,4],[2,5],[2,6]]),
					_c([[5,0],[5,1],[5,2],[5,3],[5,4],[5,5],[5,6]])]
		"R-9":
			# Two non-overlapping snakes: LIFT 1 the lower docks + delivery + lobby,
			# LIFT 2 the top store dock + cafe. Disjoint under the cap-2 tiles.
			return [_c([[4,0],[3,0],[2,0],[2,1],[2,2],[2,3],[3,3],[4,3]]),
					_c([[2,5],[2,6],[3,6],[4,6]])]
		"R-10":
			# LIFT 1 a horseshoe past all four; LIFT 2 doubles the busy apartment side.
			return [_c([[2,1],[2,2],[2,3],[2,4],[2,5],[2,6],[3,6],[3,5],[3,4],[3,3],[3,2],[3,1]]),
					_c([[2,1],[2,2],[2,3],[2,4],[2,5]])]
	return []


## Expected serve-count per car for a known route (assertion d). -1 = unchecked.
func _expect_serves(id: String) -> Array:
	match id:
		"R-1":
			return [3] # one lift serves A + both offices via the shared top dock
		"R-4":
			return [2, 2] # Bottleneck: BLUE serves A,B; GREEN serves C,D
		"R-6":
			return [3, 3] # LIFT 1 serves A,B,C; LIFT 2 serves C,D,E
	return []


func _r6_index() -> int:
	for i in Levels5.LEVELS.size():
		if str(Levels5.LEVELS[i].id) == "R-6":
			return i
	return -1


## The overlap-cap drawing limit on R-6: (b) a legal route is accepted; the two
## cooperative routes SHARE the cap-4 transfer tile (2,4) legally; a route pushing
## a cap-2 tile over its cap is REFUSED; and (c) clearing frees the width back.
func _overlap_test() -> bool:
	var idx := _r6_index()
	if idx < 0:
		print("  overlap: R-6 not found **FAIL**")
		return false
	Levels5.current = idx
	Levels5.headless = true
	var node = load("res://scenes/v5_main.tscn").instantiate()
	node.headless = true
	root.add_child(node)
	node.to_plan()
	var ok := true
	var l1 := _c([[2,0],[2,1],[2,2],[2,3],[2,4]]) # lower-left + atrium (2,4), legal
	var l2coop := _c([[2,4],[3,4],[3,5],[3,6],[3,7],[3,8]]) # upper-right; shares (2,4) cap-4
	var l2bad := _c([[2,2],[2,3]]) # would overlap L1 on cap-2 tiles (2+2 > 2)
	if not node.commit_route(0, l1, false):
		ok = false
		print("  overlap: (b) legal L1 rejected **FAIL**")
	if not node.commit_route(1, l2coop, false):
		ok = false
		print("  overlap: cap-4 transfer crossover rejected **FAIL**")
	node.commit_route(1, [], false)
	if node.commit_route(1, l2bad, false):
		ok = false
		print("  overlap: over-cap route accepted **FAIL**")
	node.commit_route(0, [], false) # clear L1, freeing its width
	if not node.commit_route(1, l2bad, false):
		ok = false
		print("  overlap: route still rejected after clear (width not freed) **FAIL**")
	node.free()
	return ok


## Runs R-6 with the given routes (r1 may be null for a one-lift attempt) to a
## decision, returning the final state string.
func _run_r6(r0, r1) -> String:
	Levels5.current = _r6_index()
	Levels5.headless = true
	var node = load("res://scenes/v5_main.tscn").instantiate()
	node.headless = true
	root.add_child(node)
	node.rng.seed = 20260814
	node.to_plan()
	if r0 != null:
		node.commit_route(0, _c(r0), false)
	if r1 != null:
		node.commit_route(1, _c(r1), false)
	node.start_run()
	var t := 0.0
	while t < CAP and node.state == node.State.PLAYING:
		node.advance(STEP)
		t += STEP
	var st: String = "WIN" if node.state == node.State.WIN \
			else ("LOSE" if node.state == node.State.LOSE else "TIMEOUT")
	node.free()
	return st


## R-6 must genuinely REQUIRE two cooperating lifts: (b) ONE lift running the whole
## shaft cannot keep up (does not WIN); (c) two lifts serving DISJOINT halves with
## no shared transfer cannot serve the cross-end trips (does not WIN). The intended
## cooperative split is verified by the main loop (R-6 WINs with transfers > 0).
func _cooperation_test() -> bool:
	var ok := true
	var one := _run_r6([[2,0],[2,1],[2,2],[2,3],[2,4],[3,4],[3,5],[3,6],[3,7],[3,8]], null)
	if one == "WIN":
		ok = false
		print("  cooperation: one lift alone WON (should be insufficient) **FAIL**")
	var disjoint := _run_r6([[2,0],[2,1],[2,2]], [[3,6],[3,7],[3,8]])
	if disjoint == "WIN":
		ok = false
		print("  cooperation: disjoint two (no transfer) WON (cross trips should fail) **FAIL**")
	print("  cooperation: one-lift=%s  disjoint-two=%s" % [one, disjoint])
	return ok


## Run one level once from a fresh scene; return stats + a determinism signature
## + corridor / walk observations. `seed` fixes the spawner so two runs match.
func _run_once(lv: Dictionary, i: int, seed: int) -> Dictionary:
	Levels5.current = i
	Levels5.headless = true
	var scene: PackedScene = load("res://scenes/v5_main.tscn")
	var node = scene.instantiate()
	node.headless = true
	root.add_child(node)
	node.rng.seed = seed
	node.to_plan()
	var sol := _solution(lv.id)
	var committed := true
	for ci in sol.size():
		if not node.commit_route(ci, sol[ci], false):
			committed = false
	var ready: bool = node.ready_to_run()
	# Which rooms each car serves (service model check).
	var serve_desc: Array = []
	var serve_sizes: Array = []
	for ci in node.cars.size():
		var rt = node.routes[ci]
		var rooms: Array = []
		if rt != null:
			for rid in rt.served_rooms():
				rooms.append(Grid5.room_letter(rid))
			rooms.sort()
		serve_desc.append("%s=[%s]" % [str(lv.cards[ci].name), ",".join(rooms)])
		serve_sizes.append(rt.served_rooms().size() if rt != null else 0)
	# Transfer rooms (served by 2+ cars).
	var serve_count := {}
	for ci in node.cars.size():
		var rt = node.routes[ci]
		if rt != null:
			for rid in rt.served_rooms():
				serve_count[rid] = int(serve_count.get(rid, 0)) + 1
	var transfer_rooms: Array = []
	for rid in serve_count:
		if serve_count[rid] >= 2:
			transfer_rooms.append(Grid5.room_letter(rid))
	transfer_rooms.sort()
	node.start_run()
	var t := 0.0
	var max_riding := 0
	var transfers := 0
	var saw_walk := false
	var corridor_ok := true
	var sig := ""
	while t < CAP and node.state == node.State.PLAYING:
		node.advance(STEP)
		t += STEP
		var riding := 0
		for p in node.active_passengers:
			if p.riding != null:
				riding += 1
			elif p.walk_left > 0.0:
				saw_walk = true
		max_riding = maxi(max_riding, riding)
		# Corridor invariant: sum of widths of cars physically in each group <=
		# group width, i.e. no two normal lifts share a width-2 corridor.
		for gi in Grid5.corridor_groups().size():
			var w := 0
			for car in node.cars:
				if car != null and car.on_grid() \
						and Grid5.corridor_group_of(car.current_cell()) == gi:
					w += car.width
			if w > Grid5.corridor_group_width(gi):
				corridor_ok = false
		# Determinism signature: served/lost + quantised car positions each step.
		sig += "%d;%d;" % [node.served, node.lost]
		for car in node.cars:
			if car != null:
				sig += "%d,%d|" % [int(round(car.position.x * 1000.0)),
						int(round(car.position.y * 1000.0))]
	for e in node.log_served:
		if int(e.rides) >= 2:
			transfers += 1
	var contended := false
	var transits: Array = []
	for car in node.cars:
		if car != null:
			transits.append(car.gate_transits)
			if car.gate_wait_total > 0.0:
				contended = true
	var st: String = "WIN" if node.state == node.State.WIN \
			else ("LOSE" if node.state == node.State.LOSE else "TIMEOUT")
	var res := {
		"committed": committed, "ready": ready, "state": st,
		"served": node.served, "lost": node.lost, "t": t,
		"ride_peak": max_riding, "transfers": transfers,
		"serve_desc": serve_desc, "serve_sizes": serve_sizes,
		"transfer_rooms": transfer_rooms, "saw_walk": saw_walk,
		"corridor_ok": corridor_ok, "contended": contended, "transits": transits,
		"reactivations": node.reactivations,
		"sig": sig,
	}
	node.free()
	return res


func _process(_delta: float) -> bool:
	if _i >= Levels5.LEVELS.size():
		print("---------------------------------------------------------------")
		# Overlap-cap mechanic: reject over-cap, accept legal, free width on clear.
		if _overlap_test():
			print("OVERLAP CAP: reject/accept/free OK")
		else:
			_fail += 1
			print("OVERLAP CAP  **FAIL**")
		# R-6 must REQUIRE two cooperating lifts (one-lift + disjoint-two both fail).
		if _cooperation_test():
			print("R-6 COOPERATION: one-lift + disjoint-two both fail as required")
		else:
			_fail += 1
			print("R-6 COOPERATION  **FAIL**")
		# Reactivation (real between-trip demand) must run in headless at least once.
		if _reacts == 0:
			_fail += 1
			print("REACTIVATION never occurred across all levels  **FAIL**")
		else:
			print("reactivation total across levels = %d" % _reacts)
		if _fail == 0:
			print("V5 SMOKE: ALL PASS")
		else:
			print("V5 SMOKE: %d FAIL" % _fail)
		quit(1 if _fail > 0 else 0)
		return true
	var lv: Dictionary = Levels5.LEVELS[_i]
	var seed := 20260813 + _i
	var a := _run_once(lv, _i, seed)
	# (b) determinism: a second run with the same seed is bit-identical.
	var b := _run_once(lv, _i, seed)
	var deterministic: bool = a.sig == b.sig and a.reactivations == b.reactivations
	_reacts += a.reactivations

	var notes: Array = []
	var ok: bool = a.committed and a.ready and a.served > 0 and a.ride_peak > 0
	if not deterministic:
		ok = false
		notes.append("NONDET")
	# (a) walk time is real: someone was seen walking in the sim.
	if not a.saw_walk:
		ok = false
		notes.append("no-walk")
	# Transfer levels must actually show a transfer (a rider changes lifts):
	# R-3 Handoff, R-5 Relay, R-6 Squeeze all route cross trips through a shared room.
	if (lv.id == "R-3" or lv.id == "R-5" or lv.id == "R-6") and a.transfers == 0:
		ok = false
		notes.append("no-xfer")
	# (c) one-lift corridor serialises two contenders (R-4 Bottleneck).
	if lv.id == "R-4":
		if not a.corridor_ok:
			ok = false
			notes.append("corridor-shared")
		if not a.contended:
			ok = false
			notes.append("no-contention")
	# (d) serve-count correct for a known route.
	var exp := _expect_serves(lv.id)
	for ci in exp.size():
		if ci < a.serve_sizes.size() and a.serve_sizes[ci] != exp[ci]:
			ok = false
			notes.append("serves[%d]=%d!=%d" % [ci, a.serve_sizes[ci], exp[ci]])
	# R-3 runs a deliberate CROWD STRESS spawn and is NOT required to win; the other
	# four keep normal spawns and must WIN. (det / served / transfer still checked.)
	if a.state != "WIN":
		ok = false
		notes.append("not-WIN")
	if not ok:
		_fail += 1
	print("%-4s %-8s served=%2d lost=%2d t=%5.1f ride_peak=%d xfers=%d react=%d det=%s walk=%s corr=%s  serve{%s} %s %s" % [
			lv.id, a.state, a.served, a.lost, a.t, a.ride_peak, a.transfers,
			a.reactivations,
			"Y" if deterministic else "N", "Y" if a.saw_walk else "N",
			("ok" if a.corridor_ok else "SHARED") if lv.id == "R-4" else "-",
			"  ".join(a.serve_desc),
			"OK" if ok else "**FAIL**", " ".join(notes)])
	_i += 1
	return false
