extends RefCounted
## Batched headless simulation for the v5 depth tools (docs/v5-transition-spec.md
## §5.1, Phase 2). The structural port of tools/sim_api.gd: same batch loop,
## same run-cache, same seed discipline, same two-branch scoring — but it loads
## scenes/v5_main.tscn + Grid5, and _harvest reads v5 stats (served / lost,
## reactivations, gate_wait, walk-time, transfers).
##
## ---------------------------------------------------------------- scoring
##
## Every run plays THE REAL v5 LEVEL: the shipped quota, max_lost and win/lose
## checks are ACTIVE, and the run stops the moment the level ends.
##
##   WIN                -> score = WIN_BONUS + (TIMEOUT - time_to_quota)
##   LOSE or TIMEOUT    -> score = served - 3.0 * lost - 0.01 * avg_wait
##
## so a faster win always beats a slower win, every win beats every loss by a
## mile (a non-win has served < quota <= 24, far under WIN_BONUS), and losers
## still have a continuous gradient to climb. `avg_wait` counts EVERY passenger
## the run ever produced — served, lost, and the ones still queueing / riding at
## the end — so a plan that quietly abandons the hard riders is not rewarded.
##
## ---------------------------------------------------------------- headless
##
## The v5 headless discipline, proven in tests/v5_smoke.gd and hardened here the
## way tools/sim_api.gd learned to (the 2026-08-12 MessageQueue failure):
##
## 1. Levels5.headless = true  — hud5._ready builds NO Controls and set_process(false).
## 2. The game node is added to the tree only long enough for _ready to fire,
##    then REMOVED. Everything the session creates afterwards (passengers, riders)
##    is added to nodes OUTSIDE the tree, so no CanvasItem redraw callback is ever
##    queued on the global MessageQueue — a whole level's search runs inside one
##    engine frame, so an in-tree session would grow that queue without bound.
##    Grid5 / Car5 / Passenger5 all drive off main5.advance(), never _process, so
##    an out-of-tree session simulates identically to an in-tree one.

const TIMEOUT := 300.0    # game-seconds; ~5x the longest shipped thesis (R-6 ~53 s)
const STEP_COARSE := 0.25 # search step
const STEP_FINE := 0.1    # reporting step (what v5_smoke and the fingerprint use)

const WIN_BONUS := 1000.0
const LOST_WEIGHT := 3.0
const WAIT_WEIGHT := 0.01 # losing branch only

## 8 + 8 disjoint seeds. Optimizers see TRAIN only; every reported number is a
## median over TEST. Distinct from the fingerprint's seeds and from any future
## scenario seeds, so measurement never overlaps regression.
const SEEDS_TRAIN := [7101, 7213, 7327, 7439, 7553, 7667, 7771, 7889]
const SEEDS_TEST := [8903, 9011, 9121, 9229, 9343, 9457, 9559, 9671]

const NEG_INF := -1.0e18

## TIP scoring (prototype, Overcooked-style). Each SERVED passenger pays a tip that
## decays with how long they waited (spawn->delivery): fast service = full tip, slow =
## floor. Each LOST trip is a negative hit. The total (summed over the run) is a
## CONTINUOUS efficiency score sensitive to EVERY lift's waits — not just the bottleneck
## that decides win-time — so a kink anywhere lowers it. Stars come from thresholds.
const TIP_MAX := 10.0     # tip for an instantly-served passenger
const TIP_RATE := 0.18    # tip lost per second waited
const TIP_FLOOR := 1.0    # a very slow but completed trip still pays this
const LOST_TIP := 8.0     # penalty subtracted per lost passenger

var tree: SceneTree
var scene: PackedScene = load("res://scenes/v5_main.tscn")

var runs := 0        # simulation counter — THE optimizer budget currency
var sim_usec := 0
var sim_seconds := 0.0

# ------------------------------------------------------- resumable run cache
# Same rationale as tools/sim_api.gd: a long-lived headless process can be
# terminated from outside, so every completed run is memoised to disk keyed by
# (level, routes, seed, step) under a scoring-rule version. A restarted shard
# replays the identical deterministic trajectory and serves prior runs from disk.
var cache_path := ""
var run_cache := {}
var cache_hits := 0
var _cache_dirty := 0
const CACHE_FLUSH_EVERY := 400


func _init(t: SceneTree) -> void:
	tree = t
	Levels5.headless = true


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
	if String(d.get("__v", "")) != _cache_version():
		print("    ignoring stale run cache (scoring changed): " + path)
		return
	d.erase("__v")
	run_cache = d
	print("    resumed: %d cached runs from %s" % [run_cache.size(), path])


