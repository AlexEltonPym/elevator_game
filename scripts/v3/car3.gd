class_name Car3
extends Node2D
## One elevator car bound to a route card. Ping-pongs along its drawn
## polyline end-to-end — unless the route is CLOSED (v3.4 loop: the stroke
## closed onto its head), in which case the car advances idx -> (idx+1) mod n
## forward forever: no reversing, no end dwell, and recall / home_cell
## deadheads also travel forward (the long way around if need be).
## At room stops it runs a DOOR PHASE cycle:
##   OPEN 0.5 s (doors slide open) ->
##   EXCHANGE max(0.8 s, 0.35 s x passenger-moves this stop; unload then
##   load, late arrivals may still board) ->
##   CLOSE 0.5 s (doors slide shut, nobody boards).
## Minimum full stop is ~1.8 s.
##
## CAR STATE MACHINE (v3.3 redeploy - committing a route mid-game no longer
## teleports the car):
##   UNDEPLOYED  no route ever / route cleared; not on the grid.
##   RUNNING     normal service on `route` (parked with "!" if < 2 stops).
##   RECALLING   route was replaced/cleared while riders were aboard: the car
##               keeps driving its OLD polyline (recall_route) to the nearest
##               room stop, cycles doors, ALL riders step out and replan,
##               then the car leaves the grid.
##   REDEPLOYING the car is absent from the grid; a ghost outline + countdown
##               sits at the NEW route's start; after REDEPLOY_DELAY (game
##               time) the car appears there and starts service. A pending
##               CLEAR skips this and goes straight to UNDEPLOYED.
## The very first commit of a never-deployed car (session start, watch mode,
## harness) deploys INSTANTLY via set_route() - the delay is the cost of
## MID-GAME redesign only. Re-commits while RECALLING/REDEPLOYING retarget
## the pending route; the countdown restarts only if the start cell changed.
##
## A RUNNING car with NOTHING to do (no riders, no waiting passenger planning
## to board it) parks at its current cell, doors closed, until work appears.
## `home_cell` (code-only hook, null everywhere for now): when set to a cell
## of the route, an idle empty car deadheads there (skipping stops) and
## waits - the future "default waiting floor" upgrade only needs a UI that
## calls set_home_cell().
##
## Gate GROUPS (contiguous corridors of G cells, Grid3.gate_groups) are FIFO
## mutexes owned by main3: the car acquires the whole group's lock BEFORE
## leaving its current cell center toward the group's first cell, waits in
## place (pulsing outline) if denied, and releases only after arriving at a
## cell center OUTSIDE the group. A single isolated G cell is a group of 1 =
## exactly the old per-cell behavior. Time spent blocked is accumulated in
## gate_wait_total; corridor entries in gate_transits (harness stats).
##
## ACCELERATION (v4 phase 2). A car no longer teleports between 0 and its top
## speed: it ramps at `accel` and brakes at `decel`, and it must arrive AT REST
## at every place it has to be stopped -
##   * a room stop it is going to open its doors at,
##   * the end of an open (ping-pong) polyline, where it reverses,
##   * a cell whose next step enters a gate corridor it cannot get into,
##   * the cell it is about to park or deadhead-home at.
## So every stop now costs momentum on top of door time, queueing at a corridor
## costs momentum too, and a long uninterrupted run is where a heavy car wins.
## Wider is heavier: pod ramps sharply, standard medium, cargo sluggishly
## (Levels3.CAR_TYPES).
##
## The lookahead (`_stop_distance`) rescans every sub-step, so a stop that
## appears late (a passenger spawning in front of a rolling car) is picked up
## as soon as it exists; if it appears inside the braking distance the car
## simply stops harder, which is the same thing today's game did to EVERY stop.
##
## Integration is ANALYTIC per phase (accelerate / cruise / brake), not a fixed
## sub-step: each call solves the exact distance covered in the time given, and
## never advances past the next cell centre. That is what keeps `advance(dt)`
## give-or-take dt-invariant - a 0.25 s search step and a 0.1 s reporting step
## see the same physics - and what makes overshooting a stop impossible.
##
## Logic time comes from game tick() calls; _process is visuals only.

