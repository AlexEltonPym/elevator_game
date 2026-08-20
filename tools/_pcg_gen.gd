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
	# LEGALITY RULE: storage(delivery) implies cafe (it delivers to one); a cafe does NOT
	# require storage. If cafe failed to place, drop any orphan storage rooms (repair, not
	# reject) so we never ship a storage with no cafe + a dangling cargo card.
	var has_cafe := false
	for rm in rooms:
		if rm.type == "cafe":
			has_cafe = true
	if not has_cafe:
		var kept := []
		for rm in rooms:
			if rm.type != "delivery":
				kept.append(rm)
		rooms = kept
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


## Wrap placed rooms into a full level: caps, cards, cover trips. `blocks` are 1x1
## impassable "window" cells routes must detour around (Grid5.passable is false for them).
func _wrap(cols: int, rows: int, rooms: Array, blocks := []) -> Dictionary:
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
	var blockset := {}
	for b in blocks:
		blockset[b] = true
	var cap3 := []
	for x in cols:
		for y in rows:
			var c := Vector2i(x, y)
			if not occ.has(c) and not dockset.has(c) and not blockset.has(c):
				cap3.append(c)
	return {
		"id": "GEN", "world": "CROSSLINK", "name": "Generated", "thesis": "", "intro": "",
		"cols": cols, "rows": rows, "blocked": blockset.keys(), "rooms": rooms,
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
	var seeds := SimApi5.SEEDS_TRAIN.slice(0, 2)
	# EXPERT ORACLE: MAP-Elites tip ceiling. Its coverage archive holds the serve-
	# everyone plan the plain EA abandons, so the expert tip total it reports is a
	# trustworthy pro ceiling (docs: mapelites5.gd). Also gives max rooms covered.
	var tsim := InjSim.new(self)
	tsim.inj = lv
	tsim.tip_mode = true
	tsim.shift = float(lv.get("shift", 90.0))
	var me = ME.new()
	me.setup(tsim, 0, lv, seeds, STEP, 40404)
	# ADEPT tier = best tips after a fixed brief effort (a player who thinks a little, not a
	# full search); EXPERT = best at full budget. The adept->expert gap is the MIN-MAX
	# HEADROOM, captured free. Keep adept_at small+fixed so it means the same "brief thought"
	# regardless of the expert budget, and so a deep level shows real headroom above it.
	var adept_at: int = mini(60, expert_budget / 2)
	var mres: Dictionary = me.run(expert_budget, adept_at)
	var expert_tips: float = mres.best_score
	if expert_tips <= 0.0:
		return {"tier": "BROKEN", "note": "no positive-tip plan (MAP-Elites best=%.0f)" % expert_tips}
	var adept_tips: float = mres.adept_score
	var adept_cover: int = mres.adept_cover
	# NOVICE accessibility: fraction of random plans reaching EXPERT_FRAC of the ceiling.
	var nov := _novice_tip(tsim, widths, seeds, EXPERT_FRAC * expert_tips, novice_tries)
	var wr: float = float(nov.hits) / float(novice_tries)
	var depth: float = maxf(0.0, expert_tips - nov.med)   # novice -> expert (correlates w/ difficulty)
	var cover: int = me.max_served()
	var nrooms: int = lv.rooms.size()
	# SWEEP = adept->expert headroom, GATED on the adept plan being a competent floor
	# (positive tips AND serving ~everyone). This decorrelates from difficulty: a level is
	# a good "sweep" when a quick plan already serves almost everyone a bit late and there's
	# real room to min-max on top — not merely when novices fail.
	var floor_ok: bool = adept_tips > 0.0 and adept_cover >= nrooms - 1
	var sweep: float = maxf(0.0, expert_tips - adept_tips) * (1.0 if floor_ok else 0.25)
	var tier := "EXPERT"
	if wr > 0.40: tier = "TUTORIAL"
	elif wr >= 0.15: tier = "EASY"
	elif wr >= 0.05: tier = "MEDIUM"
	elif wr > 0.0: tier = "HARD"
	else: tier = "EXPERT"   # novices never approach the ceiling; only search finds it
	var note := "nov %.0f%% | adept=%.0f(cov%d)%s expert=%.0f sweep=%.0f | novDepth=%.0f cover=%d/%d fcN=%d" % [
			wr * 100.0, adept_tips, adept_cover, "" if floor_ok else "!", expert_tips, sweep,
			depth, cover, nrooms, mres.full_cover_niches]
	return {"tier": tier, "note": note, "wr": wr, "expert_tips": expert_tips,
			"adept_tips": adept_tips, "adept_cover": adept_cover, "sweep": sweep,
			"floor_ok": floor_ok, "novice_tips": nov.med, "depth": depth, "cover": cover,
			"full_cover_niches": mres.full_cover_niches, "niches": mres.niches}


func _served_str(cells: Array) -> String:
	var s := []
	for rid in RG.served_rooms_of_cells(cells):
		s.append(Grid5.room_letter(rid))
	s.sort()
	return "".join(s)


# ---- OUTER MAP-ELITES over LEVEL DESIGNS (illuminate the design space) ----------------
## The 5-D design behavioral descriptor: [nrooms, compactness(2), has_cargo, has_atrium,
## has_penthouse]. nrooms + compactness are size/shape; the three binaries are the CARD
## LOADOUT (which lifts the puzzle is about) — the mechanical identity that makes designs
## feel distinct. 5*2*2*2*2 = 80 cells, but many are structurally impossible (cargo needs
## cafe+delivery, atrium needs >=6 rooms) so effective niches are ~30-40. Goal A.
func _design_bd(lv: Dictionary) -> Array:
	var nrooms: int = lv.rooms.size()
	var cells := 0
	var minx := 9999; var miny := 9999; var maxx := -1; var maxy := -1
	var has_cafe := false; var has_delivery := false; var has_atrium := false; var has_penth := false
	for rm in lv.rooms:
		match str(rm.type):
			"cafe": has_cafe = true
			"delivery": has_delivery = true
			"atrium": has_atrium = true
			"penthouse": has_penth = true
		for c in rm.cells:
			cells += 1
			minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
			miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
	var bbox: float = maxf(1.0, float((maxx - minx + 1) * (maxy - miny + 1)))
	var compact: float = float(cells) / bbox
	var cbin: int = clampi(int((compact - 0.32) / 0.14), 0, 1)   # 2 bins: sprawl vs dense
	var cargo: int = 1 if (has_cafe and has_delivery) else 0
	var has_blocks: int = 1 if (lv.get("blocked", []) as Array).size() > 0 else 0
	return [nrooms, cbin, cargo, 1 if has_atrium else 0, 1 if has_penth else 0, has_blocks]


func _bd_key(bd: Array) -> String:
	return "%d|%d|%d|%d|%d|%d" % [bd[0], bd[1], bd[2], bd[3], bd[4], bd[5]]


## A sorted room-type signature (a second, categorical read on design uniqueness).
func _type_sig(lv: Dictionary) -> String:
	var t := []
	for rm in lv.rooms:
		t.append(str(rm.type))
	t.sort()
	return "+".join(t)


## MAP-Elites over designs. Genome = (seed, nrooms); each is generated, gated (novice
## probe + MAP-Elites adept/expert oracle), and filed into the 5-D [nrooms x compactness x
## cargo x atrium x penthouse] FEASIBLE archive keeping the design that best maximises
## FITNESS = SWEEP (adept->expert min-max headroom, gated on an accessible competent floor).
## Infeasible / illegal designs go to a SEPARATE archive (the FI two-map structure) so we
## can see the broken niches; note that without a mutable genome they are catalogued, not
## evolved. Reports A (niches), B (hardest), C (widest sweep). Partial-safe JSON each eval.
func _mapgen(outer_budget: int, expert_budget: int, jpath: String, seed_offset := 0) -> void:
	# RESUMABLE: load any existing archive so a fresh short-lived process can CONTINUE it
	# (process-per-chunk sidesteps the GDScript CLI memory leak that OOM-kills long runs).
	var loaded := _mapgen_load(jpath)
	var archive: Dictionary = loaded.archive      # feasible: bd_key -> design (best sweep)
	var infeasible: Dictionary = loaded.infeasible # broken/illegal: bd_key -> {seed, reason}
	var sigs: Dictionary = loaded.sigs
	var total: int = loaded.evals                 # evals across all chunks so far
	var rng := RandomNumberGenerator.new()
	# advance the stream so chunks don't repeat; seed_offset diverges parallel workers.
	rng.seed = 20250820 + (total + seed_offset) * 1009
	var did := 0                                  # NEW evals this chunk
	var nroom_cycle := [4, 5, 6, 6, 5, 7, 8]
	while did < outer_budget:
		var seed_v: int
		var nrooms: int
		if archive.size() >= 4 and rng.randf() < 0.35:
			var vals: Array = archive.values()
			var e: Dictionary = vals[rng.randi_range(0, vals.size() - 1)]
			nrooms = clampi(int(e.req) + rng.randi_range(-1, 1), 4, 8)
			seed_v = rng.randi_range(1, 900000)
		else:
			nrooms = nroom_cycle[total % nroom_cycle.size()]
			seed_v = rng.randi_range(1, 900000)
		var lv := _generate(seed_v, nrooms)
		if lv.is_empty():
			continue   # generation miss (doesn't count as an eval)
		var res := _classify(lv, expert_budget, 20)
		did += 1
		total += 1
		var bd := _design_bd(lv)
		var nkey := _bd_key(bd)
		if res.tier == "BROKEN" or float(res.get("expert_tips", 0.0)) < 120.0:
			# INFEASIBLE map: keep one representative per niche (the two-map FI structure).
			if not infeasible.has(nkey):
				infeasible[nkey] = {"key": nkey, "seed": seed_v, "req": nrooms, "nrooms": int(lv.rooms.size()),
						"reason": str(res.get("note", res.tier)), "sig": _type_sig(lv)}
		else:
			var sig := _type_sig(lv)
			sigs[sig] = int(sigs.get(sig, 0)) + 1
			var difficulty: float = 1.0 - float(res.wr)
			var cand := {"key": nkey, "seed": seed_v, "req": nrooms, "nrooms": int(lv.rooms.size()),
					"cbin": bd[1], "cargo": bd[2], "atrium": bd[3], "penth": bd[4],
					"fitness": float(res.sweep), "sweep": float(res.sweep),
					"difficulty": difficulty, "wr": float(res.wr),
					"expert": float(res.expert_tips), "adept": float(res.adept_tips),
					"floor_ok": bool(res.floor_ok), "novice": float(res.novice_tips),
					"depth": float(res.depth), "cover": int(res.cover),
					"fcov_niches": int(res.full_cover_niches), "tier": str(res.tier), "sig": sig}
			if not archive.has(nkey) or cand.fitness > archive[nkey].fitness:
				archive[nkey] = cand
		_mapgen_save(jpath, archive, infeasible, total, sigs)
		print("  eval %d (chunk %d/%d) seed %d r%d -> %-8s %s" % [total, did, outer_budget, seed_v, nrooms,
				res.tier, res.get("note", "")])
	_mapgen_report(archive, infeasible, total, sigs)


## Reload a mapgen archive so a fresh process continues it (process-per-chunk robustness).
func _mapgen_load(jpath: String) -> Dictionary:
	var out := {"archive": {}, "infeasible": {}, "sigs": {}, "evals": 0}
	if not FileAccess.file_exists(jpath):
		return out
	var f := FileAccess.open(jpath, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return out
	out.evals = int(data.get("evals", 0))
	for e in data.get("archive", []):
		out.archive[str(e.get("key", ""))] = e
		out.sigs[str(e.get("sig", ""))] = int(out.sigs.get(str(e.get("sig", "")), 0)) + 1
	for e in data.get("infeasible", []):
		out.infeasible[str(e.get("key", ""))] = e
	return out


func _mapgen_save(jpath: String, archive: Dictionary, infeasible: Dictionary, evals: int, sigs: Dictionary) -> void:
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"evals": evals, "feasible_niches": archive.size(),
			"infeasible_niches": infeasible.size(), "distinct_types": sigs.size(),
			"archive": archive.values(), "infeasible": infeasible.values()}))
	f.close()