static func _cache_version() -> String:
	return "v5_t%.1f_w%.0f_l%.1f_a%.3f_v1" % [TIMEOUT, WIN_BONUS, LOST_WEIGHT, WAIT_WEIGHT]


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
## decoding genes / validating routes, which read Grid5). Pass an injected level
## dict to measure an off-table level.
static func load_maze(level: Dictionary) -> void:
	Grid5.load_level(level)


## Run one candidate. `routes` is an Array (one entry per card) of
## {"cells": Array[Vector2i], "closed": bool}, or null for "leave this card
## undrawn". Returns a stats Dictionary; `valid` is false (and `score` is
## NEG_INF) when any route is illegal — an invalid candidate must never crash
## the batch, and must never reach commit_route (which would push_error).
func run(level_index: int, routes: Array, seed_v: int, step: float,
		injected = null) -> Dictionary:
	var ck := ""
	if cache_path != "" and injected == null:
		ck = _key(level_index, routes, seed_v, step)
		if run_cache.has(ck):
			runs += 1
			cache_hits += 1
			return (run_cache[ck] as Dictionary).duplicate()
	Levels5.current = level_index
	Levels5.injected = injected
	Levels5.headless = true
	var game = scene.instantiate()
	game.headless = true            # kill the _process double-tick before it can happen
	tree.root.add_child(game)       # _ready: loads the maze (headless), builds the cars
	tree.root.remove_child(game)    # ...then out of the tree; see the header note
	var out := {"valid": true, "err": "", "served": 0, "lost": 0,
			"avg_wait": 0.0, "p90_wait": 0.0, "transfers": 0, "avg_transfers": 0.0,
			"reactivations": 0, "waiting_end": 0, "no_path_end": 0,
			"gate_wait": 0.0, "gate_transits": 0, "score": NEG_INF, "tips": 0.0,
			"seed": seed_v, "step": step, "result": "timeout",
			"t_end": TIMEOUT, "time_to_quota": TIMEOUT}
	# Validate the whole route-set (geometry + per-card corridor width + the
	# cumulative overlap cap) WITHOUT touching commit_route, so an illegal
	# candidate scores rather than spamming push_error inside a batch.
	var verr := validate_routes(game, routes)
	if verr != "":
		out.valid = false
		out.err = verr
		_teardown(game)
		return out
	game.rng.seed = seed_v
	game.to_plan()                  # PLAN phase: commits are legal, cars deploy instantly
	for i in mini(routes.size(), game.CARDS.size()):
		if routes[i] != null:
			if not game.commit_route(i, routes[i].cells, routes[i].get("closed", false)):
				out.valid = false
				out.err = "card %d: commit refused" % i
				_teardown(game)
				return out
	game.start_run()
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
		out.time_to_quota = t
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


## Overcooked-style SHIFT run (prototype). Spawn for `shift_secs`, then LAST ORDERS: stop
## spawning and drain until every remaining passenger is served or times out. `endless` so
## quota/max-lost never cut it short — the score is the accumulated TIPS. Anyone still
## stuck when the doors close is counted as a fail.
func run_shift(level_index: int, routes: Array, seed_v: int, shift_secs: float, step: float,
		injected = null) -> Dictionary:
	Levels5.current = level_index
	Levels5.injected = injected
	Levels5.headless = true
	var game = scene.instantiate()
	game.headless = true
	tree.root.add_child(game)
	tree.root.remove_child(game)
	var out := {"valid": true, "err": "", "served": 0, "lost": 0,
			"avg_wait": 0.0, "p90_wait": 0.0, "transfers": 0, "avg_transfers": 0.0,
			"reactivations": 0, "waiting_end": 0, "no_path_end": 0,
			"gate_wait": 0.0, "gate_transits": 0, "score": NEG_INF, "tips": 0.0,
			"seed": seed_v, "step": step, "result": "shift", "t_end": shift_secs}
	var verr := validate_routes(game, routes)
	if verr != "":
		out.valid = false
		out.err = verr
		_teardown(game)
		return out
	game.rng.seed = seed_v
	game.to_plan()
	for i in mini(routes.size(), game.CARDS.size()):
		if routes[i] != null:
			if not game.commit_route(i, routes[i].cells, routes[i].get("closed", false)):
				out.valid = false
				out.err = "card %d: commit refused" % i
				_teardown(game)
				return out
	game.endless = true                 # no quota-win / max-lost stop; the shift is the clock
	game.start_run()
	var t0 := Time.get_ticks_usec()
	var t := 0.0
	while t < shift_secs and game.state == game.State.PLAYING:
		game.advance(step)
		t += step
	game.auto_spawn = false             # LAST ORDERS: doors close, no new arrivals
	var drain := 0.0
	while _any_active(game) and drain < 100.0 and game.state == game.State.PLAYING:
		game.advance(step)
		drain += step
	sim_usec += Time.get_ticks_usec() - t0
	sim_seconds += t + drain
	runs += 1
	out.t_end = t + drain
	_harvest(game, out)
	out.tips -= LOST_TIP * float(out.waiting_end)   # anyone still stuck at close = a fail
	_teardown(game)
	return out


