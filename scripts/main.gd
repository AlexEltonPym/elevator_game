extends Node2D
## Game controller for prototype v2 "Network Planner".
## Owns: level flow (intro -> play -> win/lose -> next), the elevator network
## (4 columns, install/remove/door toggles), passenger spawning + path
## replanning, the selection model, counters, and the game time scale
## (pause / 1x / 3x — a plain variable multiplied into game ticks, so UI and
## network editing keep working while paused).

enum State { INTRO, PLAYING, WIN, LOSE, COMPLETE }

var state: int = State.INTRO
var level_index := 0
var level: Dictionary = {}
var time_scale := 1.0
var served := 0
var lost := 0
var total_served := 0
var total_lost := 0
var spawn_timer := 0.0
var auto_spawn := true # test hook: harness disables random spawns

var inventory: Array = Levels.STARTING_INVENTORY.duplicate()
var columns: Array = [null, null, null, null] # Elevator or null per shaft
var waiting: Array = [] # floor index -> Array[Passenger] in arrival order

var selected_card := -1 # index into inventory, or -1
var selected_column := -1 # column with selected elevator, or -1

@onready var building: Building = $Building
@onready var elevators_node: Node2D = $Elevators
@onready var passengers_node: Node2D = $Passengers
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	randomize()
	for f in Building.FLOORS:
		waiting.append([])
	building.game = self
	hud.game = self
	hud.refresh_inventory()
	_load_level(0)


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	var dt := delta * time_scale
	if dt > 0.0:
		if auto_spawn:
			spawn_timer -= dt
			if spawn_timer <= 0.0:
				_spawn_random()
				spawn_timer = level.spawn
		for e in columns:
			if e != null:
				e.tick(dt)
		for p in passengers_node.get_children():
			p.tick(dt)
	_reflow_queues()
	hud.refresh_stats()


# ---------------------------------------------------------------- level flow

func _load_level(i: int) -> void:
	level_index = i
	level = Levels.DATA[i]
	served = 0
	lost = 0
	_clear_passengers()
	state = State.INTRO
	hud.refresh_stats()
	hud.show_intro(level)


func start_level() -> void:
	hud.hide_overlay()
	state = State.PLAYING
	spawn_timer = level.spawn * 0.5


func choose_reward(card_type: String) -> void:
	inventory.append(card_type)
	hud.refresh_inventory()
	hud.hide_overlay()
	_load_level(level_index + 1)


func retry_level() -> void:
	# Network intact, counters reset.
	served = 0
	lost = 0
	_clear_passengers()
	hud.hide_overlay()
	state = State.PLAYING
	spawn_timer = level.spawn * 0.5


func restart_campaign() -> void:
	for c in Building.COL_COUNT:
		if columns[c] != null:
			columns[c].queue_free()
			columns[c] = null
	inventory = Levels.STARTING_INVENTORY.duplicate()
	total_served = 0
	total_lost = 0
	selected_card = -1
	selected_column = -1
	_clear_passengers()
	hud.refresh_inventory()
	hud.hide_overlay()
	_load_level(0)


func _win() -> void:
	if level_index >= Levels.DATA.size() - 1:
		state = State.COMPLETE
		hud.show_complete(total_served, total_lost)
	else:
		state = State.WIN
		hud.show_win(level, served, lost)


func _lose() -> void:
	state = State.LOSE
	hud.show_lose(served, lost)


func _clear_passengers() -> void:
	for p in passengers_node.get_children():
		p.active = false
		p.queue_free()
	for f in Building.FLOORS:
		waiting[f].clear()
	for e in columns:
		if e != null:
			e.reset_car()


# ---------------------------------------------------------------- input

func set_speed(s: float) -> void:
	time_scale = s


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if state != State.PLAYING:
			return
		_handle_tap(event.position)


func _handle_tap(pos: Vector2) -> void:
	var col := Building.column_at(pos.x, pos.y)
	if col >= 0:
		if columns[col] == null:
			if selected_card >= 0:
				install_card(selected_card, col)
			else:
				deselect()
		elif selected_column == col:
			toggle_door(col, Building.floor_at(pos.y))
		else:
			select_column(col)
	else:
		deselect()


func select_card(i: int) -> void:
	selected_card = -1 if selected_card == i else i
	selected_column = -1
	hud.refresh_inventory()


func select_column(c: int) -> void:
	selected_column = c
	selected_card = -1
	hud.refresh_inventory()


func deselect() -> void:
	selected_card = -1
	selected_column = -1
	hud.refresh_inventory()


# ---------------------------------------------------------------- network edits

func install_card(inv_index: int, col: int) -> void:
	if inv_index < 0 or inv_index >= inventory.size() or columns[col] != null:
		return
	var card_type: String = inventory[inv_index]
	inventory.remove_at(inv_index)
	var e := Elevator.new()
	e.setup(self, col, card_type)
	elevators_node.add_child(e)
	columns[col] = e
	selected_card = -1
	selected_column = col # select the new car so doors can be edited right away
	replan_all()
	hud.refresh_inventory()


