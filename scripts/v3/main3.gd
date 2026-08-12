extends Node2D
## Game controller for prototype v3 "Path Drawing".
## Owns: the level config (data-driven via Levels3), the three route cards +
## cars, drag-to-draw route editing, the gate FIFO mutexes, PULSE-based
## passenger spawning + time-based replanning, session flow (win -> next
## level / level select / keep playing, lose -> retry / level select), and
## the game time scale (pause/1x/3x - a plain variable multiplied into game
## ticks, so UI and route editing keep working while paused).
##
## Mid-game route commits/CLEAR do NOT teleport cars: Car3.apply_route runs
## the recall -> redeploy state machine (see car3.gd); only a never-deployed
## card's first commit appears instantly.
##
## All randomness flows through `rng` (one RandomNumberGenerator): normal
## play randomizes it, the balance harness sets a fixed seed for
## deterministic runs.

enum State { INTRO, PLAYING, WIN, LOSE }

## Safety bound on one magnetic-extend walk (a drag sample can never legitimately
## cross more cells than the grid holds; each step is strictly closer anyway).
const MAX_STROKE_WALK := 256

var level: Dictionary = {} # Levels3 entry for Levels3.current
var CARDS: Array = [] # this level's 3 elevator cards
var QUOTA := 30
var MAX_LOST := 8

var state: int = State.INTRO
var time_scale := 1.0
var served := 0
var lost := 0
var elapsed := 0.0 # game-time seconds since session start (drives spawn ramp)
var auto_spawn := true # test hook: harness may disable random spawns
var endless := false # after a win, "keep playing" disables win/lose checks

var rng := RandomNumberGenerator.new()

# Pulse spawner state: quiet until pulse_timer runs out, then a burst of
# burst_left passengers spawns gap seconds apart.
var pulse_timer := 0.0
var burst_left := 0
var burst_timer := 0.0

var watch := "" # "" (normal play) | "naive" | "thesis" (from Levels3.watch_strategy)

var routes: Array = [null, null, null] # Route3 or null per card
var cars: Array = [null, null, null] # Car3 per card (always exist, may be idle)
var gates := {} # gate GROUP index -> {"holder": Car3 or null, "queue": Array[Car3]}
var waiting := {} # room cell -> Array[Passenger3] in arrival order

# Session log for stats/harness: one entry per finished passenger,
# {"type", "origin", "dest", "wait", "rides"}.
var log_served: Array = []
var log_lost: Array = []

var selected_card := -1
var drawing := false
var stroke: Array = [] # Vector2i cells of the active drag
var stroke_closed := false # live stroke closed back onto stroke[0] (a loop)

@onready var grid: Grid3 = $Grid
@onready var cars_node: Node2D = $Cars
@onready var passengers_node: Node2D = $Passengers
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	level = Levels3.get_level(Levels3.current)
	watch = Levels3.watch_strategy
	Grid3.load_level(level.rows)
	CARDS = level.cards
	QUOTA = level.quota
	MAX_LOST = level.max_lost
	routes = []
	cars = []
	for gi in Grid3.gate_groups().size():
		gates[gi] = {"holder": null, "queue": []}
	for r in Grid3.rooms():
		waiting[r] = []
	grid.game = self
	hud.game = self
	for i in CARDS.size():
		routes.append(null)
		var c := Car3.new()
		c.setup(self, i, CARDS[i])
		cars_node.add_child(c)
		cars.append(c)
	if watch != "":
		# Watch mode: canonical harness seed (identical demand for both
		# strategies), scenario routes pre-drawn, editing disabled, no intro.
		rng.seed = Scenarios3.SEEDS[level.id]
		start_session()
		var rs: Array = Scenarios3.route_set(level.id, watch)
		for i in mini(rs.size(), CARDS.size()):
			commit_route(i, Scenarios3.cells_of(rs[i]), Scenarios3.closed_of(rs[i]))
	else:
		rng.randomize() # normal play is unseeded; the harness overrides rng.seed
		hud.show_intro()
	hud.refresh_cards()


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	advance(delta * time_scale)
	_reflow_queues()
	hud.refresh_stats()


## One logic step of `dt` game-seconds (also driven directly by the harness).
func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	elapsed += dt
	if auto_spawn:
		_spawn_tick(dt)
	for c in cars:
		if c != null:
			c.tick(dt)
	for p in passengers_node.get_children():
		p.tick(dt)


