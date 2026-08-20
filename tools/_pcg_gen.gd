extends SceneTree
## FROM-SCRATCH level generator (no predesigned base). Places palette rooms as islands in
## an open grid with valid horizontal docks (rule 2c enforced), wraps with coverage demand
## + cards + trips, optionally adds barrier chokepoints, then the gate can classify each.
## Modes:
##   render <seed> <png>     generate from seed, screenshot the layout
##   gate   <seed>           generate + classify into a tier
##   batch  <n>              generate n, classify each, print the tier distribution
## godot [--headless] --path . --script tools/_pcg_gen.gd -- <mode> ...
const SimApi5 = preload("res://tools/v5/sim_api5.gd")
const Opt = preload("res://tools/v5/optimizers5.gd")
const ME = preload("res://tools/v5/mapelites5.gd")
const RG = preload("res://tools/v5/routegen5.gd")
const R := Vector2i(1, 0)
const L := Vector2i(-1, 0)

const NOVICE_TRIES := 30
const EA_BUDGET := 800
const EXPERT_BUDGET := 900   # MAP-Elites budget for the gate's expert-tip oracle
const EXPERT_FRAC := 0.6     # a novice "succeeds" if its tips reach this fraction of expert's
const STEP := 0.5   # coarse survey step (halves sim cost); shippable picks re-verified fine


class InjSim extends SimApi5:
	var inj: Dictionary = {}
	var tip_mode := false     # when true, score_seeds returns median SHIFT TIPS (not win-time)
	var shift := 90.0
	func _init(t: SceneTree) -> void:
		super(t)
	func run(li: int, routes: Array, seed_v: int, step: float, injected = null) -> Dictionary:
		return super.run(li, routes, seed_v, step, inj if injected == null else injected)
	func run_shift(li: int, routes: Array, seed_v: int, ssecs: float, step: float, injected = null) -> Dictionary:
		return super.run_shift(li, routes, seed_v, ssecs, step, inj if injected == null else injected)
	func score_seeds(li: int, routes: Array, seeds: Array, step: float, injected = null) -> Dictionary:
		if not tip_mode:
			return super.score_seeds(li, routes, seeds, step, injected)
		# Tip fitness: the level carries a `shift`, so a normal run() drives the shift and
		# the game accumulates the tip total we read back.
		var tips := []
		var stats := []
		for s in seeds:
			var r := run(li, routes, s, step)
			if not r.valid:
				return {"score": SimApi5.NEG_INF, "per_seed": [], "stats": [], "err": r.err}
			tips.append(r.tips)
			stats.append(r)
		return {"score": SimApi5.median(tips), "per_seed": tips, "stats": stats, "err": ""}


# ---- palette: cell offsets from a bottom-left anchor (y up), plus dock {c, dir}. ----
func _templates() -> Dictionary:
	return {
		"lobby":     {"w": 3, "h": 2, "cells": [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(0,1),Vector2i(1,1),Vector2i(2,1)],
					"docks": [{"c": Vector2i(2,0), "dir": R}]},
		"delivery":  {"w": 2, "h": 2, "cells": [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)],
					"docks": [{"c": Vector2i(1,0), "dir": R}], "label": "storage"},
		"apartment": {"w": 2, "h": 1, "cells": [Vector2i(0,0),Vector2i(1,0)],
					"docks": [{"c": Vector2i(1,0), "dir": R}]},
		"cafe":      {"w": 4, "h": 2, "cells": [Vector2i(0,1),Vector2i(1,1),Vector2i(2,1),Vector2i(3,1),Vector2i(1,0),Vector2i(2,0)],
					"docks": [{"c": Vector2i(1,0), "dir": L}, {"c": Vector2i(2,0), "dir": R}]},
		"penthouse": {"w": 4, "h": 2, "cells": [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0),Vector2i(3,0),Vector2i(1,1),Vector2i(2,1)],
					"docks": [{"c": Vector2i(3,0), "dir": R}]},
		"atrium":    {"w": 3, "h": 1, "cells": [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0)],
					"docks": [{"c": Vector2i(0,0), "dir": L}, {"c": Vector2i(2,0), "dir": R}]},
	}


func _flip(tpl: Dictionary) -> Dictionary:
	var w: int = tpl.w
	var cells := []
	for c in tpl.cells:
		cells.append(Vector2i(w - 1 - c.x, c.y))
	var docks := []
	for d in tpl.docks:
		docks.append({"c": Vector2i(w - 1 - d.c.x, d.c.y), "dir": Vector2i(-d.dir.x, d.dir.y)})
	var out := tpl.duplicate(true)
	out.cells = cells
	out.docks = docks
	return out