func remove_elevator(col: int) -> void:
	var e = columns[col]
	if e == null:
		return
	# Riders step out at the nearest floor and rejoin the waiting pool.
	var f: int = e.current_floor()
	for r in e.riders.duplicate():
		r.riding = null
		r.cur_floor = f
		waiting[f].append(r)
	e.riders.clear()
	inventory.append(e.card_type)
	columns[col] = null
	e.queue_free()
	if selected_column == col:
		selected_column = -1
	replan_all()
	hud.refresh_inventory()


## Returns false if rejected (minimum 2 doors ON).
func toggle_door(col: int, floor_i: int) -> bool:
	var e = columns[col]
	if e == null:
		return false
	if e.doors[floor_i] and e.doors_on_count() <= 2:
		return false
	e.doors[floor_i] = not e.doors[floor_i]
	replan_all()
	return true


# ---------------------------------------------------------------- pathfinding

## Recompute paths for every WAITING passenger and patch riders whose current
## leg became invalid. Called on any network edit (install/remove/toggle).
func replan_all() -> void:
	for f in Building.FLOORS:
		for p in waiting[f]:
			_compute_path_for(p)
	for e in columns:
		if e == null:
			continue
		for r in e.riders:
			_patch_rider_leg(e, r)


func _compute_path_for(p) -> void:
	var path = Pathfind.find_path(p.cur_floor, p.dest, columns, level.transfers)
	if path == null:
		p.legs = []
		p.no_path = true
	else:
		p.legs = path
		p.no_path = false


## Riders finish their current leg, then replan on alight (see on_alight).
## If a toggle removed the door at the rider's alight floor, redirect the leg
## to the best still-reachable floor on this elevator.
func _patch_rider_leg(e, r) -> void:
	if r.legs.is_empty():
		r.legs = [{"elev": e, "board": r.cur_floor, "alight": e.current_floor()}]
	var leg: Dictionary = r.legs[0]
	if leg.elev == e and e.doors[leg.alight]:
		return
	var cands: Array = []
	for f in Building.FLOORS:
		if e.doors[f]:
			cands.append(f)
	var best: int = cands[0]
	if cands.has(r.dest):
		best = r.dest
	else:
		var pool: Array = cands.filter(func(c): return level.transfers.has(c))
		if pool.is_empty():
			pool = cands
		var best_d := 999
		for c in pool:
			if absi(c - r.dest) < best_d:
				best_d = absi(c - r.dest)
				best = c
	r.legs = [{"elev": e, "board": leg.board, "alight": best}]


# ---------------------------------------------------------------- passengers

func _spawn_random() -> void:
	var t := _pick_type()
	var od := _random_od(t)
	spawn_passenger(t, od[0], od[1])


func _pick_type() -> String:
	var roll := randf()
	var acc := 0.0
	for t in level.mix:
		acc += level.mix[t]
		if roll <= acc:
			return t
	return level.mix.keys()[0]


func _random_od(t: String) -> Array:
	if t == "emergency":
		# Destination is ALWAYS floor 7 (SURGERY).
		var o := randi() % Building.FLOORS
		while o == 7:
			o = randi() % Building.FLOORS
		return [o, 7]
	if randf() < 0.6:
		# Trip involves the lobby, either direction.
		var ward := 1 + randi() % (Building.FLOORS - 1)
		return [0, ward] if randf() < 0.5 else [ward, 0]
	var a := 1 + randi() % (Building.FLOORS - 1)
	var b := 1 + randi() % (Building.FLOORS - 1)
	while b == a:
		b = 1 + randi() % (Building.FLOORS - 1)
	return [a, b]


func spawn_passenger(ptype: String, origin: int, dest: int) -> Passenger:
	var p := Passenger.new()
	p.setup(self, ptype, origin, dest)
	passengers_node.add_child(p)
	waiting[origin].append(p)
	_compute_path_for(p)
	return p


## A rider stepped out of `elev` at floor f: served, or transfer + replan.
func on_alight(p, f: int) -> void:
	p.riding = null
	if not p.legs.is_empty():
		p.legs.pop_front()
	p.cur_floor = f
	if f == p.dest:
		on_served(p)
	else:
		_compute_path_for(p) # always replan from the transfer floor
		waiting[f].append(p)


func on_served(p) -> void:
	p.active = false
	p.queue_free()
	served += 1
	total_served += 1
	if state == State.PLAYING and served >= level.quota:
		_win()


func on_expired(p) -> void:
	waiting[p.cur_floor].erase(p)
	p.queue_free()
	lost += 1
	total_lost += 1
	if state == State.PLAYING and lost >= level.max_lost:
		_lose()


## Lay waiting passengers out beside the column their current leg targets
## (or in a "?" parking strip near the labels when there is no path).
func _reflow_queues() -> void:
	for f in Building.FLOORS:
		var next_x := {} # anchor x -> next free x (queues grow leftward)
		var y: float = Building.floor_to_y(f) - 4.0
		for p in waiting[f]:
			var ax: float
			if p.legs.is_empty():
				ax = Building.LEFT + Building.LABEL_W - 4.0
			else:
				ax = Building.COL_X[p.legs[0].elev.column] - 2.0
			var x: float = next_x.get(ax, ax - 14.0)
			p.position = Vector2(x, y)
			next_x[ax] = x - (40.0 if p.ptype == "gurney" else 24.0)
