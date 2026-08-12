extends RefCounted
## Training-data EXPORTER for the learned surrogate (docs/surrogate-design.md
## §6.4, contract in docs/export-schema.md). It logs every VALID simulation the
## depth tools run as ONE labeled JSONL row: a self-contained (level, route_set,
## seed) INPUT plus the full outcome vector LABEL, so a row can be re-simulated
## and re-labeled WITHOUT the level table it came from.
##
## OFF BY DEFAULT, and off means *absent*: nothing here runs unless a caller
## explicitly constructs an Export and assigns it to `SimApi.exporter`. A normal
## search, the balance suite (tests/balance.gd) and the determinism fingerprint
## (tools/fingerprint.gd) never build one, so the simulation is byte-identical
## with the exporter compiled in but unused.
##
## CONCURRENCY: the pool runs many worker PROCESSES. Each Export writes its own
## shard file, named with the OS process id, so two workers can never touch the
## same file and there is no cross-process interleaving to corrupt. Within one
## process the writes are sequential and each row is flushed as one whole line
## (JSON.stringify emits no newline; embedded newlines in strings are escaped),
## so a kill mid-batch truncates at a row boundary, never inside a row.
##
## VERSIONING is the point (the user has said much will change and early data is
## disposable): every row carries SCHEMA_VERSION, the scoring-rule string, the
## acceleration/restriction model, and batch provenance, so stale rows are
## filterable rather than silently mixed into a later experiment.

## Bump when the ROW SHAPE changes (a field added/removed/retyped). This is the
## coarse "can the ML side still parse this" gate; `score_rule` below is the
## finer "does this row still mean the same outcome" gate.
const SCHEMA_VERSION := 1

const RG = preload("res://tools/routegen.gd")
const SimApiScript = preload("res://tools/sim_api.gd")

var dir := ""       # output directory (created if missing)
var run_tag := ""   # free-form batch label carried into every row's meta
var shard_id := ""  # worker/shard id, part of the filename and the meta
var path := ""      # the shard file this instance owns
var rows_written := 0
var _file: FileAccess = null


## Construct = ENABLE. A caller only does this behind its own opt-in flag, so
## the mere existence of an Export is the "on" signal.
func _init(out_dir: String, tag: String, shard: String) -> void:
	dir = out_dir
	run_tag = tag
	shard_id = shard
	DirAccess.make_dir_recursive_absolute(dir)
	# The process id makes the filename unique across concurrent workers AND
	# across restarts of the same shard, so no two file handles ever alias.
	path = "%s/shard_%s_%d.jsonl" % [dir, shard, OS.get_process_id()]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("export: cannot open " + path)


## One row per VALID evaluation. Called from SimApi.run AFTER _harvest and while
## `game` is still alive (its per-passenger logs feed the label). Invalid
## geometry and cache-replayed runs are not exported (see docs/export-schema.md).
func write_row(level_index: int, routes: Array, seed_v: int, step: float,
		injected, out: Dictionary, _game) -> void:
	if _file == null or not out.get("valid", false):
		return
	var level: Dictionary = injected if injected != null else Levels3.LEVELS[level_index]
	var row := {
		"schema_version": SCHEMA_VERSION,
		"level_id": String(level.get("id", "?")),
		"level_hash": _level_hash(level),
		"route_set_key": _route_set_key(routes),
		"seed": seed_v,
		"step": step,
		"score_rule": SimApiScript._cache_version(),
		"level": _level_spec(level),
		"routes": _routes_spec(level, routes),
		"label": _label(out),
		"meta": _meta(level_index, injected),
	}
	_file.store_line(JSON.stringify(row))
	_file.flush()
	rows_written += 1


func close() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


# ------------------------------------------------------------------ level spec
#
# Self-contained: everything needed to REBUILD the level Dictionary and re-run
# the exact evaluation, so a row stays interpretable after LEVELS changes. Flavour
# text (`intro`) and draw colours are dropped — they never touch the simulation.