func _any_active(game) -> bool:
	for p in game.active_passengers:
		if p.active:
			return true
	return false


## "" when the route-set is legal on the loaded level, else a reason. Mirrors
## main5.commit_route's checks exactly (Route5.validate + route_min_corridor_width
## + the cumulative overlap cap) but as a pure predicate over the whole set, so a
## legal final configuration is accepted regardless of commit order — the RUN
## gate's semantics, not a single commit's order-dependent one.
static func validate_routes(game, routes: Array) -> String:
	var used := {} # capped cell -> summed car-width already drawn through it
	for i in mini(routes.size(), game.CARDS.size()):
		if routes[i] == null:
			continue
		var cells: Array = routes[i].cells
		var closed: bool = routes[i].get("closed", false)
		var err := Route5.validate(cells, closed and cells.size() >= 4)
		if err != "":
			return "card %d: %s" % [i, err]
		var w: int = game.cars[i].width
		if Grid5.route_min_corridor_width(cells) < w:
			return "card %d: too wide for that corridor" % i
		for c in cells:
			if Grid5.is_overlap_capped(c):
				var nu: int = int(used.get(c, 0)) + w
				if nu > Grid5.overlap_cap(c):
					return "card %d: overlap cap exceeded at %s" % [i, str(c)]
				used[c] = nu
	return ""


func _harvest(game, out: Dictionary) -> void:
	out.served = game.served
	out.lost = game.lost
	out.reactivations = game.reactivations
	var waits: Array = []
	var transfers := 0
	for e in game.log_served:
		waits.append(e.wait)
		if int(e.rides) >= 2:
			transfers += 1
	for e in game.log_lost:
		waits.append(e.wait)
	# Every passenger still in the system at the end (queueing, milling, riding),
	# counted once via active_passengers so nobody is double-counted across the
	# waiting/queues lists.
	for p in game.active_passengers:
		if p.active:
			waits.append(p.wait_time)
			out.waiting_end += 1
			if p.no_path:
				out.no_path_end += 1
	out.transfers = transfers
	if not game.log_served.is_empty():
		out.avg_transfers = float(transfers) / game.log_served.size()
	var gw := 0.0
	var gt := 0
	for c in game.cars:
		if c != null:
			gw += c.gate_wait_total
			gt += c.gate_transits
	out.gate_wait = gw
	out.gate_transits = gt
	out.tips = game.tips   # authoritative running total the game itself tracks
	if not waits.is_empty():
		var s := 0.0
		for w in waits:
			s += w
		out.avg_wait = s / waits.size()
		var sorted := waits.duplicate()
		sorted.sort()
		out.p90_wait = sorted[mini(int(sorted.size() * 0.9), sorted.size() - 1)]
	out.score = score_of(out.result, out.served, out.lost, out.avg_wait, out.t_end)


static func score_of(result: String, served: int, lost: int, avg_wait: float,
		t_end: float) -> float:
	if result == "win":
		return WIN_BONUS + (TIMEOUT - t_end)
	return float(served) - LOST_WEIGHT * float(lost) - WAIT_WEIGHT * avg_wait


func _teardown(game) -> void:
	game.free() # already out of the tree; frees the whole session subtree
	Levels5.injected = null


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
## values, so a route-set that wins 4 of 8 seeds is never reported at a
## between-branches score no run can produce. A candidate is credited with a win
## only when it wins the MAJORITY of its seeds.
static func median(a: Array) -> float:
	if a.is_empty():
		return NEG_INF
	var v := a.duplicate()
	v.sort()
	return float(v[(v.size() - 1) / 2])


static func mad(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m := median(a)
	var d: Array = []
	for x in a:
		d.append(absf(float(x) - m))
	return median(d)
