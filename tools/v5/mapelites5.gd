extends RefCounted
## MAP-Elites tip-solver as a reusable SOLVER (mirrors optimizers5.gd's setup/run
## contract so it drops into the same places the EA does). Quality-diversity search
## over route-set genomes: instead of one converging population it keeps the best plan
## PER behavioral niche in a 2-D archive
##   BD1 = rooms served (union across routes)  -- COVERAGE axis
##   BD2 = total route cells (binned)          -- ECONOMY axis
## Fitness is whatever `sim.score_seeds` returns; with a tip_mode InjSim that is the
## median SHIFT TIP total, so the archive illuminates the tip landscape. Coverage-as-an-
## axis parks the serve-everyone plan in its own niche so a clean-but-partial plan can't
## crowd it out (the plain tip-EA's under-convergence + overfitting failure mode).
##
## THE BUDGET CURRENCY IS ONE SIMULATION RUN, same as optimizers5.gd, so a MAP-Elites
## run and an EA run at equal `budget` are directly comparable.

const RG = preload("res://tools/v5/routegen5.gd")
const SimApi5 = preload("res://tools/v5/sim_api5.gd")

const CELL_W := 5              # width of a total-cells archive bin
const CELL_BINS := 12          # cap on economy-axis bins
const INIT_SEEDS := 28         # genomes offered before illumination (leave budget to iterate)

var sim                        # a SimApi5 (tip_mode InjSim for tip fitness)
var level_index := 0
var level: Dictionary = {}
var seeds: Array = []          # TRAIN seeds only
var step := 0.5
var widths: Array = []
var all_docks: Array = []
var rng := RandomNumberGenerator.new()

var archive := {}              # "served|cellbin" -> {genome, routes, fitness, served, cells}
var cache := {}                # genome_key -> score (skip re-sims of seen genomes)
var iters := 0


func setup(sim_api, li: int, lv: Dictionary, train_seeds: Array, search_step: float,
		seed_v: int) -> void:
	sim = sim_api
	level_index = li
	level = lv
	seeds = train_seeds
	step = search_step
	widths = RG.card_widths(lv)
	all_docks = RG.docks()
	rng.seed = seed_v
	archive = {}
	cache = {}
	iters = 0


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


## Decode + score a genome and file it into its niche (replace if it beats the incumbent).
func _offer(genome: Array) -> void:
	var key := RG.genome_key(genome)
	if cache.has(key):
		return
	var dec := RG.decode_genome(genome, widths)
	if dec.err != "":
		cache[key] = SimApi5.NEG_INF
		return
	var res: Dictionary = sim.score_seeds(level_index, dec.routes, seeds, step)
	cache[key] = res.score
	if res.score <= SimApi5.NEG_INF:
		return
	var bd := _bd(dec.routes)
	var nkey := "%d|%d" % [bd[0], _cell_bin(bd[1])]
	if not archive.has(nkey) or res.score > archive[nkey].fitness:
		archive[nkey] = {"genome": RG.clone(genome), "routes": dec.routes,
				"fitness": res.score, "served": bd[0], "cells": bd[1]}


## Biased emitter: 70% draw a parent from the top tier of elites by fitness (concentrate
## near the frontier), 30% uniform over all niches (keep exploring). Pure-uniform wastes
## budget perfecting niches that can't hold the champion; pure-greedy loses the diversity
## that lets MAP-Elites escape the EA's local optimum.
func _pick_parent(elites: Array) -> Dictionary:
	if elites.size() <= 2 or rng.randf() < 0.3:
		return elites[rng.randi_range(0, elites.size() - 1)]
	var sorted := elites.duplicate()
	sorted.sort_custom(func(a, b): return a.fitness > b.fitness)
	var top := maxi(3, sorted.size() / 3)
	return sorted[rng.randi_range(0, top - 1)]


func best() -> Dictionary:
	var b := {}
	for e in archive.values():
		if b.is_empty() or e.fitness > b.fitness:
			b = e
	return b


func max_served() -> int:
	var m := 0
	for e in archive.values():
		m = maxi(m, e.served)
	return m


## Run for `budget` simulations. Returns {best_score, best_genome, best_routes, niches,
## iters, runs} — best_score/best_genome named to match optimizers5.run_ea's contract.
## `adept_at` (>0): also captures the best tips + coverage found after that many sims (an
## ADEPT tier — a player who thinks only briefly), so the caller gets the anytime
## optimization curve (adept -> expert) for free, no extra simulations.
func run(budget: int, adept_at := 0) -> Dictionary:
	var start: int = sim.runs
	var adept_score := SimApi5.NEG_INF
	var adept_cover := 0
	# Seed the archive: capacity-aware primitives, then random legal draws.
	var init: Array = RG.primitive_genomes(level, widths, rng, INIT_SEEDS)
	var guard := 0
	while init.size() < INIT_SEEDS and guard < INIT_SEEDS * 6:
		guard += 1
		var g := RG.random_genome(rng, all_docks, widths)
		if not g.is_empty():
			init.append(g)
	for g in init:
		if sim.runs - start >= budget:
			break
		_offer(g)
		if adept_at > 0 and adept_score <= SimApi5.NEG_INF and sim.runs - start >= adept_at:
			var ab := best()
			adept_score = ab.get("fitness", SimApi5.NEG_INF)
			adept_cover = ab.get("served", 0)
	# Illuminate: pick a (biased) elite, vary it, file the child.
	var iter_cap := budget * 40 + 10000
	iters = 0
	while sim.runs - start < budget and not archive.is_empty() and iters < iter_cap:
		iters += 1
		var elites: Array = archive.values()
		var parent: Dictionary = _pick_parent(elites)
		var child: Array
		if elites.size() >= 2 and rng.randf() < 0.2:
			var p2: Dictionary = _pick_parent(elites)
			child = RG.crossover(rng, parent.genome, p2.genome)
			if rng.randf() < 0.5:
				child = RG.mutate(rng, child, all_docks)
		else:
			child = RG.mutate(rng, parent.genome, all_docks)
		_offer(child)
		if adept_at > 0 and adept_score <= SimApi5.NEG_INF and sim.runs - start >= adept_at:
			var ab2 := best()
			adept_score = ab2.get("fitness", SimApi5.NEG_INF)
			adept_cover = ab2.get("served", 0)
	var b := best()
	if adept_score <= SimApi5.NEG_INF:   # budget never reached the checkpoint
		adept_score = b.get("fitness", SimApi5.NEG_INF)
		adept_cover = b.get("served", 0)
	return {"best_score": b.get("fitness", SimApi5.NEG_INF),
			"best_genome": b.get("genome", []), "best_routes": b.get("routes", []),
			"adept_score": adept_score, "adept_cover": adept_cover,
			"niches": archive.size(), "iters": iters, "runs": sim.runs - start,
			"full_cover_niches": _full_cover_niches()}


## How many DISTINCT economy niches reach the max coverage — a read on whether the
## solution gradient is a smooth SWEEP (many rungs from slow-full to fast-full) or bimodal.
func _full_cover_niches() -> int:
	var mx := max_served()
	var n := 0
	for e in archive.values():
		if e.served >= mx:
			n += 1
	return n


## Archive as a served x cells heat grid of best tips (for reports).
func illumination_lines(nrooms: int) -> Array:
	var maxbin := 0
	for e in archive.values():
		maxbin = maxi(maxbin, _cell_bin(e.cells))
	var out: Array = []
	var header := "     cells:"
	for b in range(maxbin + 1):
		header += " %4d" % (b * CELL_W)
	out.append(header)
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
			out.append(line)
	return out
