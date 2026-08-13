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


func _c(pairs: Array) -> Array:
	var out: Array = []
	for p in pairs:
		out.append(Vector2i(p[0], p[1]))
	return out


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
	return []


## Expected serve-count per car for a known route (assertion d). -1 = unchecked.
func _expect_serves(id: String) -> Array:
	match id:
		"R-1":
			return [3]
		"R-5":
			return [2, 2]
	return []


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
		"sig": sig,
	}
	node.free()
	return res


func _process(_delta: float) -> bool:
	if _i >= Levels5.LEVELS.size():
		print("---------------------------------------------------------------")
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
	var deterministic: bool = a.sig == b.sig

	var notes: Array = []
	var ok: bool = a.committed and a.ready and a.served > 0 and a.ride_peak > 0
	if not deterministic:
		ok = false
		notes.append("NONDET")
	# (a) walk time is real: someone was seen walking in the sim.
	if not a.saw_walk:
		ok = false
		notes.append("no-walk")
	# R-3 must actually show a transfer (crossing the 2-wide atrium).
	if lv.id == "R-3" and a.transfers == 0:
		ok = false
		notes.append("no-xfer")
	# (c) one-lift corridor serialises two contenders.
	if lv.id == "R-5":
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
	if lv.id == "R-5" and not (a.state == "WIN"):
		pass # win asserted below via state anyway
	if a.state != "WIN":
		ok = false
		notes.append("not-WIN")
	if not ok:
		_fail += 1
	print("%-4s %-8s served=%2d lost=%2d t=%5.1f ride_peak=%d xfers=%d det=%s walk=%s corr=%s trans=%s  serve{%s} %s %s" % [
			lv.id, a.state, a.served, a.lost, a.t, a.ride_peak, a.transfers,
			"Y" if deterministic else "N", "Y" if a.saw_walk else "N",
			("ok" if a.corridor_ok else "SHARED") if lv.id == "R-5" else "-",
			str(a.transits),
			"  ".join(a.serve_desc),
			"OK" if ok else "**FAIL**", " ".join(notes)])
	_i += 1
	return false