func _mapgen_report(archive: Dictionary, infeasible: Dictionary, evals: int, sigs: Dictionary) -> void:
	var els: Array = archive.values()
	print("\n=== MAP-ELITES DESIGN ARCHIVE (%d evals | %d feasible niches, %d infeasible niches, %d distinct room-comps) ===" % [
			evals, els.size(), infeasible.size(), sigs.size()])
	els.sort_custom(func(a, b): return a.sweep > b.sweep)
	print("  [A] feasible niches (nrooms|compact|cargo|atrium|penth) -- each a distinct design:")
	print("  %-6s %-4s %-8s %-5s %-5s %-5s %-5s %-5s %s" % ["seed", "room", "tier", "sweep", "adept", "exprt", "diff", "fcovN", "cargo/atr/pen  comp"])
	for e in els:
		print("  %-6d %-4d %-8s %-5.0f %-5.0f %-5.0f %-5.2f %-5d %d/%d/%d  %s" % [
				e.seed, e.nrooms, e.tier, e.sweep, e.adept, e.expert, e.difficulty,
				e.fcov_niches, e.cargo, e.atrium, e.penth, e.sig])
	var by_diff: Array = els.duplicate()
	by_diff.sort_custom(func(a, b): return a.difficulty > b.difficulty)
	print("  [B] hardest (lowest novice success):")
	for i in mini(5, by_diff.size()):
		var e: Dictionary = by_diff[i]
		print("    seed %d r%d(req%d)  novice %.0f%% success  expert=%.0f  (%s)" % [e.seed, e.nrooms, e.req, (1.0 - e.difficulty) * 100.0, e.expert, e.tier])
	var by_sweep: Array = els.duplicate()
	by_sweep.sort_custom(func(a, b): return a.sweep > b.sweep)
	print("  [C] widest SWEEP (competent-quick -> min-maxed expert, floor accessible):")
	for i in mini(6, by_sweep.size()):
		var e: Dictionary = by_sweep[i]
		var flag: String = "" if e.floor_ok else " (floor weak)"
		print("    seed %d r%d(req%d)  adept=%.0f -> expert=%.0f  (+%.0f sweep, %d full-cov rungs)%s" % [
				e.seed, e.nrooms, e.req, e.adept, e.expert, e.sweep, e.fcov_niches, flag])
	if not infeasible.is_empty():
		print("  [FI] infeasible archive (%d niches catalogued, not yet evolved -- needs a mutable genome):" % infeasible.size())
		var infs: Array = infeasible.values()
		for i in mini(4, infs.size()):
			print("    seed %d r%d: %s" % [infs[i].seed, infs[i].nrooms, infs[i].reason])


