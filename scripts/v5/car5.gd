class_name Car5
extends Node2D
## One elevator car for v5. Ping-pongs along its drawn polyline end-to-end
## (unless CLOSED, then forward around the cycle forever). It stops at DOCK
## cells where an exchange is wanted, runs a door-phase cycle, and loads/unloads
## passengers whose current leg boards/alights at that dock.
##
## Adapted from scripts/v3/car3.gd. The acceleration integrator (_integrate),
## the analytic braking lookahead and the door phases are reused essentially
## verbatim — that is the "feel" the prototype must keep. What is REMOVED for
## the prototype: the recall/redeploy state machine, home cells, and gate
## corridor mutexes (v5 levels have no gates; all commits happen in PLAN, so
## every car deploys instantly). Stops key off dock cells + exchanges instead of
## v3's "is this a room cell".

enum DoorState { CLOSED, OPENING, EXCHANGE, CLOSING }
enum CarState { UNDEPLOYED, RUNNING }

const DOOR_OPEN_T := 0.5
const DOOR_CLOSE_T := 0.5
const EXCHANGE_MIN := 0.8
const EXCHANGE_PER_MOVE := 0.35
const BODY := 60.0
const EPS_D := 1.0e-6
const EPS_V := 1.0e-9
const MAX_SCAN_CELLS := 24

const DECEL_RATIO := 1.25
const CAR_TYPES := {
	"pod": {"width": 1, "cap": 2, "speed": 340.0, "accel": 560.0},
	"standard": {"width": 2, "cap": 4, "speed": 260.0, "accel": 300.0},
	"express": {"width": 2, "cap": 4, "speed": 520.0, "accel": 300.0},
	"cargo": {"width": 3, "cap": 6, "speed": 200.0, "accel": 160.0},
}
const STANDARD_SPEED := 260.0

var game = null # main5.gd
var card_index := 0
var width := 2
var capacity := 4
var speed := 260.0
var accel := 300.0
var decel := 375.0
var vel := 0.0
var color := Color.GRAY
var route = null # Route5 or null
var car_state := CarState.UNDEPLOYED
var idx := 0
var seg_t := 0.0
var dir := 1
var door_state := DoorState.CLOSED
var door_timer := 0.0
var exchange_elapsed := 0.0
var stop_moves := 0
var idle := false
var riders: Array = []
var vis_t := 0.0


func setup(g, i: int, card: Dictionary) -> void:
	game = g
	card_index = i
	var t: Dictionary = CAR_TYPES.get(str(card.get("type", "standard")), CAR_TYPES.standard)
	width = int(card.get("width", t.width))
	capacity = int(card.get("cap", t.cap))
	speed = float(card.get("speed", t.speed))
	accel = float(card.get("accel", t.accel))
	decel = float(card.get("decel", accel * DECEL_RATIO))
	color = card.color
	visible = false


## Momentum time lost to one extra intermediate stop (planner's half of accel).
func stop_penalty() -> float:
	return speed * (1.0 / (2.0 * accel) + 1.0 / (2.0 * decel))


func fits(w: int) -> bool:
	return w <= width


func body_w() -> float:
	return 4.0 + 28.0 * width


## The committed route can run service: >= 2 rooms served.
func running() -> bool:
	return route != null and route.served_rooms().size() >= 2


func on_grid() -> bool:
	return car_state == CarState.RUNNING


func used_slots() -> int:
	var used := 0
	for p in riders:
		used += p.width
	return used


func free_slots() -> int:
	return capacity - used_slots()


func _wrap_idx(i: int) -> int:
	if route != null and route.closed:
		return posmod(i, route.cells.size())
	return i


func current_cell() -> Vector2i:
	if not on_grid() or route == null:
		return Vector2i(-1, -1)
	return route.cells[idx]


# ------------------------------------------------------------- route changes

## INSTANT deploy: bind a route (or null) and appear at its start. All v5
## commits happen in PLAN, so this is the only path.
func set_route(r) -> void:
	route = r
	idx = 0
	seg_t = 0.0
	dir = 1
	vel = 0.0
	door_state = DoorState.CLOSED
	door_timer = 0.0
	exchange_elapsed = 0.0
	stop_moves = 0
	idle = false
	car_state = CarState.RUNNING if route != null else CarState.UNDEPLOYED
	visible = route != null
	if route != null and route.cells.size() > 0:
		position = Grid5.cell_center(route.cells[0])
		if running():
			_arrive_center()


# ---------------------------------------------------------------- movement

func tick(dt: float) -> void:
	if car_state != CarState.RUNNING or not running():
		return
	_move_tick(dt)


