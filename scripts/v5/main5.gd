extends Node2D
## Game controller for the v5 "Rooms" feel-prototype. Adapted from
## scripts/v3/main3.gd: the phase machine (PLAN -> PLAYING -> WIN/LOSE), the pulse
## spawner and the MAGNETIC route-drawing verb are reused essentially verbatim
## (that verb is the thing the prototype must keep). The BRIEFING phase was CUT:
## picking a level lands straight in PLAN (the roster reads off the card chips and
## demand is learned by playing). The narrative fields (thesis/intro) stay in the
## level data so a light briefing can return later.
##
## What is different from v4:
##   * Rooms are multi-cell areas with authored dropoffs; routes serve a room by
##     passing through one of its dock cells (Grid5 / Route5).
##   * Passengers want ROOMS; waiting is keyed by room id; pathfinding is over
##     rooms (Pathfind5) with "elevator serves both rooms" as the edge.
##   * The roster is variable (1..3 cars). RUN gates on the level's ACTUAL
##     roster: every PROVIDED card must have a route serving >= 2 rooms. There is
##     no "every one of three cards must be drawn" assumption.
##   * No recall/redeploy, no gates, no home cells (prototype scope).

const Demand5 := preload("res://scripts/v5/demand5.gd")

enum State { PLAN, PLAYING, WIN, LOSE }

const MAX_STROKE_WALK := 256

var level: Dictionary = {}
var CARDS: Array = []
var QUOTA := 12
var MAX_LOST := 8

# SHIFT / TIP model (opt-in via level.shift > 0). A level with a shift runs for that many
# seconds spawning arrivals, then LAST ORDERS: spawning stops and it plays on until every
# remaining passenger is served or times out. The score is the accumulated TIP TOTAL —
# each served rider tips more the faster they were served; each lost rider is a penalty.
# Stars are a later UI layer over this total; the sim only tracks the raw tips.
const TIP_MAX := 10.0     # tip for an instantly-served rider
const TIP_RATE := 0.18    # tip lost per second waited (spawn -> delivery)
const TIP_FLOOR := 1.0    # a slow but completed trip still tips this
const LOST_TIP := 10.0    # penalty per lost rider
var shift_len := 0.0      # 0 = classic quota/max-lost level; >0 = shift/tip level
var shift_closed := false # true once the doors close (last orders)
var tips := 0.0           # running tip total (the score)

var state: int = State.PLAN
const DEFAULT_SPEED := 5.0  # 5x is the default pace (1x is an opt-in slow-down)
var time_scale := DEFAULT_SPEED
var served := 0
var lost := 0
var elapsed := 0.0
var auto_spawn := true
var endless := false
var headless := false

var rng := RandomNumberGenerator.new()

var pulse_timer := 0.0
var burst_left := 0
var burst_timer := 0.0

# COVERAGE DEMAND (opt-in via level.spawn.cover == true). Instead of pure weighted-
# random trips (which let a low-weight room spawn ~nobody, so abandoning it is free),
# the spawner ROUND-ROBINS over every demand room so each gets an equal share of the
# load. With max_lost tuned below a room's guaranteed share, skipping ANY room is a
# guaranteed loss - so a real solution must serve every room (the numberlink premise).
# Off by default: a level without `cover` draws the identical weighted stream as before.
var _cover_on := false
var _cover_rooms: Array = []   # demand room ids (from OR to in trips), sorted
var _cover_by_room := {}       # rid -> Array of trip rows originating at rid (else ending)
var _cover_idx := 0
var _served_rooms := {}         # rid -> true once a passenger has been delivered there

# FIXED MANIFEST (opt-in via level.manifest). An ORDERED list of exact passengers
# [{type, from, to, return?}, ...] the spawner plays IN SEQUENCE (one per spawn tick) instead
# of the weighted/derived trip picker — so a level's roster is authored, deterministic, and
# previewable (the "who's coming" UI reads it). When the list is exhausted, spawning stops
# (a fixed head-count). A level with no manifest keeps the derived-demand behaviour untouched.
var _manifest: Array = []
var _manifest_idx := 0

var active_passengers: Array = []
var reactivations := 0 # completed trips that spawned a fresh trip (stat / smoke)
var _passengers_dirty := false

var routes: Array = []
var cars: Array = []
var waiting := {} # room_id -> Array[Passenger5] in arrival order
var queues := {} # room_id -> Array[Passenger5] in QUEUE LINE order (front boards)
var corridors := {} # corridor group index -> {width, used, holders, queue}

var log_served: Array = []
var log_lost: Array = []

var selected_card := -1
var drawing := false
var stroke: Array = []
var stroke_closed := false
# Grab-to-edit session state (interactive PLAN editing only; never touched by the
# scripted direct-commit path). stroke_reversed = the active stroke is a TAIL grab,
# held reversed so the magnet works from the start end; restored on commit.
# stroke_spawn = the tile the car must keep spawning/parking at across edits
# (Vector2i(-1,-1) = "use the committed cells[0]", the default for fresh strokes).
var stroke_reversed := false
var stroke_spawn := Vector2i(-1, -1)
# LOOP-EDIT smart end: true between grabbing a committed LOOP and its first drag move,
# during which the drag DIRECTION decides which loop end the player controls (see
# _resolve_loop_grab). Open (non-loop) grabs never set this — they resolve their
# head/tail choice immediately in _try_grab_end, exactly as before.
var stroke_loop_pending := false
# Which loop end the finger actually landed ON at grab time: 0 = the front end
# (stroke[0]), 1 = the back end (stroke.back()), -1 = between/ambiguous. Used as the
# TIEBREAKER in _resolve_loop_grab so tapping directly on one end controls THAT end,
# instead of always defaulting to the head when the first drag is directionless.
var stroke_loop_end_hint := -1

var reject_msg := ""
var reject_card := -1
var reject_until_ms := 0
# MOMENTUM (express min-hop): the dock cell whose stop violated the min-hop rule on
# the last rejected commit, so Grid5 can glow it. Vector2i(-1,-1) = none.
var reject_stop := Vector2i(-1, -1)