enum DoorState { CLOSED, OPENING, EXCHANGE, CLOSING }
enum CarState { UNDEPLOYED, RUNNING, RECALLING, REDEPLOYING }

const DOOR_OPEN_T := 0.5
const DOOR_CLOSE_T := 0.5
const EXCHANGE_MIN := 0.8
const EXCHANGE_PER_MOVE := 0.35
const REDEPLOY_DELAY := 3.0 # game-seconds of ghost countdown before service
const VANISH_T := 0.35 # real-seconds of the shrink/fade flourish (visual only)
const BODY := 60.0

const EPS_D := 1.0e-6 # px: "close enough to the cell centre"
const EPS_V := 1.0e-9
const MAX_SCAN_CELLS := 24 # hard cap on the braking lookahead

var game = null # main3.gd
var card_index := 0
var card_type := "standard"
var width := 2 # v4 phase 2: doorway units (pod 1, standard/express 2, cargo 3)
var capacity := 4 # in WIDTH-UNITS, default 2 * width (Levels3.card_capacity)
var speed := 260.0 # MAX speed, px/s
var accel := 300.0 # px/s^2 while ramping up
var decel := 375.0 # px/s^2 while braking for a stop
var vel := 0.0 # current speed, px/s (0 whenever the car is standing still)
var color := Color.GRAY
var route = null # Route3 or null - the COMMITTED route (what planning uses)
var car_state := CarState.UNDEPLOYED
var ever_deployed := false # first commit deploys instantly; later ones redeploy
var recall_route = null # Route3 - the OLD polyline still driven while RECALLING
var recall_stop_idx := -1 # index into recall_route.cells of the drop stop
var redeploy_left := 0.0 # game-seconds left on the ghost countdown
var idx := 0 # index of the last cell center reached (on the drive route)
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
var gate_transits := 0 # corridor lock acquisitions (stat / harness)
var held_gates: Array = [] # gate GROUP indices currently locked by this car
var riders: Array = [] # Passenger3 nodes on board
var vis_t := 0.0
var vanish_from := Vector2.ZERO # where the shrink/fade flourish plays
var vanish_timer := 0.0 # real-time, ticked in _process (visual only)


func setup(g, i: int, card: Dictionary) -> void:
	game = g
	card_index = i
	card_type = card.type
	width = Levels3.card_width(card)
	capacity = Levels3.card_capacity(card)
	speed = Levels3.card_speed(card)
	accel = Levels3.card_accel(card)
	decel = Levels3.card_decel(card)
	color = card.color
	visible = false


## Time (s) this car loses to ONE extra intermediate stop, purely from
## momentum: braking to rest and getting back up to speed. Pathfind3 prices a
## many-stop leg with it, which is the planner's half of acceleration.
func stop_penalty() -> float:
	return speed * (1.0 / (2.0 * accel) + 1.0 / (2.0 * decel))


## True when a party of `w` doorway units can physically fit through this
## car's doors. The capacity check is separate (free_slots).
func fits(w: int) -> bool:
	return w <= width


## Drawn body width in px: a pod is visibly a third of a cargo car.
func body_w() -> float:
	return 4.0 + 28.0 * width


## True when the committed route can run service (>= 2 stops). Pathfinding
## keys off this: RECALLING / REDEPLOYING cars still plan (passengers wait
## out the gap; the flat per-leg wait absorbs it).
func running() -> bool:
	return route != null and route.stop_cells().size() >= 2


## Physically present on the grid (moving/stopping there) right now.
func on_grid() -> bool:
	return car_state == CarState.RUNNING or car_state == CarState.RECALLING


## Capacity in use, counted in WIDTH-UNITS (a couple costs 2, a big delivery 3).
func used_slots() -> int:
	var used := 0
	for p in riders:
		used += p.width
	return used


func free_slots() -> int:
	return capacity - used_slots()


## The polyline the car is physically driving (old route while RECALLING).
func _drive():
	return recall_route if car_state == CarState.RECALLING else route


## Wrap a cell index onto the drive polyline: closed routes cycle mod n
## (the seam n-1 -> 0 is a real travel segment), open routes pass through.
func _wrap_idx(i: int) -> int:
	var r = _drive()
	if r != null and r.closed:
		return posmod(i, r.cells.size())
	return i