func _move_tick(dt: float) -> void:
	var rem := dt
	var guard := 0
	while rem > 0.0 and guard < 500:
		guard += 1
		match door_state:
			DoorState.OPENING:
				_load_waiting()
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
						vel = 0.0
						if door_state != DoorState.CLOSED:
							continue # doors just began opening
						break # idle: retry next tick
				var need := Grid5.CELL - seg_t
				var move := _integrate(need, _stop_distance(need), rem)
				seg_t += move.d
				rem -= move.t
				if seg_t >= Grid5.CELL - EPS_D:
					seg_t = 0.0
					idx = _wrap_idx(idx + dir)
					_arrive_center()
				elif move.t <= 0.0:
					break
	_update_position()


# ------------------------------------------------------------ acceleration

func _stop_distance(need: float) -> float:
	var r = route
	var n: int = r.cells.size()
	if not _has_work():
		return need # nothing to do: park at the very next centre
	var scan := 2 + int(speed * speed / (2.0 * decel) / Grid5.CELL)
	scan = mini(scan, mini(MAX_SCAN_CELLS, n))
	var d := need
	for k in scan:
		var j := idx + (k + 1) * dir
		if not r.closed and (j < 0 or j >= n):
			break
		var cell: Vector2i = r.cells[_wrap_idx(j)]
		if _wants_stop(cell):
			return d
		if not r.closed and (j + dir < 0 or j + dir >= n):
			return d # the end of an open line: the car reverses (stops) here
		d += Grid5.CELL
	return d


func _integrate(dmax: float, d_stop: float, rem: float) -> Dictionary:
	var u := 0.0
	var t := 0.0
	var guard := 0
	while u < dmax - EPS_D and t < rem and guard < 6:
		guard += 1
		var left_d := dmax - u
		var left_t := rem - t
		var to_stop := maxf(d_stop - u, 0.0)
		var v_lim := sqrt(2.0 * decel * to_stop)
		var phase_d := left_d
		var mode := "cruise"
		if vel > v_lim + EPS_V:
			mode = "brake"
		elif vel < speed - EPS_V:
			mode = "accel"
			var d_top := (speed * speed - vel * vel) / (2.0 * accel)
			var d_meet := (2.0 * decel * to_stop - vel * vel) / (2.0 * (accel + decel))
			phase_d = minf(phase_d, maxf(minf(d_top, d_meet), 0.0))
		else:
			phase_d = minf(phase_d, maxf(to_stop - speed * speed / (2.0 * decel), 0.0))
			if phase_d <= EPS_D:
				mode = "brake"
				phase_d = left_d
		if phase_d <= EPS_D and mode != "brake":
			mode = "brake"
			phase_d = left_d
		match mode:
			"accel":
				var v_end := sqrt(vel * vel + 2.0 * accel * phase_d)
				var dt := (v_end - vel) / accel
				if dt <= left_t:
					u += phase_d
					t += dt
					vel = v_end
				else:
					u += vel * left_t + 0.5 * accel * left_t * left_t
					vel += accel * left_t
					t = rem
			"cruise":
				var dt2 := phase_d / speed
				if dt2 <= left_t:
					u += phase_d
					t += dt2
				else:
					u += speed * left_t
					t = rem
			_:
				if vel <= EPS_V:
					t = rem
					break
				var t_zero := vel / decel
				var d_zero := vel * vel / (2.0 * decel)
				var d_phase := minf(phase_d, d_zero)
				var v_end2 := sqrt(maxf(vel * vel - 2.0 * decel * d_phase, 0.0))
				var dt3 := (vel - v_end2) / decel
				if dt3 <= left_t:
					u += d_phase
					t += dt3
					vel = v_end2
					if d_phase >= d_zero - EPS_D and d_phase < left_d - EPS_D:
						t = rem
						break
				else:
					var ct := minf(left_t, t_zero)
					u += vel * ct - 0.5 * decel * ct * ct
					vel = maxf(vel - decel * ct, 0.0)
					t = rem
	return {"d": minf(u, dmax), "t": minf(t, rem)}


## At a cell centre with doors closed: open doors for an exchange, drive on, or
## park. Returns true when the car should move along its segment this iteration.
func _decide_at_center() -> bool:
	var cell: Vector2i = route.cells[idx]
	if _wants_stop(cell):
		idle = false
		_begin_stop()
		return false
	if _has_work():
		idle = false
		return _depart(_pingpong_target())
	idle = true
	return false


func _has_work() -> bool:
	if not riders.is_empty():
		return true
	for rid in game.waiting:
		for p in game.waiting[rid]:
			if not p.legs.is_empty() and p.legs[0].car == self:
				return true
	return false