## Try to place `type` (optionally flipped) somewhere legal. Returns a room dict or {}.
func _place(type: String, cols: int, rows: int, occ: Dictionary, docks_all: Dictionary,
		rng: RandomNumberGenerator, tries: int, bottom_only := false) -> Dictionary:
	var tpl: Dictionary = _templates()[type]
	for _t in tries:
		var t2: Dictionary = _flip(tpl) if rng.randf() < 0.5 else tpl.duplicate(true)
		var ax := rng.randi_range(0, cols - t2.w)
		var ay := 0 if bottom_only else rng.randi_range(0, rows - t2.h)
		var cells := []
		var ok := true
		for c in t2.cells:
			var cell := Vector2i(ax + c.x, ay + c.y)
			if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows or occ.has(cell) or docks_all.has(cell):
				ok = false; break
			cells.append(cell)
		if not ok:
			continue
		var cellset := {}
		for c in cells:
			cellset[c] = true
		var drops := []
		var dockcells := []
		for d in t2.docks:
			var dc: Vector2i = Vector2i(ax + d.c.x, ay + d.c.y) + d.dir
			# dock must be open (not any room cell, not another dock) and in bounds
			if dc.x < 0 or dc.y < 0 or dc.x >= cols or dc.y >= rows or occ.has(dc) or docks_all.has(dc) or cellset.has(dc):
				ok = false; break
			# rule 2c: dock not directly above/below a DIFFERENT room's cell
			if occ.has(dc + Vector2i(0,1)) or occ.has(dc + Vector2i(0,-1)):
				ok = false; break
			drops.append({"cell": Vector2i(ax + d.c.x, ay + d.c.y), "dir": d.dir})
			dockcells.append(dc)
		if not ok:
			continue
		# rule 2c reverse: none of MY cells sit directly above/below an EXISTING dock
		for c in cells:
			if docks_all.has(c + Vector2i(0,1)) or docks_all.has(c + Vector2i(0,-1)):
				ok = false; break
		if not ok:
			continue
		var room := {"type": type, "cells": cells, "drops": drops}
		if tpl.has("label"):
			room["label"] = tpl.label
		return {"room": room, "cellset": cellset, "dockcells": dockcells}
	return {}


