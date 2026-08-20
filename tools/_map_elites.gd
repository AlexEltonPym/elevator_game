extends SceneTree
## MAP-Elites tip-solver: quality-DIVERSITY search over route-sets, scored by the
## shift TIP total. Instead of one converging population (the EA), it keeps the best
## plan PER behavioral niche in a 2-D archive:
##   BD1 = rooms served (union across all routes)  -- the COVERAGE axis
##   BD2 = total route cells (binned)              -- the ECONOMY axis
## Why this fixes the EA's under-convergence on 6-room levels: a plain population lets
## a clean-but-slow local optimum (fewer rooms, high tips-per-rider) crowd out the
## sprawling all-rooms plan before it gets optimized. MAP-Elites parks the all-rooms
## plan in its own coverage niche and keeps mutating it toward efficiency in place, so
## the full-coverage optimum is never lost to a partial-coverage one.
##
## Modes (godot [--headless] --path . --script tools/_map_elites.gd -- <mode> ...):
##   ship  <LEVEL_ID> <budget> <out.json>          MAP-Elites vs EA vs shipped solution
##   gen   <seed> <nrooms> <budget> <out.json>     generate a level, MAP-Elites vs EA
const SimApi5 = preload("res://tools/v5/sim_api5.gd")
const Opt = preload("res://tools/v5/optimizers5.gd")
const RG = preload("res://tools/v5/routegen5.gd")
const Gen = preload("res://tools/_pcg_gen.gd")

const STEP := 0.5              # coarse survey step; shared by both contestants
const CELL_W := 5              # width of a total-cells archive bin
const CELL_BINS := 12          # cap on economy-axis bins
const INIT_SEEDS := 28         # initial genomes offered to the archive (leave budget to illuminate)
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


# ---------------------------------------------------------------- MAP-Elites core

var rng := RandomNumberGenerator.new()


func _cell_bin(tot: int) -> int:
	return mini(CELL_BINS - 1, tot / CELL_W)


## Behavioral descriptor of a decoded route-set: [rooms_served, total_cells].
func _bd(routes: Array) -> Array:
	var served := {}
	var tot := 0
	for rt in routes:
		tot += (rt.cells as Array).size()
		for rid in RG.served_rooms_of_cells(rt.cells):
			served[rid] = true
	return [served.size(), tot]


## Decode + tip-score a genome and file it into the archive (replace if it beats the
## incumbent elite of its niche). Returns true iff it spent a simulation (was novel).
func _offer(archive: Dictionary, cache: Dictionary, sim: InjSim, genome: Array,
		widths: Array, seeds: Array) -> bool:
	var key := RG.genome_key(genome)
	if cache.has(key):
		return false
	var dec := RG.decode_genome(genome, widths)
	if dec.err != "":
		cache[key] = SimApi5.NEG_INF
		return false
	var res: Dictionary = sim.score_seeds(0, dec.routes, seeds, STEP)
	cache[key] = res.score
	if res.score <= SimApi5.NEG_INF:
		return true
	var bd := _bd(dec.routes)
	var nkey := "%d|%d" % [bd[0], _cell_bin(bd[1])]
	if not archive.has(nkey) or res.score > archive[nkey].fitness:
		archive[nkey] = {"genome": RG.clone(genome), "routes": dec.routes,
				"fitness": res.score, "served": bd[0], "cells": bd[1]}
	return true


func _elites(archive: Dictionary) -> Array:
	return archive.values()


## Biased emitter: 70% of the time draw a parent from the top tier of elites by
## fitness (concentrate optimization near the frontier), 30% uniform over all niches
## (keep exploring dead-looking corners). Pure-uniform selection wastes budget
## perfecting niches that can never hold the champion; pure-greedy loses the diversity
## that lets MAP-Elites escape the EA's local optimum. This keeps both.
func _pick_parent(elites: Array) -> Dictionary:
	if elites.size() <= 2 or rng.randf() < 0.3:
		return elites[rng.randi_range(0, elites.size() - 1)]
	var sorted := elites.duplicate()
	sorted.sort_custom(func(a, b): return a.fitness > b.fitness)
	var top := maxi(3, sorted.size() / 3)
	return sorted[rng.randi_range(0, top - 1)]