## Would the car stop at `cell`: a dock where a rider alights, or a boarder in a
## room served by it is waiting (and fits).
func _wants_stop(cell: Vector2i) -> bool:
	if route == null or not route.is_dropoff(cell):
		return false
	for r in riders:
		if not r.legs.is_empty() and r.legs[0].alight_cell == cell:
			return true
	var free := free_slots()
	for rid in route.rooms_of_cell(cell):
		for p in game.waiting.get(rid, []):
			if p.legs.is_empty():
				continue
			var leg: Dictionary = p.legs[0]
			if leg.car == self and leg.board_cell == cell and fits(p.width) \
					and free >= p.width:
				return true
	return false


func _begin_stop() -> void:
	door_state = DoorState.OPENING
	door_timer = DOOR_OPEN_T
	stop_moves = 0
	vel = 0.0


func _pingpong_target() -> int:
	if route.closed:
		if dir != 1:
			vel = 0.0
		dir = 1
		return idx + 1
	if idx + dir < 0 or idx + dir >= route.cells.size():
		dir = -dir
		vel = 0.0
	return idx + dir


func _depart(target_idx: int) -> bool:
	var want := 1 if route.closed or target_idx > idx else -1
	if want != dir:
		vel = 0.0
	dir = want
	return true


func _arrive_center() -> void:
	var cell: Vector2i = route.cells[idx]
	if _wants_stop(cell):
		_begin_stop()


func _update_position() -> void:
	if not on_grid() or route == null or route.cells.is_empty():
		return
	var a := Grid5.cell_center(route.cells[idx])
	if seg_t <= 0.0:
		position = a
	else:
		var b := Grid5.cell_center(route.cells[_wrap_idx(idx + dir)])
		position = a.lerp(b, seg_t / Grid5.CELL)


# ---------------------------------------------------------------- riders

func _unload() -> void:
	var cell: Vector2i = route.cells[idx]
	for r in riders.duplicate():
		if not r.legs.is_empty() and r.legs[0].alight_cell == cell:
			riders.erase(r)
			stop_moves += 1
			game.on_alight(r, r.legs[0].to_room)


func _load_waiting() -> void:
	var cell: Vector2i = route.cells[idx]
	if route == null or not route.is_dropoff(cell):
		return
	for rid in route.rooms_of_cell(cell):
		for p in game.waiting.get(rid, []).duplicate():
			if p.legs.is_empty():
				continue
			var leg: Dictionary = p.legs[0]
			if leg.car == self and leg.board_cell == cell and fits(p.width) \
					and free_slots() >= p.width:
				game.waiting[rid].erase(p)
				p.riding = self
				p.no_path = false
				p.rides += 1
				riders.append(p)
				stop_moves += 1


## Where a rider stands inside the car (width-units per row).
func slot_position(p) -> Vector2:
	var i := 0
	for r in riders:
		if r == p:
			break
		i += r.width
	var cols := maxi(1, width)
	var col := i % cols
	var row := int(i / float(cols))
	return position + Vector2((col - (cols - 1) / 2.0) * 26.0, 12.0 - row * 20.0)


# ---------------------------------------------------------------- visuals

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
	if car_state == CarState.UNDEPLOYED:
		return
	var half := body_w() / 2.0
	var hh := BODY / 2.0
	var body := Rect2(-half, -hh, body_w(), BODY)
	var parked := not running()
	var fill_a := 0.5 if door_state != DoorState.CLOSED else 0.26
	if idle:
		fill_a = 0.16
	draw_rect(body, Color(color, 0.12 if parked else fill_a))
	if not parked:
		var frac := door_frac()
		var leaf_w := (body_w() - 12.0) / 2.0 * (1.0 - frac)
		var door_col := Color(color.lightened(0.25), 0.85)
		if leaf_w > 0.5:
			draw_rect(Rect2(-half + 6.0, -hh + 10.0, leaf_w, BODY - 20.0), door_col)
			draw_rect(Rect2(half - 6.0 - leaf_w, -hh + 10.0, leaf_w, BODY - 20.0), door_col)
	draw_rect(body, Color(color, 0.4 if parked else 1.0), false, 4.0)
	if speed > STANDARD_SPEED:
		for i in 2:
			var cy := 6.0 - i * 12.0
			draw_polyline(PackedVector2Array([
					Vector2(-11.0, cy), Vector2(0.0, cy - 9.0), Vector2(11.0, cy)]),
					Color(color, 0.9), 4.0)
	# Capacity pips along the roof, one per width-unit of capacity.
	var used := used_slots()
	var pitch := (body_w() - 12.0) / maxi(capacity, 1)
	for i in capacity:
		var px := -half + 6.0 + i * pitch
		var pip := color if i < used else Color(1, 1, 1, 0.18)
		draw_rect(Rect2(px, -hh + 5.0, maxf(4.0, pitch - 4.0), 5.0), pip)
	if parked:
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 24, Color(0.9, 0.3, 0.25))
