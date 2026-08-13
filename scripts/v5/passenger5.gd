class_name Passenger5
extends Node2D
## One v5 passenger. Spawns INSIDE a room (origin), wants another ROOM (dest), and
## is rendered at a valid in-room tile from the instant it spawns. Adapted from
## scripts/v3/passenger3.gd.
##
## LIFECYCLE (v5.1b):
##   MILL   - spawn at a room tile, rendered there, and DWELL a short deterministic
##            beat ("decide to hit the button"). Not boardable. Patience drains.
##   QUEUE  - then walk (orthogonally) to the room's QUEUE tile (a non-door cell
##            near, but not on, the dock). Boardable only AFTER arriving.
##   BOARD  - when a serving car stops at the adjacent dock and opens its doors,
##            the car assigns this passenger; it walks queue -> dock during the
##            (extended) door hold and boards on arrival.
##   RIDE   - aboard.
##   ALIGHT - steps onto the dock at door-open, walks dock -> queue, and is served
##            (dest) or replanned (transfer) on arrival.
##   WANDER - purely cosmetic post-served: after the outcome is locked, walk to
##            another room tile, wait, then disappear. Never touches the sim.
##
## Walk duration = Manhattan tiles * Grid5.WALK_PER_TILE. The BOARD/ALIGHT walks
## are queue<->dock and are priced by Pathfind5. The MILL dwell+walk is route-
## independent (same queue tile whatever lift is taken) so it is NOT priced; it
## only uniformly delays boardability. Figures walk right-angle TILE paths (X then
## Y), never diagonals. All tween positions are derived from cell centres and the
## logical `walk_left`, so the visual never feeds back into the deterministic sim.

const PTYPES := {
	"visitor": {"width": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"width": 1, "patience": 78.0, "color": Color(0.35, 0.6, 0.95)},
	"shopper": {"width": 1, "patience": 95.0, "color": Color(0.9, 0.6, 0.35)},
}

enum Walk { NONE, MILL, BOARD, ALIGHT, WANDER }

## Spawn dwell before milling to the queue: DWELL_MIN..DWELL_MAX seconds, keyed
## deterministically off the passenger's salt.
const DWELL_MIN := 1.0
const DWELL_MAX := 3.0
## Post-served wander pause before the figure disappears.
const WANDER_MIN := 1.0
const WANDER_MAX := 2.0

var game = null # main5.gd
var ptype := "visitor"
var origin_room := 0
var dest_room := 0
var cur_room := 0 # room currently waiting in (or last alighted at)
var width := 1
var patience_max := 90.0
var patience := 90.0
var legs: Array = [] # remaining legs; legs[0] is current
var riding = null # Car5 while aboard, else null
var boarding_car = null # Car5 that assigned this passenger to board this stop
var no_path := false
var active := true
var vis_t := 0.0
var wait_time := 0.0
var rides := 0
var salt := 0.0

# Pre-board life.
var spawn_cell := Vector2i.ZERO
var queue_cell := Vector2i.ZERO
var spawn_jitter := Vector2.ZERO
var dwell_left := 0.0
var milled := false # reached the queue tile => boardable
var wandering := false # post-served cosmetic; excluded from all logical state

# Walk state (sim). walk_left > 0 => walking; walk_kind says what completes it.
var walk_kind := Walk.NONE
var walk_left := 0.0
var walk_total := 0.0
var walk_from := Vector2.ZERO
var walk_to := Vector2.ZERO
var wander_hold := 0.0


func setup(g, t: String, o: int, d: int) -> void:
	game = g
	ptype = t
	origin_room = o
	dest_room = d
	cur_room = o
	var info: Dictionary = PTYPES.get(t, PTYPES.visitor)
	width = int(info.width)
	patience_max = info.patience
	if game.level is Dictionary and game.level.has("patience"):
		patience_max = game.level.patience.get(t, patience_max)
	patience = patience_max


## Deterministic 0..1 from the salt with a per-call twist (so dwell / spawn cell /
## jitter / wander don't all key off the same value).
func _r(seed_mul: float) -> float:
	var v: float = sin(salt * 91.7 + seed_mul) * 43758.5453
	return v - floorf(v)


## Begin the pre-board life: choose a spawn tile + jitter, render there, set the
## dwell, and cache the room's queue tile. Called once at spawn (salt already set).
func begin_life() -> void:
	queue_cell = Grid5.room_queue(cur_room)
	var cells: Array = Grid5.room_cells(cur_room)
	spawn_cell = cells[int(_r(1.0) * cells.size()) % maxi(1, cells.size())]
	spawn_jitter = Vector2((_r(2.0) - 0.5) * 34.0, (_r(3.0) - 0.5) * 26.0)
	dwell_left = DWELL_MIN + (DWELL_MAX - DWELL_MIN) * _r(4.0)
	milled = false
	walk_kind = Walk.NONE
	position = Grid5.cell_center(spawn_cell) + spawn_jitter


## Waiting at the queue tile with a plan: a boarder a stopped car may pick up.
func is_waiting_to_board() -> bool:
	return active and riding == null and boarding_car == null and milled \
			and walk_left <= 0.0 and dwell_left <= 0.0 and not legs.is_empty() \
			and not wandering


