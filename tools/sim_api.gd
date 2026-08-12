extends RefCounted
## Batched headless simulation for the depth tools (docs/depth-tools-spec.md §1).
##
## ONE process runs many candidates SEQUENTIALLY in-process: Godot startup is
## 375 ms, ~4x a whole run, so forking per candidate would be absurd
## (docs/sim-search-feasibility.md §4). Parallelism is per-LEVEL shards across
## processes, because Grid3's maze is static — two different levels can never
## be in flight in one process at the same time.
##
## ---------------------------------------------------------------- scoring
##
## Every run plays THE REAL LEVEL: the shipped quota, max_lost and win/lose
## checks are ACTIVE, and the run stops the moment the level ends.
##
##   WIN                -> score = WIN_BONUS + (TIMEOUT - time_to_quota)
##   LOSE or TIMEOUT    -> score = served - 3.0 * lost - 0.01 * avg_wait
##
## so a faster win always beats a slower win, every win beats every loss by a
## mile, and losers still have a continuous gradient to climb (`lost` is the
## failure currency; avg_wait is a deliberately tiny tiebreak, applied ONLY on
## the losing branch so it cannot re-order wins).
##
## This SUPERSEDES the original spec's "240 s of ENDLESS play" score. That
## measured a game nobody plays: levels stop at their quota, so most of a
## fixed 240 s endless evaluation happened in an overload regime the player
## never faces, and route-sets that win the real level comfortably were
## punished for degrading under a demand ramp that does not exist in the
## shipped game (L4's one-way-loop thesis was the clearest victim).
##
## `avg_wait` counts EVERY passenger the run ever produced — served, lost, and
## the ones still queueing or riding at the end. Averaging over log_served
## alone is survivorship-biased toward route-sets that quietly abandon the hard
## riders (docs/sim-search-feasibility.md §5).
##
## ---------------------------------------------------------------- headless
##
## Two things make a long batch survivable, both learned the hard way (the
## 2026-08-12 full-run failure, see docs/depth-tools-spec.md §1):
##
## 1. `Levels3.headless = true` — the HUD builds NO Controls.
## 2. The game is added to the tree only long enough for _ready to fire, then
##    REMOVED. Everything the session creates afterwards (passengers, riders)
##    is therefore outside the tree.
##
## Why: every CanvasItem entering the tree pushes a deferred
## `CanvasItem::_redraw_callback` onto the global MessageQueue, and every
## Control adds `_update_minimum_size` + `_clear_size_warning`. That queue is
## drained at the END of an engine frame — but a whole level's search runs
## inside ONE frame, so it only grows, while `_teardown` frees every one of
## those targets. Measured before this fix: ~132 stale messages per run, the
## 32 MB queue full after ~8 k runs; after that EVERY push fails, and each
## failed push calls CallQueue::statistics(), which prints one
## "Object was deleted while awaiting a callback." line per queued message —
## O(queue) output per push, i.e. 1.5 M lines, 65 MB logs, then a segfault.
## `CanvasItem::queue_redraw()` and `Control::update_minimum_size()` both
## early-return when the node is not inside the tree, so keeping the session
## out of the tree costs the queue nothing.
##
## Global state reset between runs (the leak list from the feasibility doc):
## Levels3.current / injected / watch_strategy are set before every
## instantiate(); Grid3's maze + caches are reloaded by main3._ready; the game
## node is freed (recursively, so unflushed passengers go with it).

## Generous cap on one run. Every level's quota is reachable in well under
## this; a run that hits it has genuinely failed to close the level out.
const TIMEOUT := 300.0 # game-seconds
const STEP_COARSE := 0.25 # search step
const STEP_FINE := 0.1 # reporting step (what every balance number is tuned at)

## Big enough that WIN_BONUS + 0 beats the best conceivable losing score: a
## non-win always has served < quota, so its score is bounded above by the
## largest quota in the table (90 on L3). Verified empirically per level by
## `--scorecheck`, not just argued.
const WIN_BONUS := 1000.0

const LOST_WEIGHT := 3.0
const WAIT_WEIGHT := 0.01 # losing branch only

## 8 + 8 disjoint seeds. Optimizers see TRAIN only; every reported number is a
## median over TEST. Deliberately NOT the canonical Scenarios3.SEEDS — those
## are regression seeds and must stay separate from design measurement
## (docs/autodesign-research.md §6.2).
const SEEDS_TRAIN := [1101, 1213, 1327, 1439, 1553, 1667, 1771, 1889]
const SEEDS_TEST := [2903, 3011, 3121, 3229, 3343, 3457, 3559, 3671]

const NEG_INF := -1.0e18