## Average per-passenger spawn interval right now (ramps over the session).
func current_interval() -> float:
	var s: Dictionary = level.spawn
	return lerpf(s.interval_start, s.interval_end,
			clampf(elapsed / float(s.ramp), 0.0, 1.0))


## Pulse spawning: bursts of burst_min..burst_max passengers `gap` s apart,
## then quiet for burst_size * interval (average rate == interval, but with
## visible lulls where cars go idle and door timing reads).
func _spawn_tick(dt: float) -> void:
	var s: Dictionary = level.spawn
	if burst_left > 0:
		burst_timer -= dt
		if burst_timer <= 0.0:
			_spawn_random()
			burst_left -= 1
			burst_timer = s.gap
	else:
		pulse_timer -= dt
		if pulse_timer <= 0.0:
			var n: int = rng.randi_range(s.burst_min, s.burst_max)
			burst_left = n
			burst_timer = 0.0 # first of the burst spawns immediately
			pulse_timer = n * current_interval()


# ---------------------------------------------------------------- session flow

func start_session() -> void:
	hud.hide_overlay()
	state = State.PLAYING
	_reset_spawner()


func keep_playing() -> void:
	endless = true
	hud.hide_overlay()
	state = State.PLAYING


## Reset counters/passengers (routes are KEPT — free redraw makes wiping them
## pointless); used by the lose "Retry".
func restart_session() -> void:
	served = 0
	lost = 0
	elapsed = 0.0
	endless = false
	log_served = []
	log_lost = []
	_clear_passengers()
	hud.hide_overlay()
	state = State.PLAYING
	_reset_spawner()


func next_level() -> void:
	Levels3.current = mini(Levels3.current + 1, Levels3.LEVELS.size() - 1)
	Levels3.watch_strategy = ""
	get_tree().change_scene_to_file("res://scenes/v3_main.tscn")


func to_level_select() -> void:
	Levels3.watch_strategy = ""
	get_tree().change_scene_to_file("res://scenes/v3_select.tscn")


## Watch overlays' "Watch Again": reload the scene with the same strategy
## (Levels3.watch_strategy is still set), so the seeded run replays exactly.
func watch_again() -> void:
	get_tree().change_scene_to_file("res://scenes/v3_main.tscn")


func _reset_spawner() -> void:
	pulse_timer = 2.0
	burst_left = 0
	burst_timer = 0.0


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
	for r in waiting:
		waiting[r].clear()
	for c in cars:
		c.riders.clear()
		c.set_route(c.route) # re-park at route start


func set_speed(s: float) -> void:
	time_scale = s


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if watch != "" or state != State.PLAYING:
		return # watch mode: routes are the scenario's, taps do nothing
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
	elif event is InputEventScreenDrag:
		_extend_stroke(event.position)


func select_card(i: int) -> void:
	if watch != "":
		return # card chips are display-only while watching
	selected_card = -1 if selected_card == i else i
	drawing = false
	stroke = []
	stroke_closed = false
	hud.refresh_cards()


func _begin_stroke(pos: Vector2) -> void:
	if selected_card < 0:
		return
	var cell := Grid3.cell_at(pos)
	if cell.x < 0 or not Grid3.passable(cell):
		return
	drawing = true
	stroke = [cell]
	stroke_closed = false


func _extend_stroke(pos: Vector2) -> void:
	if not drawing:
		return
	var cell := Grid3.cell_at(pos)
	if cell.x < 0:
		return
	stroke_try_extend(cell)


