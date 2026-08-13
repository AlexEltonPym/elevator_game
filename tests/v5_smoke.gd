extends SceneTree
## Headless smoke for the v5 "Rooms" prototype. Drives the REAL input/sim path:
## for each level it instantiates scenes/v5_main.tscn, commits a hand solution,
## starts the run and advances game time until win/lose or a time cap — checking
## that passengers spawn in rooms, board, ride, transfer (R-3) and alight to
## their destination rooms. One level per engine frame so node frees flush.
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
					_c([[4,4],[4,5],[4,6]])]
		"R-4":
			return [_c([[3,1],[4,1],[5,1]]),
					_c([[2,5],[2,6],[3,6],[3,5],[3,4],[3,3],[3,2],[3,1],[4,1],[5,1]]),
					_c([[5,1],[5,2],[5,3],[5,4],[5,5]])]
	return []


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
	Levels5.current = _i
	Levels5.headless = true
	var scene: PackedScene = load("res://scenes/v5_main.tscn")
	var node = scene.instantiate()
	node.headless = true
	root.add_child(node)
	node.rng.seed = 20260813 + _i
	node.to_plan()
	# Commit the hand solution and gate-check.
	var sol := _solution(lv.id)
	var committed := true
	for ci in sol.size():
		if not node.commit_route(ci, sol[ci], false):
			committed = false
	var ready: bool = node.ready_to_run()
	# Report which rooms each car serves (service model check).
	var serve_desc: Array = []
	for ci in node.cars.size():
		var rt = node.routes[ci]
		var rooms: Array = []
		if rt != null:
			for rid in rt.served_rooms():
				rooms.append(Grid5.room_letter(rid))
			rooms.sort()
		serve_desc.append("%s=[%s]" % [str(lv.cards[ci].name), ",".join(rooms)])
	# Detect the R-3 transfer room (served by 2+ cars).
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
	while t < CAP and node.state == node.State.PLAYING:
		node.advance(STEP)
		t += STEP
		var riding := 0
		for p in node.active_passengers:
			if p.riding != null:
				riding += 1
		max_riding = maxi(max_riding, riding)
	for e in node.log_served:
		if int(e.rides) >= 2:
			transfers += 1
	var st: String = "WIN" if node.state == node.State.WIN \
			else ("LOSE" if node.state == node.State.LOSE else "TIMEOUT")
	var ok: bool = committed and ready and node.served > 0 and max_riding > 0
	if lv.id != "R-1" and lv.id != "R-2":
		pass
	if lv.id == "R-3" and transfers == 0:
		ok = false # the crossing level must show at least one transfer
	if not ok:
		_fail += 1
	print("%-4s %-8s served=%2d lost=%2d t=%5.1f ride_peak=%d transfers=%d  serve{%s} xfer{%s} %s" % [
			lv.id, st, node.served, node.lost, t, max_riding, transfers,
			"  ".join(serve_desc), ",".join(transfer_rooms),
			"OK" if ok else "**FAIL**"])
	node.free()
	_i += 1
	return false