var tree: SceneTree
var scene: PackedScene = load("res://scenes/v3_main.tscn")
var runs := 0 # simulation counter — THE optimizer budget currency
var sim_usec := 0
var sim_seconds := 0.0 # game-seconds actually simulated (runs now end early)

# ------------------------------------------------------- resumable run cache
#
# A shard is a long-lived process, and on this machine long-lived headless
# processes get terminated from outside at unpredictable times (no crash
# record, no stderr, exit -1). Rather than lose an hour of search to that,
# every completed run is memoised to disk keyed by (level, routes, seed, step).
#
# Because the whole search is deterministic — seeded RNG, deterministic BFS
# decode, deterministic tick loop — a restarted shard REPLAYS the identical
# trajectory, and every run it already did returns from the cache in
# microseconds. `runs` still increments on a cache hit, because the budget
# means "simulations this optimizer was allowed", and a replayed run was
# already paid for; that keeps every rung's budget accounting identical to an
# uninterrupted run. So attempt N+1 fast-forwards to wherever attempt N died
# and carries on.
var cache_path := "" # "" disables caching entirely
var run_cache := {}
var cache_hits := 0
var _cache_dirty := 0
const CACHE_FLUSH_EVERY := 400


func _init(t: SceneTree) -> void:
	tree = t
	Levels3.headless = true


## Point the cache at a file and load whatever a previous attempt left there.
func open_cache(path: String) -> void:
	cache_path = path
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return
	# A cache written under different scoring rules is WORSE than no cache: it
	# would silently feed stale numbers into a new experiment. Version it.
	if String(d.get("__v", "")) != _cache_version():
		print("    ignoring stale run cache (scoring changed): " + path)
		return
	d.erase("__v")
	run_cache = d
	print("    resumed: %d cached runs from %s" % [run_cache.size(), path])


## Everything that changes what a run MEANS. Bump implicitly by editing any of
## these constants — an old cache is then rejected instead of trusted.
static func _cache_version() -> String:
	return "t%.1f_w%.0f_l%.1f_a%.3f_v3" % [TIMEOUT, WIN_BONUS, LOST_WEIGHT, WAIT_WEIGHT]


## Write the cache out via a temp file + rename, so a kill mid-write cannot
## leave a truncated JSON behind that would poison the next attempt.
func flush_cache(force := false) -> void:
	if cache_path == "" or (not force and _cache_dirty < CACHE_FLUSH_EVERY):
		return
	_cache_dirty = 0
	var tmp := cache_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	var payload := run_cache.duplicate()
	payload["__v"] = _cache_version()
	f.store_string(JSON.stringify(payload))
	f.close()
	DirAccess.remove_absolute(cache_path)
	DirAccess.rename_absolute(tmp, cache_path)


## Cache key: everything that can change a run's outcome.
static func _key(level_index: int, routes: Array, seed_v: int, step: float) -> String:
	var s := "%d|%d|%.3f" % [level_index, seed_v, step]
	for r in routes:
		s += "|"
		if r == null:
			continue
		s += "C" if r.get("closed", false) else "O"
		for c in r.cells:
			s += "%d,%d;" % [c.x, c.y]
	return s


## Install a level's maze statically without building a game (needed before
## decoding genes / validating routes, which read Grid3).
static func load_maze(level: Dictionary) -> void:
	Grid3.load_level(level.rows)


## Run one candidate. `routes` is an Array (one entry per card) of
## {"cells": Array[Vector2i], "closed": bool}, or null for "leave this card
## undrawn". Returns a stats Dictionary; `valid` is false (and `score` is
## NEG_INF) when any route is illegal — an invalid candidate must never crash
## the batch.
func run(level_index: int, routes: Array, seed_v: int, step: float,
		injected = null) -> Dictionary:
	var ck := ""
	if cache_path != "" and injected == null:
		ck = _key(level_index, routes, seed_v, step)
		if run_cache.has(ck):
			# Replayed run: costs the budget it always cost, costs no CPU.
			runs += 1
			cache_hits += 1
			return (run_cache[ck] as Dictionary).duplicate()
	Levels3.current = level_index
	Levels3.watch_strategy = ""
	Levels3.injected = injected
	var game = scene.instantiate()
	game.headless = true # kill the _process double-tick before it can happen
	tree.root.add_child(game) # _ready: loads the maze, builds the cars
	tree.root.remove_child(game) # ...then out of the tree; see the header note
	var out := {"valid": true, "err": "", "served": 0, "lost": 0,
			"avg_wait": 0.0, "p90_wait": 0.0, "avg_transfers": 0.0,
			"waiting_end": 0, "no_path_end": 0, "gate_wait": 0.0,
			"gate_transits": 0, "score": NEG_INF, "seed": seed_v, "step": step,
			"result": "timeout", "t_end": TIMEOUT}
	for i in mini(routes.size(), game.CARDS.size()):
		if routes[i] == null:
			continue
		var err := Route3.validate(routes[i].cells, routes[i].get("closed", false))
		if err != "":
			out.valid = false
			out.err = "card %d: %s" % [i, err]
			_teardown(game)
			return out
	game.rng.seed = seed_v
	game.endless = false # play the REAL level: quota / max_lost / win / lose
	game.start_session()
	for i in mini(routes.size(), game.CARDS.size()):
		if routes[i] != null:
			game.commit_route(i, routes[i].cells, routes[i].get("closed", false))
	var t := 0.0
	var t0 := Time.get_ticks_usec()
	while t < TIMEOUT and game.state == game.State.PLAYING:
		game.advance(step)
		t += step
	sim_usec += Time.get_ticks_usec() - t0
	sim_seconds += t
	runs += 1
	out.t_end = t
	if game.state == game.State.WIN:
		out.result = "win"
	elif game.state == game.State.LOSE:
		out.result = "lose"
	else:
		out.result = "timeout"
	_harvest(game, out)
	_teardown(game)
	if ck != "":
		run_cache[ck] = out.duplicate()
		_cache_dirty += 1
		flush_cache()
	return out


