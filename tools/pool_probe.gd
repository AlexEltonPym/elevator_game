extends SceneTree
## Microbenchmarks for the candidate-granularity parallel harness (orchestration
## + measurement only; does NOT touch the simulation). Answers three questions
## the pool design needs before it can be sized:
##
##   1. Raw single-process eval time per level (warm), split into the tick loop
##      (raw sim) vs the per-run setup/teardown overhead. This is the "1 worker"
##      denominator for the scaling table and the steady-state-overhead number.
##   2. The isolated cost of Grid3.load_level(rows) — the per-task RELOAD cost.
##   3. reload-per-task vs batch-by-level: run a mixed multi-level workload in
##      the level order given (reload almost every task) and sorted by level
##      (reloads amortised), and compare wall time. Under the current SimApi a
##      fresh scene is built per run and _ready reloads the maze every time, so
##      this measures whether sorting can save anything at all.
##
## Usage:
##   & godot --headless --path . --script tools/pool_probe.gd -- [--step 0.25] [--n 8]

const SimApi = preload("res://tools/sim_api.gd")
const RG = preload("res://tools/routegen.gd")

const ALL := ["L1", "L2", "L3", "L4", "W-1", "W-2", "W-3", "X-1"]


func _process(_d: float) -> bool:
	_probe()
	quit(0)
	return true


func _thesis(id: String) -> Array:
	var out: Array = []
	for e in Scenarios3.route_set(id, "thesis"):
		var r := {"cells": Scenarios3.cells_of(e), "closed": Scenarios3.closed_of(e)}
		var h = Scenarios3.home_of(e)
		if h != null:
			r["home"] = h
		out.append(r)
	return out


func _probe() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var step := SimApi.STEP_COARSE
	var si := args.find("--step")
	if si >= 0 and si + 1 < args.size():
		step = float(args[si + 1])
	var n := 8
	var ni := args.find("--n")
	if ni >= 0 and ni + 1 < args.size():
		n = int(args[ni + 1])
	var sim = SimApi.new(self)

	print("=== 1. reload cost: Grid3.load_level(rows) in isolation ===")
	for id in ["L1", "L3", "L4", "W-2"]:
		var li := Levels3.index_of(id)
		var lv: Dictionary = Levels3.LEVELS[li]
		var reps := 400
		var t0 := Time.get_ticks_usec()
		for _i in reps:
			Grid3.load_level(lv.rows)
		var us := float(Time.get_ticks_usec() - t0) / reps
		print("  %-4s  %.3f ms/load  (%d rooms)" % [id, us / 1000.0, Grid3.rooms().size()])

	print("\n=== 2. single-process eval time per level (warm, step %.2f) ===" % step)
	print("  level  wall_ms  tick_ms  ovhd_ms  evals/s")
	var wall_sum := 0.0
	for id in ALL:
		var li := Levels3.index_of(id)
		var routes := _thesis(id)
		sim.run(li, routes, 1101, step) # warm
		var t0 := Time.get_ticks_usec()
		var tick0: int = sim.sim_usec
		for i in n:
			sim.run(li, routes, 1101 + i, step)
		var wall := float(Time.get_ticks_usec() - t0) / 1000.0 / n
		var tick := float(sim.sim_usec - tick0) / 1000.0 / n
		wall_sum += wall
		print("  %-4s  %6.2f  %6.2f  %6.2f  %6.1f" % [id, wall, tick, wall - tick, 1000.0 / wall])
	print("  MEAN over %d levels: %.2f ms/run -> %.1f evals/s single process" % [
			ALL.size(), wall_sum / ALL.size(), 1000.0 / (wall_sum / ALL.size())])

	print("\n=== 3. reload-per-task vs batch-by-level (mixed 4-level workload) ===")
	var mix := ["L1", "L2", "L3", "L4"]
	var reps := 16
	# Interleaved: the level changes on almost every task.
	var t0 := Time.get_ticks_usec()
	for r in reps:
		for id in mix:
			sim.run(Levels3.index_of(id), _thesis(id), 1101 + r, step)
	var inter := float(Time.get_ticks_usec() - t0) / 1000.0
	# Sorted by level: each level's runs are consecutive.
	t0 = Time.get_ticks_usec()
	for id in mix:
		for r in reps:
			sim.run(Levels3.index_of(id), _thesis(id), 1101 + r, step)
	var sortd := float(Time.get_ticks_usec() - t0) / 1000.0
	var total := reps * mix.size()
	print("  %d runs  interleaved %.0f ms (%.2f ms/run)  sorted-by-level %.0f ms (%.2f ms/run)  delta %.1f%%" % [
			total, inter, inter / total, sortd, sortd / total, 100.0 * (inter - sortd) / sortd])
	print("  (SimApi rebuilds the scene every run and _ready reloads the maze regardless,")
	print("   so batching by level cannot amortise the reload under the current API.)")
