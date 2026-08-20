extends SceneTree
## MAP-Elites tip-solver CLI. The search core lives in tools/v5/mapelites5.gd (reused by
## the PCG gate); this wraps it with the tip-scoring InjSim, a head-to-head contest vs the
## EA + the shipped smoke plan, and a windowed renderer for the difficulty artifact.
##
## Modes (godot [--headless] --path . --script tools/_map_elites.gd -- <mode> ...):
##   ship  <LEVEL_ID> <budget> <out.json>     MAP-Elites vs EA vs shipped smoke plan
##   gen   <seed> <nrooms> <budget> <out.json>  generate a level, MAP-Elites vs EA
##   draw  <LEVEL_ID> <plan.json> <shot.png>  draw a saved MAP-Elites plan on a shipped level
const SimApi5 = preload("res://tools/v5/sim_api5.gd")
const Opt = preload("res://tools/v5/optimizers5.gd")
const ME = preload("res://tools/v5/mapelites5.gd")
const RG = preload("res://tools/v5/routegen5.gd")
const Gen = preload("res://tools/_pcg_gen.gd")

const STEP := 0.5              # coarse survey step; shared by both contestants
const SEARCH_SEEDS := 2        # train seeds per evaluation during search (verify uses full test set)


class InjSim extends SimApi5:
	var inj: Dictionary = {}
	var tip_mode := true       # score_seeds returns median SHIFT TIPS (the design metric)
	func _init(t: SceneTree) -> void:
		super(t)
	func run(li: int, routes: Array, seed_v: int, step: float, injected = null) -> Dictionary:
		return super.run(li, routes, seed_v, step, inj if injected == null else injected)
	func run_shift(li: int, routes: Array, seed_v: int, ssecs: float, step: float, injected = null) -> Dictionary:
		return super.run_shift(li, routes, seed_v, ssecs, step, inj if injected == null else injected)
	func score_seeds(li: int, routes: Array, seeds: Array, step: float, injected = null) -> Dictionary:
		if not tip_mode:
			return super.score_seeds(li, routes, seeds, step, injected)
		var tips := []
		for s in seeds:
			var r := run(li, routes, s, step)
			if not r.valid:
				return {"score": SimApi5.NEG_INF, "per_seed": [], "stats": [], "err": r.err}
			tips.append(r.tips)
		return {"score": SimApi5.median(tips), "per_seed": tips, "stats": [], "err": ""}


# ---------------------------------------------------------------- reporting

func _routes_json(routes: Array) -> Array:
	var out := []
	for r in routes:
		var cells := []
		for c in r.cells:
			cells.append([c.x, c.y])
		var served := []
		for rid in RG.served_rooms_of_cells(r.cells):
			served.append(Grid5.room_letter(rid))
		served.sort()
		out.append({"cells": cells, "closed": r.get("closed", false), "serves": "".join(served)})
	return out


func _tot_cells(routes: Array) -> int:
	var t := 0
	for r in routes:
		t += (r.cells as Array).size()
	return t


func _plan_tips(sim: InjSim, routes: Array, seeds: Array, step: float) -> Dictionary:
	var res: Dictionary = sim.score_seeds(0, routes, seeds, step)
	var r0: Dictionary = sim.run(0, routes, seeds[0], step)
	return {"tips": res.score, "served": r0.served, "lost": r0.lost, "wait": r0.avg_wait}


# ---------------------------------------------------------------- level sources

func _shipped_level(id: String) -> Dictionary:
	for lv in Levels5.LEVELS:
		if str(lv.get("id", "")) == id:
			return lv
	return {}