@onready var background: Node2D = $Background
@onready var grid: Grid5 = $Grid
@onready var cars_node: Node2D = $Cars
@onready var passengers_node: Node2D = $Passengers
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	if headless:
		set_process(false)
	level = Levels5.get_level(Levels5.current).duplicate(true)
	# DERIVE demand from the rooms + fixed seed when the level ships no trips of its own
	# (shipped levels never store trips — see Demand5). Explicit-trip fixtures (the smoke's
	# delivery/injected levels) keep theirs. The solver drives this same main5, so its
	# thresholds match live play.
	if (level.get("trips", []) as Array).is_empty():
		level["trips"] = Demand5.derive(level.rooms, level_seed(), level.get("demand", {}))
	Grid5.load_level(level)
	if not headless:
		for n in [grid, cars_node, passengers_node]:
			n.scale = Vector2(Grid5.view_scale, Grid5.view_scale)
			n.position = Grid5.view_offset
		# The background draws in raw screen space (it lines up on Grid5.GROUND_Y itself),
		# so it is NOT given the grid view transform — only the shift clock, for day/night.
		background.game = self
	CARDS = level.cards
	_standardize_card_colors()
	QUOTA = level.quota
	MAX_LOST = level.max_lost
	shift_len = float(level.get("shift", 0.0))
	_build_cover(level)
	routes = []
	cars = []
	for gi in Grid5.corridor_groups().size():
		corridors[gi] = {"width": Grid5.corridor_group_width(gi), "used": 0,
				"holders": [], "queue": []}
	for rid in Grid5.room_count():
		waiting[rid] = []
		queues[rid] = []
	grid.game = self
	hud.game = self
	for i in CARDS.size():
		routes.append(null)
		var c := Car5.new()
		c.setup(self, i, CARDS[i])
		cars_node.add_child(c)
		cars.append(c)
	rng.randomize()
	# No BRIEFING phase: land straight in PLAN so picking a level is immediately
	# playable. to_plan() hides any overlay and refreshes the card chips (the roster).
	to_plan()
	# "Solution" launch (select screen button): pre-draw the level's stored expert plan so
	# you can inspect it / press RUN to watch it, then compare to your own. One-shot.
	if not headless and Levels5.autosolve:
		_commit_solution()
	Levels5.autosolve = false


## Pre-commit a stored plan (list of routes, each a list of [x,y] cells). The secret 1-4
## hover shortcut picks a star tier from the level's `sols` [1-star..4-star]; otherwise the
## default is the perfect plan (tier 4 / the `solution` field).
func _commit_solution() -> void:
	var sol: Array = level.get("solution", [])
	var sols: Array = level.get("sols", [])
	var tier: int = clampi(Levels5.autosolve_tier, 1, 4)
	if sols.size() >= tier and (sols[tier - 1] as Array).size() > 0:
		sol = sols[tier - 1]
	Levels5.autosolve_tier = 4  # reset to default for the next launch
	for i in mini(sol.size(), cars.size()):
		var cells: Array = []
		for xy in sol[i]:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
		commit_route(i, cells, false)


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	advance(delta * time_scale)
	hud.refresh_stats()


# FIXED-TIMESTEP sim. The renderer calls advance() with the frame's (speed-scaled, and
# possibly spiky) dt, but the sim only ever integrates in SIM_DT chunks: a big frame just
# runs more chunks. This makes the outcome DETERMINISTIC regardless of framerate or speed
# (so the same plan always scores the same tips → the same stars), and immune to a large
# first-frame delta. The headless solver drives this same advance(), so its thresholds are
# exactly what the game reproduces. SIM_DT is a static so the solver can search coarse for
# speed then score at the game's step; the game leaves it at the fine default.
static var SIM_DT: float = 0.1
var _sim_accum := 0.0

func advance(dt: float) -> void:
	if SIM_DT == null or SIM_DT <= 0.0:
		SIM_DT = 0.1
	if dt <= 0.0:
		return
	_sim_accum += dt
	var guard := 0
	while _sim_accum >= SIM_DT - 1.0e-9 and guard < 100000:
		guard += 1
		_sim_accum -= SIM_DT
		_step(SIM_DT)
		if state != State.PLAYING:
			_sim_accum = 0.0
			return


## Render interpolation factor 0..1: how far the leftover accumulator is into the NEXT sim
## tick. Cars/passengers lerp from their previous tick's state to the current one by this, so
## motion stays smooth at ANY speed (esp. 1x = 10 ticks/s) WITHOUT shrinking SIM_DT (which
## would multiply solve cost and rebaseline the fingerprint). Render-only — never touches the
## sim. Headless (no rendering) never calls this.
func render_alpha() -> float:
	if SIM_DT <= 0.0:
		return 1.0
	return clampf(_sim_accum / SIM_DT, 0.0, 1.0)


## One fixed sim step (the old advance body).
func _step(dt: float) -> void:
	elapsed += dt
	if auto_spawn:
		_spawn_tick(dt)
	for c in cars:
		if c != null:
			c.tick(dt)
	for p in active_passengers:
		p.tick(dt)
	if _passengers_dirty:
		_passengers_dirty = false
		var keep: Array = []
		for p in active_passengers:
			if p.active:
				keep.append(p)
		active_passengers = keep
	# SHIFT model: the day just ENDS at the bell — no "last orders" drain. Whatever's earned by
	# then is the score; anyone still mid-trip is simply left unserved.
	if shift_len > 0.0 and state == State.PLAYING and elapsed >= shift_len:
		_shift_end()


func current_interval() -> float:
	var s: Dictionary = level.spawn
	return lerpf(s.interval_start, s.interval_end,
			clampf(elapsed / float(s.ramp), 0.0, 1.0))


func _spawn_tick(dt: float) -> void:
	var s: Dictionary = level.spawn
	var rem := dt
	var guard := 0
	while rem > 0.0 and guard < 256:
		guard += 1
		if burst_left > 0:
			if burst_timer > rem:
				burst_timer -= rem
				rem = 0.0
			else:
				rem -= burst_timer
				burst_timer = 0.0
				_spawn_random()
				burst_left -= 1
				burst_timer = s.gap
		else:
			if pulse_timer > rem:
				pulse_timer -= rem
				rem = 0.0
			else:
				rem -= pulse_timer
				pulse_timer = 0.0
				var n: int = rng.randi_range(s.burst_min, s.burst_max)
				burst_left = n
				burst_timer = 0.0
				pulse_timer = n * current_interval()


# ---------------------------------------------------------------- phase flow

func to_plan() -> void:
	state = State.PLAN
	time_scale = DEFAULT_SPEED
	drawing = false
	stroke = []
	stroke_closed = false
	stroke_reversed = false
	stroke_spawn = Vector2i(-1, -1)
	stroke_loop_pending = false
	stroke_loop_end_hint = -1
	served = 0
	lost = 0
	elapsed = 0.0
	endless = false
	log_served = []
	log_lost = []
	_clear_passengers()
	_reset_spawner()
	hud.hide_overlay()
	hud.refresh_cards()
	# Special-mechanic intro card(s) first (cargo / executives), THEN the draw demo.
	if not _maybe_intro_cards():
		_maybe_play_demo()


