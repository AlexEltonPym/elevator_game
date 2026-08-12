extends SceneTree
## PERSISTENT candidate-granularity worker for the parallel evaluation pool.
## Orchestration + measurement only; it calls the existing SimApi and does NOT
## change the simulation.
##
## One worker is a LONG-LIVED Godot process: it pays the ~375 ms engine startup
## ONCE, then drains candidates from a shared queue until empty. Candidates are
## pulled with DYNAMIC load balancing (work-stealing), so the fastest worker
## naturally does more and none idles at the tail — there is no static
## pre-sharding.
##
## CHANNEL: a claim-file queue. The coordinator drops one empty marker file per
## chunk into <queue>; a worker claims a chunk by ATOMICALLY renaming its marker
## into <taken> (DirAccess.rename_absolute is a single NTFS MoveFile: it is
## atomic and fails if the source is already gone, so exactly one worker wins
## each chunk with no lock, no coordinator in the loop, and no fragile async
## pipe reads). Chosen over stdin/stdout streaming because PowerShell 5.1 cannot
## reliably multiplex many child stdouts, and because a file queue survives a
## worker being killed mid-flight (this machine kills long headless processes at
## random) — an unclaimed chunk is simply picked up by a survivor.
##
## A "candidate" i in [0, n) is evaluated as (level, thesis route-set, base+i)
## through SimApi.run. The route-set and seed fully determine the run, so every
## candidate is a full-length deterministic simulation and the batch is
## homogeneous. Because the run is deterministic, the SAME candidate produces
## bit-identical stats on any worker — which is what makes the pool's result
## bit-identical to the sequential path.
##
## Args (after `--`):
##   --worker N        worker id (for the output filename and claim suffix)
##   --queue DIR       absolute path to the chunk-marker queue directory
##   --taken DIR       absolute path to the claimed-marker directory
##   --out FILE        absolute path to write this worker's result JSON
##   --level L3        level id
##   --strategy thesis route-set to replicate across candidates
##   --step 0.25       sim step
##   --base 500000     candidate 0's seed; candidate i uses base+i
##   --n 640           total candidates
##   --chunk 4         candidates per claimable chunk

const SimApi = preload("res://tools/sim_api.gd")


func _process(_d: float) -> bool:
	_run()
	quit(0)
	return true


func _arg(a: Array, flag: String, dflt: String) -> String:
	var i := a.find(flag)
	if i >= 0 and i + 1 < a.size():
		return String(a[i + 1])
	return dflt


func _run() -> void:
	var a := Array(OS.get_cmdline_user_args())
	var wid := _arg(a, "--worker", "0")
	var queue := _arg(a, "--queue", "")
	var taken := _arg(a, "--taken", "")
	var out_path := _arg(a, "--out", "")
	var level_id := _arg(a, "--level", "L3")
	var strategy := _arg(a, "--strategy", "thesis")
	var step := float(_arg(a, "--step", "0.25"))
	var base := int(_arg(a, "--base", "500000"))
	var n := int(_arg(a, "--n", "640"))
	var chunk := int(_arg(a, "--chunk", "4"))

	var li := Levels3.index_of(level_id)
	var routes := _strategy_routes(level_id, strategy)
	var sim = SimApi.new(self) # cache stays off — caching would fake the throughput

	var results := {} # seed -> "served|lost|score|avg_wait|result"
	var busy_us := 0
	var claims := 0
	var t_worker0 := Time.get_ticks_usec()

	var dir := DirAccess.open(queue)
	if dir == null:
		push_error("worker %s: cannot open queue %s" % [wid, queue])
		return
	# Work-stealing claim loop: scan the queue, atomically claim the first marker
	# we can, process that chunk, then rescan (others have moved on). A full scan
	# that claims nothing means the queue is drained — every remaining marker was
	# taken by another worker, so no work is left for us.
	while true:
		var got := false
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if not dir.current_is_dir():
				var from := queue.path_join(name)
				var to := taken.path_join("%s.%s" % [name, wid])
				if DirAccess.rename_absolute(from, to) == OK:
					got = true
					claims += 1
					var start := int(name.substr(1)) # marker "cNNNNNN" -> start index
					var stop := mini(start + chunk, n)
					for c in range(start, stop):
						var seed := base + c
						var t0 := Time.get_ticks_usec()
						var r: Dictionary = sim.run(li, routes, seed, step)
						busy_us += Time.get_ticks_usec() - t0
						results[str(seed)] = "%d|%d|%.6f|%.9f|%s" % [
								r.served, r.lost, r.score, r.avg_wait, r.result]
					break
			name = dir.get_next()
		dir.list_dir_end()
		if not got:
			break

	var wall_us := Time.get_ticks_usec() - t_worker0
	var payload := {
		"worker": wid, "level": level_id, "n_done": results.size(),
		"claims": claims, "wall_us": wall_us, "busy_us": busy_us,
		"tick_us": sim.sim_usec, "runs": sim.runs, "results": results,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("worker %s: cannot write %s" % [wid, out_path])
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	print("worker %s: %d candidates, %d claims, busy %.1f s / wall %.1f s (tick %.1f s)" % [
			wid, results.size(), claims, busy_us / 1.0e6, wall_us / 1.0e6, sim.sim_usec / 1.0e6])


## Route-set for a level + strategy in SimApi shape (mirrors run_depth.gd).
func _strategy_routes(id: String, strategy: String) -> Array:
	var out: Array = []
	for e in Scenarios3.route_set(id, strategy):
		var r := {"cells": Scenarios3.cells_of(e), "closed": Scenarios3.closed_of(e)}
		var h = Scenarios3.home_of(e)
		if h != null:
			r["home"] = h
		out.append(r)
	return out