# ===== MUTABLE LEVEL GENOME + FEASIBLE-INFEASIBLE MAP-ELITES ============================
## Genome = {cols, rows, rooms:[{type, ax, ay, flip}]} (lobby is rooms[0]). Unlike the
## seed-sampler, this is a DIRECTLY MUTABLE design: small edits give nearby designs (a
## smooth landscape for QD), and an infeasible design can be REPAIRED toward feasibility
## and migrate into the feasible archive -- the whole point of keeping a two-map FI split.
const PALETTE := ["apartment", "cafe", "penthouse", "delivery", "atrium"]
const MAX_BLOCKS := 6


func _clone_design(g: Dictionary) -> Dictionary:
	var rooms := []
	for r in g.rooms:
		rooms.append((r as Dictionary).duplicate())
	var blocks := []
	for b in g.get("blocks", []):
		blocks.append(b)
	return {"cols": g.cols, "rows": g.rows, "rooms": rooms, "blocks": blocks}


## Build a room's cells/drops from a gene (no legality; cells may fall out of bounds).
func _gene_room(gene: Dictionary) -> Dictionary:
	var type: String = gene.type
	var tpl: Dictionary = _flip(_templates()[type]) if gene.get("flip", false) else _templates()[type].duplicate(true)
	var ax: int = gene.ax
	var ay: int = gene.ay
	var cells := []
	for c in tpl.cells:
		cells.append(Vector2i(ax + c.x, ay + c.y))
	var drops := []
	for d in tpl.docks:
		drops.append({"cell": Vector2i(ax + d.c.x, ay + d.c.y), "dir": d.dir})
	var room := {"type": type, "cells": cells, "drops": drops}
	if tpl.has("label"):
		room["label"] = tpl.label
	return room