func start_run() -> void:
	hud.hide_overlay()
	_sim_accum = 0.0
	state = State.PLAYING
	# FIXED per-level passenger seed: a level always spawns the identical arrival
	# sequence, so you can't re-run hoping for an easier crowd — the plan is the only
	# variable. (The headless smoke sets its own seed before start_run, overriding this.)
	if not headless:
		rng.seed = level_seed()
	_reset_spawner()


## Deterministic per-level RNG seed (stable hash of the level id).
func level_seed() -> int:
	return hash(str(level.get("id", "")))


## Standard lift colours by TYPE, applied at load so every level reads the same regardless of
## what colour the level data stored: LOCAL = blue, a 2nd local = green, CARGO = yellow,
## EXPRESS = orange. Visual only (colour feeds the card chip, route line and car).
const LIFT_BLUE := Color(0.42, 0.66, 0.95)
const LIFT_GREEN := Color(0.46, 0.84, 0.52)
const LIFT_YELLOW := Color(0.96, 0.82, 0.26)
const LIFT_ORANGE := Color(0.97, 0.58, 0.17)

func _standardize_card_colors() -> void:
	var local_n := 0
	for c in CARDS:
		match str(c.get("type", "standard")):
			"express":
				c.color = LIFT_ORANGE
			"cargo":
				c.color = LIFT_YELLOW
			_:
				c.color = LIFT_BLUE if local_n == 0 else LIFT_GREEN
				local_n += 1


func abort_run() -> void:
	to_plan()


## The first few tutorials play a one-time GHOST-HAND DEMO on entering PLAN: a finger taps a
## lift chip and draws each route (from the level's solution), teaching tap->draw->repeat (and,
## on T-2/T-3, two lifts / a shared dock) without text. Persisted per level so it shows once;
## tap to skip. Visual only — the board stays empty, the player draws for real.
const IntroCard5 := preload("res://scripts/v5/intro_card5.gd")

## The mechanic-intro levels: their card shows EVERY time you open them (not persisted) as an
## overlay at PLAN start. T-5 teaches cargo, T-6 teaches executives.
const INTRO_CARDS := {
	"T-1": ["offices"], "T-2": ["atrium"], "T-3": ["overlap"],
	"T-4": ["cargo"], "T-5": ["executive"], "T-6": ["finale"],
}

## Show the intro card(s) for this level. Returns true if any card was shown (so the draw demo
## waits until they're done).
func _maybe_intro_cards() -> bool:
	if headless:
		return false
	var queue: Array = INTRO_CARDS.get(str(level.get("id", "")), []).duplicate()
	if queue.is_empty():
		return false
	_show_intro_queue(queue)
	return true


func _show_intro_queue(queue: Array) -> void:
	if queue.is_empty():
		_maybe_play_demo()   # (special-mechanic levels aren't in DEMO_LEVELS; this is a no-op there)
		return
	var m: String = queue.pop_front()
	var card = IntroCard5.new()
	var val := 0
	if str(m) == "finale":
		var th: Array = level.get("stars", [])
		if th.size() >= 4:
			val = int(th[3])
	card.setup(str(m), val)
	hud.add_child(card)
	card.dismissed.connect(func():
		_show_intro_queue(queue))


const DEMO_LEVELS := ["T-1", "T-2", "T-3"]  # T-4 (cargo) will get explanatory text instead

func _maybe_play_demo() -> void:
	if headless or not DEMO_LEVELS.has(str(level.get("id", ""))):
		return
	# The demo plays EVERY time a demo level opens (user: no "seen" gate) — it's an interactive,
	# non-blocking hint, so re-showing it is harmless and helps while iterating.
	# Hand-authored ghost paths (`demo`) override the solution-derived trace: the solver's
	# route order can zig-zag or draw bottom-to-top, which reads oddly as a taught gesture.
	# `demo` is the same [route -> [[x,y]...]] shape, drawn verbatim in card order, built into a
	# per-card `paths` array (null where a card has no demo path) for the guided overlay.
	var sol: Array = level.get("demo", level.get("solution", []))
	if sol.is_empty():
		return
	var paths: Array = []
	var any := false
	for ri in CARDS.size():
		if ri < sol.size() and not (sol[ri] as Array).is_empty():
			var pts: Array = []
			var cells: Array = []
			var served := {}
			for xy in sol[ri]:
				var cell := Vector2i(int(xy[0]), int(xy[1]))
				cells.append(cell)
				pts.append(Grid5.view_offset + Grid5.view_scale * Grid5.cell_center(cell))
				for rid in Grid5.dock_rooms(cell):
					served[rid] = true
			# `cells` lets the guide treat each demo route as a JOB and steer an undrawn lift to
			# whichever job the player hasn't already covered (so it never guides a lift on top of
			# the other one). `roomset` is the rooms this job serves — the demo is DONE only when
			# every intended room (union across jobs) is covered, so a partial plan can't finish it.
			paths.append({"color": CARDS[ri].color, "chip": hud.chip_center(ri),
					"pts": pts, "cells": cells, "roomset": served.keys(), "rooms": served.size()})
			any = true
		else:
			paths.append(null)
	if not any:
		return
	hud.start_guided_demo(paths)


func next_level() -> void:
	Levels5.current = mini(Levels5.current + 1, Levels5.LEVELS.size() - 1)
	get_tree().change_scene_to_file("res://scenes/v5_main.tscn")


func to_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/v5_select.tscn")


func _reset_spawner() -> void:
	pulse_timer = 0.0   # first person spawns on the FIRST tick (no warm-up); the rest follow at the normal interval
	burst_left = 0
	burst_timer = 0.0
	_cover_idx = 0
	_served_rooms = {}
	_manifest = level.get("manifest", [])
	_manifest_idx = 0
	tips = 0.0
	shift_closed = false
	auto_spawn = true


## Precompute the round-robin demand rooms for coverage spawning (opt-in). A no-op that
## leaves _cover_on false for every level that doesn't set spawn.cover (byte-identical).
func _build_cover(lv: Dictionary) -> void:
	_cover_on = bool((lv.get("spawn", {}) as Dictionary).get("cover", false))
	_cover_rooms = []
	_cover_by_room = {}
	_cover_idx = 0
	if not _cover_on:
		return
	var to_map := {}
	var seen := {}
	for row in lv.trips:
		var o: int = Levels5.room_id_of_letter(lv, str(row.from))
		var d: int = Levels5.room_id_of_letter(lv, str(row.to))
		if o >= 0:
			if not _cover_by_room.has(o):
				_cover_by_room[o] = []
			(_cover_by_room[o] as Array).append(row)
		if d >= 0:
			if not to_map.has(d):
				to_map[d] = []
			(to_map[d] as Array).append(row)
		for rid in [o, d]:
			if rid >= 0 and not seen.has(rid):
				seen[rid] = true
				_cover_rooms.append(rid)
	_cover_rooms.sort()
	# A room that never appears as an origin still needs demand: fall back to trips that
	# END at it (a passenger heading there still requires that room be served).
	for rid in _cover_rooms:
		if not _cover_by_room.has(rid) or (_cover_by_room[rid] as Array).is_empty():
			_cover_by_room[rid] = to_map.get(rid, [])


