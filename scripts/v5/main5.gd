extends Node2D
## Game controller for the v5 "Rooms" feel-prototype. Adapted from
## scripts/v3/main3.gd: the phase machine (BRIEFING -> PLAN -> PLAYING ->
## WIN/LOSE), the pulse spawner and the MAGNETIC route-drawing verb are reused
## essentially verbatim (that verb is the thing the prototype must keep).
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

enum State { BRIEFING, PLAN, PLAYING, WIN, LOSE }

const MAX_STROKE_WALK := 256

var level: Dictionary = {}
var CARDS: Array = []
var QUOTA := 12
var MAX_LOST := 8

var state: int = State.BRIEFING
var time_scale := 1.0
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

var active_passengers: Array = []
var _passengers_dirty := false

var routes: Array = []
var cars: Array = []
var waiting := {} # room_id -> Array[Passenger5] in arrival order
var corridors := {} # corridor group index -> {width, used, holders, queue}

var log_served: Array = []
var log_lost: Array = []

var selected_card := -1
var drawing := false
var stroke: Array = []
var stroke_closed := false

var reject_msg := ""
var reject_card := -1
var reject_until_ms := 0

@onready var grid: Grid5 = $Grid
@onready var cars_node: Node2D = $Cars
@onready var passengers_node: Node2D = $Passengers
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	if headless:
		set_process(false)
	level = Levels5.get_level(Levels5.current)
	Grid5.load_level(level)
	if not headless:
		for n in [grid, cars_node, passengers_node]:
			n.scale = Vector2(Grid5.view_scale, Grid5.view_scale)
			n.position = Grid5.view_offset
	CARDS = level.cards
	QUOTA = level.quota
	MAX_LOST = level.max_lost
	routes = []
	cars = []
	for gi in Grid5.corridor_groups().size():
		corridors[gi] = {"width": Grid5.corridor_group_width(gi), "used": 0,
				"holders": [], "queue": []}
	for rid in Grid5.room_count():
		waiting[rid] = []
	grid.game = self
	hud.game = self
	for i in CARDS.size():
		routes.append(null)
		var c := Car5.new()
		c.setup(self, i, CARDS[i])
		cars_node.add_child(c)
		cars.append(c)
	rng.randomize()
	hud.show_briefing()
	hud.refresh_cards()


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	advance(delta * time_scale)
	_reflow_queues()
	hud.refresh_stats()


func advance(dt: float) -> void:
	if dt <= 0.0:
		return
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
	time_scale = 1.0
	drawing = false
	stroke = []
	stroke_closed = false
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


func start_run() -> void:
	hud.hide_overlay()
	state = State.PLAYING
	_reset_spawner()


func abort_run() -> void:
	to_plan()


func next_level() -> void:
	Levels5.current = mini(Levels5.current + 1, Levels5.LEVELS.size() - 1)
	get_tree().change_scene_to_file("res://scenes/v5_main.tscn")


func to_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/v5_select.tscn")


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
	active_passengers = []
	_passengers_dirty = false
	for rid in waiting:
		waiting[rid].clear()
	for c in cars:
		c.riders.clear()
		c.set_route(c.route) # re-park at route start


func set_speed(s: float) -> void:
	time_scale = s


# ---------------------------------------------------------------- input (magnetic)

func can_edit() -> bool:
	return state == State.PLAN


func cards_not_ready() -> Array:
	var out: Array = []
	for i in CARDS.size():
		if routes[i] == null or routes[i].served_rooms().size() < 2:
			out.append(CARDS[i].name)
	return out


func ready_to_run() -> bool:
	return cards_not_ready().is_empty()


func route_warning(i: int) -> bool:
	return routes[i] != null and routes[i].served_rooms().size() < 2


func _unhandled_input(event: InputEvent) -> void:
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
	if not can_edit():
		return
	selected_card = -1 if selected_card == i else i
	drawing = false
	stroke = []
	stroke_closed = false
	reject_until_ms = 0
	hud.refresh_cards()


func _begin_stroke(pos: Vector2) -> void:
	if selected_card < 0 or not can_edit():
		return
	var cell := Grid5.cell_at(pos)
	if cell.x < 0 or not _drawable(cell):
		return
	drawing = true
	stroke = [cell]
	stroke_closed = false