## Generate a level. `n_rooms` (0 = derive from seed, 4..8) is the LOOSEN KNOB: fewer
## rooms in the fixed grid = more open space = easier (novices can fit a plan); more rooms
## = tighter = harder. Returns a built level dict or {} (also rejects enclosed docks).
func _generate(seed_v: int, n_rooms := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	if n_rooms <= 0:
		n_rooms = 4 + (seed_v % 5)   # 4..8
	var cols := 9
	var rows := rng.randi_range(9, 11)
	var occ := {}
	var docks_all := {}
	var rooms := []
	var add := func(res: Dictionary) -> bool:
		if res.is_empty():
			return false
		rooms.append(res.room)
		for c in res.cellset:
			occ[c] = true
		for dc in res.dockcells:
			docks_all[dc] = true
		return true
	# Lobby first, forced to the bottom row (people entrance).
	if not add.call(_place("lobby", cols, rows, occ, docks_all, rng, 40, true)):
		return {}
	# Build a wishlist sized to n_rooms: cafe + penthouse (enable express); delivery when
	# there's budget (enable cargo); fill the rest with apartments, maybe one atrium.
	var wish := ["cafe", "penthouse"]
	if n_rooms >= 5:
		wish.append("delivery")
	while wish.size() < n_rooms - 1:
		wish.append("apartment")
	if n_rooms >= 6 and rng.randf() < 0.6 and wish.size() >= 1:
		wish[wish.size() - 1] = "atrium"
	for type in wish:
		add.call(_place(type, cols, rows, occ, docks_all, rng, 60))
	if rooms.size() < 4:
		return {}
	# Reject enclosed docks (unreachable in the open field) at generation time.
	var docklist := []
	for rm in rooms:
		for dr in rm.drops:
			docklist.append(dr.cell + dr.dir)
	if not _reachable_all(cols, rows, occ, docklist):
		return {}
	return _wrap(cols, rows, rooms)


## Every dock reachable from the first over open (non-room) cells? (generation-time A-check)
func _reachable_all(cols: int, rows: int, occ: Dictionary, docks: Array) -> bool:
	if docks.is_empty():
		return false
	var seen := {docks[0]: true}
	var q: Array = [docks[0]]
	var head := 0
	while head < q.size():
		var u: Vector2i = q[head]; head += 1
		for d in RG.NEIGHBORS:
			var v: Vector2i = u + d
			if v.x < 0 or v.y < 0 or v.x >= cols or v.y >= rows or seen.has(v) or occ.has(v):
				continue
			seen[v] = true
			q.append(v)
	for dk in docks:
		if not seen.has(dk):
			return false
	return true


## Wrap placed rooms into a full level: caps, cards, cover trips.
func _wrap(cols: int, rows: int, rooms: Array) -> Dictionary:
	# letters by room order; classify which types exist.
	var has := {}
	var letter_of := {}
	for i in rooms.size():
		has[rooms[i].type] = true
		letter_of[rooms[i].type] = letter_of.get(rooms[i].type, [])
		letter_of[rooms[i].type].append(char(65 + i))
	var cards := [{"name": "LOCAL", "type": "standard", "color": Color(0.45,0.68,0.95)}]
	if has.has("penthouse"):
		cards.append({"name": "EXPRESS", "type": "express", "color": Color(0.80,0.55,0.92), "speed": 1500.0, "accel": 1200.0})
	if has.has("cafe") and has.has("delivery"):
		cards.append({"name": "CARGO", "type": "cargo", "color": Color(0.98,0.68,0.2), "speed": 100.0, "accel": 80.0})
	# lobby letter
	var lobby := "A"
	for i in rooms.size():
		if rooms[i].type == "lobby":
			lobby = char(65 + i)
	# trips: lobby <-> every non-atrium/non-lobby room; storage<->cafe if both.
	var trips := []
	for i in rooms.size():
		var lt := char(65 + i)
		var ty: String = rooms[i].type
		if ty == "lobby" or ty == "atrium":
			continue
		var w := 0.16 if ty == "penthouse" else 0.10
		trips.append({"w": w, "from": lobby, "to": lt})
		trips.append({"w": w * 0.6, "from": lt, "to": lobby})
	if has.has("cafe") and has.has("delivery"):
		var cf: String = letter_of["cafe"][0]
		var st: String = letter_of["delivery"][0]
		trips.append({"w": 0.14, "from": st, "to": cf, "type": "delivery"})
		trips.append({"w": 0.06, "from": cf, "to": st, "type": "delivery"})
	# caps
	var occ := {}
	for rm in rooms:
		for c in rm.cells:
			occ[c] = true
	var dockset := {}
	for rm in rooms:
		for dr in rm.drops:
			dockset[dr.cell + dr.dir] = true
	var cap3 := []
	for x in cols:
		for y in rows:
			var c := Vector2i(x, y)
			if not occ.has(c) and not dockset.has(c):
				cap3.append(c)
	return {
		"id": "GEN", "world": "CROSSLINK", "name": "Generated", "thesis": "", "intro": "",
		"cols": cols, "rows": rows, "blocked": [], "rooms": rooms,
		"overlaps": [{"cells": cap3, "max": 3}, {"cells": dockset.keys(), "max": 6}],
		"cards": cards, "quota": 20, "max_lost": 4, "shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15}, "trips": trips,
	}


## ---- gate (reused from _pcg_evolve): feasibility + novice probe + EA classify ----
func _feasible() -> bool:
	var all_docks := RG.docks()
	if all_docks.is_empty():
		return false
	var seen := {all_docks[0]: true}
	var q: Array = [all_docks[0]]
	var head := 0
	while head < q.size():
		var u: Vector2i = q[head]; head += 1
		for d in RG.NEIGHBORS:
			var vv: Vector2i = u + d
			if not seen.has(vv) and Grid5.passable(vv):
				seen[vv] = true
				q.append(vv)
	for dk in all_docks:
		if not seen.has(dk):
			return false
	return true


## Tip-native novice probe: sample random LEGAL plans and count how many reach a
## fraction of the EXPERT tip ceiling (wins-per-attempt reframed for the tip model —
## a novice "succeeds" when a naive plan already scores near-optimal). `tsim` must be
## a tip_mode InjSim; `thresh` is the expert-fraction tip bar.
func _novice_tip(tsim: InjSim, widths: Array, seeds: Array, thresh: float, tries := NOVICE_TRIES) -> Dictionary:
	var all_docks := RG.docks()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var legal := 0
	var hits := 0
	var tips := []
	for _i in tries:
		var g := RG.random_genome(rng, all_docks, widths)
		if g.is_empty():
			continue
		var dec := RG.decode_genome(g, widths)
		if dec.err != "":
			continue
		legal += 1
		var r: Dictionary = tsim.score_seeds(0, dec.routes, seeds, STEP)
		tips.append(r.score)
		if r.score >= thresh:
			hits += 1
	return {"legal": legal, "hits": hits, "med": _median(tips)}


func _classify(lv: Dictionary, expert_budget := EXPERT_BUDGET, novice_tries := NOVICE_TRIES) -> Dictionary:
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	if not _feasible():
		return {"tier": "BROKEN", "note": "a dock is walled off"}
	var widths := RG.card_widths(lv)
	var seeds := SimApi5.SEEDS_TRAIN.slice(0, 3)
	# EXPERT ORACLE: MAP-Elites tip ceiling. Its coverage archive holds the serve-
	# everyone plan the plain EA abandons, so the expert tip total it reports is a
	# trustworthy pro ceiling (docs: mapelites5.gd). Also gives max rooms covered.
	var tsim := InjSim.new(self)
	tsim.inj = lv
	tsim.tip_mode = true
	tsim.shift = float(lv.get("shift", 90.0))
	var me = ME.new()
	me.setup(tsim, 0, lv, seeds, STEP, 40404)
	var mres: Dictionary = me.run(expert_budget)
	var expert_tips: float = mres.best_score
	if expert_tips <= 0.0:
		return {"tier": "BROKEN", "note": "no positive-tip plan (MAP-Elites best=%.0f)" % expert_tips}
	# NOVICE accessibility: fraction of random plans reaching EXPERT_FRAC of the ceiling.
	var nov := _novice_tip(tsim, widths, seeds, EXPERT_FRAC * expert_tips, novice_tries)
	var wr: float = float(nov.hits) / float(novice_tries)
	var depth: float = maxf(0.0, expert_tips - nov.med)   # tip headroom (novice -> expert)
	var cover: int = me.max_served()
	var nrooms: int = lv.rooms.size()
	var tier := "EXPERT"
	if wr > 0.40: tier = "TUTORIAL"
	elif wr >= 0.15: tier = "EASY"
	elif wr >= 0.05: tier = "MEDIUM"
	elif wr > 0.0: tier = "HARD"
	else: tier = "EXPERT"   # novices never approach the ceiling; only search finds it
	var note := "nov %.0f%% (legal %d) | novTips=%.0f expertTips=%.0f depth=%.0f cover=%d/%d niches=%d" % [
			wr * 100.0, nov.legal, nov.med, expert_tips, depth, cover, nrooms, mres.niches]
	return {"tier": tier, "note": note, "wr": wr, "expert_tips": expert_tips,
			"novice_tips": nov.med, "depth": depth, "cover": cover, "niches": mres.niches}


func _served_str(cells: Array) -> String:
	var s := []
	for rid in RG.served_rooms_of_cells(cells):
		s.append(Grid5.room_letter(rid))
	s.sort()
	return "".join(s)


# ---- OUTER MAP-ELITES over LEVEL DESIGNS (illuminate the design space) ----------------
## The design behavioral descriptor: [nrooms, compactness_bin]. nrooms is the size axis;
## compactness = room cells / bounding-box area (dense packing vs sprawl) is a shape axis
## independent of size. Two designs in different niches LOOK different -> gives goal A.
func _design_bd(lv: Dictionary) -> Array:
	var nrooms: int = lv.rooms.size()
	var cells := 0
	var minx := 9999; var miny := 9999; var maxx := -1; var maxy := -1
	for rm in lv.rooms:
		for c in rm.cells:
			cells += 1
			minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
			miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
	var bbox: float = maxf(1.0, float((maxx - minx + 1) * (maxy - miny + 1)))
	var compact: float = float(cells) / bbox
	var cbin: int = clampi(int((compact - 0.2) / 0.13), 0, 3)
	return [nrooms, cbin]


## A sorted room-type signature (a second, categorical read on design uniqueness).
func _type_sig(lv: Dictionary) -> String:
	var t := []
	for rm in lv.rooms:
		t.append(str(rm.type))
	t.sort()
	return "+".join(t)


## MAP-Elites over designs. Genome = (seed, nrooms); each is generated, gated (novice
## probe + MAP-Elites expert oracle), and filed into the [nrooms x compactness] archive
## keeping the design that best maximises FITNESS = difficulty (1-novice_success) + range
## (depth/expert). One elite per niche = a diverse set (A); fitness rewards hard (B) and
## wide-gap (C) designs. Emitter: mostly fresh random draws (seed chaotic => ~restart),
## with nrooms cycled to fill size niches, plus occasional nudges of an elite's nrooms.
## Writes the archive to `jpath` after every eval so a long run's partial results survive.
func _mapgen(outer_budget: int, expert_budget: int, jpath: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250820
	var archive := {}
	var rejects := 0
	var evals := 0
	var sigs := {}
	var nroom_cycle := [4, 5, 6, 6, 5, 7]
	while evals < outer_budget:
		# choose a design genome
		var seed_v: int
		var nrooms: int
		if archive.size() >= 4 and rng.randf() < 0.35:
			var vals: Array = archive.values()
			var e: Dictionary = vals[rng.randi_range(0, vals.size() - 1)]
			nrooms = clampi(int(e.nrooms) + rng.randi_range(-1, 1), 4, 8)
			seed_v = rng.randi_range(1, 900000)
		else:
			nrooms = nroom_cycle[evals % nroom_cycle.size()]
			seed_v = rng.randi_range(1, 900000)
		var lv := _generate(seed_v, nrooms)
		if lv.is_empty():
			continue   # generation miss (doesn't count as an eval)
		var res := _classify(lv, expert_budget, 20)
		evals += 1
		if res.tier == "BROKEN" or float(res.get("expert_tips", 0.0)) < 120.0:
			rejects += 1
		else:
			var difficulty: float = 1.0 - float(res.wr)
			var rng_score: float = float(res.depth) / maxf(1.0, float(res.expert_tips))
			var fitness: float = difficulty + rng_score
			var bd := _design_bd(lv)
			var sig := _type_sig(lv)
			sigs[sig] = int(sigs.get(sig, 0)) + 1
			var cand := {"seed": seed_v, "req": nrooms, "nrooms": int(lv.rooms.size()), "cbin": bd[1],
					"fitness": fitness, "difficulty": difficulty, "range": rng_score,
					"wr": float(res.wr), "expert": float(res.expert_tips),
					"novice": float(res.novice_tips), "depth": float(res.depth),
					"cover": int(res.cover), "tier": str(res.tier), "sig": sig}
			var nkey := "%d|%d" % [bd[0], bd[1]]
			if not archive.has(nkey) or fitness > archive[nkey].fitness:
				archive[nkey] = cand
		_mapgen_save(jpath, archive, evals, rejects, sigs)
		print("  eval %d/%d seed %d r%d -> %-8s %s" % [evals, outer_budget, seed_v, nrooms,
				res.tier, res.get("note", "")])
	_mapgen_report(archive, evals, rejects, sigs)


func _mapgen_save(jpath: String, archive: Dictionary, evals: int, rejects: int, sigs: Dictionary) -> void:
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"evals": evals, "rejects": rejects,
			"distinct_types": sigs.size(), "archive": archive.values()}))
	f.close()