func _tip_of(wait: float) -> float:
	return maxf(TIP_FLOOR, TIP_MAX - TIP_RATE * wait)


func _any_active_pax() -> bool:
	for p in active_passengers:
		if p.active:
			return true
	return false


## Shift complete: freeze the run on the tip total. Reuses the WIN state (there is no
## lose in a shift — you always finish; the tip total is the score, stars come later).
func _shift_end() -> void:
	# FIXED-MANIFEST levels: the roster is finite and finished spawning, so anyone still in the
	# building at the bell was genuinely ABANDONED -- count them lost (same "skipping a room is a
	# guaranteed loss" rule the PCG cover levels use). Without this the solver rationally skips
	# low-value rooms because a rider whose patience outlasts the shift costs nothing. Returning
	# (empty) delivery men have already made their delivery, so they don't count. Derived-demand
	# levels (continuous spawning, always someone mid-trip at the bell) are untouched.
	if not _manifest.is_empty():
		for p in active_passengers.duplicate():
			if p.active and not p.returning:
				on_expired(p)
	state = State.WIN
	if not headless:
		Levels5.record_stars(str(level.get("id", "")), star_count())
	hud.show_win(served, lost)


## Stars earned this run for the current tip total (0..4; 4 = secret optimal). Levels are
## GENERATED so their best solution loses nobody (the PCG gate discards any level whose
## optimum still drops riders), so a clean shift is achievable by design — no runtime cap here.
func star_count() -> int:
	return Levels5.stars_for(level, tips)


## True unless this is a coverage level with a demand room not yet served.
func _rooms_covered() -> bool:
	if not _cover_on:
		return true
	for rid in _cover_rooms:
		if not _served_rooms.has(rid):
			return false
	return true


func _win() -> void:
	state = State.WIN
	hud.show_win(served, lost)


func _lose() -> void:
	state = State.LOSE
	hud.show_lose(served, lost)


func _clear_passengers() -> void:
	for p in passengers_node.get_children():
		p.active = false
		p.queue_free()
	active_passengers = []
	reactivations = 0
	_passengers_dirty = false
	for rid in waiting:
		waiting[rid].clear()
	for rid in queues:
		queues[rid].clear()
	for c in cars:
		c.riders.clear()
		c.set_route(c.route) # re-park at route start


func set_speed(s: float) -> void:
	time_scale = s


# ---------------------------------------------------------------- input (magnetic)

func can_edit() -> bool:
	return state == State.PLAN


## Cards whose DRAWN route is incomplete (serves < 2 rooms). An UNPLACED lift is fine — you
## don't have to place every lift — so a null route is NOT "not ready"; only a started-but-
## unfinished route blocks RUN.
func cards_not_ready() -> Array:
	var out: Array = []
	for i in CARDS.size():
		if routes[i] != null and routes[i].served_rooms().size() < 2:
			out.append(CARDS[i].name)
	return out


## RUN is allowed once no placed route is incomplete AND at least one lift is actually placed
## (running with zero lifts would be a no-op).
func ready_to_run() -> bool:
	if not cards_not_ready().is_empty():
		return false
	for i in CARDS.size():
		if routes[i] != null:
			return true
	return false


func route_warning(i: int) -> bool:
	return routes[i] != null and routes[i].served_rooms().size() < 2


func _unhandled_input(event: InputEvent) -> void:
	# During the run you can't edit, but tapping the board (away from a chip) DESELECTS the
	# highlighted line. (Chip taps are GUI events, so they don't reach here.)
	if state == State.PLAYING:
		var tap: bool = (event is InputEventScreenTouch and event.pressed) \
				or (event is InputEventMouseButton and event.pressed)
		if tap and selected_card >= 0:
			selected_card = -1
			hud.refresh_cards()
		return
	if not can_edit():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
	elif event is InputEventScreenDrag:
		_extend_stroke(event.position)


func select_card(i: int) -> void:
	# Selectable in PLAN (to draw) and during PLAYING (to just HIGHLIGHT the running line).
	if state != State.PLAN and state != State.PLAYING:
		return
	selected_card = -1 if selected_card == i else i
	drawing = false
	stroke = []
	stroke_closed = false
	stroke_reversed = false
	stroke_spawn = Vector2i(-1, -1)
	stroke_loop_pending = false
	reject_until_ms = 0
	hud.refresh_cards()


func _begin_stroke(pos: Vector2) -> void:
	if selected_card < 0 or not can_edit():
		return
	var cell := Grid5.cell_at(pos)
	if cell.x < 0:
		return
	# Grab-to-edit (v5 UX): a drag that begins on — or immediately beside — EITHER
	# end of the selected card's already-committed route resumes that route instead
	# of starting a fresh stroke that would replace it.
	if _try_grab_end(cell):
		return
	if not _drawable(cell):
		return
	drawing = true
	stroke = [cell]
	stroke_closed = false
	stroke_reversed = false
	stroke_spawn = Vector2i(-1, -1)
	stroke_loop_pending = false


## The head cell of a committed route: the last cell of an open polyline, or the
## closing point (cells[0], where the loop closes and the preview pulse sits) of a
## loop. The magnet always drives from the head.
func _route_head(r: Route5) -> Vector2i:
	if r.closed:
		return r.cells[0]
	return r.cells[r.cells.size() - 1]


## The tail (start-side) grab cell: cells[0] for an open route; for a loop the other
## joined stroke end (cells.back()), so either point of a loop is grabbable.
func _route_tail(r: Route5) -> Vector2i:
	if r.closed:
		return r.cells[r.cells.size() - 1]
	return r.cells[0]