## Assess a genome: returns {feasible, distance, level}. distance = weighted count of rule
## violations (overlaps, out-of-bounds, dock-on-room, rule-2c, unreachable docks, orphan
## storage). 0 => feasible and `level` is the wrapped playable dict. INFEASIBLE assessment
## is CHEAP (pure geometry, no simulation) -- only feasible designs pay the gate.
func _assess_design(genome: Dictionary) -> Dictionary:
	var cols: int = genome.cols
	var rows: int = genome.rows
	var occ := {}          # room cell -> owning room index
	var dockcells := {}    # dock cell -> owning room index (first owner; shared docks OK)
	var built := []
	var viol := 0
	var types := {}
	for gi in genome.rooms.size():
		var gene: Dictionary = genome.rooms[gi]
		types[gene.type] = true
		var room := _gene_room(gene)
		built.append(room)
		for c in room.cells:
			if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
				viol += 1
				continue
			if occ.has(c):
				viol += 1
			occ[c] = gi
	# docks (after all room cells claimed, so dock-on-room is detectable)
	for gi in built.size():
		for dr in built[gi].drops:
			var dc: Vector2i = dr.cell + dr.dir
			if dc.x < 0 or dc.y < 0 or dc.x >= cols or dc.y >= rows:
				viol += 1
				continue
			if occ.has(dc) and occ[dc] != gi:   # dock on ANOTHER room's cell
				viol += 1
			if not dockcells.has(dc):
				dockcells[dc] = gi
	# rule 2c: a dock directly above/below a DIFFERENT room's cell (its own room is fine --
	# e.g. a cafe dock sits under its own cell by design).
	for dc in dockcells:
		var owner: int = dockcells[dc]
		var up: Vector2i = dc + Vector2i(0, 1)
		var dn: Vector2i = dc + Vector2i(0, -1)
		if (occ.has(up) and occ[up] != owner) or (occ.has(dn) and occ[dn] != owner):
			viol += 1
	# BLOCKS: 1x1 impassable window cells. A block on a room cell or a dock cell is illegal
	# (can't wall a room/dock); otherwise blocks are walls routes detour around. `walls` =
	# rooms + blocks is what the reachability flood must go around.
	var blocks: Array = genome.get("blocks", [])
	var walls := occ.duplicate()
	var blockset := {}
	for b in blocks:
		if not (b is Vector2i):
			continue
		if b.x < 0 or b.y < 0 or b.x >= cols or b.y >= rows:
			viol += 1
			continue
		if occ.has(b) or dockcells.has(b) or blockset.has(b):
			viol += 1
			continue
		blockset[b] = true
		walls[b] = true
	# reachability: every dock cell reachable from the first over open cells (not walls)
	var docklist: Array = dockcells.keys()
	if not docklist.is_empty():
		var seen := {}
		var start: Vector2i = docklist[0]
		if not walls.has(start):
			seen[start] = true
			var q: Array = [start]
			var head := 0
			while head < q.size():
				var u: Vector2i = q[head]; head += 1
				for d in RG.NEIGHBORS:
					var v: Vector2i = u + d
					if v.x < 0 or v.y < 0 or v.x >= cols or v.y >= rows or seen.has(v) or walls.has(v):
						continue
					seen[v] = true
					q.append(v)
		for dk in docklist:
			if not seen.has(dk):
				viol += 1
	# legality: storage(delivery) implies cafe
	if types.has("delivery") and not types.has("cafe"):
		viol += 2
	# a valid level needs >= 4 rooms and a lobby
	if built.size() < 4 or not types.has("lobby"):
		viol += 3
	var out := {"feasible": viol == 0, "distance": viol, "level": {}}
	if viol == 0:
		out.level = _wrap(cols, rows, built, blockset.keys())
	return out


## A random (possibly infeasible) design of ~nrooms rooms: lobby on the bottom row, a
## card-enabling wishlist, random anchors + flips. Feasibility is NOT enforced here.
func _random_design(rng: RandomNumberGenerator, nrooms: int, cols: int, rows: int) -> Dictionary:
	var wish := ["lobby", "cafe", "penthouse"]
	if nrooms >= 5:
		wish.append("delivery")
	while wish.size() < nrooms:
		wish.append("apartment")
	if nrooms >= 6 and rng.randf() < 0.5:
		wish[wish.size() - 1] = "atrium"
	var rooms := []
	for type in wish:
		var tpl: Dictionary = _templates()[type]
		var flip: bool = rng.randf() < 0.5
		var ax: int = rng.randi_range(0, maxi(0, cols - int(tpl.w)))
		var ay: int = 0 if type == "lobby" else rng.randi_range(0, maxi(0, rows - int(tpl.h)))
		rooms.append({"type": type, "ax": ax, "ay": ay, "flip": flip})
	return {"cols": cols, "rows": rows, "rooms": rooms, "blocks": []}


## Render one fievo design (genome -> level -> screenshot). `selector`: an integer index
## into the feasible archive sorted by sweep (desc), or "block" for the first block-bearing
## design. Rebuilds the level from the stored genome (fievo designs aren't seed-addressable).
func _draw_gen(jpath: String, selector: String, png: String) -> void:
	var f := FileAccess.open(jpath, FileAccess.READ)
	if f == null:
		print("cannot read %s" % jpath); return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	var feas: Array = data.get("feasible", [])
	feas.sort_custom(func(a, b): return float(a.get("sweep", 0)) > float(b.get("sweep", 0)))
	var pick: Dictionary = {}
	if selector == "block":
		for c in feas:
			if (c.genome.get("blocks", []) as Array).size() > 0:
				pick = c; break
	else:
		var idx: int = clampi(int(selector), 0, feas.size() - 1)
		pick = feas[idx]
	if pick.is_empty():
		print("no design matched selector '%s'" % selector); return
	var genome := _genome_parse(pick.genome)
	var a := _assess_design(genome)
	if not a.feasible:
		print("selected design is infeasible (dist %d)" % a.distance); return
	Levels5.injected = a.level
	Levels5.headless = false
	Levels5.current = 0
	var scene: Node = load("res://scenes/v5_main.tscn").instantiate()
	root.add_child(scene)
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(png)
	print("drew %s r%d sweep=%.0f blocks=%d (%s) -> %s" % [pick.get("tier", "?"), int(pick.get("nrooms", 0)),
			float(pick.get("sweep", 0)), (genome.blocks as Array).size(), pick.get("sig", ""), png])