## The shipped "optimal" plans (the smoke solutions) for the CROSSLINK world.
func _shipped_plan(id: String) -> Array:
	var raw := {}
	raw["XLINK"] = [[[3,0],[3,1],[3,2],[3,3],[2,3],[2,4],[2,5],[2,6],[2,7],[2,8]],
			[[7,7],[7,6],[8,6],[8,5],[8,4],[7,4],[7,3],[6,3],[6,2],[6,1],[6,0],[5,0],[4,0],[3,0]],
			[[4,4],[4,3],[5,3],[5,2],[5,1],[6,1]]]
	raw["XL2"] = [[[5,0],[5,1],[5,2],[5,3]],
			[[7,5],[7,4],[6,4],[6,3],[6,2],[7,2],[7,1],[7,0],[6,0],[5,0]]]
	raw["XL3"] = [[[2,4],[3,4],[4,4],[4,3],[4,2],[3,2],[3,1],[4,1],[4,0]],
			[[4,0],[3,0],[2,0],[1,0],[1,1],[1,2],[1,3],[2,3],[2,4],[2,5],[2,6],[3,6],[4,6],[5,6],[6,6],[6,7]]]
	raw["XL4"] = [[[8,7],[8,6],[8,5],[7,5],[6,5],[5,5],[4,5]],
			[[4,0],[4,1],[3,1],[2,1],[2,2],[2,3],[2,4],[3,4],[4,4],[5,4],[6,4],[7,4],[8,4],[8,3],[8,2]],
			[[1,5],[1,4],[1,3],[1,2],[2,2]]]
	raw["XL5"] = [[[5,8],[5,7],[5,6],[5,5],[5,4],[5,3],[4,3]],
			[[0,6],[0,5],[1,5],[2,5],[3,5],[4,5],[4,4],[4,3],[4,2],[3,2],[2,2],[2,1],[2,0]],
			[[3,6],[4,6],[4,7],[4,8],[4,9],[5,9],[6,9],[7,9],[8,9],[8,8],[8,7],[8,6],[8,5],[8,4],[8,3],[8,2],[8,1],[8,0]]]
	if not raw.has(id):
		return []
	var out := []
	for r in raw[id]:
		var cells := []
		for xy in r:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
		out.append({"cells": cells, "closed": false})
	return out


# ---------------------------------------------------------------- contest

## Head-to-head on one level: shipped plan (if any) vs EA-tips vs MAP-Elites, all under
## the tip metric, all on the same seeds/step/budget. Verifies winners on held-out seeds.
func _contest(lv: Dictionary, budget: int, jpath: String, shipped_id: String) -> void:
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var nrooms: int = lv.rooms.size()
	var train := SimApi5.SEEDS_TRAIN.slice(0, SEARCH_SEEDS)
	var verify := SimApi5.SEEDS_TEST

	var ship_row := {}
	if shipped_id != "":
		var plan := _shipped_plan(shipped_id)
		if not plan.is_empty():
			var vsim := InjSim.new(self); vsim.inj = lv
			var tr := _plan_tips(vsim, plan, train, STEP)
			var te := _plan_tips(vsim, plan, verify, 0.25)
			ship_row = {"tips_train": tr.tips, "tips_test": te.tips,
					"cells": _tot_cells(plan), "served": te.served, "lost": te.lost}

	var ea_sim := InjSim.new(self); ea_sim.inj = lv
	var opt = Opt.new()
	opt.setup(ea_sim, 0, lv, train, STEP, 40404)
	var ea_res: Dictionary = opt.run_ea(budget, [budget])
	var ea_dec := RG.decode_genome(ea_res.best_genome, RG.card_widths(lv))
	var ea_plan: Array = ea_dec.routes if ea_dec.err == "" else []
	var ea_te := _plan_tips(ea_sim, ea_plan, verify, 0.25) if not ea_plan.is_empty() else {"tips": SimApi5.NEG_INF, "served": 0, "lost": 0}

	var me_sim := InjSim.new(self); me_sim.inj = lv
	var me = ME.new()
	me.setup(me_sim, 0, lv, train, STEP, 40404)
	var me_res: Dictionary = me.run(budget)
	var me_te := _plan_tips(me_sim, me_res.best_routes, verify, 0.25) if not me_res.best_routes.is_empty() else {"tips": SimApi5.NEG_INF, "served": 0, "lost": 0}

	print("\n=== %s  (%d rooms, budget %d sims/side) ===" % [str(lv.get("id", "GEN")), nrooms, budget])
	print("  %-12s %-11s %-11s %-6s %s" % ["contestant", "tips(train)", "tips(test)", "cells", "served/lost @test"])
	if not ship_row.is_empty():
		print("  %-12s %11.1f %11.1f %6d   %d served, %d lost" % ["SHIPPED", ship_row.tips_train, ship_row.tips_test, ship_row.cells, ship_row.served, ship_row.lost])
	print("  %-12s %11.1f %11.1f %6d   %d served, %d lost" % ["EA-tips", ea_res.best_score, ea_te.tips, _tot_cells(ea_plan), ea_te.served, ea_te.lost])
	print("  %-12s %11.1f %11.1f %6d   %d served, %d lost" % ["MAP-Elites", me_res.best_score, me_te.tips, _tot_cells(me_res.best_routes), me_te.served, me_te.lost])
	print("  MAP-Elites archive: %d niches filled, %d iters, %d sims spent" % [me_res.niches, me_res.iters, me_res.runs])
	for line in me.illumination_lines(nrooms):
		print(line)
	var me_test: float = me_te.tips
	var ea_test: float = ea_te.tips
	var ship_test: float = ship_row.get("tips_test", SimApi5.NEG_INF) if not ship_row.is_empty() else SimApi5.NEG_INF
	var beat := []
	if me_test > ea_test + 0.5: beat.append("EA by %.1f" % (me_test - ea_test))
	elif ea_test > me_test + 0.5: beat.append("(EA leads by %.1f)" % (ea_test - me_test))
	if ship_test > SimApi5.NEG_INF + 1.0:
		if me_test > ship_test + 0.5: beat.append("SHIPPED by %.1f" % (me_test - ship_test))
		elif ship_test > me_test + 0.5: beat.append("(shipped leads by %.1f)" % (ship_test - me_test))
	print("  VERDICT (held-out tips): MAP-Elites %s" % (", ".join(beat) if not beat.is_empty() else "ties the field"))

	if jpath != "" and not me_res.best_routes.is_empty():
		var save := {"id": str(lv.get("id", "GEN")), "expert": {"routes": _routes_json(me_res.best_routes),
				"tips": me_res.best_score, "cells": _tot_cells(me_res.best_routes)}}
		var f := FileAccess.open(jpath, FileAccess.WRITE)
		f.store_string(JSON.stringify(save))
		f.close()
		print("  saved MAP-Elites best -> %s" % jpath)