## If the selected card has a committed route and `cell` is on or orthogonally
## adjacent to EITHER end, SEED the active stroke with the route's cells and resume
## magnetic drawing from that end. Grabbing the HEAD resumes as-is; grabbing the
## TAIL holds the stroke REVERSED so the magnet works from the start end (restored
## on commit). Either way the ORIGINAL spawn tile is preserved (stroke_spawn) so the
## lift keeps living where it was. Head wins when both ends are in range (short
## route). Returns true when it took over the drag; otherwise the caller starts a
## fresh replace stroke. Loops seed closed and resume under the existing reopen rule.
func _try_grab_end(cell: Vector2i) -> bool:
	var r: Route5 = routes[selected_card]
	if r == null or r.cells.size() < 2:
		return false
	var grab_head: bool = _md(cell, _route_head(r)) <= 1
	var grab_tail: bool = _md(cell, _route_tail(r)) <= 1
	if not grab_head and not grab_tail:
		return false
	drawing = true
	stroke = r.cells.duplicate()
	stroke_closed = r.closed
	stroke_spawn = r.cells[r.spawn_index()]
	stroke_loop_pending = false
	stroke_loop_end_hint = -1
	if r.closed:
		# LOOP: which end the magnet drives is decided by the DRAG DIRECTION on the
		# first move (_resolve_loop_grab), not now — a loop's two ends sit adjacent, so
		# direction disambiguates which the player means. But remember which end TILE the
		# finger is actually on (front=stroke[0], back=stroke.back()) as a tiebreaker: a
		# tap right on one end must control THAT end, not silently jump to the other.
		var d_front: int = _md(cell, r.cells[0])
		var d_back: int = _md(cell, r.cells[r.cells.size() - 1])
		if d_front < d_back:
			stroke_loop_end_hint = 0
		elif d_back < d_front:
			stroke_loop_end_hint = 1
		stroke_loop_pending = true
		stroke_reversed = false
		return true
	# OPEN route: reverse only when grabbing the tail (head preferred when both hit).
	stroke_reversed = grab_tail and not grab_head
	if stroke_reversed:
		stroke.reverse()
	return true


## First drag move on a grabbed LOOP: pick which end the magnet drives from the drag
## DIRECTION. `cell` is the finger's first target. A drag that heads toward an end's
## interior neighbour is a legal retract/undo of THAT end. If exactly one end can
## legally retract in this direction, control it; if both or neither (ambiguous), fall
## back to the HEAD (cells[0]) — the user-approved default. Controlling the back end
## (cells.back()) leaves the stroke as-is; controlling the front/head end reverses it
## so that end becomes the magnet head (stroke.back()), restored to original loop
## orientation on commit. Open routes never reach here.
func _resolve_loop_grab(cell: Vector2i) -> void:
	stroke_loop_pending = false
	var n := stroke.size()
	if not stroke_closed or n < 4:
		return
	var end_back: Vector2i = stroke[n - 1]
	var in_back: Vector2i = stroke[n - 2]
	var end_front: Vector2i = stroke[0]
	var in_front: Vector2i = stroke[1]
	var retract_back: bool = _md(cell, in_back) < _md(cell, end_back)
	var retract_front: bool = _md(cell, in_front) < _md(cell, end_front)
	var control_back: bool
	if retract_back != retract_front:
		# Exactly one end can legally retract in this drag direction: control that end.
		control_back = retract_back
	elif stroke_loop_end_hint != -1:
		# Direction is ambiguous (both or neither retract). Honour the end the FINGER
		# landed on so a tap right on one end controls THAT end (the reported bug: a tap
		# on the tail was jumping to the head because the head was the blanket default).
		control_back = stroke_loop_end_hint == 1
	else:
		control_back = false # truly between the ends: default to the head, as before.
	if control_back:
		stroke_reversed = false # magnet head stays stroke.back()
	else:
		stroke.reverse() # front end becomes the magnet head
		stroke_reversed = true


func _extend_stroke(pos: Vector2) -> void:
	if not drawing:
		return
	var cell := Grid5.cell_at(pos)
	if cell.x < 0:
		return
	if stroke_loop_pending:
		_resolve_loop_grab(cell)
	stroke_try_extend(cell)


## The magnetic drawing head, copied from main3.stroke_try_extend verbatim: the
## head is a magnet that slides along the path it has drawn, retracting when the
## cell behind is closer to the finger and extending one legal cell at a time
## toward it (axis with the most ground to cover first). Closing onto stroke[0]
## makes a loop. This is the v4 verb the prototype must preserve exactly.
func stroke_try_extend(cell: Vector2i) -> bool:
	if stroke.is_empty():
		return false
	if stroke_closed:
		if cell == stroke.back():
			stroke_closed = false
			return true
		return false
	if cell == stroke.back():
		return false
	if cell == stroke[0] and stroke.size() >= 4:
		var dh: Vector2i = cell - stroke.back()
		if absi(dh.x) + absi(dh.y) == 1:
			stroke_closed = true
			return true
	var changed := false
	while stroke.size() >= 2:
		var h: Vector2i = stroke[stroke.size() - 1]
		var p: Vector2i = stroke[stroke.size() - 2]
		if _md(cell, p) < _md(cell, h):
			stroke.remove_at(stroke.size() - 1)
			changed = true
		else:
			break
	var guard := 0
	while guard < MAX_STROKE_WALK:
		guard += 1
		var h: Vector2i = stroke[stroke.size() - 1]
		if h == cell:
			break
		var d: Vector2i = cell - h
		var steps: Array = []
		if absi(d.x) >= absi(d.y):
			if d.x != 0:
				steps.append(Vector2i(signi(d.x), 0))
			if d.y != 0:
				steps.append(Vector2i(0, signi(d.y)))
		else:
			if d.y != 0:
				steps.append(Vector2i(0, signi(d.y)))
			if d.x != 0:
				steps.append(Vector2i(signi(d.x), 0))
		var moved := false
		for s in steps:
			var n: Vector2i = h + s
			if _drawable(n) and not stroke.has(n):
				stroke.append(n)
				changed = true
				moved = true
				break
		if not moved:
			break
	return changed


