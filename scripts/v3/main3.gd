extends Node2D
## Game controller for prototype v3 "Path Drawing".
## Owns: the three route cards + cars, drag-to-draw route editing, the gate
## FIFO mutexes, passenger spawning + time-based replanning, session flow
## (X-1: Served 30 before Lost 8, win -> keep playing/restart, lose -> retry),
## and the game time scale (pause/1x/3x — a plain variable multiplied into
## game ticks, so UI and route editing keep working while paused).

enum State { INTRO, PLAYING, WIN, LOSE }

const CARDS := [
	{"name": "LOCAL A", "type": "standard", "cap": 4, "speed": 260.0,
			"color": Color(0.45, 0.68, 0.95)},
	{"name": "LOCAL B", "type": "standard", "cap": 4, "speed": 260.0,
			"color": Color(0.5, 0.88, 0.55)},
	{"name": "EXPRESS", "type": "express", "cap": 4, "speed": 520.0,
			"color": Color(0.98, 0.68, 0.2)},
]

const QUOTA := 30
const MAX_LOST := 8
const SPAWN_START := 5.5
const SPAWN_END := 3.0
const SPAWN_RAMP_T := 240.0

var state: int = State.INTRO
var time_scale := 1.0
var served := 0
var lost := 0
var elapsed := 0.0 # game-time seconds since session start (drives spawn ramp)
var spawn_timer := 0.0
var auto_spawn := true # test hook: harness disables random spawns
var endless := false # after a win, "keep playing" disables win/lose checks

var routes: Array = [null, null, null] # Route3 or null per card
var cars: Array = [null, null, null] # Car3 per card (always exist, may be idle)
var gates := {} # gate cell -> {"holder": Car3 or null, "queue": Array[Car3]}
var waiting := {} # room cell -> Array[Passenger3] in arrival order

var selected_card := -1
var drawing := false
var stroke: Array = [] # Vector2i cells of the active drag

@onready var grid: Grid3 = $Grid
@onready var cars_node: Node2D = $Cars
@onready var passengers_node: Node2D = $Passengers
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	randomize()
	for g in Grid3.gate_cells():
		gates[g] = {"holder": null, "queue": []}
	for r in Grid3.rooms():
		waiting[r] = []
	grid.game = self
	hud.game = self
	for i in CARDS.size():
		var c := Car3.new()
		c.setup(self, i, CARDS[i])
		cars_node.add_child(c)
		cars[i] = c
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
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			_spawn_random()
			spawn_timer = spawn_interval()
	for c in cars:
		if c != null:
			c.tick(dt)
	for p in passengers_node.get_children():
		p.tick(dt)


func spawn_interval() -> float:
	return lerpf(SPAWN_START, SPAWN_END, clampf(elapsed / SPAWN_RAMP_T, 0.0, 1.0))


# ---------------------------------------------------------------- session flow

func start_session() -> void:
	hud.hide_overlay()
	state = State.PLAYING
	spawn_timer = 2.0


func keep_playing() -> void:
	endless = true
	hud.hide_overlay()
	state = State.PLAYING


## Reset counters/passengers (routes are KEPT — free redraw makes wiping them
## pointless); used by both the win "Restart" and the lose "Retry".
func restart_session() -> void:
	served = 0
	lost = 0
	elapsed = 0.0
	endless = false
	_clear_passengers()
	hud.hide_overlay()
	state = State.PLAYING
	spawn_timer = 2.0


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
	var path = Pathfind3.find_path(p.cur_cell, p.dest_cell, cars)
	if path == null:
		p.legs = []
		p.no_path = true
	else:
		p.legs = path
		p.no_path = false


# ---------------------------------------------------------------- passengers

func _spawn_random() -> void:
	var t := "visitor" if randf() < 0.55 else "patient"
	var rooms := Grid3.rooms()
	var lobby: Array = rooms.filter(func(c): return c.y == 0)
	var upper: Array = rooms.filter(func(c): return c.y > 0)
	var o: Vector2i
	var d: Vector2i
	if randf() < 0.6:
		# Trip involves a lobby room, either direction.
		var l: Vector2i = lobby.pick_random()
		var u: Vector2i = upper.pick_random()
		if randf() < 0.5:
			o = l
			d = u
		else:
			o = u
			d = l
	else:
		o = upper.pick_random()
		d = upper.pick_random()
		while d == o:
			d = upper.pick_random()
	spawn_passenger(t, o, d)


func spawn_passenger(ptype: String, origin: Vector2i, dest: Vector2i) -> Passenger3:
	var p := Passenger3.new()
	p.setup(self, ptype, origin, dest)
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
	p.queue_free()
	served += 1
	if state == State.PLAYING and not endless and served >= QUOTA:
		_win()


func on_expired(p) -> void:
	waiting[p.cur_cell].erase(p)
	p.queue_free()
	lost += 1
	if state == State.PLAYING and not endless and lost >= MAX_LOST:
		_lose()


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