## Index distance from `from_idx` to `to_idx` along `r`: forward-only on a
## closed route, symmetric on an open one. Mirrors Route3.ride_dist in index
## space (used for recall nearest-stop selection).
func _stop_dist(r, from_idx: int, to_idx: int) -> int:
	if r.closed:
		return posmod(to_idx - from_idx, r.cells.size())
	return absi(to_idx - from_idx)


## The cell whose center the car last reached, or (-1,-1) when off the grid.
func current_cell() -> Vector2i:
	var r = _drive()
	if not on_grid() or r == null:
		return Vector2i(-1, -1)
	return r.cells[idx]


## Hook for the future "default waiting floor" upgrade UI: pass a cell of
## the route (or null to clear). Idle empty cars deadhead there and wait.
func set_home_cell(cell) -> void:
	home_cell = cell


# ------------------------------------------------------------- route changes

## INSTANT deploy: bind a new route (or null) and appear at its start at
## once. Used for the first commit of a never-deployed car (session start /
## watch mode / harness) and session restarts. Riders must already be gone.
func set_route(r) -> void:
	game.gate_cancel(self)
	held_gates.clear()
	route = r
	recall_route = null
	recall_stop_idx = -1
	idx = 0
	seg_t = 0.0
	dir = 1
	vel = 0.0
	door_state = DoorState.CLOSED
	door_timer = 0.0
	exchange_elapsed = 0.0
	stop_moves = 0
	idle = false
	waiting_gate = false
	car_state = CarState.RUNNING if route != null else CarState.UNDEPLOYED
	visible = route != null
	if route != null and route.cells.size() > 0:
		ever_deployed = true
		position = Grid3.cell_center(route.cells[0])
		if running():
			_arrive_center()


## MID-GAME commit (or CLEAR, r == null): recall riders first if any, then
## redeploy at the new start after a countdown. Never-deployed cars (and
## only those) still deploy instantly.
func apply_route(r) -> void:
	if not ever_deployed:
		set_route(r)
		return
	match car_state:
		CarState.UNDEPLOYED:
			route = r
			if r != null:
				_start_redeploy()
		CarState.RUNNING:
			var old = route
			route = r
			if riders.is_empty() or old == null or old.stop_indices().is_empty():
				if r == null:
					_to_undeployed()
				else:
					_start_redeploy()
			else:
				_begin_recall(old)
		CarState.RECALLING:
			route = r # retarget only; the recall drive continues unchanged
		CarState.REDEPLOYING:
			if r == null:
				_to_undeployed()
			else:
				var restart: bool = route == null or route.cells[0] != r.cells[0]
				route = r
				if restart: # countdown restarts only if the start cell moved
					redeploy_left = REDEPLOY_DELAY
					position = Grid3.cell_center(r.cells[0])


func _begin_recall(old) -> void:
	car_state = CarState.RECALLING
	recall_route = old
	# Doors snap shut; the recall stop reopens them for the dump.
	door_state = DoorState.CLOSED
	door_timer = 0.0
	exchange_elapsed = 0.0
	idle = false
	# Nearest stop by ride distance. On a closed route "nearest" is FORWARD
	# distance (recall never reverses a loop); measure from the NEXT cell when
	# the car has already left its cell center, so a just-passed stop reads as
	# almost-a-full-lap away instead of 0.
	var base := idx
	if old.closed and seg_t > 0.0:
		base = posmod(idx + 1, old.cells.size())
	var stops: Array = old.stop_indices()
	recall_stop_idx = stops[0]
	for s in stops:
		if _stop_dist(old, base, s) < _stop_dist(old, base, recall_stop_idx):
			recall_stop_idx = s


func _start_redeploy() -> void:
	game.gate_cancel(self)
	held_gates.clear()
	vanish_from = position
	vanish_timer = VANISH_T
	recall_route = null
	recall_stop_idx = -1
	car_state = CarState.REDEPLOYING
	redeploy_left = REDEPLOY_DELAY
	idx = 0
	seg_t = 0.0
	dir = 1
	vel = 0.0
	door_state = DoorState.CLOSED
	door_timer = 0.0
	stop_moves = 0
	idle = false
	waiting_gate = false
	visible = true # the ghost outline + countdown draw at the new start
	position = Grid3.cell_center(route.cells[0])


