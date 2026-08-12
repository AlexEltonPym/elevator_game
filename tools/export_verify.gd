extends SceneTree
## ROUND-TRIP proof for the training-data exporter (tools/export.gd).
##
## A row is only training data if it is SELF-CONTAINED: the level spec + route_set
## it stores must be enough to re-run that exact evaluation and get the SAME
## label, without the LEVELS table the row came from. This tool proves it: it
## reads exported JSONL rows, rebuilds the level Dictionary and the routes purely
## from each row, re-runs them through the unmodified SimApi (injecting the
## rebuilt level, so LEVELS is never consulted), and checks the outcome matches
## the row's stored label.
##
##   & "<godot_console.exe>" --headless --path . --script tools/export_verify.gd -- \
##       [--file <shard.jsonl>] [--dir tools/out/export] [--n 8]
##
## Exit 0 iff every checked row round-trips. (Godot/mono may still print a
## benign nonzero on shutdown — judge by the ALL PASS line.)

const SimApi = preload("res://tools/sim_api.gd")


func _process(_delta: float) -> bool:
	var a := Array(OS.get_cmdline_user_args())
	var file := _arg(a, "--file", "")
	var dir := _arg(a, "--dir", "res://tools/out/export")
	var n := int(_arg(a, "--n", "8"))
	if file == "":
		file = _newest_jsonl(dir)
	if file == "":
		print("no JSONL shard found under " + dir)
		quit(1)
		return true
	print("=== export round-trip: %s ===" % file)
	var rows := _read_rows(file, n)
	if rows.is_empty():
		print("no rows read")
		quit(1)
		return true
	var sim = SimApi.new(self)
	var ok := true
	var checked := 0
	for row in rows:
		var level := _rebuild_level(row.level)
		var routes := _rebuild_routes(row.routes)
		var seed_v := int(row.seed)
		var step := float(row.step)
		var li := Levels3.index_of(String(row.level_id))
		var r: Dictionary = sim.run(maxi(0, li), routes, seed_v, step, level)
		var lab: Dictionary = row.label
		var same: bool = r.valid \
				and String(r.result) == String(lab.result) \
				and int(r.served) == int(lab.served) \
				and int(r.lost) == int(lab.lost) \
				and absf(float(r.score) - float(lab.score)) < 1.0e-4 \
				and absf(float(r.t_end) - float(lab.t_end)) < 1.0e-6
		checked += 1
		ok = ok and same
		print("[%s] %s seed %d  stored(%s served=%d lost=%d score=%.4f)  rerun(%s served=%d lost=%d score=%.4f)" % [
				"PASS" if same else "FAIL", String(row.level_id), seed_v,
				String(lab.result), int(lab.served), int(lab.lost), float(lab.score),
				String(r.result), int(r.served), int(r.lost), float(r.score)])
	print("\nROUND-TRIP: %s (%d rows)" % ["ALL PASS" if ok else "FAILURES PRESENT", checked])
	quit(0 if ok else 1)
	return true


# ---------------------------------------------------------------- rebuild

func _rebuild_level(spec: Dictionary) -> Dictionary:
	var lv := {
		"id": String(spec.id),
		"name": String(spec.get("name", "")),
		"thesis": String(spec.get("thesis", "")),
		"rows": (spec.rows as Array).duplicate(),
		"quota": int(spec.quota),
		"max_lost": int(spec.max_lost),
		"spawn": (spec.spawn as Dictionary).duplicate(),
		# Rebuild mix in its ORIGINAL iteration order (mix_order), because
		# main3._pick_type rolls the mix in that order — JSON alphabetized the keys.
		"mix": _rebuild_mix(spec),
		"patience": (spec.get("patience", {}) as Dictionary).duplicate(),
		"cards": _rebuild_cards(spec.cards),
		"exec_origins": _v2_list(spec.get("exec_origins", [])),
		"exec_dests": _v2_list(spec.get("exec_dests", [])),
		"groups": _rebuild_groups(spec.get("groups", {})),
		"trips": _rebuild_trips(spec.get("trips", [])),
		"type_rooms": _rebuild_type_rooms(spec.get("type_rooms", {})),
	}
	return lv


func _rebuild_mix(spec: Dictionary) -> Dictionary:
	var mix: Dictionary = spec.mix
	var order: Array = spec.get("mix_order", mix.keys())
	var out := {}
	for t in order:
		out[String(t)] = mix[String(t)]
	# Any key not covered by mix_order (shouldn't happen) still gets carried.
	for t in mix:
		if not out.has(t):
			out[String(t)] = mix[t]
	return out


func _rebuild_cards(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		# All features stored EXPLICITLY, so the Levels3 accessors return exactly
		# what the original run used, regardless of the accel_model / restrict
		# globals now in force.
		out.append({
			"name": String(c.get("name", "")),
			"type": String(c.type),
			"width": int(c.width),
			"cap": int(c.cap),
			"speed": float(c.speed),
			"accel": float(c.accel),
		})
	return out


func _rebuild_routes(routes: Array) -> Array:
	var out: Array = []
	for r in routes:
		if r == null:
			out.append(null)
			continue
		var entry := {"cells": _v2_list(r.cells), "closed": bool(r.closed)}
		if r.get("home", null) != null:
			entry["home"] = _v2(r.home)
		out.append(entry)
	return out


func _rebuild_groups(groups: Dictionary) -> Dictionary:
	var out := {}
	for name in groups:
		out[String(name)] = _v2_list(groups[name])
	return out


func _rebuild_trips(trips: Array) -> Array:
	var out: Array = []
	for t in trips:
		out.append({"w": float(t.w), "from": String(t.from), "to": String(t.to)})
	return out


func _rebuild_type_rooms(tr: Dictionary) -> Dictionary:
	var out := {}
	for t in tr:
		out[String(t)] = {"from": _v2_list(tr[t].from), "to": _v2_list(tr[t].to)}
	return out


func _v2(p) -> Vector2i:
	return Vector2i(int(p[0]), int(p[1]))


func _v2_list(a: Array) -> Array:
	var out: Array = []
	for p in a:
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


# ---------------------------------------------------------------- io

func _read_rows(path: String, n: int) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached() and out.size() < n:
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var d = JSON.parse_string(line)
		if d is Dictionary:
			out.append(d)
	f.close()
	return out


func _newest_jsonl(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	var best := ""
	var best_mtime := -1
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".jsonl"):
			var full := dir.path_join(name)
			var mt := FileAccess.get_modified_time(full)
			if mt > best_mtime:
				best_mtime = mt
				best = full
		name = d.get_next()
	d.list_dir_end()
	return best


func _arg(a: Array, flag: String, dflt: String) -> String:
	var i := a.find(flag)
	if i >= 0 and i + 1 < a.size():
		return String(a[i + 1])
	return dflt
