class_name Elevator
extends Node2D
## One installed elevator car. Autonomous sweep AI (spec):
## keep moving in the current direction while stops exist that way (a rider
## wants to alight, or a waiter's current leg names this elevator at a door-ON
## floor); otherwise reverse; otherwise idle. Dwell ~1.2 s at stops; unload
## then load, slot-aware (gurney = 2 slots).
##
## Logic time comes from game.tick() calls; _process is visuals only.

const DWELL_TIME := 1.2

var game = null # main.gd
var column := 0
var card_type := "standard"
var capacity := 4
var speed := 300.0
var doors: Array = [] # bool per floor
var riders: Array = [] # Passenger nodes on board
var dir := 0 # 1 up, -1 down, 0 idle
var dwell := 0.0
var dwell_floor := -1


func setup(g, col: int, t: String) -> void:
	game = g
	column = col
	card_type = t
	var info: Dictionary = Levels.CARDS[t]
	capacity = info.cap
	speed = info.speed
	doors = []
	for f in Building.FLOORS:
		doors.append(true)
	position = Vector2(Building.COL_X[col] + Building.COL_W / 2.0, Building.floor_to_y(0))


func doors_on_count() -> int:
	var n := 0
	for d in doors:
		if d:
			n += 1
	return n


func used_slots() -> int:
	var used := 0
	for p in riders:
		used += p.slots
	return used


func free_slots() -> int:
	return capacity - used_slots()


func current_floor() -> int:
	return clampi(int(round((Building.BOTTOM - position.y) / Building.FLOOR_H)), 0, Building.FLOORS - 1)


func reset_car() -> void:
	riders.clear()
	dir = 0
	dwell = 0.0
	dwell_floor = -1
	position.y = Building.floor_to_y(0)


## Game-time tick from main.
func tick(dt: float) -> void:
	if dwell > 0.0:
		dwell -= dt
		_load() # late arrivals can hop on while doors are open
		if dwell <= 0.0:
			dwell_floor = -1
		return
	var stops := _stop_floors()
	if stops.is_empty():
		dir = 0
		return
	# Already sitting on a stop floor? Open doors there.
	for f in stops:
		if absf(position.y - Building.floor_to_y(f)) < 1.0:
			_arrive(f)
			return
	var up: Array = [] # stops above the car (higher floor index, smaller y)
	var down: Array = []
	for f in stops:
		if Building.floor_to_y(f) < position.y - 1.0:
			up.append(f)
		else:
			down.append(f)
	if dir == 0:
		# Idle: head toward the nearest stop.
		var cf := current_floor()
		var best_d := 999
		for f in stops:
			if absi(f - cf) < best_d:
				best_d = absi(f - cf)
				dir = 1 if f > cf else -1
	if dir == 1 and up.is_empty():
		dir = -1 if not down.is_empty() else 0
	elif dir == -1 and down.is_empty():
		dir = 1 if not up.is_empty() else 0
	if dir == 0:
		return
	var target_f: int = up.min() if dir == 1 else down.max()
	var ty := Building.floor_to_y(target_f)
	var step := speed * dt
	if absf(ty - position.y) <= step:
		position.y = ty
		_arrive(target_f)
	else:
		position.y += signf(ty - position.y) * step


## Floors this car currently wants to stop at.
func _stop_floors() -> Dictionary:
	var stops := {}
	for r in riders:
		if not r.legs.is_empty():
			stops[r.legs[0].alight] = true
	for f in Building.FLOORS:
		if stops.has(f) or not doors[f]:
			continue
		# Slots that would free up by unloading at f (none, since no rider
		# alights at f here), so only current free slots count.
		for p in game.waiting[f]:
			if p.legs.is_empty():
				continue
			var leg: Dictionary = p.legs[0]
			if leg.elev == self and leg.board == f and free_slots() >= p.slots:
				stops[f] = true
				break
	return stops


func _arrive(floor_i: int) -> void:
	position.y = Building.floor_to_y(floor_i)
	dwell = DWELL_TIME
	dwell_floor = floor_i
	# Unload first...
	var leaving: Array = []
	for r in riders:
		if not r.legs.is_empty() and r.legs[0].alight == floor_i:
			leaving.append(r)
	for r in leaving:
		riders.erase(r)
		game.on_alight(r, floor_i)
	# ...then load.
	_load()


func _load() -> void:
	if dwell_floor < 0:
		return
	for p in game.waiting[dwell_floor].duplicate():
		if p.legs.is_empty():
			continue
		var leg: Dictionary = p.legs[0]
		if leg.elev == self and leg.board == dwell_floor and free_slots() >= p.slots:
			game.waiting[dwell_floor].erase(p)
			p.riding = self
			p.no_path = false
			riders.append(p)


## Where a rider stands inside the car (2 slots per row, bottom-up).
func slot_position(p) -> Vector2:
	var idx := 0
	for r in riders:
		if r == p:
			break
		idx += r.slots
	var col := idx % 2
	var row := int(idx / 2.0)
	return position + Vector2(-21.0 + col * 42.0, -6.0 - row * 19.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var body := Levels.card_color(card_type)
	var w := 96.0 if card_type == "large" else 80.0
	# Cable.
	draw_line(Vector2(0, Building.TOP - position.y), Vector2(0, -Building.CAR_H),
			Color(0.06, 0.06, 0.07), 3.0)
	# Car body: brighter while doors are open.
	var car := Rect2(-w / 2.0, -Building.CAR_H, w, Building.CAR_H - 3.0)
	draw_rect(car, Color(body, 0.5 if dwell > 0.0 else 0.24))
	draw_rect(car, body, false, 4.0)
	if card_type == "express":
		# Chevrons.
		for i in 2:
			var cy := -30.0 - i * 14.0
			draw_polyline(PackedVector2Array([
					Vector2(-14.0, cy), Vector2(0.0, cy - 10.0), Vector2(14.0, cy)]),
					Color(0.25, 0.15, 0.05), 4.0)
	# Capacity pips along the car roof (max 2 rows of 4).
	var used := used_slots()
	for i in capacity:
		var px := -w / 2.0 + 8.0 + (i % 4) * 22.0
		var py := -Building.CAR_H + 7.0 + int(i / 4.0) * 10.0
		var pip_col := body if i < used else Color(1, 1, 1, 0.18)
		draw_rect(Rect2(px, py, 16.0, 6.0), pip_col)
	# Direction indicator.
	if dir != 0 and dwell <= 0.0:
		var ay := -Building.CAR_H - 8.0
		var tip := Vector2(0, ay - 10.0) if dir == 1 else Vector2(0, ay + 2.0)
		var base_y := ay + 2.0 if dir == 1 else ay - 10.0
		draw_colored_polygon(PackedVector2Array([
				tip, Vector2(-9.0, base_y), Vector2(9.0, base_y)]), Color(1, 1, 1, 0.7))