func _mapgen_report(archive: Dictionary, evals: int, rejects: int, sigs: Dictionary) -> void:
	var els: Array = archive.values()
	print("\n=== MAP-ELITES DESIGN ARCHIVE (%d evals, %d shippable, %d rejects, %d distinct type-sigs) ===" % [
			evals, els.size(), rejects, sigs.size()])
	els.sort_custom(func(a, b): return a.fitness > b.fitness)
	print("  [A] archive niches (nrooms x compactness) -- each a distinct design:")
	print("  %-6s %-5s %-8s %-4s %-5s %-5s %-5s %-5s %s" % ["seed", "rooms", "tier", "cbin", "fit", "diff", "range", "cover", "expert/novice/depth"])
	for e in els:
		print("  %-6d %-5d %-8s %-4d %-5.2f %-5.2f %-5.2f %d/%d  %.0f/%.0f/%.0f  %s" % [
				e.seed, e.nrooms, e.tier, e.cbin, e.fitness, e.difficulty, e.range,
				e.cover, e.nrooms, e.expert, e.novice, e.depth, e.sig])
	var by_diff: Array = els.duplicate()
	by_diff.sort_custom(func(a, b): return a.difficulty > b.difficulty)
	print("  [B] hardest (lowest novice success):")
	for i in mini(5, by_diff.size()):
		var e: Dictionary = by_diff[i]
		print("    seed %d r%d  novice %.0f%% success  expert=%.0f  (%s)" % [e.seed, e.nrooms, (1.0 - e.difficulty) * 100.0, e.expert, e.tier])
	var by_rng: Array = els.duplicate()
	by_rng.sort_custom(func(a, b): return a.depth > b.depth)
	print("  [C] widest novice->expert gap:")
	for i in mini(5, by_rng.size()):
		var e: Dictionary = by_rng[i]
		print("    seed %d r%d  novice=%.0f -> expert=%.0f  (+%.0f tips, range %.2f)" % [e.seed, e.nrooms, e.novice, e.expert, e.depth, e.range])