func _to_undeployed() -> void:
	game.gate_cancel(self)
	held_gates.clear()
	recall_route = null
	recall_stop_idx = -1
	car_state = CarState.UNDEPLOYED
	waiting_gate = false
	idle = false
	vel = 0.0
	visible = false


## Countdown expired: appear at the new start and begin service.
func _deploy_now() -> void:
	car_state = CarState.RUNNING
	ever_deployed = true
	if running():
		_arrive_center()


## Recall drive reached the drop stop and the doors have closed again.
func _finish_recall() -> void:
	if route != null:
		_start_redeploy()
	else:
		_to_undeployed()


# ---------------------------------------------------------------- movement

## Game-time tick from main3.
func tick(dt: float) -> void:
	match car_state:
		CarState.UNDEPLOYED:
			return
		CarState.REDEPLOYING:
			redeploy_left -= dt
			if redeploy_left <= 0.0:
				_deploy_now()
			return
		CarState.RECALLING:
			_move_tick(dt)
		CarState.RUNNING:
			if not running():
				return # parked: route needs >= 2 stops
			_move_tick(dt)


func _move_tick(dt: float) -> void:
	var rem := dt
	var guard := 0
	while rem > 0.0 and guard < 500:
		guard += 1
		if not on_grid():
			break # recall completed mid-loop; the car left the grid
		match door_state:
			DoorState.OPENING:
				if car_state != CarState.RECALLING:
					_load_waiting() # late arrivals board while doors open
				if door_timer > rem:
					door_timer -= rem
					rem = 0.0
				else:
					rem -= door_timer
					door_timer = 0.0
					door_state = DoorState.EXCHANGE
					exchange_elapsed = 0.0
					if car_state == CarState.RECALLING:
						_recall_dump()
					else:
						_unload()
						_load_waiting()
			DoorState.EXCHANGE:
				if car_state != CarState.RECALLING:
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
					if car_state == CarState.RECALLING:
						_finish_recall() # dump done; leave the grid
			DoorState.CLOSED:
				if seg_t == 0.0:
					if not _decide_at_center():
						vel = 0.0
						if door_state != DoorState.CLOSED:
							continue # doors just began opening: consume time there
						if not on_grid():
							break # recall finished right here
						if waiting_gate:
							gate_wait_total += rem
						break # idle, or blocked at a gate: retry next tick
				var need := Grid3.CELL - seg_t
				var move := _integrate(need, _stop_distance(need), rem)
				seg_t += move.d
				rem -= move.t
				if seg_t >= Grid3.CELL - EPS_D:
					seg_t = 0.0
					idx = _wrap_idx(idx + dir) # closed: glide across the n-1 -> 0 seam
					_arrive_center()
				elif move.t <= 0.0:
					break # standing still with nowhere to go: retry next tick
	_update_position()


# ------------------------------------------------------------ acceleration

## Distance (px) from the car's current position to the next cell centre it
## MUST be at rest at, given `need` px still to run to the next centre. A big
## number when nothing within the braking lookahead demands a stop.
##
## Re-evaluated every sub-step, so it always reflects the world as it is now.
func _stop_distance(need: float) -> float:
	var r = _drive()
	var n: int = r.cells.size()
	var has_work := car_state != CarState.RECALLING and _has_work()
	# Nothing to do and nowhere to be: the car parks at the very next centre.
	if not has_work and car_state != CarState.RECALLING and home_cell == null:
		return need
	var scan := 2 + int(speed * speed / (2.0 * decel) / Grid3.CELL)
	scan = mini(scan, mini(MAX_SCAN_CELLS, n))
	var d := need
	for k in scan:
		var j := idx + (k + 1) * dir
		if not r.closed and (j < 0 or j >= n):
			break # ran off the polyline; the reversal below already caught it
		var cell: Vector2i = r.cells[_wrap_idx(j)]
		if _stops_at(cell, _wrap_idx(j), has_work):
			return d
		# The end of an open line: the car reverses there, so it stops there.
		if not r.closed and (j + dir < 0 or j + dir >= n):
			return d
		# A corridor the car cannot get into right now.
		var nxt: Vector2i = r.cells[_wrap_idx(j + dir)]
		var gi := Grid3.gate_group_of(nxt)
		if gi != -1 and not held_gates.has(gi) and not game.gate_free_for(self, gi):
			return d
		d += Grid3.CELL
	return d