func _level_spec(level: Dictionary) -> Dictionary:
	var rooms: Array = Grid3.rooms()
	var idx := {}
	for i in rooms.size():
		idx[rooms[i]] = i
	var spec := {
		"id": String(level.get("id", "?")),
		"name": String(level.get("name", "")),
		"thesis": String(level.get("thesis", "")),
		"rows": (level.rows as Array).duplicate(),
		"quota": int(level.quota),
		"max_lost": int(level.max_lost),
		"spawn": _num_dict(level.get("spawn", {})),
		"mix": _num_dict(level.get("mix", {})),
		# main3._pick_type() rolls the type mix in DICT ITERATION ORDER, so that
		# order is load-bearing for which passenger a spawn RNG draw produces — and
		# JSON.stringify alphabetizes keys, dropping it. Preserve it explicitly so a
		# rebuilt level reproduces the exact spawn stream (see docs/export-schema.md).
		"mix_order": (level.get("mix", {}) as Dictionary).keys(),
		"cards": _cards_spec(level),
		"passenger_types": _ptypes_spec(level),
		"rooms": _v2_list(rooms),
		"exec_origins": _v2_list(level.get("exec_origins", [])),
		"exec_dests": _v2_list(level.get("exec_dests", [])),
		"groups": _groups_spec(level.get("groups", {})),
		"trips": _trips_spec(level.get("trips", [])),
		"type_rooms": _type_rooms_spec(level.get("type_rooms", {})),
		"patience": _num_dict(level.get("patience", {})),
	}
	# Derived demand: what the sim actually samples (§6.4). Per-room in/out weight
	# for the level encoder, plus the pairwise table indexed into `rooms` for the
	# room graph's edges. Cheap, and it spares the ML side re-deriving it.
	var dmd: Dictionary = RG.demand(level)
	var win := {}
	var wout := {}
	var pairs: Array = []
	for a in dmd:
		for b in dmd[a]:
			var w: float = dmd[a][b]
			wout[a] = float(wout.get(a, 0.0)) + w
			win[b] = float(win.get(b, 0.0)) + w
			pairs.append([idx.get(a, -1), idx.get(b, -1), w])
	var room_demand: Array = []
	for r in rooms:
		room_demand.append({"cell": _v2(r), "in": float(win.get(r, 0.0)),
				"out": float(wout.get(r, 0.0))})
	spec["room_demand"] = room_demand
	spec["demand_pairs"] = pairs
	return spec


## Resolved card features through the SAME accessors Car3.setup uses, and stored
## EXPLICITLY (width/cap/speed/accel), so rebuilding a card from this dict makes
## the accessors return these exact numbers regardless of the accel_model /
## restrict globals in force at rebuild time — a row is config-independent to
## re-run. The globals are still recorded in meta so a stale row is filterable.
func _cards_spec(level: Dictionary) -> Array:
	var out: Array = []
	for c in level.cards:
		out.append({
			"name": String(c.get("name", "")),
			"type": String(c.get("type", "standard")),
			"width": Levels3.card_width(c),
			"cap": Levels3.card_capacity(c),
			"speed": Levels3.card_speed(c),
			"accel": Levels3.card_accel(c),
		})
	return out


## Per spawnable type: width and the patience actually in effect (level override
## folded in), matching what Passenger3.setup applies.
func _ptypes_spec(level: Dictionary) -> Dictionary:
	var out := {}
	var pat: Dictionary = level.get("patience", {})
	for t in level.get("mix", {}):
		var info: Dictionary = Passenger3.PTYPES.get(t, {})
		out[t] = {
			"width": int(info.get("width", 1)),
			"patience": float(pat.get(t, info.get("patience", 90.0))),
		}
	return out


# ------------------------------------------------------------- route_set spec
#
# The "set of loadouts" shape §2.2.D wants: per route the ordered stop cells, the
# closed/home bits, the bound card's features, AND the decoded polyline (so a row
# re-runs verbatim — SimApi.run consumes `cells`). stops are the room cells the
# polyline actually visits, in travel order.

func _routes_spec(level: Dictionary, routes: Array) -> Array:
	var cards := _cards_spec(level)
	var out: Array = []
	for i in routes.size():
		var r = routes[i]
		if r == null:
			out.append(null)
			continue
		var cells: Array = r.cells
		var entry := {
			"card": i,
			"stops": _v2_list(RG.stops_of_cells(cells)),
			"closed": bool(r.get("closed", false)),
			"home": _v2(r.get("home", null)) if r.get("home", null) != null else null,
			"cells": _v2_list(cells),
		}
		if i < cards.size():
			var cf: Dictionary = cards[i]
			entry["type"] = cf.type
			entry["width"] = cf.width
			entry["cap"] = cf.cap
			entry["speed"] = cf.speed
			entry["accel"] = cf.accel
		out.append(entry)
	return out