func _harvest(game, out: Dictionary) -> void:
	out.served = game.served
	out.lost = game.lost
	out.gate_wait = game.gate_wait_total()
	out.gate_transits = game.gate_transit_total()
	# Every passenger the run produced, not just the ones that finished.
	var waits: Array = []
	var transfers := 0.0
	for e in game.log_served:
		waits.append(e.wait)
		transfers += maxi(0, e.rides - 1)
	for e in game.log_lost:
		waits.append(e.wait)
	for r in game.waiting:
		for p in game.waiting[r]:
			waits.append(p.wait_time)
			out.waiting_end += 1
			if p.no_path:
				out.no_path_end += 1
	for c in game.cars:
		if c == null:
			continue
		for p in c.riders:
			waits.append(p.wait_time)
	if not waits.is_empty():
		var s := 0.0
		for w in waits:
			s += w
		out.avg_wait = s / waits.size()
		var sorted := waits.duplicate()
		sorted.sort()
		out.p90_wait = sorted[mini(int(sorted.size() * 0.9), sorted.size() - 1)]
	if not game.log_served.is_empty():
		out.avg_transfers = transfers / game.log_served.size()
	out.score = score_of(out.result, out.served, out.lost, out.avg_wait, out.t_end)


## The scoring rule, in one place so the report and the checks agree with the
## optimizer. A win is worth WIN_BONUS plus every game-second it saved.
static func score_of(result: String, served: int, lost: int, avg_wait: float,
		t_end: float) -> float:
	if result == "win":
		return WIN_BONUS + (TIMEOUT - t_end)
	return float(served) - LOST_WEIGHT * float(lost) - WAIT_WEIGHT * avg_wait


func _teardown(game) -> void:
	game.free() # already out of the tree; frees the whole session subtree
	Levels3.injected = null


# ------------------------------------------------------------- multi-seed

## Median score of `routes` over `seeds`. Invalid geometry scores NEG_INF once
## and costs no budget. Returns {"score", "per_seed", "stats"}.
func score_seeds(level_index: int, routes: Array, seeds: Array, step: float,
		injected = null) -> Dictionary:
	var per: Array = []
	var stats: Array = []
	for s in seeds:
		var r := run(level_index, routes, s, step, injected)
		if not r.valid:
			return {"score": NEG_INF, "per_seed": [], "stats": [], "err": r.err}
		per.append(r.score)
		stats.append(r)
	return {"score": median(per), "per_seed": per, "stats": stats, "err": ""}


## LOWER median: for an even sample this returns the lower of the two middle
## values instead of averaging them.
##
## That is deliberate and it matters. The score has two branches ~1000 apart
## (win vs loss), so a route-set that wins 4 of 8 seeds would otherwise be
## reported at ~560 — a number no run can ever produce, sitting in the gap
## between the branches, and read by every downstream metric as if it meant
## something. Taking an actual order statistic keeps every reported score
## inside a real branch, and is the conservative choice: a candidate is
## credited with a win only when it wins the MAJORITY of its seeds.
static func median(a: Array) -> float:
	if a.is_empty():
		return NEG_INF
	var v := a.duplicate()
	v.sort()
	return float(v[(v.size() - 1) / 2])


## Median absolute deviation — the outlier-robust spread we use for the
## ladder's noise band.
static func mad(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m := median(a)
	var d: Array = []
	for x in a:
		d.append(absf(float(x) - m))
	return median(d)