# ---------------------------------------------------------------- draw

## Draw a saved plan's routes onto a shipped level and screenshot it (windowed).
func _draw(id: String, plan_json: String, shot: String) -> void:
	var lv := _shipped_level(id)
	if lv.is_empty():
		print("no shipped level id '%s'" % id); return
	var f := FileAccess.open(plan_json, FileAccess.READ)
	if f == null:
		print("cannot read %s" % plan_json); return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	Levels5.injected = lv
	Levels5.headless = false
	Levels5.current = 0
	var scene: Node = load("res://scenes/v5_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.to_plan()
	var routes: Array = data.expert.routes
	for i in routes.size():
		var cells: Array = []
		for xy in routes[i].cells:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
		scene.commit_route(i, cells, bool(routes[i].get("closed", false)))
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot)
	print("drew %s (%d routes, %d tips) -> %s" % [id, routes.size(), int(data.expert.get("tips", 0)), shot])


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode: String = str(args[0]) if args.size() > 0 else "ship"
	if mode == "ship":
		var id := str(args[1])
		var budget := int(args[2]) if args.size() > 2 else 3000
		var jpath := str(args[3]) if args.size() > 3 else ""
		var lv := _shipped_level(id)
		if lv.is_empty():
			print("no shipped level id '%s'" % id); quit(); return
		_contest(lv, budget, jpath, id)
		quit(); return
	if mode == "gen":
		var seed_v := int(args[1])
		var nrooms := int(args[2])
		var budget := int(args[3]) if args.size() > 3 else 3000
		var jpath := str(args[4]) if args.size() > 4 else ""
		var gen = Gen.new()
		var lv: Dictionary = gen._generate(seed_v, nrooms)
		if lv.is_empty():
			print("gen failed for seed %d r%d" % [seed_v, nrooms]); quit(); return
		lv["id"] = "GEN_%d_%d" % [seed_v, nrooms]
		_contest(lv, budget, jpath, "")
		quit(); return
	if mode == "draw":
		await _draw(str(args[1]), str(args[2]), str(args[3]))
		quit(); return
	print("usage: ship <ID> <budget> <out> | gen <seed> <nrooms> <budget> <out> | draw <ID> <plan.json> <shot.png>")
	quit()