## Pick one design from a fievo archive: integer index into feasible-by-sweep, or "block".
func _pick_gen(jpath: String, selector: String) -> Dictionary:
	var f := FileAccess.open(jpath, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	var feas: Array = data.get("feasible", [])
	feas.sort_custom(func(a, b): return float(a.get("sweep", 0)) > float(b.get("sweep", 0)))
	if selector == "block":
		for c in feas:
			if (c.genome.get("blocks", []) as Array).size() > 0:
				return c
		return {}
	var idx: int = clampi(int(selector), 0, feas.size() - 1)
	return feas[idx] if not feas.is_empty() else {}


## Solve a fievo design: EXPERT (MAP-Elites tip optimum) + NOVICE (a representative random
## legal plan, median tips). Saves genome + both route-sets + held-out tips for the artifact.
func _solve_gen(jpath: String, selector: String, out: String) -> void:
	var pick := _pick_gen(jpath, selector)
	if pick.is_empty():
		print("no design matched '%s'" % selector); return
	var genome := _genome_parse(pick.genome)
	var a := _assess_design(genome)
	if not a.feasible:
		print("selected design infeasible"); return
	var lv: Dictionary = a.level
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var sim := InjSim.new(self)
	sim.inj = lv
	sim.tip_mode = true
	sim.shift = 90.0
	var test := SimApi5.SEEDS_TEST
	# EXPERT via MAP-Elites
	var me = ME.new()
	me.setup(sim, 0, lv, SimApi5.SEEDS_TRAIN.slice(0, 3), STEP, 40404)
	var eres: Dictionary = me.run(1200)
	var expert_routes: Array = eres.best_routes
	var expert_tips: float = sim.score_seeds(0, expert_routes, test, 0.25).score
	# NOVICE: sample random legal plans, keep the median-tip one (a plausible clumsy plan)
	var widths := RG.card_widths(lv)
	var all_docks := RG.docks()
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	var cands := []
	for _i in 50:
		var g := RG.random_genome(rng, all_docks, widths)
		if g.is_empty():
			continue
		var dec := RG.decode_genome(g, widths)
		if dec.err != "":
			continue
		cands.append({"routes": dec.routes, "tips": sim.score_seeds(0, dec.routes, test, 0.25).score})
	cands.sort_custom(func(x, y): return x.tips < y.tips)
	# A representative NOVICE is a plausible clumsy-but-working plan: the median among the
	# POSITIVE-scoring random plans (a beginner who gets the building served, just slowly),
	# not a money-losing disaster. Fall back to the best plan if none score positive.
	var pos := cands.filter(func(c): return c.tips > 0.0)
	var novice: Dictionary
	if pos.size() >= 1:
		novice = pos[pos.size() / 2]
	elif not cands.is_empty():
		novice = cands[cands.size() - 1]
	else:
		novice = {"routes": [], "tips": 0.0}
	var save := {
		"genome": _genome_json(genome), "sig": pick.get("sig", ""), "tier": pick.get("tier", ""),
		"nrooms": int(pick.get("nrooms", 0)), "sweep": float(pick.get("sweep", 0)),
		"nblocks": (genome.blocks as Array).size(),
		"novice": {"routes": _routes_json(novice.routes), "tips": novice.tips},
		"expert": {"routes": _routes_json(expert_routes), "tips": expert_tips}}
	var wf := FileAccess.open(out, FileAccess.WRITE)
	wf.store_string(JSON.stringify(save))
	wf.close()
	print("solvegen %s: novice=%.0f expert=%.0f (r%d %s blk%d) -> %s" % [selector, novice.tips, expert_tips,
			int(pick.get("nrooms", 0)), pick.get("sig", ""), (genome.blocks as Array).size(), out])


## Draw a solved design's NOVICE or EXPERT routes onto its level (windowed screenshot).
func _draw_sol(out: String, which: String, png: String) -> void:
	var f := FileAccess.open(out, FileAccess.READ)
	if f == null:
		print("cannot read %s" % out); return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	var genome := _genome_parse(data.genome)
	var a := _assess_design(genome)
	if not a.feasible:
		print("infeasible"); return
	Levels5.injected = a.level
	Levels5.headless = false
	Levels5.current = 0
	var scene: Node = load("res://scenes/v5_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.to_plan()
	var routes: Array = data[which].routes
	for i in routes.size():
		var cells: Array = []
		for xy in routes[i].cells:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
		scene.commit_route(i, cells, bool(routes[i].get("closed", false)))
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(png)
	print("drew %s (%d routes, %.0f tips) -> %s" % [which, routes.size(), float(data[which].get("tips", 0)), png])


func _same_cells(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var s := {}
	for c in a:
		s[c] = true
	for c in b:
		if not s.has(c):
			return false
	return true


## Recover a gene {type, ax, ay, flip} from a placed room (anchor = min cell corner; flip
## detected by matching the rebuilt cells). Lets us convert a proven-feasible _generate
## level into a mutable genome to SEED the feasible archive (so evolution starts legal).
func _gene_for_room(room: Dictionary) -> Dictionary:
	var minx := 9999; var miny := 9999
	for c in room.cells:
		minx = mini(minx, c.x); miny = mini(miny, c.y)
	for flip in [false, true]:
		var g := {"type": str(room.type), "ax": minx, "ay": miny, "flip": flip}
		if _same_cells(_gene_room(g).cells, room.cells):
			return g
	return {"type": str(room.type), "ax": minx, "ay": miny, "flip": false}


func _level_to_genome(lv: Dictionary) -> Dictionary:
	var rooms := []
	for rm in lv.rooms:
		rooms.append(_gene_for_room(rm))
	var blocks := []
	for b in lv.get("blocked", []):
		blocks.append(b)
	return {"cols": int(lv.cols), "rows": int(lv.rows), "rooms": rooms, "blocks": blocks}


func _clamp_anchor(gene: Dictionary, cols: int, rows: int) -> void:
	var tpl: Dictionary = _templates()[gene.type]
	gene.ax = clampi(gene.ax, 0, maxi(0, cols - int(tpl.w)))
	gene.ay = 0 if gene.type == "lobby" else clampi(gene.ay, 0, maxi(0, rows - int(tpl.h)))


func _nonlobby_idxs(g: Dictionary) -> Array:
	var out := []
	for i in g.rooms.size():
		if g.rooms[i].type != "lobby":
			out.append(i)
	return out


## One mutation. Operator mix tuned for tile puzzles: JIGGLE dominates (local moves keep a
## smooth landscape); RETYPE moves across the cargo/atrium/penthouse archive axes; SWAP
## rearranges the same set; ADD/REMOVE move the size axis; FLIP is cheap variety. When
## `repair` (parent was infeasible) it biases toward re-anchoring a room to open the design
## up, so infeasibles can climb back to feasibility.
func _mut_design(rng: RandomNumberGenerator, g: Dictionary, repair := false) -> Dictionary:
	var out := _clone_design(g)
	var cols: int = out.cols
	var rows: int = out.rows
	var nl := _nonlobby_idxs(out)
	if repair and rng.randf() < 0.6 and not nl.is_empty():
		var ri: int = nl[rng.randi_range(0, nl.size() - 1)]
		out.rooms[ri].ax = rng.randi_range(0, maxi(0, cols - int(_templates()[out.rooms[ri].type].w)))
		out.rooms[ri].ay = rng.randi_range(0, maxi(0, rows - int(_templates()[out.rooms[ri].type].h)))
		return out
	# ~18% of mutations edit BLOCKS (add/move/remove a 1x1 impassable window). A block that
	# lands on a room/dock is caught as an infeasibility and repaired; good blocks force the
	# route detours that make a level interesting.
	if not repair and rng.randf() < 0.18:
		var blocks: Array = out.blocks
		match rng.randi_range(0, 2):
			0:
				if blocks.size() < MAX_BLOCKS:
					blocks.append(Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1)))
			1:
				if not blocks.is_empty():
					var bi: int = rng.randi_range(0, blocks.size() - 1)
					var nb: Vector2i = blocks[bi] + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
					blocks[bi] = Vector2i(clampi(nb.x, 0, cols - 1), clampi(nb.y, 0, rows - 1))
			2:
				if not blocks.is_empty():
					blocks.remove_at(rng.randi_range(0, blocks.size() - 1))
		return out
	var roll := rng.randf()
	if roll < 0.40 and not nl.is_empty():            # JIGGLE
		var i: int = nl[rng.randi_range(0, nl.size() - 1)]
		out.rooms[i].ax += rng.randi_range(-2, 2)
		out.rooms[i].ay += rng.randi_range(-2, 2)
		_clamp_anchor(out.rooms[i], cols, rows)
	elif roll < 0.55 and not nl.is_empty():          # RETYPE
		var i2: int = nl[rng.randi_range(0, nl.size() - 1)]
		var nt: String = PALETTE[rng.randi_range(0, PALETTE.size() - 1)]
		# keep legality: only allow delivery if a cafe exists elsewhere
		var has_cafe := false
		for j in out.rooms.size():
			if j != i2 and out.rooms[j].type == "cafe":
				has_cafe = true
		if nt == "delivery" and not has_cafe:
			nt = "cafe"
		out.rooms[i2].type = nt
		_clamp_anchor(out.rooms[i2], cols, rows)
	elif roll < 0.65 and nl.size() >= 2:             # SWAP positions
		var a: int = nl[rng.randi_range(0, nl.size() - 1)]
		var b: int = nl[rng.randi_range(0, nl.size() - 1)]
		var tax: int = out.rooms[a].ax; var tay: int = out.rooms[a].ay
		out.rooms[a].ax = out.rooms[b].ax; out.rooms[a].ay = out.rooms[b].ay
		out.rooms[b].ax = tax; out.rooms[b].ay = tay
		_clamp_anchor(out.rooms[a], cols, rows); _clamp_anchor(out.rooms[b], cols, rows)
	elif roll < 0.75 and not nl.is_empty():          # FLIP
		var i3: int = nl[rng.randi_range(0, nl.size() - 1)]
		out.rooms[i3].flip = not bool(out.rooms[i3].get("flip", false))
	elif roll < 0.85 and out.rooms.size() < 8:       # ADD
		var t: String = PALETTE[rng.randi_range(0, PALETTE.size() - 1)]
		if t == "delivery":
			var cafe := false
			for r in out.rooms:
				if r.type == "cafe": cafe = true
			if not cafe: t = "apartment"
		out.rooms.append({"type": t, "ax": rng.randi_range(0, cols - 2),
				"ay": rng.randi_range(0, rows - 2), "flip": rng.randf() < 0.5})
	elif not nl.is_empty() and out.rooms.size() > 4: # REMOVE
		# don't drop the only cafe while a storage remains (would orphan it)
		var cafes := 0; var deliveries := 0
		for r in out.rooms:
			if r.type == "cafe": cafes += 1
			elif r.type == "delivery": deliveries += 1
		var pick: int = nl[rng.randi_range(0, nl.size() - 1)]
		if not (out.rooms[pick].type == "cafe" and cafes == 1 and deliveries > 0):
			out.rooms.remove_at(pick)
	else:                                             # fallback JIGGLE
		if not nl.is_empty():
			var i4: int = nl[rng.randi_range(0, nl.size() - 1)]
			out.rooms[i4].ax += rng.randi_range(-1, 1)
			_clamp_anchor(out.rooms[i4], cols, rows)
	return out


## Spatial crossover: child takes parent A's rooms left of a cut + B's rooms to the right.
## Overlaps at the seam are common but harmless -- an infeasible child is catalogued and
## later repaired (why FI makes crossover affordable). Guarantees a lobby + 4..8 rooms.
func _cross_design(rng: RandomNumberGenerator, a: Dictionary, b: Dictionary) -> Dictionary:
	var split := rng.randi_range(2, maxi(3, int(a.cols) - 2))
	var rooms := []
	var has_lobby := false
	for r in a.rooms:
		if int(r.ax) < split:
			rooms.append((r as Dictionary).duplicate())
			if r.type == "lobby": has_lobby = true
	for r in b.rooms:
		if int(r.ax) >= split:
			rooms.append((r as Dictionary).duplicate())
			if r.type == "lobby": has_lobby = true
	if not has_lobby:
		rooms.push_front((a.rooms[0] as Dictionary).duplicate())
	if rooms.size() > 8:
		rooms = rooms.slice(0, 8)
	if rooms.size() < 4:
		return _clone_design(a)
	var blocks := []
	for bl in a.get("blocks", []):
		blocks.append(bl)
	return {"cols": a.cols, "rows": a.rows, "rooms": rooms, "blocks": blocks}


## Descriptor for an (infeasible) genome, from its room types + count (geometry may be
## malformed). compactness bin is 0 -- it doesn't matter for the infeasible catalogue.
func _design_bd_genome(g: Dictionary) -> Array:
	var types := {}
	for r in g.rooms:
		types[r.type] = true
	var cargo := 1 if (types.has("cafe") and types.has("delivery")) else 0
	var has_blocks := 1 if (g.get("blocks", []) as Array).size() > 0 else 0
	return [g.rooms.size(), 0, cargo, 1 if types.has("atrium") else 0, 1 if types.has("penthouse") else 0, has_blocks]


# ---- genome (de)serialization: blocks are Vector2i, not JSON-native ------------------
func _genome_json(g: Dictionary) -> Dictionary:
	var blocks := []
	for b in g.get("blocks", []):
		blocks.append([b.x, b.y])
	return {"cols": int(g.cols), "rows": int(g.rows), "rooms": g.rooms, "blocks": blocks}


func _genome_parse(d: Dictionary) -> Dictionary:
	var rooms := []
	for r in d.get("rooms", []):
		rooms.append({"type": str(r.type), "ax": int(r.ax), "ay": int(r.ay), "flip": bool(r.get("flip", false))})
	var blocks := []
	for xy in d.get("blocks", []):
		blocks.append(Vector2i(int(xy[0]), int(xy[1])))
	return {"cols": int(d.cols), "rows": int(d.rows), "rooms": rooms, "blocks": blocks}


func _fievo_load(jpath: String) -> Dictionary:
	var out := {"feasible": {}, "infeasible": {}, "evals": 0}
	if not FileAccess.file_exists(jpath):
		return out
	var f := FileAccess.open(jpath, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return out
	out.evals = int(data.get("evals", 0))
	for c in data.get("feasible", []):
		c["genome"] = _genome_parse(c.genome)
		out.feasible[str(c.get("key", ""))] = c
	for c in data.get("infeasible", []):
		c["genome"] = _genome_parse(c.genome)
		out.infeasible[str(c.get("key", ""))] = c
	return out


## FEASIBLE-INFEASIBLE MAP-Elites over the mutable genome. RESUMABLE + chunked: loads the
## master, seeds its population from the loaded elites (island model for parallel workers),
## evolves `chunk` MORE feasible evals, merges, exits (process-per-chunk = leak-robust).
## Feasible designs kept by SWEEP per niche; infeasible by MIN violation-distance and mutated
## (repair-biased) back toward feasibility. Only feasible designs cost simulations.
func _fievo(chunk: int, expert_budget: int, jpath: String, seed_offset := 0) -> void:
	var cols := 9
	var rows := 11
	var loaded := _fievo_load(jpath)
	var feasible: Dictionary = loaded.feasible
	var infeasible: Dictionary = loaded.infeasible
	var base_evals: int = loaded.evals
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250821 + (base_evals + seed_offset) * 1009
	var st := {"evals": 0, "migrated": 0, "born_inf": 0}   # NEW this chunk
	var iters := 0
	var cycle := [4, 5, 6, 7, 6, 5, 8]
	var file_feasible := func(child: Dictionary, level: Dictionary, from_inf: bool) -> void:
		var res := _classify(level, expert_budget, 20)
		st.evals += 1
		if res.tier == "BROKEN" or float(res.get("expert_tips", 0.0)) < 120.0:
			return
		var bd := _design_bd(level)
		var nkey := _bd_key(bd)
		var difficulty: float = 1.0 - float(res.wr)
		var cand := {"key": nkey, "genome": child, "cbin": bd[1], "cargo": bd[2], "atrium": bd[3],
				"penth": bd[4], "nblocks": (level.get("blocked", []) as Array).size(),
				"nrooms": int(level.rooms.size()), "sweep": float(res.sweep), "fitness": float(res.sweep),
				"difficulty": difficulty, "wr": float(res.wr), "expert": float(res.expert_tips),
				"adept": float(res.adept_tips), "floor_ok": bool(res.floor_ok),
				"novice": float(res.novice_tips), "depth": float(res.depth),
				"cover": int(res.cover), "fcov_niches": int(res.full_cover_niches),
				"tier": str(res.tier), "sig": _type_sig(level)}
		if not feasible.has(nkey) or cand.fitness > feasible[nkey].fitness:
			feasible[nkey] = cand
			if from_inf:
				st.migrated += 1
	var offer := func(child: Dictionary, from_inf: bool) -> void:
		var a := _assess_design(child)
		if a.feasible:
			file_feasible.call(child, a.level, from_inf)
		else:
			st.born_inf += 1
			var bd := _design_bd_genome(child)
			var nkey := _bd_key(bd)
			if not infeasible.has(nkey) or a.distance < infeasible[nkey].distance:
				infeasible[nkey] = {"key": nkey, "genome": child, "distance": a.distance, "nrooms": child.rooms.size()}
	# init population ONLY on a cold start: seed from _generate (retry-places legally).
	if feasible.is_empty() and infeasible.is_empty():
		for i in 16:
			var lv := _generate(rng.randi_range(1, 900000), cycle[i % cycle.size()])
			if lv.is_empty():
				offer.call(_random_design(rng, cycle[i % cycle.size()], cols, rows), false)
			else:
				offer.call(_level_to_genome(lv), false)
	# illuminate: evolve `chunk` new feasible evals
	var iter_cap := chunk * 300 + 20000
	while st.evals < chunk and iters < iter_cap:
		iters += 1
		var use_inf: bool = feasible.is_empty() or (not infeasible.is_empty() and rng.randf() < 0.3)
		var pool: Array = infeasible.values() if use_inf else feasible.values()
		if pool.is_empty():
			pool = feasible.values() if not feasible.is_empty() else infeasible.values()
			use_inf = not use_inf
		if pool.is_empty():
			offer.call(_random_design(rng, cycle[iters % cycle.size()], cols, rows), false)
			continue
		var parent: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var child: Dictionary
		if not feasible.is_empty() and not use_inf and rng.randf() < 0.15:
			var mate: Array = feasible.values()
			child = _cross_design(rng, parent.genome, mate[rng.randi_range(0, mate.size() - 1)].genome)
		else:
			child = _mut_design(rng, parent.genome, use_inf)
		offer.call(child, use_inf)
		if iters % 5 == 0:
			_fievo_save(jpath, feasible, infeasible, base_evals + st.evals, st.migrated, st.born_inf)
	_fievo_save(jpath, feasible, infeasible, base_evals + st.evals, st.migrated, st.born_inf)
	_fievo_report(feasible, infeasible, base_evals + st.evals, st.migrated, st.born_inf)


func _fievo_save(jpath: String, feasible: Dictionary, infeasible: Dictionary,
		evals: int, migrated: int, born_inf: int) -> void:
	var f := FileAccess.open(jpath, FileAccess.WRITE)
	if f == null:
		return
	var feas := []
	for e in feasible.values():
		var c: Dictionary = (e as Dictionary).duplicate()
		c["genome"] = _genome_json(e.genome)
		feas.append(c)
	var infeas := []
	for e in infeasible.values():
		var c: Dictionary = (e as Dictionary).duplicate()
		c["genome"] = _genome_json(e.genome)
		infeas.append(c)
	f.store_string(JSON.stringify({"evals": evals, "migrated": migrated,
			"born_infeasible": born_inf, "feasible_niches": feasible.size(),
			"infeasible_niches": infeasible.size(), "feasible": feas, "infeasible": infeas}))
	f.close()


func _fievo_report(feasible: Dictionary, infeasible: Dictionary, evals: int,
		migrated: int, born_inf: int) -> void:
	var els: Array = feasible.values()
	els.sort_custom(func(a, b): return a.sweep > b.sweep)
	print("\n=== FI-MAP-ELITES (mutable genome) : %d feasible evals ===" % evals)
	print("  feasible niches %d | infeasible niches %d | born-infeasible %d | REPAIRED->feasible %d" % [
			feasible.size(), infeasible.size(), born_inf, migrated])
	print("  [A/B/C] feasible elites (by sweep):")
	print("  %-4s %-8s %-5s %-5s %-5s %-5s %-4s %s" % ["room", "tier", "sweep", "adept", "exprt", "diff", "blk", "cargo/atr/pen  comp"])
	for e in els:
		print("  %-4d %-8s %-5.0f %-5.0f %-5.0f %-5.2f %-4d %d/%d/%d  %s" % [
				e.nrooms, e.tier, e.sweep, e.adept, e.expert, e.difficulty,
				int(e.get("nblocks", 0)), e.cargo, e.atrium, e.penth, e.sig])


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


## Emit a level dict as a GDScript LEVELS entry (blocked included) + its smoke _solution
## case from `expert_routes` (list of {cells:[[x,y]], closed}).
func _dump_level(lv: Dictionary, id: String, name: String, expert_routes: Array) -> void:
	print("\t{")
	print("\t\t\"id\": \"%s\", \"world\": \"CROSSLINK\", \"name\": \"%s\", \"thesis\": \"\", \"intro\": \"\"," % [id, name])
	print("\t\t\"cols\": %d, \"rows\": %d, \"blocked\": [%s]," % [lv.cols, lv.rows, _vecs(lv.get("blocked", []))])
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
	if not expert_routes.is_empty():
		print("\t\t\t\"%s\":" % id)
		var parts := []
		for r in expert_routes:
			var cc := []
			for xy in r.cells:
				cc.append("[%d,%d]" % [int(xy[0]), int(xy[1])])
			parts.append("_c([%s])" % ",".join(cc))
		print("\t\t\t\treturn [%s]" % ",\n\t\t\t\t\t\t".join(parts))


## Emit a SEED-generated level (legacy path).
func _dump(seed_v: int, nrooms: int, id: String, name: String, soljson: String) -> void:
	var lv := _generate(seed_v, nrooms)
	if lv.is_empty():
		print("gen failed"); return
	var routes := []
	var f := FileAccess.open(soljson, FileAccess.READ)
	if f != null:
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		if data.has("expert"):
			routes = data.expert.routes
	_dump_level(lv, id, name, routes)


## Emit a FIEVO design (from a solvegen sol.json holding genome + expert routes).
func _dumpgen(soljson: String, id: String, name: String) -> void:
	var f := FileAccess.open(soljson, FileAccess.READ)
	if f == null:
		print("cannot read %s" % soljson); return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var genome := _genome_parse(data.genome)
	var a := _assess_design(genome)
	if not a.feasible:
		print("design infeasible"); return
	_dump_level(a.level, id, name, data.expert.routes)


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
	if mode == "drawgen":
		await _draw_gen(str(args[1]), str(args[2]), str(args[3]))
		quit(); return
	if mode == "solvegen":
		_solve_gen(str(args[1]), str(args[2]), str(args[3]))
		quit(); return
	if mode == "drawsol":
		await _draw_sol(str(args[1]), str(args[2]), str(args[3]))
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
		var soff := int(args[4]) if args.size() > 4 else 0
		_mapgen(outer, expert_b, jp, soff)
		quit(); return
	if mode == "fievo":
		var outer := int(args[1])
		var expert_b := int(args[2]) if args.size() > 2 else 400
		var jp := str(args[3]) if args.size() > 3 else "fievo.json"
		var soff := int(args[4]) if args.size() > 4 else 0
		_fievo(outer, expert_b, jp, soff)
		quit(); return
	if mode == "dump":
		_dump(int(args[1]), int(args[2]), str(args[3]), str(args[4]), str(args[5]))
		quit(); return
	if mode == "dumpgen":
		_dumpgen(str(args[1]), str(args[2]), str(args[3]))
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