func tick(dt: float) -> void:
	if not active:
		return
	if riding != null:
		return # aboard: no walk, no patience drain
	wait_time += dt
	# Patience drains from spawn through queueing, but not once a car has claimed
	# the passenger (boarding_car) nor while it is mid-transfer (an alight walk).
	if boarding_car == null and walk_kind != Walk.ALIGHT:
		patience -= dt
	if dwell_left > 0.0:
		dwell_left -= dt
		if dwell_left <= 0.0:
			dwell_left = 0.0
			_start_mill_walk()
	elif walk_left > 0.0:
		walk_left -= dt
		if walk_left <= 0.0:
			walk_left = 0.0
			_on_walk_done()
	if patience <= 0.0 and active:
		active = false
		game.on_expired(self)


func _begin_walk(kind: int, from_cell: Vector2i, to_cell: Vector2i) -> void:
	walk_kind = kind
	var tiles := Grid5.manhattan(from_cell, to_cell)
	walk_total = tiles * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = Grid5.cell_center(from_cell)
	walk_to = Grid5.cell_center(to_cell)
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


func _start_mill_walk() -> void:
	_begin_walk(Walk.MILL, spawn_cell, queue_cell)


## Board walk (called by the car that assigned this passenger): queue tile -> the
## current leg's boarding dock, during the door hold.
func start_board_walk() -> void:
	if legs.is_empty():
		walk_left = 0.0
		walk_total = 0.0
		return
	_begin_walk(Walk.BOARD, queue_cell, legs[0].board_cell)


## Alight walk: the alighting dock -> the room's queue tile. Only when it finishes
## is the passenger served (dest) or replanned (transfer).
func start_alight_walk(alight_cell: Vector2i, room: int) -> void:
	riding = null
	boarding_car = null
	cur_room = room
	milled = true # already in the flow; will wait at the queue tile
	queue_cell = Grid5.room_queue(room)
	_begin_walk(Walk.ALIGHT, alight_cell, queue_cell)


func _on_walk_done() -> void:
	match walk_kind:
		Walk.MILL:
			milled = true # now boardable
			walk_kind = Walk.NONE
		Walk.BOARD:
			if boarding_car != null:
				boarding_car._board_arrived(self)
		Walk.ALIGHT:
			game.finish_alight(self)
		Walk.WANDER:
			pass # the hold + free are driven by main5 via tick_wander


## Post-served cosmetic: walk to another tile in the room, then linger. Excluded
## from every logical list, so it cannot affect served/lost or the sim.
func begin_wander() -> void:
	wandering = true
	var cells: Array = Grid5.room_cells(cur_room)
	var w: Vector2i = queue_cell
	if cells.size() > 1:
		w = cells[int(_r(5.0) * cells.size()) % cells.size()]
		if w == queue_cell:
			w = cells[(cells.find(queue_cell) + 1) % cells.size()]
	wander_hold = WANDER_MIN + (WANDER_MAX - WANDER_MIN) * _r(6.0)
	_begin_walk(Walk.WANDER, queue_cell, w)


## Advance the wander animation (main5 ticks this off the logical list). Returns
## true when the figure should be freed. Deterministic; never touches the sim.
func tick_wander(dt: float) -> bool:
	vis_t += dt
	if walk_left > 0.0:
		walk_left -= dt
		if walk_left < 0.0:
			walk_left = 0.0
		return false
	wander_hold -= dt
	return wander_hold <= 0.0


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
	elif walk_left > 0.0 and walk_total > 0.0:
		var f := clampf(1.0 - walk_left / walk_total, 0.0, 1.0)
		position = _ortho_point(walk_from, walk_to, f)
	queue_redraw()


## Right-angle path from a to b: cover the X axis first, then Y, at a constant
## pace over the whole Manhattan length. Deterministic axis order.
func _ortho_point(a: Vector2, b: Vector2, f: float) -> Vector2:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var total := absf(dx) + absf(dy)
	if total <= 0.001:
		return b
	var d := f * total
	if d <= absf(dx):
		return Vector2(a.x + signf(dx) * d, a.y)
	return Vector2(b.x, a.y + signf(dy) * (d - absf(dx)))


func _draw() -> void:
	var col: Color = PTYPES.get(ptype, PTYPES.visitor).color
	var dark := Color(0, 0, 0, 0.45)
	if wandering:
		# Arrived and leaving: a faded figure, no chip / patience bar.
		draw_circle(Vector2.ZERO, 10.0, Color(col, 0.5))
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.25), 2.0)
		return
	draw_circle(Vector2.ZERO, 10.0, col)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, dark, 2.0)
	# Destination room letter, on a light chip.
	draw_rect(Rect2(Vector2(-7.0, -8.0), Vector2(14.0, 16.0)), Color(1, 1, 1, 0.85))
	draw_string(ThemeDB.fallback_font, Vector2(-5.0, 5.0),
			Grid5.room_letter(dest_room),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 13, Color(0.1, 0.1, 0.1))
	if riding == null:
		var w := 26.0
		var top := -20.0
		var frac := clampf(patience / patience_max, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, top, w, 4.0), Color(0, 0, 0, 0.55))
		var bar_col := Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac)
		draw_rect(Rect2(-w / 2.0, top, w * frac, 4.0), bar_col)
		if no_path:
			var by := -34.0
			draw_circle(Vector2(0, by), 10.0, Color(1, 1, 1, 0.92))
			draw_string(ThemeDB.fallback_font, Vector2(-4.0, by + 6.0), "?",
					HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16, Color(0.1, 0.1, 0.1))