## Would the car come to a stop at this cell, as _arrive_center decides it?
func _stops_at(cell: Vector2i, j: int, has_work: bool) -> bool:
	if car_state == CarState.RECALLING:
		return j == recall_stop_idx
	if not has_work:
		return home_cell != null and cell == home_cell # deadhead target
	return Grid3.is_room(cell)


## Advance along the current segment: cover at most `dmax` px in at most `rem`
## seconds, braking so the car can be at rest `d_stop` px from here
## (`d_stop` >= `dmax`, because every stop sits on a cell centre).
##
## Solved phase by phase in CLOSED FORM - accelerate at `accel`, hold `speed`,
## brake at `decel` - so the answer does not depend on how the caller chopped
## up its time, and the car can never roll past `dmax`.
## Returns {"d": px covered, "t": seconds used}.
func _integrate(dmax: float, d_stop: float, rem: float) -> Dictionary:
	var u := 0.0
	var t := 0.0
	var guard := 0
	while u < dmax - EPS_D and t < rem and guard < 6:
		guard += 1
		var left_d := dmax - u
		var left_t := rem - t
		var to_stop := maxf(d_stop - u, 0.0)
		var v_lim := sqrt(2.0 * decel * to_stop) # fastest we may legally be here
		var phase_d := left_d
		var mode := "cruise"
		if vel > v_lim + EPS_V:
			mode = "brake" # over the braking curve (a stop appeared late)
		elif vel < speed - EPS_V:
			mode = "accel"
			# ...until we top out, or until we meet the braking curve.
			var d_top := (speed * speed - vel * vel) / (2.0 * accel)
			var d_meet := (2.0 * decel * to_stop - vel * vel) / (2.0 * (accel + decel))
			phase_d = minf(phase_d, maxf(minf(d_top, d_meet), 0.0))
		else:
			# At top speed: cruise until the last moment we can still brake.
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
			_: # brake
				if vel <= EPS_V:
					t = rem # standing still against a stop: burn the time
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
						t = rem # braked to a halt short of the boundary
						break
				else:
					var ct := minf(left_t, t_zero)
					u += vel * ct - 0.5 * decel * ct * ct
					vel = maxf(vel - decel * ct, 0.0)
					t = rem
	return {"d": minf(u, dmax), "t": minf(t, rem)}


## At a cell center with doors closed: open doors, start a hop, or park.
## Returns true when the car should move along its segment this iteration.
func _decide_at_center() -> bool:
	if car_state == CarState.RECALLING:
		if idx == recall_stop_idx:
			if riders.is_empty():
				_finish_recall()
				return false
			_begin_stop()
			return false
		return _depart(recall_stop_idx)
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
		if leg.car == self and leg.board == cell and fits(p.width) and free >= p.width:
			return true
	return false


func _begin_stop() -> void:
	door_state = DoorState.OPENING
	door_timer = DOOR_OPEN_T
	stop_moves = 0
	vel = 0.0 # a car with its doors open is standing still


## Next sweep target index. Open routes ping-pong (reverse at the ends);
## CLOSED routes advance forward forever — no reversing, no end dwell (the
## polyline has no ends; the wrap happens on arrival via _wrap_idx).
func _pingpong_target() -> int:
	if _drive().closed:
		if dir != 1:
			vel = 0.0
		dir = 1
		return idx + 1
	if idx + dir < 0 or idx + dir >= _drive().cells.size():
		dir = -dir
		vel = 0.0 # reversing at the end of the line means stopping first
	return idx + dir


