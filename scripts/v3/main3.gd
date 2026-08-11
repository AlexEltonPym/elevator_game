extends Node2D
## Game controller for prototype v3 "Path Drawing".
## Owns: the level config (data-driven via Levels3), the three route cards +
## cars, drag-to-draw route editing, the gate FIFO mutexes, PULSE-based
## passenger spawning + time-based replanning, session flow (win -> next
## level / level select / keep playing, lose -> retry / level select), and
## the game time scale (pause/1x/3x - a plain variable multiplied into game
## ticks, so UI and route editing keep working while paused).
##
## All randomness flows through `rng` (one RandomNumberGenerator): normal
## play randomizes it, the balance harness sets a fixed seed for
## deterministic runs.

enum State { INTRO, PLAYING, WIN, LOSE }

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

var routes: Array = [null, null, null] # Route3 or null per card
var cars: Array = [null, null, null] # Car3 per card (always exist, may be idle)
var gates := {} # gate cell -> {"holder": Car3 or null, "queue": Array[Car3]}
var waiting := {} # room cell -> Array[Passenger3] in arrival order

# Session log for stats/harness: one entry per finished passenger,
# {"type", "origin", "dest", "wait", "rides"}.
var log_served: Array = []
var log_lost: Array = []

var selected_card := -1
var drawing := false
var stroke: Array = [] # Vector2i cells of the active drag

@onready var grid: Grid3 = $Grid
@onready var cars_node: Node2D = $Cars
@onready var passengers_node: Node2D = $Passengers
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	rng.randomize() # normal play is unseeded; the harness overrides rng.seed
	level = Levels3.get_level(Levels3.current)
	Grid3.load_level(level.rows)
	CARDS = level.cards
	QUOTA = level.quota
	MAX_LOST = level.max_lost
	routes = []
	cars = []
	for g in Grid3.gate_cells():
		gates[g] = {"holder": null, "queue": []}
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
	hud.refresh_cards()
	hud.show_intro()


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
	get_tree().change_scene_to_file("res://scenes/v3_main.tscn")


func to_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/v3_select.tscn")


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
	if state != State.PLAYING:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(event.position)
		else:
			_end_stroke()
	elif event is InputEventScreenDrag:
		_extend_stroke(event.position)


func select_card(i: int) -> void:
	selected_card = -1 if selected_card == i else i
	drawing = false
	stroke = []
	hud.refresh_cards()


func _begin_stroke(pos: Vector2) -> void:
	if selected_card < 0:
		return
	var cell := Grid3.cell_at(pos)
	if cell.x < 0 or not Grid3.passable(cell):
		return
	drawing = true
	stroke = [cell]


func _extend_stroke(pos: Vector2) -> void:
	if not drawing:
		return
	var cell := Grid3.cell_at(pos)
	if cell.x < 0:
		return
	stroke_try_extend(cell)


## Grow the active stroke toward `cell`. Legal only into an orthogonally
## adjacent, non-blocked, not-yet-used cell. Dragging back onto a cell already
## in the stroke RETRACTS the stroke to that cell (ONI pipe-style undo).
## A fast drag that skipped cells is filled in ONLY when there is an
## unambiguous straight-line legal path from the last cell; anything else is
## ignored (never teleport). Returns true if the stroke changed.
func stroke_try_extend(cell: Vector2i) -> bool:
	if stroke.is_empty():
		return false
	var last: Vector2i = stroke.back()
	if cell == last:
		return false
	var idx := stroke.find(cell)
	if idx != -1:
		stroke.resize(idx + 1)
		return true
	if not Grid3.passable(cell):
		return false
	var d := cell - last
	if absi(d.x) + absi(d.y) == 1:
		stroke.append(cell)
		return true
	if d.x != 0 and d.y != 0:
		return false # diagonal jump: ambiguous, ignore
	var step := Vector2i(signi(d.x), signi(d.y))
	var fill: Array = []
	var c := last + step
	while true:
		if not Grid3.passable(c) or stroke.has(c):
			return false # any illegal intermediate voids the whole jump
		fill.append(c)
		if c == cell:
			break
		c += step
	stroke.append_array(fill)
	return true


func _end_stroke() -> void:
	if not drawing:
		return
	drawing = false
	if selected_card >= 0 and stroke.size() > 0:
		commit_route(selected_card, stroke)
	stroke = []


# ---------------------------------------------------------------- route edits

## Commit `cells` as card i's route (REPLACES any previous route). Riders of
## the old route step out at its nearest room stop and rejoin the waiting
## pool; every waiting passenger replans.
func commit_route(i: int, cells: Array) -> void:
	_drop_riders(i)
	var r: Route3 = null
	if cells.size() > 0:
		r = Route3.new()
		r.cells = cells.duplicate()
	routes[i] = r
	cars[i].set_route(r)
	replan_all()
	hud.refresh_cards()


func clear_route(i: int) -> void:
	_drop_riders(i)
	routes[i] = null
	cars[i].set_route(null)
	replan_all()
	hud.refresh_cards()


## Route i is about to change: its riders step out at the old route's room
## stop nearest to the car and rejoin the waiting pool (replan_all follows).
func _drop_riders(i: int) -> void:
	var car = cars[i]
	if car == null or car.riders.is_empty() or car.route == null:
		return
	var stop_idx: Array = car.route.stop_indices()
	if stop_idx.is_empty():
		return
	var best: int = stop_idx[0]
	for s in stop_idx:
		if absi(s - car.idx) < absi(best - car.idx):
			best = s
	var room: Vector2i = car.route.cells[best]
	for p in car.riders.duplicate():
		p.riding = null
		p.cur_cell = room
		waiting[room].append(p)
	car.riders.clear()


func route_warning(i: int) -> bool:
	return routes[i] != null and routes[i].stop_cells().size() < 2


# ---------------------------------------------------------------- gates

## FIFO mutex. Grants the lock iff the gate is free and `car` is at the front
## of the queue; otherwise the car stays queued and must retry.
func gate_request(car, cell: Vector2i) -> bool:
	var g: Dictionary = gates[cell]
	if g.holder == car:
		return true
	if not g.queue.has(car):
		g.queue.append(car)
	if g.holder == null and g.queue[0] == car:
		g.queue.pop_front()
		g.holder = car
		return true
	return false


func gate_release(car, cell: Vector2i) -> void:
	if gates[cell].holder == car:
		gates[cell].holder = null


## Remove a car from every gate queue/lock (route replaced or cleared).
func gate_cancel(car) -> void:
	for cell in gates:
		gates[cell].queue.erase(car)
		if gates[cell].holder == car:
			gates[cell].holder = null


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