# -------------------------------------------------------------------- label
#
# The full outcome vector _harvest emits, unabridged (docs/surrogate-design.md
# §5): the primary WIN/LOSE + score, and every dense auxiliary the surrogate's
# auxiliary heads want, including the per-type served/lost added to _harvest.

func _label(out: Dictionary) -> Dictionary:
	return {
		"result": String(out.result),
		"score": float(out.score),
		"t_end": float(out.t_end),
		"served": int(out.served),
		"lost": int(out.lost),
		"avg_wait": float(out.avg_wait),
		"p90_wait": float(out.p90_wait),
		"avg_transfers": float(out.avg_transfers),
		"waiting_end": int(out.waiting_end),
		"no_path_end": int(out.no_path_end),
		"gate_wait": float(out.gate_wait),
		"gate_transits": int(out.gate_transits),
		"served_by_type": out.get("served_by_type", {}),
		"lost_by_type": out.get("lost_by_type", {}),
	}


func _meta(level_index: int, injected) -> Dictionary:
	return {
		"level_index": level_index,
		# true = a PARAMETERISED level (e.g. a length-sweep quota), not the shipped
		# LEVELS[level_index] entry; the level spec above is the injected one.
		"injected": injected != null,
		"accel_model": Levels3.accel_model,
		"restrict": Levels3.restrict,
		"timeout": SimApiScript.TIMEOUT,
		"win_bonus": SimApiScript.WIN_BONUS,
		"lost_weight": SimApiScript.LOST_WEIGHT,
		"wait_weight": SimApiScript.WAIT_WEIGHT,
		"seeds_train": SimApiScript.SEEDS_TRAIN,
		"seeds_test": SimApiScript.SEEDS_TEST,
		"run_tag": run_tag,
		"shard": shard_id,
		"pid": OS.get_process_id(),
		"exported_at": Time.get_datetime_string_from_system(),
	}


# ----------------------------------------------------------------- hashing
#
# sha1 over a CANONICAL string of the level's simulation-relevant fields (rows +
# resolved cards + quota/max_lost + spawn + mix + patience + the derived demand
# table). Sorted keys and fixed formatting make it stable across processes, so
# two rows of the same level share a level_hash and the ML side can group by it.

func _level_hash(level: Dictionary) -> String:
	var s := "id=%s\n" % String(level.get("id", "?"))
	s += "rows=" + "\n".join(level.rows) + "\n"
	s += "quota=%d\nmax_lost=%d\n" % [int(level.quota), int(level.max_lost)]
	for c in level.cards:
		s += "card=%s,%d,%d,%.4f,%.4f\n" % [String(c.get("type", "standard")),
				Levels3.card_width(c), Levels3.card_capacity(c),
				Levels3.card_speed(c), Levels3.card_accel(c)]
	s += _kv_sorted("mix", level.get("mix", {}))
	s += _kv_sorted("patience", level.get("patience", {}))
	s += _kv_sorted("spawn", level.get("spawn", {}))
	var dmd: Dictionary = RG.demand(level)
	var lines: Array = []
	for a in dmd:
		for b in dmd[a]:
			lines.append("%d,%d>%d,%d=%.6f" % [a.x, a.y, b.x, b.y, dmd[a][b]])
	lines.sort()
	s += "demand=" + ";".join(lines) + "\n"
	return s.sha1_text()


func _route_set_key(routes: Array) -> String:
	# The decoded-cells key SimApi already uses to dedupe a run; reused here so
	# the export key and the run cache agree on "same route_set".
	return SimApiScript._key(0, routes, 0, 0.0)


# ------------------------------------------------------------- serialization

func _v2(c) -> Array:
	return [c.x, c.y]


func _v2_list(a: Array) -> Array:
	var out: Array = []
	for c in a:
		out.append([c.x, c.y])
	return out


func _num_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out


func _groups_spec(groups: Dictionary) -> Dictionary:
	var out := {}
	for name in groups:
		out[String(name)] = _v2_list(groups[name])
	return out


func _trips_spec(trips: Array) -> Array:
	var out: Array = []
	for row in trips:
		out.append({"w": float(row.w), "from": String(row.from), "to": String(row.to)})
	return out


func _type_rooms_spec(tr: Dictionary) -> Dictionary:
	var out := {}
	for t in tr:
		out[String(t)] = {"from": _v2_list(tr[t].from), "to": _v2_list(tr[t].to)}
	return out


func _kv_sorted(label: String, d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [String(k), str(d[k])])
	return "%s=%s\n" % [label, ";".join(parts)]