## Try to start the hop toward cells[target_idx] (sets dir from it).
## On a CLOSED route travel is always FORWARD regardless of where the target
## sits (recall stops and home_cell deadheads drive the long way around, never
## backwards). Acquires the gate GROUP lock when the next cell belongs to a
## group this car does not hold. Returns false if the car must wait (group
## held by someone else).
func _depart(target_idx: int) -> bool:
	var want := 1 if _drive().closed or target_idx > idx else -1
	if want != dir:
		vel = 0.0 # any change of direction happens from a standstill
	dir = want
	var next: Vector2i = _drive().cells[_wrap_idx(idx + dir)]
	var gi := Grid3.gate_group_of(next)
	if gi != -1 and not held_gates.has(gi):
		if game.gate_request(self, gi):
			held_gates.append(gi)
			gate_transits += 1
		else:
			waiting_gate = true
			return false
	waiting_gate = false
	return true


## Reached the center of cells[idx]: release any gate group we have fully
## exited (the current cell is outside it), and open doors if this is a room
## stop and the car is working. Deadheading or idle cars skip stops (there is
## nobody aboard and nobody who planned on this car - boarding requires
## legs[0].car == self).
func _arrive_center() -> void:
	var cell: Vector2i = _drive().cells[idx]
	var cur_gi := Grid3.gate_group_of(cell)
	for g in held_gates.duplicate():
		if g != cur_gi:
			game.gate_release(self, g)
			held_gates.erase(g)
	if car_state == CarState.RECALLING:
		if idx == recall_stop_idx:
			if riders.is_empty():
				_finish_recall()
			else:
				_begin_stop()
		return
	if Grid3.is_room(cell) and _has_work():
		_begin_stop()


func _update_position() -> void:
	var r = _drive()
	if not on_grid() or r == null or r.cells.is_empty():
		return
	var a := Grid3.cell_center(r.cells[idx])
	if seg_t <= 0.0:
		position = a
	else:
		# _wrap_idx keeps the lerp smooth across a closed route's seam
		# (cells[n-1] -> cells[0] are adjacent cells; no snap).
		var b := Grid3.cell_center(r.cells[_wrap_idx(idx + dir)])
		position = a.lerp(b, seg_t / Grid3.CELL)


# ---------------------------------------------------------------- riders

func _unload() -> void:
	var cell: Vector2i = route.cells[idx]
	for r in riders.duplicate():
		if not r.legs.is_empty() and r.legs[0].alight == cell:
			riders.erase(r)
			stop_moves += 1
			game.on_alight(r, cell)


## Recall drop: ALL riders step out here (regardless of their planned legs)
## and rejoin the world via main3.on_recall_drop (served / replan + rewait).
func _recall_dump() -> void:
	var cell: Vector2i = recall_route.cells[idx]
	for r in riders.duplicate():
		riders.erase(r)
		stop_moves += 1
		game.on_recall_drop(r, cell)


func _load_waiting() -> void:
	var cell: Vector2i = route.cells[idx]
	if not Grid3.is_room(cell):
		return
	for p in game.waiting.get(cell, []).duplicate():
		if p.legs.is_empty():
			continue
		var leg: Dictionary = p.legs[0]
		if leg.car == self and leg.board == cell and fits(p.width) \
				and free_slots() >= p.width:
			game.waiting[cell].erase(p)
			p.riding = self
			p.no_path = false
			p.rides += 1
			riders.append(p)
			stop_moves += 1


## Where a rider stands inside the car: `width` width-units per row, so a pod
## is a single file, a standard is two abreast and a cargo three.
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
	if vanish_timer > 0.0:
		vanish_timer = maxf(0.0, vanish_timer - delta)
	queue_redraw()