## Grow the active stroke toward `cell` (the finger's cell this drag sample).
## MAGNETIC HEAD: picture the head as a magnet pulled toward the finger, free to
## slide along the path it has drawn. One idea, applied in both directions and
## purely positional (drag speed is irrelevant):
##   RETRACT — pop the head while the cell BEHIND it is strictly closer to the
##     finger than the head is. Gives straight-run snapping, cutting back around
##     corners, and rerouting at a junction (the abandoned leg pops off, then the
##     outbound walk below draws the new one).
##   EXTEND — push the head onward while a legal neighbour is strictly closer to
##     the finger than the head is, preferring the axis with the most ground left
##     to cover. Gives straight-line fill across a fast skip and corners that
##     turn on their own, without ever teleporting: the walk moves one adjacent
##     legal cell at a time, so a wall or the stroke's own body simply stops it
##     where it stands.
## A finger that pulls neither way — a sideways graze of an earlier part of the
## path — makes nothing closer, so the stroke holds still (the graze collides).
## CLOSING (v3.4): dragging onto stroke[0] when the stroke has >= 4 cells and
## the last cell is orthogonally adjacent to it CLOSES the loop — checked before
## retract. While closed, forward drags are ignored and retracting is impossible;
## reversing onto the TAIL cell REOPENS the loop, after which retract continues.
## Returns true if the stroke changed.
func stroke_try_extend(cell: Vector2i) -> bool:
	if stroke.is_empty():
		return false
	if stroke_closed:
		if cell == stroke.back():
			stroke_closed = false # reopen: remove the closing link only
			return true
		return false # closed: any other drag is ignored
	if cell == stroke.back():
		return false
	# Closing takes precedence over retract when the head is adjacent to start.
	if cell == stroke[0] and stroke.size() >= 4:
		var dh: Vector2i = cell - stroke.back()
		if absi(dh.x) + absi(dh.y) == 1:
			stroke_closed = true # close the loop; stroke cells unchanged
			return true
	# Magnetic retract: slide the head back toward the finger along the path.
	var changed := false
	while stroke.size() >= 2:
		var h: Vector2i = stroke[stroke.size() - 1]
		var p: Vector2i = stroke[stroke.size() - 2]
		if _md(cell, p) < _md(cell, h):
			stroke.remove_at(stroke.size() - 1)
			changed = true
		else:
			break
	# Magnetic extend: walk the head toward the finger one legal cell at a time,
	# each step strictly closer (so the walk always terminates), taking the axis
	# with the most ground left to cover first so corners turn naturally.
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
			if Grid3.passable(n) and not stroke.has(n):
				stroke.append(n)
				changed = true
				moved = true
				break
		if not moved:
			break # walled in, or blocked by the stroke's own body
	return changed