func _routes_json(routes: Array) -> Array:
	var out := []
	for r in routes:
		var cells := []
		for c in r.cells:
			cells.append([c.x, c.y])
		out.append({"cells": cells, "closed": r.get("closed", false), "serves": _served_str(r.cells)})
	return out


## Solve a generated level and save NOVICE (a clumsy/near-miss plan) + EXPERT (optimal)
## route-sets, so a windowed pass can draw each for the comparison shots.
func _solve(seed_v: int, nrooms: int, jpath: String) -> void:
	var lv := _generate(seed_v, nrooms)
	if lv.is_empty():
		print("gen failed"); return
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var sim := InjSim.new(self)
	sim.inj = lv
	var seeds := SimApi5.SEEDS_TRAIN.slice(0, 3)
	var opt = Opt.new()
	opt.setup(sim, 0, lv, seeds, STEP, 40404)
	opt.run_ea(1600, [1600])
	var winners := []
	var losers := []
	for e in opt.archive:
		if e.score >= SimApi5.WIN_BONUS:
			winners.append(e)
		elif e.score > SimApi5.NEG_INF + 1.0:
			losers.append(e)
	winners.sort_custom(func(a, b): return a.score > b.score)
	losers.sort_custom(func(a, b): return a.score > b.score)
	var save := {"seed": seed_v, "nrooms": nrooms}
	if not winners.is_empty():
		save["expert"] = {"routes": _routes_json(winners[0].routes), "twin": 1300.0 - winners[0].score}
		save["slow"] = {"routes": _routes_json(winners[winners.size() - 1].routes), "twin": 1300.0 - winners[winners.size() - 1].score}
	if not losers.is_empty():
		save["loser"] = {"routes": _routes_json(losers[0].routes), "score": losers[0].score}
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(save))
	f.close()
	print("solve seed %d r%d: winners=%d losers=%d expert=%.0fs slow=%.0fs -> %s" % [
			seed_v, nrooms, winners.size(), losers.size(),
			save.get("expert", {}).get("twin", -1.0), save.get("slow", {}).get("twin", -1.0), jpath])


