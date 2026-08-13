class_name Passenger5
extends Node2D
## One v5 passenger. Adapted from scripts/v3/passenger3.gd. It runs one or more
## TRIPS (origin room -> destination room); on arrival it may reactivate into a
## fresh trip (the seed of an itinerary system) or vanish.
##
## TRIP LIFECYCLE (v5.1c):
##   MILL(inactive) - spawns on a FAR room tile, rendered there, with NO patience
##                    timer. Dwells a short seeded beat.
##   ACTIVATE       - patience STARTS here (not at spawn). Walks (orthogonally) to
##                    the room's QUEUE tile (a door cell by the dock) and queues
##                    behind whoever is already there (FIFO, boards in arrival
##                    order).
##   BOARD          - a stopped car assigns it; it walks queue->dock during the
##                    door hold and boards.
##   RIDE / ALIGHT  - aboard, then steps onto the dock and walks dock->queue;
##                    served (dest) or replanned (transfer) on arrival.
##   BETWEEN        - post-arrival: walks to the opposite tile and dwells (no
##                    patience). Then, by a seeded per-level probability, either
##                    VANISHES or REACTIVATES with a new destination (a new trip).
##
## Board/alight walks are queue<->dock and are priced by Pathfind5. The dwell/mill
## and between phases are route-independent and NOT priced; they uniformly delay
## boardability. The reactivation DECISION + new destination are LOGICAL (run in
## headless, affect served/outcome); the walk tweens are visual only. Everything
## is seeded off `salt` so a repeated headless run is bit-identical.

const PTYPES := {
	"visitor": {"width": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"width": 1, "patience": 78.0, "color": Color(0.35, 0.6, 0.95)},
	"shopper": {"width": 1, "patience": 95.0, "color": Color(0.9, 0.6, 0.35)},
}

enum Walk { NONE, MILL, BOARD, ALIGHT, COSMETIC }

## Seeded activation dwell (spawn -> becomes active) and post-arrival between dwell.
const ACT_DWELL_MIN := 0.8
const ACT_DWELL_MAX := 2.2
const BETWEEN_MIN := 1.0
const BETWEEN_MAX := 2.0

var game = null # main5.gd
var ptype := "visitor"
var origin_room := 0
var dest_room := 0
var cur_room := 0 # room currently in (or last alighted at)
var width := 1
var patience_max := 90.0
var patience := 90.0
var legs: Array = [] # remaining legs; legs[0] is current
var riding = null # Car5 while aboard, else null
var boarding_car = null # Car5 that assigned this passenger to board this stop
var no_path := false
var active := true # alive in the sim
var vis_t := 0.0
var wait_time := 0.0
var rides := 0
var salt := 0.0
var trip := 0 # trip index (seeds activation / reactivation)

# Phase.
var activated := false # past the spawn dwell => patience running
var between := false # post-arrival, pre-decision => no patience
var milled := false # reached the queue tile => boardable
var spawn_cell := Vector2i.ZERO
var queue_cell := Vector2i.ZERO
var far_cell := Vector2i.ZERO
var dwell_left := 0.0
var between_left := 0.0
var board_lane := 0 # position in this stop's boarding queue (spaces the approach)

# Walk state (sim). walk_left > 0 => walking; walk_kind says what completes it.
var walk_kind := Walk.NONE
var walk_left := 0.0
var walk_total := 0.0
var walk_from := Vector2.ZERO
var walk_to := Vector2.ZERO


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


## Deterministic 0..1 from salt + trip + a per-call twist.
func _r(k: float) -> float:
	var v: float = sin(salt * 91.7 + trip * 13.1 + k) * 43758.5453
	return v - floorf(v)


## Begin a trip's pre-board life: pick a far spawn tile in the current room, render
## there INACTIVE (no patience yet), and set the activation dwell.
func begin_life() -> void:
	queue_cell = Grid5.room_queue(cur_room)
	far_cell = _pick_far()
	spawn_cell = far_cell
	dwell_left = ACT_DWELL_MIN + (ACT_DWELL_MAX - ACT_DWELL_MIN) * _r(4.0)
	activated = false
	between = false
	milled = false
	board_lane = 0
	walk_kind = Walk.NONE
	walk_left = 0.0
	# Initial in-room position (the crowd packer re-slots it next frame).
	position = Grid5.cell_center(spawn_cell)


## A non-queue tile in the CURRENT room (a real room cell), deterministic. Used
## as the spawn tile and the in-place "opposite tile" a finished figure retires to.
func _pick_far() -> Vector2i:
	var cells: Array = Grid5.room_cells(cur_room)
	var opts: Array = []
	for c in cells:
		if c != queue_cell:
			opts.append(c)
	if opts.is_empty():
		opts = cells
	return opts[int(_r(1.0) * opts.size()) % opts.size()]


## Patience is only running once activated, while genuinely waiting (not aboard,
## not claimed by a car, not mid-transfer, not between trips).
func patience_running() -> bool:
	return active and activated and not between and riding == null \
			and boarding_car == null and walk_kind != Walk.ALIGHT


## A boarder a stopped car may pick up: activated, arrived at the queue tile, idle.
func is_waiting_to_board() -> bool:
	return active and activated and milled and not between and riding == null \
			and boarding_car == null and walk_left <= 0.0 and not legs.is_empty()


