class_name Car3
extends Node2D
## One elevator car bound to a route card. Ping-pongs along its drawn
## polyline end-to-end, dwelling DWELL_TIME at room cells (unload then load,
## slot-aware). Gate cells are a FIFO mutex owned by main3: the car acquires
## the lock BEFORE leaving its current cell center toward the gate, waits in
## place (pulsing outline) if denied, and releases only after arriving at the
## next cell center past the gate (body fully out of the gate cell).
##
## Logic time comes from game tick() calls; _process is visuals only.

const DWELL_TIME := 1.0
const BODY := 60.0

var game = null # main3.gd
var card_index := 0
var card_type := "standard"
var capacity := 4
var speed := 260.0
var color := Color.GRAY
var route = null # Route3 or null
var idx := 0 # index of the last cell center reached
var seg_t := 0.0 # px progressed from cells[idx] toward cells[idx + dir]
var dir := 1 # +1 toward end of polyline, -1 toward start
var dwell := 0.0
var waiting_gate := false
var held_gates: Array = [] # Vector2i gate cells currently locked by this car
var riders: Array = [] # Passenger3 nodes on board
var vis_t := 0.0


func setup(g, i: int, card: Dictionary) -> void:
	game = g
	card_index = i
	card_type = card.type
	capacity = card.cap
	speed = card.speed
	color = card.color
	visible = false


func running() -> bool:
	return route != null and route.stop_cells().size() >= 2


func used_slots() -> int:
	var used := 0
	for p in riders:
		used += p.slots
	return used


func free_slots() -> int:
	return capacity - used_slots()


## The cell whose center the car last reached (or currently sits in).
func current_cell() -> Vector2i:
	if route == null:
		return Vector2i(-1, -1)
	return route.cells[idx]


## Bind a new route (or null). Riders must have been dropped off by main3
## BEFORE this is called. Resets to the start of the polyline.
func set_route(r) -> void:
	game.gate_cancel(self)
	held_gates.clear()
	route = r
	idx = 0
	seg_t = 0.0
	dir = 1
	dwell = 0.0
	waiting_gate = false
	visible = route != null
	if route != null and route.cells.size() > 0:
		position = Grid3.cell_center(route.cells[0])
		if running():
			_arrive_center()


# ---------------------------------------------------------------- movement

## Game-time tick from main3.
func tick(dt: float) -> void:
	if not running():
		return
	var rem := dt
	var guard := 0
	while rem > 0.0 and guard < 400:
		guard += 1
		if dwell > 0.0:
			_load_waiting() # late arrivals can hop on while doors are open
			if dwell > rem:
				dwell -= rem
				break
			rem -= dwell
			dwell = 0.0
		if seg_t == 0.0:
			if not _depart():
				break # waiting for a gate; retry next tick
		var need := Grid3.CELL - seg_t
		var step := speed * rem
		if step < need:
			seg_t += step
			rem = 0.0
		else:
			rem -= need / speed
			seg_t = 0.0
			idx += dir
			_arrive_center()
	_update_position()


## Reached the center of cells[idx]: release any gate we have fully exited,
## and start a dwell if this is a room.
func _arrive_center() -> void:
	var cell: Vector2i = route.cells[idx]
	for g in held_gates.duplicate():
		if g != cell:
			game.gate_release(self, g)
			held_gates.erase(g)
	if Grid3.is_room(cell):
		dwell = DWELL_TIME
		_unload()
		_load_waiting()


## Decide the next hop from the current cell center. Reverses at polyline
## ends; acquires the gate lock when the NEXT cell is a gate. Returns false
## if the car must wait (gate held by someone else).
func _depart() -> bool:
	if idx + dir < 0 or idx + dir >= route.cells.size():
		dir = -dir
	var next: Vector2i = route.cells[idx + dir]
	if Grid3.is_gate(next) and not held_gates.has(next):
		if game.gate_request(self, next):
			held_gates.append(next)
		else:
			waiting_gate = true
			return false
	waiting_gate = false
	return true


func _update_position() -> void:
	if route == null or route.cells.is_empty():
		return
	var a := Grid3.cell_center(route.cells[idx])
	if seg_t <= 0.0:
		position = a
	else:
		var b := Grid3.cell_center(route.cells[idx + dir])
		position = a.lerp(b, seg_t / Grid3.CELL)


# ---------------------------------------------------------------- riders

func _unload() -> void:
	var cell: Vector2i = route.cells[idx]
	for r in riders.duplicate():
		if not r.legs.is_empty() and r.legs[0].alight == cell:
			riders.erase(r)
			game.on_alight(r, cell)


func _load_waiting() -> void:
	var cell: Vector2i = route.cells[idx]
	if not Grid3.is_room(cell):
		return
	for p in game.waiting.get(cell, []).duplicate():
		if p.legs.is_empty():
			continue
		var leg: Dictionary = p.legs[0]
		if leg.car == self and leg.board == cell and free_slots() >= p.slots:
			game.waiting[cell].erase(p)
			p.riding = self
			p.no_path = false
			riders.append(p)


## Where a rider stands inside the car (2 slots per row).
func slot_position(p) -> Vector2:
	var i := 0
	for r in riders:
		if r == p:
			break
		i += r.slots
	var col := i % 2
	var row := int(i / 2.0)
	return position + Vector2(-14.0 + col * 28.0, 12.0 - row * 20.0)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	vis_t += delta
	queue_redraw()


func _draw() -> void:
	if route == null:
		return
	var half := BODY / 2.0
	var body := Rect2(-half, -half, BODY, BODY)
	var parked := not running()
	var fill_a := 0.5 if dwell > 0.0 else 0.26
	draw_rect(body, Color(color, 0.12 if parked else fill_a))
	draw_rect(body, Color(color, 0.4 if parked else 1.0), false, 4.0)
	if card_type == "express":
		for i in 2:
			var cy := 6.0 - i * 12.0
			draw_polyline(PackedVector2Array([
					Vector2(-11.0, cy), Vector2(0.0, cy - 9.0), Vector2(11.0, cy)]),
					Color(color, 0.9), 4.0)
	# Capacity pips along the roof.
	var used := used_slots()
	for i in capacity:
		var px := -half + 6.0 + i * 13.0
		var pip := color if i < used else Color(1, 1, 1, 0.18)
		draw_rect(Rect2(px, -half + 5.0, 9.0, 5.0), pip)
	# Waiting for a gate: pulsing white outline.
	if waiting_gate:
		var pulse := 0.45 + 0.45 * sin(vis_t * 8.0)
		draw_rect(body.grow(7.0), Color(1, 1, 1, pulse), false, 4.0)
	if parked:
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 24, Color(0.9, 0.3, 0.25))