func _best(archive: Dictionary) -> Dictionary:
	var b := {}
	for e in archive.values():
		if b.is_empty() or e.fitness > b.fitness:
			b = e
	return b


## Run MAP-Elites for `budget` simulations. Returns the illuminated archive.
func _map_elites(sim: InjSim, lv: Dictionary, seeds: Array, budget: int, seed_v: int) -> Dictionary:
	rng.seed = seed_v
	var widths := RG.card_widths(lv)
	var all_docks := RG.docks()
	var archive := {}
	var cache := {}
	var start := sim.runs
	# Seed the archive: capacity-aware primitives, then random legal draws.
	var init: Array = RG.primitive_genomes(lv, widths, rng, INIT_SEEDS)
	var guard := 0
	while init.size() < INIT_SEEDS and guard < INIT_SEEDS * 6:
		guard += 1
		var g := RG.random_genome(rng, all_docks, widths)
		if not g.is_empty():
			init.append(g)
	for g in init:
		if sim.runs - start >= budget:
			break
		_offer(archive, cache, sim, g, widths, seeds)
	# Illuminate: pick a random elite, vary it, file the child.
	var iters := 0
	var iter_cap := budget * 40 + 10000
	while sim.runs - start < budget and not archive.is_empty() and iters < iter_cap:
		iters += 1
		var elites := _elites(archive)
		var parent: Dictionary = _pick_parent(elites)
		var child: Array
		if elites.size() >= 2 and rng.randf() < 0.2:
			var p2: Dictionary = _pick_parent(elites)
			child = RG.crossover(rng, parent.genome, p2.genome)
			if rng.randf() < 0.5:
				child = RG.mutate(rng, child, all_docks)
		else:
			child = RG.mutate(rng, parent.genome, all_docks)
		_offer(archive, cache, sim, child, widths, seeds)
	return {"archive": archive, "runs": sim.runs - start, "iters": iters}


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


## Median tips of a fixed plan over a seed set (held-out verification).
func _plan_tips(sim: InjSim, routes: Array, seeds: Array, step: float) -> Dictionary:
	var res: Dictionary = sim.score_seeds(0, routes, seeds, step)
	# also gather served/lost on the first seed for context
	var r0: Dictionary = sim.run(0, routes, seeds[0], step)
	return {"tips": res.score, "served": r0.served, "lost": r0.lost, "wait": r0.avg_wait}


## Draw the archive as a served x cells heat grid of best tips.
func _print_archive(archive: Dictionary, nrooms: int) -> void:
	var maxbin := 0
	for e in archive.values():
		maxbin = maxi(maxbin, _cell_bin(e.cells))
	print("  archive illumination (rows = rooms served, cols = total-cell bins of %d):" % CELL_W)
	var header := "     cells:"
	for b in range(maxbin + 1):
		header += " %4d" % (b * CELL_W)
	print(header)
	for s in range(nrooms, -1, -1):
		var any := false
		var line := "  serve %2d:" % s
		for b in range(maxbin + 1):
			var k := "%d|%d" % [s, b]
			if archive.has(k):
				line += " %4.0f" % archive[k].fitness
				any = true
			else:
				line += "    ."
		if any:
			print(line)


# ---------------------------------------------------------------- level sources

func _shipped_level(id: String) -> Dictionary:
	for lv in Levels5.LEVELS:
		if str(lv.get("id", "")) == id:
			return lv
	return {}


## The shipped "optimal" plans (the smoke solutions) for the CROSSLINK world, so we
## can measure MAP-Elites against the solution we actually ship, not just the EA.
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


# ---------------------------------------------------------------- run