func _draw() -> void:
	if car_state == CarState.UNDEPLOYED:
		return
	if car_state == CarState.REDEPLOYING:
		_draw_redeploy_ghost()
		return
	var half := body_w() / 2.0
	var hh := BODY / 2.0
	var body := Rect2(-half, -hh, body_w(), BODY)
	var parked := car_state == CarState.RUNNING and not running()
	var fill_a := 0.5 if door_state != DoorState.CLOSED else 0.26
	if idle:
		fill_a = 0.16
	draw_rect(body, Color(color, 0.12 if parked else fill_a))
	# Sliding door panels: two leaves parting from the center.
	if not parked:
		var frac := door_frac()
		var leaf_w := (body_w() - 12.0) / 2.0 * (1.0 - frac)
		var door_col := Color(color.lightened(0.25), 0.85)
		if leaf_w > 0.5:
			draw_rect(Rect2(-half + 6.0, -hh + 10.0, leaf_w, BODY - 20.0), door_col)
			draw_rect(Rect2(half - 6.0 - leaf_w, -hh + 10.0, leaf_w, BODY - 20.0), door_col)
			draw_line(Vector2(-half + 6.0 + leaf_w, -hh + 10.0),
					Vector2(-half + 6.0 + leaf_w, hh - 10.0), Color(0, 0, 0, 0.4), 2.0)
			draw_line(Vector2(half - 6.0 - leaf_w, -hh + 10.0),
					Vector2(half - 6.0 - leaf_w, hh - 10.0), Color(0, 0, 0, 0.4), 2.0)
	draw_rect(body, Color(color, 0.4 if parked else 1.0), false, 4.0)
	if speed > Levels3.STANDARD_SPEED:
		# Chevrons = this car is faster than a standard, whatever its width.
		for i in 2:
			var cy := 6.0 - i * 12.0
			draw_polyline(PackedVector2Array([
					Vector2(-11.0, cy), Vector2(0.0, cy - 9.0), Vector2(11.0, cy)]),
					Color(color, 0.9), 4.0)
	if width >= 3:
		# Freight hatching: the heavy car reads as heavy at a glance.
		for t in range(-int(half) + 8, int(half) - 6, 12):
			draw_line(Vector2(t, hh - 8.0), Vector2(t + 8.0, hh - 18.0),
					Color(0.05, 0.05, 0.07, 0.5), 3.0)
	# Capacity pips along the roof, one per WIDTH-UNIT of capacity.
	var used := used_slots()
	var pitch := (body_w() - 12.0) / maxi(capacity, 1)
	for i in capacity:
		var px := -half + 6.0 + i * pitch
		var pip := color if i < used else Color(1, 1, 1, 0.18)
		draw_rect(Rect2(px, -hh + 5.0, maxf(4.0, pitch - 4.0), 5.0), pip)
	# Waiting for a gate: pulsing white outline.
	if waiting_gate:
		var pulse := 0.45 + 0.45 * sin(vis_t * 8.0)
		draw_rect(body.grow(7.0), Color(1, 1, 1, pulse), false, 4.0)
	if home_cell != null and current_cell() == home_cell and idle:
		# Parked on its home floor: a small roof lamp, so "waiting where I was
		# told to wait" is distinguishable from "stranded".
		draw_circle(Vector2(0.0, -hh - 8.0), 5.0, Color(color.lightened(0.4), 0.9))
	# Recalling: soft white pulse + "rewind" chevrons over the roof.
	if car_state == CarState.RECALLING:
		var rp := 0.35 + 0.3 * sin(vis_t * 6.0)
		draw_rect(body.grow(5.0), Color(1, 1, 1, rp), false, 3.0)
		for i in 2:
			var bx := -2.0 - i * 12.0
			draw_colored_polygon(PackedVector2Array([
					Vector2(bx + 10.0, -half - 16.0), Vector2(bx, -half - 10.0),
					Vector2(bx + 10.0, -half - 4.0)]), Color(1, 1, 1, 0.85))
	if parked:
		draw_string(ThemeDB.fallback_font, Vector2(-8.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 24, Color(0.9, 0.3, 0.25))


## Ghost outline + countdown at the new route's start (car absent from the
## grid), plus the brief shrink/fade flourish at the cell the car left.
func _draw_redeploy_ghost() -> void:
	if vanish_timer > 0.0:
		var f := vanish_timer / VANISH_T
		var s := BODY * f
		var p := vanish_from - position
		draw_rect(Rect2(p - Vector2(s / 2.0, s / 2.0), Vector2(s, s)),
				Color(color, 0.55 * f))
	var half := body_w() / 2.0
	var body := Rect2(-half, -BODY / 2.0, body_w(), BODY)
	var pulse := 0.35 + 0.25 * sin(vis_t * 5.0)
	draw_rect(body, Color(color, 0.08))
	draw_rect(body, Color(color, pulse), false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(-9.0, 13.0),
			str(ceili(maxf(redeploy_left, 0.001))),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 38, Color(1, 1, 1, 0.95))