func tick(dt: float) -> void:
	if not active or riding != null:
		return
	if between:
		if walk_left > 0.0:
			walk_left -= dt
			if walk_left < 0.0:
				walk_left = 0.0
		between_left -= dt
		if between_left <= 0.0:
			between = false
			game.resolve_between(self)
		return
	if not activated:
		dwell_left -= dt
		if dwell_left <= 0.0:
			dwell_left = 0.0
			_activate()
		return
	if walk_left > 0.0:
		walk_left -= dt
		if walk_left <= 0.0:
			walk_left = 0.0
			_on_walk_done()
	if patience_running():
		patience -= dt
		wait_time += dt
		if patience <= 0.0 and active:
			active = false
			game.on_expired(self)


## Dwell finished: patience starts and the passenger walks to the queue tile.
func _activate() -> void:
	activated = true
	_begin_walk(Walk.MILL, spawn_cell, queue_cell)
	walk_from = position # leave from the packed slot it is standing in


func _begin_walk(kind: int, from_cell: Vector2i, to_cell: Vector2i) -> void:
	walk_kind = kind
	var tiles := Grid5.manhattan(from_cell, to_cell)
	walk_total = tiles * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = Grid5.cell_center(from_cell)
	walk_to = Grid5.cell_center(to_cell)
	if walk_left <= 0.0 and kind != Walk.COSMETIC:
		walk_left = 0.0
		_on_walk_done()


## Board walk (called by the assigning car): queue tile -> the leg's boarding dock.
## `board_lane` (order in this stop's boarding queue) offsets the visual approach —
## boarders start single-file behind the queue tile and fan out at the dock — so
## they never stack on the same pixel. The DURATION is still the tile distance, so
## sim timing / Pathfind pricing are untouched.
func start_board_walk() -> void:
	if legs.is_empty():
		walk_left = 0.0
		return
	var board: Vector2i = legs[0].board_cell
	walk_kind = Walk.BOARD
	walk_total = Grid5.manhattan(queue_cell, board) * Grid5.WALK_PER_TILE
	walk_left = walk_total
	var qc := Grid5.cell_center(queue_cell)
	var bc := Grid5.cell_center(board)
	var approach := (bc - qc)
	approach = approach.normalized() if approach.length() > 0.01 else Vector2(1, 0)
	var perp := Vector2(-approach.y, approach.x)
	# Leave from the actual slot it is standing in; fan out per lane at the dock so
	# concurrent boarders don't converge on one pixel.
	walk_from = position
	walk_to = bc + perp * (board_lane * 14.0)
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


## Alight walk: the alighting dock -> the room's queue tile.
func start_alight_walk(alight_cell: Vector2i, room: int) -> void:
	riding = null
	boarding_car = null
	cur_room = room
	milled = true
	queue_cell = Grid5.room_queue(room)
	_begin_walk(Walk.ALIGHT, alight_cell, queue_cell)


func _on_walk_done() -> void:
	match walk_kind:
		Walk.MILL:
			milled = true
			walk_kind = Walk.NONE
		Walk.BOARD:
			if boarding_car != null:
				boarding_car._board_arrived(self)
		Walk.ALIGHT:
			walk_kind = Walk.NONE
			game.finish_alight(self)


## Enter the post-arrival BETWEEN phase: walk to the opposite tile and dwell (no
## patience). main5.resolve_between decides vanish vs reactivate when it ends.
func begin_between() -> void:
	between = true
	activated = false
	milled = false
	between_left = BETWEEN_MIN + (BETWEEN_MAX - BETWEEN_MIN) * _r(5.0)
	# The opposite tile in the CURRENT (destination) room — a real room cell, so the
	# figure retires IN PLACE and never slides toward another room / off the grid.
	queue_cell = Grid5.room_queue(cur_room)
	far_cell = _pick_far()
	_begin_walk(Walk.COSMETIC, queue_cell, far_cell)
	walk_from = position # ease off from where it is standing, not a fixed cell


## Reset for a fresh trip to `new_dest` from the current room (spawn-in-place ->
## activate -> queue -> ride). Called by main5.resolve_between when reactivating.
func reactivate(new_dest: int) -> void:
	trip += 1
	origin_room = cur_room
	dest_room = new_dest
	patience = patience_max
	rides = 0
	wait_time = 0.0
	legs = []
	no_path = false
	begin_life()


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
	elif walk_left > 0.0 and walk_total > 0.0:
		var f := clampf(1.0 - walk_left / walk_total, 0.0, 1.0)
		position = _ortho_point(walk_from, walk_to, f)
	queue_redraw()


## Right-angle path from a to b: X axis first, then Y, constant pace over the whole
## Manhattan length. Deterministic axis order.
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
	# Finished / inactive / between-trip people keep their EXACT normal colour and
	# look; the ONLY difference is they show no impatience bar (patience is not
	# running). The centre destination chip is always drawn so the body never reads
	# as a different (brighter) shade.
	var col: Color = PTYPES.get(ptype, PTYPES.visitor).color
	draw_circle(Vector2.ZERO, 10.0, col)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 2.0)
	draw_rect(Rect2(Vector2(-7.0, -8.0), Vector2(14.0, 16.0)), Color(1, 1, 1, 0.85))
	draw_string(ThemeDB.fallback_font, Vector2(-5.0, 5.0),
			Grid5.room_letter(dest_room),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 13, Color(0.1, 0.1, 0.1))
	if patience_running():
		var w := 26.0
		var top := -20.0
		var frac := clampf(patience / patience_max, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, top, w, 4.0), Color(0, 0, 0, 0.55))
		var bar_col := Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac)
		draw_rect(Rect2(-w / 2.0, top, w * frac, 4.0), bar_col)
	if no_path and activated and not between and riding == null:
		var by := -34.0
		draw_circle(Vector2(0, by), 10.0, Color(1, 1, 1, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(-4.0, by + 6.0), "?",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16, Color(0.1, 0.1, 0.1))