## Head-to-head on one level: shipped plan (if any) vs EA-tips vs MAP-Elites, all under
## the tip metric, all on the same seeds/step/budget. Verifies winners on held-out seeds.
func _contest(lv: Dictionary, budget: int, jpath: String, shipped_id: String) -> void:
	Levels5.injected = lv
	Levels5.headless = true
	SimApi5.load_maze(lv)
	var nrooms: int = lv.rooms.size()
	var train := SimApi5.SEEDS_TRAIN.slice(0, SEARCH_SEEDS)
	var verify := SimApi5.SEEDS_TEST

	# --- shipped baseline ---
	var ship_row := {}
	if shipped_id != "":
		var plan := _shipped_plan(shipped_id)
		if not plan.is_empty():
			var vsim := InjSim.new(self); vsim.inj = lv
			var tr := _plan_tips(vsim, plan, train, STEP)
			var te := _plan_tips(vsim, plan, verify, 0.25)
			ship_row = {"tips_train": tr.tips, "tips_test": te.tips,
					"cells": _tot_cells(plan), "served": te.served, "lost": te.lost}

	# --- EA (tip fitness) ---
	var ea_sim := InjSim.new(self); ea_sim.inj = lv
	var opt = Opt.new()
	opt.setup(ea_sim, 0, lv, train, STEP, 40404)
	var ea_res: Dictionary = opt.run_ea(budget, [budget])
	var ea_dec := RG.decode_genome(ea_res.best_genome, RG.card_widths(lv))
	var ea_plan: Array = ea_dec.routes if ea_dec.err == "" else []
	var ea_te := _plan_tips(ea_sim, ea_plan, verify, 0.25) if not ea_plan.is_empty() else {"tips": SimApi5.NEG_INF, "served": 0, "lost": 0}

	# --- MAP-Elites (tip fitness) ---
	var me_sim := InjSim.new(self); me_sim.inj = lv
	var me := _map_elites(me_sim, lv, train, budget, 40404)
	var me_best := _best(me.archive)
	var me_te := _plan_tips(me_sim, me_best.routes, verify, 0.25) if not me_best.is_empty() else {"tips": SimApi5.NEG_INF, "served": 0, "lost": 0}

	# --- report ---
	print("\n=== %s  (%d rooms, budget %d sims/side) ===" % [str(lv.get("id", "GEN")), nrooms, budget])
	print("  %-12s %-11s %-11s %-6s %s" % ["contestant", "tips(train)", "tips(test)", "cells", "served/lost @test"])
	if not ship_row.is_empty():
		print("  %-12s %11.1f %11.1f %6d   %d served, %d lost" % ["SHIPPED", ship_row.tips_train, ship_row.tips_test, ship_row.cells, ship_row.served, ship_row.lost])
	print("  %-12s %11.1f %11.1f %6d   %d served, %d lost" % ["EA-tips", ea_res.best_score, ea_te.tips, _tot_cells(ea_plan), ea_te.served, ea_te.lost])
	print("  %-12s %11.1f %11.1f %6d   %d served, %d lost" % ["MAP-Elites", me_best.get("fitness", SimApi5.NEG_INF), me_te.tips, me_best.get("cells", 0), me_te.served, me_te.lost])
	print("  MAP-Elites archive: %d niches filled, %d iters, %d sims spent" % [me.archive.size(), me.iters, me.runs])
	_print_archive(me.archive, nrooms)
	# verdict on held-out tips
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

	if jpath != "" and not me_best.is_empty():
		var save := {"id": str(lv.get("id", "GEN")), "expert": {"routes": _routes_json(me_best.routes),
				"tips": me_best.fitness, "cells": me_best.cells}}
		var f := FileAccess.open(jpath, FileAccess.WRITE)
		f.store_string(JSON.stringify(save))
		f.close()
		print("  saved MAP-Elites best -> %s" % jpath)


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
	print("usage: ship <ID> <budget> <out> | gen <seed> <nrooms> <budget> <out>")
	quit()