func _md(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _end_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if selected_card >= 0 and stroke.size() > 1:
		var cells := stroke.duplicate()
		if stroke_reversed:
			cells.reverse() # restore the route's original orientation before commit
		# Keep the original spawn tile if it survived the edit; else fall back to the
		# current start end (only happens when a tail edit trims the spawn away).
		var spawn: Vector2i = stroke_spawn if (stroke_spawn.x >= 0 \
				and cells.has(stroke_spawn)) else cells[0]
		commit_route(selected_card, cells, stroke_closed, spawn)
	stroke = []
	stroke_closed = false
	stroke_reversed = false
	stroke_spawn = Vector2i(-1, -1)
	stroke_loop_pending = false


## True when the selected card may draw through `cell`: an open, routable cell
## that still has overlap capacity for THIS car's width (a capped tile already
## full for the selected car reads as a wall — felt as resistance, like corridors).
func _drawable(cell: Vector2i) -> bool:
	if not Grid5.passable(cell):
		return false
	if selected_card < 0:
		return true
	return _overlap_used(cell, selected_card) + cars[selected_card].width \
			<= Grid5.overlap_cap(cell)


## Summed car-width of every committed route (except route `except_i`) drawn
## through `cell` — how much of the tile's overlap cap is already spent.
func _overlap_used(cell: Vector2i, except_i: int) -> int:
	var used := 0
	for j in routes.size():
		if j == except_i or routes[j] == null:
			continue
		if routes[j].index_of(cell) >= 0:
			used += cars[j].width
	return used


# ---------------------------------------------------------------- route edits

## `spawn` is the tile the car should spawn/park at. Default Vector2i(-1,-1) means
## "use cells[0]" — the scripted direct-commit path passes nothing, so its behaviour
## (and the fingerprint) is unchanged. Interactive editing threads the preserved
## start tile through here so it survives reshaping either end of the route.
func commit_route(i: int, cells: Array, closed := false,
		spawn := Vector2i(-1, -1)) -> bool:
	if state != State.PLAN:
		push_error("commit_route(%d) refused: routes are locked outside PLAN" % i)
		return false
	var r: Route5 = null
	if cells.size() > 0:
		var err := Route5.validate(cells, closed and cells.size() >= 4)
		if err == "" and Grid5.route_min_corridor_width(cells) < cars[i].width:
			err = "too wide for that corridor"
		# MOMENTUM (opt-in per card via `min_hop`): a car with this flag physically
		# needs `min_hop` floors of run-up to brake, so two of its stops may not sit
		# closer than that. Walk the route's dock cells in travel order and reject if
		# consecutive stops on DIFFERENT floors are < min_hop apart. Cards without
		# `min_hop` (every shipped level) skip this entirely -> sim byte-identical.
		if err == "":
			var mh := int(CARDS[i].get("min_hop", 0))
			if mh > 0:
				var prev_y := 0
				var have_prev := false
				for mc in cells:
					if not Grid5.is_dock(mc):
						continue
					if have_prev and mc.y != prev_y and absi(mc.y - prev_y) < mh:
						err = "needs %d floors to brake between stops" % mh
						reject_stop = mc
						break
					prev_y = mc.y
					have_prev = true
		if err == "":
			# Overlap cap: this route's width plus the OTHER committed routes' widths
			# through any capped tile must not exceed that tile's cap (Numberlink-
			# style drawing limit; frees back on clear because routes[i] is replaced).
			for c in cells:
				if _overlap_used(c, i) + cars[i].width > Grid5.overlap_cap(c):
					err = "no room to thread through %s" % str(c)
					break
		if err != "":
			push_error("commit_route(%d) rejected: %s" % [i, err])
			reject_card = i
			reject_until_ms = Time.get_ticks_msec() + 4000
			reject_msg = "%s can't run there: %s" % [CARDS[i].name, err]
			return false
		r = Route5.new()
		r.cells = cells.duplicate()
		r.closed = closed and cells.size() >= 4
		r.spawn_cell = spawn if (spawn.x >= 0 and cells.has(spawn)) else cells[0]
	reject_stop = Vector2i(-1, -1) # a valid commit clears any lingering momentum glow
	routes[i] = r
	cars[i].set_route(r)
	replan_all()
	hud.refresh_cards()
	return true


func clear_route(i: int) -> void:
	if not can_edit():
		return
	commit_route(i, [], false)


# ---------------------------------------------------------------- pathfinding

func replan_all() -> void:
	for rid in waiting:
		for p in waiting[rid]:
			_compute_path_for(p)


func _compute_path_for(p) -> void:
	var path = Pathfind5.find_path(p.cur_room, p.dest_room, cars, p.salt, p.width, p.walk_mult)
	if path == null:
		p.legs = []
		p.no_path = true
	else:
		p.legs = path
		p.no_path = false


# ---------------------------------------------------------------- passengers

func _pick_type() -> String:
	var mix: Dictionary = level.mix
	var total := 0.0
	for t in mix:
		total += mix[t]
	var roll := rng.randf() * total
	for t in mix:
		roll -= mix[t]
		if roll <= 0.0:
			return t
	return mix.keys().back()


func _spawn_random() -> void:
	# FIXED-MANIFEST MODE: play the authored roster in order, one per spawn tick, then stop.
	if not _manifest.is_empty():
		if _manifest_idx >= _manifest.size():
			return  # roster exhausted -> no more spawns (fixed head-count)
		var m: Dictionary = _manifest[_manifest_idx]
		_manifest_idx += 1
		var mo := Levels5.room_id_of_letter(level, str(m.get("from", "")))
		var md := Levels5.room_id_of_letter(level, str(m.get("to", "")))
		if mo < 0 or md < 0 or mo == md:
			return
		var mret := -1
		if m.has("return"):
			mret = Levels5.room_id_of_letter(level, str(m.get("return")))
		spawn_passenger(str(m.get("type", "visitor")), mo, md, mret)
		return
	var t := _pick_type()
	var trips: Array = level.trips
	var picked: Dictionary
	if _cover_on and not _cover_rooms.is_empty():
		# Round-robin: this spawn belongs to the next demand room, weighted among its trips.
		var r: int = _cover_rooms[_cover_idx % _cover_rooms.size()]
		_cover_idx += 1
		var cand: Array = _cover_by_room.get(r, [])
		if cand.is_empty():
			cand = trips
		var ctotal := 0.0
		for row in cand:
			ctotal += row.w
		var croll := rng.randf() * ctotal
		picked = cand.back()
		for row in cand:
			croll -= row.w
			if croll <= 0.0:
				picked = row
				break
	else:
		var total := 0.0
		for row in trips:
			total += row.w
		var roll := rng.randf() * total
		picked = trips.back()
		for row in trips:
			roll -= row.w
			if roll <= 0.0:
				picked = row
				break
	# THEMATIC DEMAND (per-trip type binding): a trip row may DECLARE who takes it
	# via an OPTIONAL `type` field — "this run is only ever wheeled by delivery men",
	# "these seats are commuters". When the chosen trip carries a `type`, it OVERRIDES
	# the mix draw above so the passenger IS that type; a trip with NO `type` keeps the
	# mix-drawn `t` and behaves exactly as before. This is how a level makes its fiction
	# literal (R-8 binds the delivery-bay supply run to delivery men).
	#
	# DETERMINISM: the mix draw (_pick_type) and the trip draw (rng.randf above) still
	# run in the SAME order with the SAME rng calls regardless of whether the trip is
	# typed — the override only reassigns the resulting string. So every level that uses
	# no typed trips draws a byte-identical spawn stream and keeps its exact fingerprint.
	if picked.has("type"):
		t = str(picked.type)
	var o := Levels5.room_id_of_letter(level, str(picked.from))
	var d := Levels5.room_id_of_letter(level, str(picked.to))
	if o < 0 or d < 0 or o == d:
		return
	# ITINERARY (round trip): an OPTIONAL `return` letter on the trip means the figure,
	# after being served at `to`, runs one deterministic RETURN leg toward that room
	# (the bay/lobby area — never a random room) as an EMPTY width-1 person. Adds no rng
	# draw, so an untyped/return-less level's spawn stream is byte-identical as before.
	var ret := -1
	if picked.has("return"):
		ret = Levels5.room_id_of_letter(level, str(picked.get("return")))
	spawn_passenger(t, o, d, ret)


func spawn_passenger(ptype: String, origin: int, dest: int, return_room := -1) -> Passenger5:
	var p := Passenger5.new()
	p.setup(self, ptype, origin, dest)
	p.return_room = return_room
	p.salt = rng.randf()
	passengers_node.add_child(p)
	active_passengers.append(p)
	waiting[origin].append(p)
	_compute_path_for(p)
	p.begin_life()
	return p


## A rider stepped out of a car at dock `alight_cell` beside `room`. If this is its
## DESTINATION it walks to the back and is served (finish_alight). Otherwise it is a
## mid-journey TRANSFER: replan and send it straight to the next lift's queue at
## once — no back detour, no fresh activation dwell (start_transfer_walk).
func on_alight(p, alight_cell: Vector2i, room: int) -> void:
	if not p.legs.is_empty():
		p.legs.pop_front()
	p.cur_room = room
	if room == p.dest_room:
		p.start_alight_walk(alight_cell, room)
	else:
		_compute_path_for(p)
		if not waiting[room].has(p):
			waiting[room].append(p)
		p.start_transfer_walk(alight_cell)


## The (final) alight walk finished: the rider reached its destination room.
func finish_alight(p) -> void:
	on_served(p)


## A trip completed at its destination: count it served, log it, and drop the
## passenger into the BETWEEN phase (walk to the opposite tile + dwell). It stays
## alive; resolve_between decides vanish vs a fresh trip when the dwell ends.
func on_served(p) -> void:
	if waiting.has(p.cur_room):
		waiting[p.cur_room].erase(p)
	# SPECIAL TIPS (user): CARGO pays 5x on the LOADED leg (delivery man with a cart, not the
	# empty walk home). EXECUTIVES pay 2x — impatient VIPs who tip big for a quick lift. `cat`
	# groups the served log for the score screen: pax / exec / cargo.
	var mult := 1.0
	var cat := "pax"
	if p.ptype == "delivery" and not p.returning:
		mult = 5.0
		cat = "cargo"
	elif p.ptype == "executive":
		mult = 2.0
		cat = "exec"
	var tip: float = _tip_of(p.wait_time) * mult
	log_served.append({"type": p.ptype, "cat": cat, "wait": p.wait_time, "rides": p.rides, "tip": tip})
	served += 1
	tips += tip
	# A tip coin flies from the served passenger up to the TIPS counter (visual only, so it
	# reads that tips come from passengers). Cargo shows its 5x as a burst of 5 coins.
	# Deterministic arc side; skipped in headless.
	if not headless:
		# Coins scale with the TIP earned (~1 per $4), so a big exec/cargo payout throws a fat
		# stream of coins. Capped so a busy shift stays cheap.
		var coins: int = clampi(roundi(tip / 4.0), 3, 16)
		hud.fly_coin(p.global_position, 1.0 if served % 2 == 0 else -1.0, coins)
	if _cover_on:
		_served_rooms[p.cur_room] = true
	p.begin_between()
	# Coverage levels also require EVERY demand room to have been served: hitting the
	# passenger quota while abandoning a room is not a win (the room keeps spawning and
	# eventually loses you the run). Non-cover levels keep the plain quota check. SHIFT
	# levels ignore quota entirely — the shift clock ends the run (see advance).
	if shift_len <= 0.0 and state == State.PLAYING and not endless and served >= QUOTA and _rooms_covered():
		_win()


## The between-trip dwell ended: by a seeded per-level probability the passenger
## REACTIVATES with a new (reachable) destination — real demand, headless too — or
## VANISHES. Deterministic: keyed off the passenger's salt + trip, so it never
## perturbs the spawn rng stream and repeated runs are bit-identical.
func resolve_between(p) -> void:
	# ITINERARY (deterministic round trip) takes priority over the probabilistic
	# reactivate. A LOADED delivery man (return_room set, not yet returning) has just
	# dropped his cargo off: he sheds the cart (become_empty_return -> width 1, normal
	# speed), then reactivates toward his bound return room (the bay/lobby) as a plain
	# w1 person — any lift, normal pace, priced w1/normal by Pathfind5. This ALWAYS
	# happens (not seeded by probability), so every loaded delivery man makes the round
	# trip exactly once; when that return leg is served he falls through here again with
	# `returning` true and simply VANISHES (itinerary complete, no further wandering).
	if p.return_room >= 0:
		if not p.returning:
			p.become_empty_return()
			p.reactivate(p.return_room)
			_compute_path_for(p)
			waiting[p.cur_room].append(p)
			reactivations += 1
			return
		p.active = false
		_passengers_dirty = true
		p.queue_free()
		return
	var prob: float = float(level.get("reactivate", 0.25))
	if _seed01(p.salt, p.trip * 3 + 1) < prob:
		var dest := _pick_reactivate_dest(p)
		if dest >= 0:
			p.reactivate(dest)
			_compute_path_for(p)
			waiting[p.cur_room].append(p)
			reactivations += 1
			return
	# Vanish.
	p.active = false
	_passengers_dirty = true
	p.queue_free()


## A reachable room other than the current one, chosen deterministically. Empty
## (-1) if nothing is reachable from here on the committed network.
func _pick_reactivate_dest(p) -> int:
	var from: int = p.cur_room
	var reach: Array = []
	for r in Grid5.room_count():
		if r == from:
			continue
		if Pathfind5.find_path(from, r, cars, -1.0, p.width, p.walk_mult) != null:
			reach.append(r)
	if reach.is_empty():
		return -1
	return reach[int(_seed01(p.salt, p.trip * 3 + 2) * reach.size()) % reach.size()]


static func _seed01(salt: float, k: int) -> float:
	var v := sin(salt * 127.1 + float(k) * 311.7) * 43758.5453
	return absf(v - floorf(v))


func on_expired(p) -> void:
	_passengers_dirty = true
	queue_leave(p)
	if waiting.has(p.cur_room):
		waiting[p.cur_room].erase(p)
	log_lost.append({"type": p.ptype, "wait": p.wait_time, "rides": p.rides})
	p.queue_free()
	lost += 1
	tips -= LOST_TIP
	if shift_len <= 0.0 and state == State.PLAYING and not endless and lost >= MAX_LOST:
		_lose()


# -------------------------------------------------------------- queue line

## A passenger reached "activated" and joins its room's QUEUE at the TAIL. Its slot
## is FIXED from here; it only moves when someone ahead leaves (queue_leave). The
## queue is a single straight line from the dock extending back — no re-sorting.
func queue_join(p) -> void:
	var arr: Array = queues.get(p.cur_room, [])
	if arr.has(p):
		return
	arr.append(p)
	queues[p.cur_room] = arr
	p.queue_slot = arr.size() - 1
	_place_in_queue(p, p.cur_room, p.queue_slot)


## A passenger left the queue (boarded, expired, or removed). Everyone BEHIND it
## steps FORWARD one slot — a single event-driven step, not a per-frame re-sort.
func queue_leave(p) -> void:
	var rid: int = p.cur_room
	if not queues.has(rid):
		return
	var arr: Array = queues[rid]
	var idx: int = arr.find(p)
	if idx < 0:
		return
	arr.remove_at(idx)
	p.queue_slot = -1
	for j in range(idx, arr.size()):
		arr[j].queue_slot = j
		_place_in_queue(arr[j], rid, j)


const QUEUE_SPACING := 15.0     # px per unit-width (tight stack)
const QUEUE_FLOOR_OFFSET := 31.0 # cell bottom - 31 = the one floor line (car front-row height)
## Extras beyond this many unit-widths of queue wait INVISIBLY, stacked at the back, so a
## long line never spills across the building. Width-aware: a cargo room (width-3 carts)
## shows fewer figures than a passenger room, both bounded to the same physical span.
const QUEUE_MAX_VISIBLE_UNITS := 7.0


## The queue tile+dir a passenger waits at: the door of the SPECIFIC dock its next lift
## boards at (so a multi-dock room — e.g. the lobby: express left, local right — splits its
## line so each rider stands at the dock its lift actually uses). Falls back to the room's
## single default tile when the rider has no plan yet (no legs => the fingerprint no-route sim,
## which stays identical).
func _rider_qtile(p) -> Dictionary:
	if not p.legs.is_empty():
		var bc: Vector2i = p.legs[0].get("board_cell", Vector2i(-1, -1))
		if bc.x >= 0:
			return Grid5.queue_tile_for_dock(p.cur_room, bc)
	return {"cell": Grid5.room_queue(p.cur_room), "dir": Grid5.room_queue_dir(p.cur_room)}


## World position for a figure whose reserved-span CENTRE is at `center_units` of linear
## queue depth: a straight line on the floor from the queue tile (unit 0, at the dock)
## extending back into the room.
func _pos_at_units(qcell: Vector2i, qdir: Vector2i, center_units: float) -> Vector2:
	var qc := Grid5.cell_center(qcell)
	var toward := Grid5.cell_center(qcell + qdir) - qc
	var tx := signf(toward.x) if absf(toward.x) > 0.01 else 1.0
	var floor_y := Grid5.cell_rect(qcell).end.y - QUEUE_FLOOR_OFFSET
	# Pull the whole line one SPACING toward the dock so the front waits right at the doors.
	return Vector2(qc.x - tx * (center_units - 1.0) * QUEUE_SPACING, floor_y)


## Unit-widths of queue AHEAD of slot `idx` (its front edge) THAT SHARE THE SAME DOCK — so
## each dock's sub-line packs independently. WIDTH-AWARE: a width-3 delivery man reserves a
## 3-wide span so waiting figures never overlap.
func _queue_units_before(rid: int, idx: int, tile: Vector2i) -> float:
	var arr: Array = queues.get(rid, [])
	var u := 0.0
	for j in mini(idx, arr.size()):
		if _rider_qtile(arr[j]).cell == tile:
			u += float(arr[j].width)
	return u


## Stand a queued figure at its slot AND set its visibility: within the visible span it
## shows at its slot; beyond it, it waits invisibly clamped just behind the last visible
## figure (so it eases in smoothly when the queue advances). An all-width-1 queue inside
## the cap reduces EXACTLY to idx * SPACING (short queues render as before, just tighter).
func _place_in_queue(p, rid: int, idx: int) -> void:
	var t := _rider_qtile(p)
	var before := _queue_units_before(rid, idx, t.cell)
	var half := (float(p.width) - 1.0) * 0.5
	if before < QUEUE_MAX_VISIBLE_UNITS:
		p.visible = true
		p.set_stand(_pos_at_units(t.cell, t.dir, before + half))
	else:
		p.visible = false
		p.set_stand(_pos_at_units(t.cell, t.dir, QUEUE_MAX_VISIBLE_UNITS + half))


# ---------------------------------------------------------------- corridors

## FIFO WIDTH-SHARED corridor mutex per contiguous corridor GROUP, ported from
## v3 main3. A car may be inside only if car.width <= corridor.width AND the sum
## of widths inside <= corridor.width, and only the FRONT of the queue is ever
## admitted (strict FIFO, so a stream of pods can't starve a waiting normal car).
## With the default corridor width 2 and a normal car at width 2 this is exactly
## a one-lift mutex: the first car takes all the width, the next can't fit until
## it leaves.
func corridor_request(car, group: int) -> bool:
	var g: Dictionary = corridors[group]
	if g.holders.has(car):
		return true
	if car.width > g.width:
		return false # too wide for this corridor, ever: never queue for it
	if not g.queue.has(car):
		g.queue.append(car)
	if g.queue[0] == car and g.used + car.width <= g.width:
		g.queue.pop_front()
		g.holders.append(car)
		g.used += car.width
		return true
	return false


## Would corridor_request() succeed right now? A PURE PREDICATE (never queues) —
## the braking lookahead asks it so a car that can't enter arrives at the mouth
## already stopped.
func corridor_free_for(car, group: int) -> bool:
	var g: Dictionary = corridors[group]
	if g.holders.has(car):
		return true
	if car.width > g.width:
		return false
	if not g.queue.is_empty() and g.queue[0] != car:
		return false
	return g.used + car.width <= g.width


func corridor_release(car, group: int) -> void:
	var g: Dictionary = corridors[group]
	if g.holders.has(car):
		g.holders.erase(car)
		g.used -= car.width


## Remove a car from every corridor queue/lock (route replaced or cleared).
func corridor_cancel(car) -> void:
	for gi in corridors:
		corridors[gi].queue.erase(car)
		corridor_release(car, gi)