func _draw(jpath: String, which: String, shot: String) -> void:
	var f := FileAccess.open(jpath, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var lv := _generate(int(data.seed), int(data.nrooms))
	Levels5.injected = lv
	Levels5.headless = false
	Levels5.current = 0
	var scene: Node = load("res://scenes/v5_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.to_plan()
	if data.has(which):
		for i in data[which].routes.size():
			var cells: Array = []
			for xy in data[which].routes[i].cells:
				cells.append(Vector2i(int(xy[0]), int(xy[1])))
			scene.commit_route(i, cells, bool(data[which].routes[i].closed))
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot)
	print("drew %s -> %s" % [which, shot])


## Overfitting probe: score a saved EXPERT plan on the seeds the EA trained on (coarse
## step) vs the SAME seeds fine vs HELD-OUT test seeds. A big train->test drop = the
## kinks are seed-timing hacks; equal scores = the kinks are harmless (neutral drift).
func _check(jpath: String) -> void:
	var f := FileAccess.open(jpath, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var lv := _generate(int(data.seed), int(data.nrooms))
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var sim := InjSim.new(self)
	sim.inj = lv
	var routes := []
	for r in data.expert.routes:
		var cells := []
		for xy in r.cells:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
		routes.append({"cells": cells, "closed": bool(r.closed)})
	var train := SimApi5.SEEDS_TRAIN.slice(0, 3)
	var report := func(label: String, seedset: Array, step: float) -> void:
		var res: Dictionary = sim.score_seeds(0, routes, seedset, step)
		var wins := 0
		var times := []
		for st in res.stats:
			if st.result == "win":
				wins += 1
				times.append(st.t_end)
		var avg := 0.0
		for t in times:
			avg += t
		avg = (avg / times.size()) if times.size() > 0 else -1.0
		print("  %-22s median=%.1f  wins=%d/%d  avg_win=%.1fs" % [label, res.score, wins, seedset.size(), avg])
	print("EXPERT plan check: seed %d r%d (serves %s)" % [int(data.seed), int(data.nrooms),
			str(data.expert.routes.map(func(r): return r.serves))])
	report.call("TRAIN x3 @0.5 (EA view)", train, 0.5)
	report.call("TRAIN x3 @0.1 (fine)", train, 0.1)
	report.call("TRAIN x8 @0.1", SimApi5.SEEDS_TRAIN, 0.1)
	report.call("TEST  x8 @0.1 (held out)", SimApi5.SEEDS_TEST, 0.1)


func _parse_routes(rj: Array) -> Array:
	var out := []
	for r in rj:
		var cells := []
		for xy in r.cells:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
		out.append({"cells": cells, "closed": bool(r.closed)})
	return out


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var v := a.duplicate()
	v.sort()
	return float(v[(v.size() - 1) / 2])


## TIP prototype: score expert (clean/optimal) vs slow (kinky) vs loser plans under the
## tip metric on HELD-OUT seeds, and map to Overcooked-style stars. Shows the tips give a
## gradient where win-time is flat: the kinky plan collects fewer tips.
func _tips(jpath: String) -> void:
	var f := FileAccess.open(jpath, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var lv := _generate(int(data.seed), int(data.nrooms))
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var sim := InjSim.new(self)
	sim.inj = lv
	var rows := []
	for k in ["expert", "slow", "loser"]:
		if not data.has(k):
			continue
		var routes := _parse_routes(data[k].routes)
		var cells := 0
		for rt in routes:
			cells += (rt.cells as Array).size()
		var tips := []
		var served := []
		var lost := []
		var wait := []
		for s in SimApi5.SEEDS_TEST:
			var r: Dictionary = sim.run(0, routes, s, 0.25, lv)
			tips.append(r.tips)
			served.append(float(r.served))
			lost.append(float(r.lost))
			wait.append(r.avg_wait)
		rows.append({"k": k, "tips": _median(tips), "served": _median(served),
				"lost": _median(lost), "wait": _median(wait), "cells": cells})
	print("TIP totals (game shift model): seed %d r%d" % [int(data.seed), int(data.nrooms)])
	for r in rows:
		print("  %-7s tips=%6.1f  served=%2.0f fail=%2.0f  avg_wait=%4.1fs  cells=%2d" % [
				r.k, r.tips, r.served, r.lost, r.wait, r.cells])


## Solve with TIPS as the fitness (shift model) via the MAP-Elites oracle. The archive's
## coverage axis holds the serve-everyone plan the plain EA abandons, so the expert plan
## comes out full-coverage without a smoothness tiebreaker. Saves as `expert` for drawing.
func _solve_tips(seed_v: int, nrooms: int, jpath: String, budget := 1600) -> void:
	var lv := _generate(seed_v, nrooms)
	if lv.is_empty():
		print("gen failed"); return
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var sim := InjSim.new(self)
	sim.inj = lv
	sim.tip_mode = true
	sim.shift = 90.0
	var me = ME.new()
	me.setup(sim, 0, lv, SimApi5.SEEDS_TRAIN.slice(0, 3), STEP, 40404)
	var res: Dictionary = me.run(budget)
	var routes: Array = res.best_routes
	var save := {"seed": seed_v, "nrooms": nrooms,
			"expert": {"routes": _routes_json(routes), "tips": res.best_score}}
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(save))
	f.close()
	var cells := 0
	for rt in routes:
		cells += (rt.cells as Array).size()
	print("solvetips(MAP-Elites) seed %d r%d: best_tips=%.1f cells=%d niches=%d serves=%s -> %s" % [
			seed_v, nrooms, res.best_score, cells, res.niches, str(routes.map(func(r): return _served_str(r.cells))), jpath])


func _vecs(cells: Array) -> String:
	var toks := []
	for c in cells:
		toks.append("Vector2i(%d, %d)" % [c.x, c.y])
	return ", ".join(toks)


func _dir(d: Vector2i) -> String:
	if d == Vector2i(1, 0): return "R"
	if d == Vector2i(-1, 0): return "L"
	if d == Vector2i(0, 1): return "U"
	return "D"


func _colname(c: Color) -> String:
	if c.is_equal_approx(Color(0.45, 0.68, 0.95)): return "COL_A"
	if c.is_equal_approx(Color(0.80, 0.55, 0.92)): return "COL_D"
	if c.is_equal_approx(Color(0.98, 0.68, 0.2)): return "COL_C"
	return "Color(%.2f, %.2f, %.2f)" % [c.r, c.g, c.b]


## Emit a generated level as a GDScript LEVELS entry + its smoke _solution case.
func _dump(seed_v: int, nrooms: int, id: String, name: String, soljson: String) -> void:
	var lv := _generate(seed_v, nrooms)
	if lv.is_empty():
		print("gen failed"); return
	print("\t{")
	print("\t\t\"id\": \"%s\", \"world\": \"CROSSLINK\", \"name\": \"%s\", \"thesis\": \"\", \"intro\": \"\"," % [id, name])
	print("\t\t\"cols\": %d, \"rows\": %d, \"blocked\": []," % [lv.cols, lv.rows])
	print("\t\t\"overlaps\": [")
	print("\t\t\t{\"cells\": [%s], \"max\": 3}," % _vecs(lv.overlaps[0].cells))
	print("\t\t\t{\"cells\": [%s], \"max\": 6}," % _vecs(lv.overlaps[1].cells))
	print("\t\t],")
	print("\t\t\"rooms\": [")
	for rm in lv.rooms:
		var lbl: String = (", \"label\": \"%s\"" % rm.label) if rm.has("label") else ""
		var drops := []
		for dr in rm.drops:
			drops.append("{\"cell\": Vector2i(%d, %d), \"dir\": %s}" % [dr.cell.x, dr.cell.y, _dir(dr.dir)])
		print("\t\t\t{\"type\": \"%s\"%s, \"cells\": [%s], \"drops\": [%s]}," % [rm.type, lbl, _vecs(rm.cells), ", ".join(drops)])
	print("\t\t],")
	print("\t\t\"cards\": [")
	for cd in lv.cards:
		var extra := ""
		if cd.has("speed"):
			extra = ", \"speed\": %.1f, \"accel\": %.1f" % [cd.speed, cd.accel]
		print("\t\t\t{\"name\": \"%s\", \"type\": \"%s\", \"color\": %s%s}," % [cd.name, cd.type, _colname(cd.color), extra])
	print("\t\t],")
	print("\t\t\"quota\": %d, \"max_lost\": %d, \"shift\": %.1f," % [lv.quota, lv.max_lost, lv.get("shift", 90.0)])
	var sp: Dictionary = lv.spawn
	print("\t\t\"spawn\": {\"interval_start\": %.1f, \"interval_end\": %.1f, \"ramp\": %.1f, \"burst_min\": %d, \"burst_max\": %d, \"gap\": %.1f, \"cover\": true}," % [
			sp.interval_start, sp.interval_end, sp.ramp, sp.burst_min, sp.burst_max, sp.gap])
	print("\t\t\"mix\": {\"visitor\": 0.6, \"shopper\": 0.25, \"patient\": 0.15},")
	print("\t\t\"trips\": [")
	for tr in lv.trips:
		var ty: String = (", \"type\": \"%s\"" % tr.type) if tr.has("type") else ""
		print("\t\t\t{\"w\": %.2f, \"from\": \"%s\", \"to\": \"%s\"%s}," % [tr.w, tr.from, tr.to, ty])
	print("\t\t],")
	print("\t},")
	# smoke solution (win-optimal expert routes, quota-mode winnable)
	var f := FileAccess.open(soljson, FileAccess.READ)
	if f != null:
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		if data.has("expert"):
			print("\t\t\t\"%s\":" % id)
			var parts := []
			for r in data.expert.routes:
				var cc := []
				for xy in r.cells:
					cc.append("[%d,%d]" % [int(xy[0]), int(xy[1])])
				parts.append("_c([%s])" % ",".join(cc))
			print("\t\t\t\treturn [%s]" % ",\n\t\t\t\t\t\t".join(parts))


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode: String = str(args[0]) if args.size() > 0 else "render"
	if mode == "solve":
		_solve(int(args[1]), int(args[2]), str(args[3]))
		quit(); return
	if mode == "draw":
		await _draw(str(args[1]), str(args[2]), str(args[3]))
		quit(); return
	if mode == "check":
		_check(str(args[1]))
		quit(); return
	if mode == "tips":
		_tips(str(args[1]))
		quit(); return
	if mode == "solvetips":
		var b := int(args[4]) if args.size() > 4 else 1600
		_solve_tips(int(args[1]), int(args[2]), str(args[3]), b)
		quit(); return
	if mode == "mapgen":
		var outer := int(args[1])
		var expert_b := int(args[2]) if args.size() > 2 else 500
		var jp := str(args[3]) if args.size() > 3 else "mapgen.json"
		_mapgen(outer, expert_b, jp)
		quit(); return
	if mode == "dump":
		_dump(int(args[1]), int(args[2]), str(args[3]), str(args[4]), str(args[5]))
		quit(); return
	if mode == "gate" or mode == "batch":
		var lo := int(args[1])
		var hi := int(args[2]) if args.size() > 2 else lo
		var nrooms := int(args[3]) if args.size() > 3 else 0   # 0 = seed-derived
		var tally := {}
		for s in range(lo, hi + 1):
			var lv := _generate(s, nrooms)
			if lv.is_empty():
				print("  seed %d -> (gen failed)" % s)
				continue
			var res := _classify(lv)
			tally[res.tier] = int(tally.get(res.tier, 0)) + 1
			print("  seed %d (r%d): %d rooms %dx%d cards=%d -> %-8s %s" % [s, nrooms, lv.rooms.size(), lv.cols, lv.rows, lv.cards.size(), res.tier, res.note])
		print("\nTIER TALLY: %s" % str(tally))
		quit(); return
	if mode == "render":
		var seed_v := int(args[1])
		var shot: String = str(args[2])
		var nr := int(args[3]) if args.size() > 3 else 0
		var lv := _generate(seed_v, nr)
		if lv.is_empty():
			print("seed %d: generation failed" % seed_v)
			quit(); return
		Levels5.injected = lv
		Levels5.headless = false
		Levels5.current = 0
		var scene: Node = load("res://scenes/v5_main.tscn").instantiate()
		root.add_child(scene)
		for _i in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("seed %d: %d rooms %dx%d cards=%d -> %s" % [seed_v, lv.rooms.size(), lv.cols, lv.rows, lv.cards.size(), shot])
	quit()