func _extend_stroke(pos: Vector2) -> void:
	if not drawing:
		return
	var cell := Grid5.cell_at(pos)
	if cell.x < 0:
		return
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
		commit_route(selected_card, stroke, stroke_closed)
	stroke = []
	stroke_closed = false


## True when the selected card may draw through `cell`: an open, routable cell.
func _drawable(cell: Vector2i) -> bool:
	return Grid5.passable(cell)


# ---------------------------------------------------------------- route edits

func commit_route(i: int, cells: Array, closed := false) -> bool:
	if state != State.PLAN and state != State.BRIEFING:
		push_error("commit_route(%d) refused: routes are locked outside PLAN" % i)
		return false
	var r: Route5 = null
	if cells.size() > 0:
		var err := Route5.validate(cells, closed and cells.size() >= 4)
		if err == "" and Grid5.route_min_corridor_width(cells) < cars[i].width:
			err = "too wide for that corridor"
		if err != "":
			push_error("commit_route(%d) rejected: %s" % [i, err])
			reject_card = i
			reject_until_ms = Time.get_ticks_msec() + 4000
			reject_msg = "%s can't run there: %s" % [CARDS[i].name, err]
			return false
		r = Route5.new()
		r.cells = cells.duplicate()
		r.closed = closed and cells.size() >= 4
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
	var path = Pathfind5.find_path(p.cur_room, p.dest_room, cars, p.salt, p.width)
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
	var t := _pick_type()
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
	var o := Levels5.room_id_of_letter(level, str(picked.from))
	var d := Levels5.room_id_of_letter(level, str(picked.to))
	if o < 0 or d < 0 or o == d:
		return
	spawn_passenger(t, o, d)


func spawn_passenger(ptype: String, origin: int, dest: int) -> Passenger5:
	var p := Passenger5.new()
	p.setup(self, ptype, origin, dest)
	p.salt = rng.randf()
	passengers_node.add_child(p)
	active_passengers.append(p)
	waiting[origin].append(p)
	_compute_path_for(p)
	return p


## A rider stepped out of a car at dock `alight_cell` beside `room`. The rider
## now WALKS from that dock to the room's anchor (real game-time); only when the
## walk finishes (finish_alight) are they served or replanned for a transfer.
func on_alight(p, alight_cell: Vector2i, room: int) -> void:
	if not p.legs.is_empty():
		p.legs.pop_front()
	p.start_alight_walk(alight_cell, room)


## The alight walk finished: at the destination they are served; otherwise this
## is a transfer room, so replan from here and start a fresh board walk toward
## the next leg's dock (rejoining the room's waiting pool).
func finish_alight(p) -> void:
	if p.cur_room == p.dest_room:
		on_served(p)
	else:
		_compute_path_for(p)
		if not waiting[p.cur_room].has(p):
			waiting[p.cur_room].append(p)


func on_served(p) -> void:
	p.active = false
	_passengers_dirty = true
	if waiting.has(p.cur_room):
		waiting[p.cur_room].erase(p)
	log_served.append({"type": p.ptype, "wait": p.wait_time, "rides": p.rides})
	p.queue_free()
	served += 1
	if state == State.PLAYING and not endless and served >= QUOTA:
		_win()


func on_expired(p) -> void:
	_passengers_dirty = true
	if waiting.has(p.cur_room):
		waiting[p.cur_room].erase(p)
	log_lost.append({"type": p.ptype, "wait": p.wait_time, "rides": p.rides})
	p.queue_free()
	lost += 1
	if state == State.PLAYING and not endless and lost >= MAX_LOST:
		_lose()


## Position waiting passengers (visual only). Riders and walkers drive their own
## position (car slot / orthogonal walk tween); everyone else waits stacked inside
## the room footprint until a car stops and assigns them.
func _reflow_queues() -> void:
	for rid in waiting:
		var rect := Grid5.room_rect(rid)
		var band := rect.size.x - 16.0
		var base := rect.get_center() + Vector2(0.0, rect.size.y / 2.0 - 16.0)
		var x := 0.0
		var row := 0
		for p in waiting[rid]:
			if p.riding != null or p.walk_left > 0.0:
				continue # the walk tween / car slot owns this figure's position
			var w := 24.0
			if x > 0.0 and x + w > band:
				row += 1
				x = 0.0
			p.position = base + Vector2(-band / 2.0 + x + w / 2.0, -row * 22.0)
			x += w


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
