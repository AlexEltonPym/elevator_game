class_name Car3
extends Node2D
## One elevator car bound to a route card. Ping-pongs along its drawn
## polyline end-to-end. At room stops it runs a DOOR PHASE cycle:
##   OPEN 0.5 s (doors slide open) ->
##   EXCHANGE max(0.8 s, 0.35 s x passenger-moves this stop; unload then
##   load, late arrivals may still board) ->
##   CLOSE 0.5 s (doors slide shut, nobody boards).
## Minimum full stop is ~1.8 s.
##
## A car with NOTHING to do (no riders, no waiting passenger planning to
## board it) parks at its current cell, doors closed, until work appears.
## `home_cell` (code-only hook, null everywhere for now): when set to a cell
## of the route, an idle empty car deadheads there (skipping stops) and
## waits - the future "default waiting floor" upgrade only needs a UI that
## calls set_home_cell().
##
## Gate cells are a FIFO mutex owned by main3: the car acquires the lock
## BEFORE leaving its current cell center toward the gate, waits in place
## (pulsing outline) if denied, and releases only after arriving at the next
## cell center past the gate. Time spent blocked is accumulated in
## gate_wait_total (harness stat).
##
## Logic time comes from game tick() calls; _process is visuals only.

enum DoorState { CLOSED, OPENING, EXCHANGE, CLOSING }

const DOOR_OPEN_T := 0.5
const DOOR_CLOSE_T := 0.5
const EXCHANGE_MIN := 0.8
const EXCHANGE_PER_MOVE := 0.35
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
var door_state := DoorState.CLOSED
var door_timer := 0.0 # time left in OPENING / CLOSING
var exchange_elapsed := 0.0
var stop_moves := 0 # passenger moves (unloads + loads) at the current stop
var idle := false # parked with nothing to do (visual + harness)
var home_cell = null # Vector2i or null; idle empty cars deadhead here
var waiting_gate := false
var gate_wait_total := 0.0 # game-seconds spent blocked at gates (stat)
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


## Hook for the future "default waiting floor" upgrade UI: pass a cell of
## the route (or null to clear). Idle empty cars deadhead there and wait.
func set_home_cell(cell) -> void:
	home_cell = cell


## Bind a new route (or null). Riders must have been dropped off by main3
## BEFORE this is called. Resets to the start of the polyline.
func set_route(r) -> void:
	game.gate_cancel(self)
	held_gates.clear()
	route = r
	idx = 0
	seg_t = 0.0
	dir = 1
	door_state = DoorState.CLOSED
	door_timer = 0.0
	exchange_elapsed = 0.0
	stop_moves = 0
	idle = false
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
	while rem > 0.0 and guard < 500:
		guard += 1
		match door_state:
			DoorState.OPENING:
				_load_waiting() # late arrivals board while doors open
				if door_timer > rem:
					door_timer -= rem
					rem = 0.0
				else:
					rem -= door_timer
					door_timer = 0.0
					door_state = DoorState.EXCHANGE
					exchange_elapsed = 0.0
					_unload()
					_load_waiting()
			DoorState.EXCHANGE:
				_load_waiting()
				var dur := maxf(EXCHANGE_MIN, EXCHANGE_PER_MOVE * stop_moves)
				var left := maxf(0.0, dur - exchange_elapsed)
				if left > rem:
					exchange_elapsed += rem
					rem = 0.0
				else:
					rem -= left
					door_state = DoorState.CLOSING
					door_timer = DOOR_CLOSE_T
			DoorState.CLOSING:
				# Nobody boards during CLOSE.
				if door_timer > rem:
					door_timer -= rem
					rem = 0.0
				else:
					rem -= door_timer
					door_timer = 0.0
					door_state = DoorState.CLOSED
			DoorState.CLOSED:
				if seg_t == 0.0:
					if not _decide_at_center():
						if door_state != DoorState.CLOSED:
							continue # doors just began opening: consume time there
						if waiting_gate:
							gate_wait_total += rem
						break # idle, or blocked at a gate: retry next tick
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


## At a cell center with doors closed: open doors, start a hop, or park.
## Returns true when the car should move along its segment this iteration.
func _decide_at_center() -> bool:
	var cell: Vector2i = route.cells[idx]
	if _has_work():
		idle = false
		# Someone to exchange right here? Reopen instead of driving off.
		if Grid3.is_room(cell) and _exchange_wanted(cell):
			_begin_stop()
			return false
		return _depart(_pingpong_target())
	# No work: deadhead home if a home cell is set, else park in place.
	if home_cell != null and cell != home_cell and route.index_of(home_cell) != -1:
		idle = false
		return _depart(route.index_of(home_cell))
	idle = true
	waiting_gate = false
	return false