## Manhattan distance between two cells (the metric the magnetic pull uses).
func _md(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _end_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if selected_card >= 0 and stroke.size() > 0:
		commit_route(selected_card, stroke, stroke_closed)
	stroke = []
	stroke_closed = false


# ---------------------------------------------------------------- route edits

## Commit `cells` as card i's route (REPLACES any previous route). The car
## decides how to get there (Car3.apply_route): a never-deployed car appears
## instantly; a deployed one recalls its riders to the nearest old-route room
## stop first, then redeploys at the new start after a ghost countdown.
## `closed` marks a loop (stroke closed onto its head — the car will travel
## forward around the cycle forever). Every waiting passenger replans against
## the NEW route immediately.
func commit_route(i: int, cells: Array, closed := false) -> void:
	var r: Route3 = null
	if cells.size() > 0:
		r = Route3.new()
		r.cells = cells.duplicate()
		r.closed = closed and cells.size() >= 4
	routes[i] = r
	cars[i].apply_route(r)
	replan_all()
	hud.refresh_cards()


func clear_route(i: int) -> void:
	routes[i] = null
	cars[i].apply_route(null)
	replan_all()
	hud.refresh_cards()


## A recalled car dumped a rider at `cell` (a room stop of its OLD route):
## either that's their destination (served) or they rejoin the waiting pool
## there with a fresh plan against the current network.
func on_recall_drop(p, cell: Vector2i) -> void:
	p.riding = null
	p.cur_cell = cell
	if not p.legs.is_empty():
		p.legs = []
	if cell == p.dest_cell:
		on_served(p)
		return
	_compute_path_for(p)
	waiting[cell].append(p)


func route_warning(i: int) -> bool:
	return routes[i] != null and routes[i].stop_cells().size() < 2


# ---------------------------------------------------------------- gates

## FIFO mutex per gate GROUP (a whole corridor of contiguous G cells).
## Grants the lock iff the group is free and `car` is at the front of the
## queue; otherwise the car stays queued and must retry.
func gate_request(car, group: int) -> bool:
	var g: Dictionary = gates[group]
	if g.holder == car:
		return true
	if not g.queue.has(car):
		g.queue.append(car)
	if g.holder == null and g.queue[0] == car:
		g.queue.pop_front()
		g.holder = car
		return true
	return false


func gate_release(car, group: int) -> void:
	if gates[group].holder == car:
		gates[group].holder = null


## Remove a car from every gate queue/lock (route replaced or cleared).
func gate_cancel(car) -> void:
	for gi in gates:
		gates[gi].queue.erase(car)
		if gates[gi].holder == car:
			gates[gi].holder = null


# ---------------------------------------------------------------- pathfinding

## Recompute paths for every WAITING passenger. Called on any route commit or
## clear. Riders keep their current leg and replan on alight.
func replan_all() -> void:
	for r in waiting:
		for p in waiting[r]:
			_compute_path_for(p)


func _compute_path_for(p) -> void:
	var path = Pathfind3.find_path(p.cur_cell, p.dest_cell, cars, p.salt)
	if path == null:
		p.legs = []
		p.no_path = true
	else:
		p.legs = path
		p.no_path = false


# ---------------------------------------------------------------- passengers

## Weighted pick from the level's type mix.
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


func _pick_room(group: Array, avoid: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var pool := group.filter(func(c): return c != avoid)
	if pool.is_empty():
		pool = group
	return pool[rng.randi_range(0, pool.size() - 1)]


func _spawn_random() -> void:
	var t := _pick_type()
	var o: Vector2i
	var d: Vector2i
	if t == "exec" and not level.exec_origins.is_empty() \
			and not level.exec_dests.is_empty():
		# Execs use only the level-designated origin/destination rooms.
		o = _pick_room(level.exec_origins)
		d = _pick_room(level.exec_dests, o)
	else:
		if t == "exec":
			t = "visitor" # level configured exec weight but no rooms: degrade
		# Weighted trip table between named room groups.
		var groups: Dictionary = level.groups
		var trips: Array = level.trips
		var total := 0.0
		for row in trips:
			total += row.w
		var roll := rng.randf() * total
		var picked: Dictionary = trips.back()
		for row in trips:
			roll -= row.w
			if roll <= 0.0:
				picked = row
				break
		o = _pick_room(groups[picked.from])
		d = _pick_room(groups[picked.to], o)
	if o == d:
		return # degenerate config (single shared room); skip this spawn
	spawn_passenger(t, o, d)


func spawn_passenger(ptype: String, origin: Vector2i, dest: Vector2i) -> Passenger3:
	var p := Passenger3.new()
	p.setup(self, ptype, origin, dest)
	p.salt = rng.randf()
	passengers_node.add_child(p)
	waiting[origin].append(p)
	_compute_path_for(p)
	return p


## A rider stepped out of a car at room cell: served, or transfer + replan.
func on_alight(p, cell: Vector2i) -> void:
	p.riding = null
	if not p.legs.is_empty():
		p.legs.pop_front()
	p.cur_cell = cell
	if cell == p.dest_cell:
		on_served(p)
	else:
		_compute_path_for(p) # always replan from the transfer room
		waiting[cell].append(p)


func on_served(p) -> void:
	p.active = false
	log_served.append({"type": p.ptype, "origin": p.origin_cell,
			"dest": p.dest_cell, "wait": p.wait_time, "rides": p.rides})
	p.queue_free()
	served += 1
	if state == State.PLAYING and not endless and served >= QUOTA:
		_win()


func on_expired(p) -> void:
	waiting[p.cur_cell].erase(p)
	log_lost.append({"type": p.ptype, "origin": p.origin_cell,
			"dest": p.dest_cell, "wait": p.wait_time, "rides": p.rides})
	p.queue_free()
	lost += 1
	if state == State.PLAYING and not endless and lost >= MAX_LOST:
		_lose()


## Total game-seconds cars of this session spent blocked at gates (stat).
func gate_wait_total() -> float:
	var t := 0.0
	for c in cars:
		if c != null:
			t += c.gate_wait_total
	return t


## Total gate-corridor lock acquisitions this session (stat / harness).
func gate_transit_total() -> int:
	var n := 0
	for c in cars:
		if c != null:
			n += c.gate_transits
	return n


## Stack waiting passengers inside their room cell (queue beside the room).
func _reflow_queues() -> void:
	for r in waiting:
		var base := Grid3.cell_center(r)
		var i := 0
		for p in waiting[r]:
			var col := i % 3
			var row := int(i / 3.0)
			p.position = base + Vector2(-22.0 + col * 22.0, 30.0 - row * 22.0)
			i += 1