## True if any rider is aboard or any waiting passenger's current leg boards
## this car (the car has a reason to move).
func _has_work() -> bool:
	if not riders.is_empty():
		return true
	for r in game.waiting:
		for p in game.waiting[r]:
			if not p.legs.is_empty() and p.legs[0].car == self:
				return true
	return false


## True if an exchange can happen at `cell` right now: a rider alights here,
## or a waiting passenger boards here (and fits).
func _exchange_wanted(cell: Vector2i) -> bool:
	for r in riders:
		if not r.legs.is_empty() and r.legs[0].alight == cell:
			return true
	var free := free_slots()
	for p in game.waiting.get(cell, []):
		if p.legs.is_empty():
			continue
		var leg: Dictionary = p.legs[0]
		if leg.car == self and leg.board == cell and free >= p.slots:
			return true
	return false


func _begin_stop() -> void:
	door_state = DoorState.OPENING
	door_timer = DOOR_OPEN_T
	stop_moves = 0


## Next ping-pong target index (just "keep going", reversing at the ends).
func _pingpong_target() -> int:
	if idx + dir < 0 or idx + dir >= route.cells.size():
		dir = -dir
	return idx + dir


## Try to start the hop toward cells[target_idx] (sets dir from it).
## Acquires the gate lock when the NEXT cell is a gate. Returns false if the
## car must wait (gate held by someone else).
func _depart(target_idx: int) -> bool:
	dir = 1 if target_idx > idx else -1
	var next: Vector2i = route.cells[idx + dir]
	if Grid3.is_gate(next) and not held_gates.has(next):
		if game.gate_request(self, next):
			held_gates.append(next)
		else:
			waiting_gate = true
			return false
	waiting_gate = false
	return true


## Reached the center of cells[idx]: release any gate we have fully exited,
## and open doors if this is a room stop and the car is working. Deadheading
## or idle cars skip stops (there is nobody aboard and nobody who planned on
## this car - boarding requires legs[0].car == self).
func _arrive_center() -> void:
	var cell: Vector2i = route.cells[idx]
	for g in held_gates.duplicate():
		if g != cell:
			game.gate_release(self, g)
			held_gates.erase(g)
	if Grid3.is_room(cell) and _has_work():
		_begin_stop()


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
			stop_moves += 1
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
			p.rides += 1
			riders.append(p)
			stop_moves += 1


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

## 0 = doors shut, 1 = fully open.
func door_frac() -> float:
	match door_state:
		DoorState.OPENING:
			return 1.0 - door_timer / DOOR_OPEN_T
		DoorState.EXCHANGE:
			return 1.0
		DoorState.CLOSING:
			return door_timer / DOOR_CLOSE_T
	return 0.0


func _process(delta: float) -> void:
	vis_t += delta
	queue_redraw()


func _draw() -> void:
	if route == null:
		return
	var half := BODY / 2.0
	var body := Rect2(-half, -half, BODY, BODY)
	var parked := not running()
	var fill_a := 0.5 if door_state != DoorState.CLOSED else 0.26
	if idle:
		fill_a = 0.16
	draw_rect(body, Color(color, 0.12 if parked else fill_a))
	# Sliding door panels: two leaves parting from the center.
	if not parked:
		var frac := door_frac()
		var leaf_w := (BODY - 12.0) / 2.0 * (1.0 - frac)
		var door_col := Color(color.lightened(0.25), 0.85)
		if leaf_w > 0.5:
			draw_rect(Rect2(-half + 6.0, -half + 10.0, leaf_w, BODY - 20.0), door_col)
			draw_rect(Rect2(half - 6.0 - leaf_w, -half + 10.0, leaf_w, BODY - 20.0), door_col)
			draw_line(Vector2(-half + 6.0 + leaf_w, -half + 10.0),
					Vector2(-half + 6.0 + leaf_w, half - 10.0), Color(0, 0, 0, 0.4), 2.0)
			draw_line(Vector2(half - 6.0 - leaf_w, -half + 10.0),
					Vector2(half - 6.0 - leaf_w, half - 10.0), Color(0, 0, 0, 0.4), 2.0)
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
