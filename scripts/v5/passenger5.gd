class_name Passenger5
extends Node2D
## One v5 passenger. Adapted from scripts/v3/passenger3.gd. It runs one or more
## TRIPS (origin room -> destination room); on arrival it may reactivate into a
## fresh trip (the seed of an itinerary system) or vanish.
##
## POSITION MODEL (v5.1h). People behave like PEOPLE, not a sorting pass. A figure
## has ONE stable standing target (`stand_pos`) that changes only on DISCRETE
## EVENTS — never re-sorted per frame. Two zones per room:
##   * BACK zone — a loose spot (picked once, clipping allowed) where a figure
##     spawns and mills, and where deboarders / between-trip figures wait.
##   * QUEUE — an ordered straight line from the dock extending back. A figure
##     joins at the TAIL when it activates and keeps its slot; when the person in
##     front boards, everyone behind steps FORWARD one slot (a single event-driven
##     step, main5.queue_leave). No isometric rows.
## Standing figures EASE toward `stand_pos`; the SIM walks (mill/board/alight) tween
## along `walk_from -> target`. All of this is visual: board order, sim timing,
## Pathfind pricing and determinism are unaffected (positions aren't in the sig).
##
## TRIP LIFECYCLE:
##   MILL(inactive) at the BACK, no patience -> ACTIVATE (patience starts, walk to
##   the QUEUE tail) -> BOARD (queue->dock during the door hold) -> RIDE -> ALIGHT
##   (dock->BACK) -> served (dest) or transfer (re-join the queue). On serving, a
##   BETWEEN dwell then a seeded vanish / reactivate. All seeded off `salt`.

const PTYPES := {
	"visitor": {"width": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"width": 1, "patience": 78.0, "color": Color(0.35, 0.6, 0.95)},
	"shopper": {"width": 1, "patience": 95.0, "color": Color(0.9, 0.6, 0.35)},
}

enum Walk { NONE, MILL, BOARD, ALIGHT, TRANSFER }

## Seeded activation dwell (spawn -> becomes active) and post-arrival between dwell.
const ACT_DWELL_MIN := 0.8
const ACT_DWELL_MAX := 2.2
const BETWEEN_MIN := 1.0
const BETWEEN_MAX := 2.0
## Standing figures ease toward their target at this speed (px/s) — a single smooth
## step when the queue advances, no per-frame jitter.
const STAND_EASE := 130.0
## The single FLOOR LINE of a room: cell_bottom - FLOOR_OFF puts a figure's centre
## at cell_centre + 14 = the docked car's front-row rider height (Car5.slot_position
## base_y), so ALL standing figures share one grounded floor and boarding is a
## horizontal step into the car (no vertical pop). = CELL - (CELL/2 + car base_y).
const FLOOR_OFF := 31.0

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
var milled := false # reached the queue => boardable
var spawn_cell := Vector2i.ZERO # far cell (mill-walk sim distance is from here)
var queue_cell := Vector2i.ZERO
var dwell_left := 0.0
var between_left := 0.0
var queue_slot := -1 # index in its room's queue line, or -1 (not queued)

# Position targets (visual). stand_pos is the stable standing goal; back_pos is the
# loose spot in the back this figure keeps for the trip.
var stand_pos := Vector2.ZERO
var back_pos := Vector2.ZERO

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


## Begin a trip's pre-board life: choose a loose BACK spot in the current room,
## stand there INACTIVE (no patience yet), and set the activation dwell.
func begin_life() -> void:
	queue_cell = Grid5.room_queue(cur_room)
	spawn_cell = _pick_far()
	back_pos = _pick_back()
	stand_pos = back_pos
	position = back_pos
	dwell_left = ACT_DWELL_MIN + (ACT_DWELL_MAX - ACT_DWELL_MIN) * _r(4.0)
	activated = false
	between = false
	milled = false
	queue_slot = -1
	walk_kind = Walk.NONE
	walk_left = 0.0


## A non-queue tile in the current room (mill-walk SIM distance reference).
func _pick_far() -> Vector2i:
	var cells: Array = Grid5.room_cells(cur_room)
	var opts: Array = []
	for c in cells:
		if c != queue_cell:
			opts.append(c)
	if opts.is_empty():
		opts = cells
	return opts[int(_r(1.0) * opts.size()) % opts.size()]


## A loose standing spot in the BACK of the room (away from the dock), salt-spread
## along X only — everyone stands GROUNDED on the one floor line (no vertical
## variation). Clipping allowed; it is not re-sorted.
func _pick_back() -> Vector2:
	var rect: Rect2 = Grid5.room_rect(cur_room)
	var qcell: Vector2i = Grid5.room_queue(cur_room)
	var floor_y: float = Grid5.cell_rect(qcell).end.y - FLOOR_OFF
	var qc: Vector2 = Grid5.cell_center(qcell)
	var toward: Vector2 = Grid5.cell_center(qcell + Grid5.room_queue_dir(cur_room)) - qc
	var tx: float = signf(toward.x) if absf(toward.x) > 0.01 else 1.0
	# Far-from-dock edge, spread loosely across the back third — on the floor.
	var far_x: float = rect.position.x + 22.0 if tx > 0.0 else rect.end.x - 22.0
	var x := far_x + tx * _r(1.5) * (rect.size.x * 0.45)
	return Vector2(x, floor_y)


## Waiting in the queue (reached it), boardable.
func is_waiting_to_board() -> bool:
	return active and activated and milled and not between and riding == null \
			and boarding_car == null and walk_left <= 0.0 and not legs.is_empty()


func tick(dt: float) -> void:
	if not active or riding != null:
		return
	if between:
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
	if _patience_running():
		patience -= dt
		wait_time += dt
		if patience <= 0.0 and active:
			active = false
			game.on_expired(self)


func _patience_running() -> bool:
	return active and activated and not between and riding == null \
			and boarding_car == null and walk_kind != Walk.ALIGHT


## Dwell finished: patience starts, the passenger joins the queue TAIL and walks to
## its slot. (main5.queue_join sets queue_slot + stand_pos.)
func _activate() -> void:
	activated = true
	game.queue_join(self)
	walk_kind = Walk.MILL
	walk_total = Grid5.manhattan(spawn_cell, queue_cell) * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = position
	walk_to = stand_pos
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


## Board walk (called by the assigning car): leave the queue line (so those behind
## step forward) and walk from the slot to the dock — targeting the dock's FLOOR
## line (car front-row height), so it is a horizontal step INTO the car, not a pop.
func start_board_walk() -> void:
	game.queue_leave(self)
	walk_kind = Walk.BOARD
	if legs.is_empty():
		walk_left = 0.0
		return
	var board: Vector2i = legs[0].board_cell
	walk_total = Grid5.manhattan(queue_cell, board) * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = position
	walk_to = Vector2(Grid5.cell_center(board).x, Grid5.cell_rect(board).end.y - FLOOR_OFF)
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


## Snappy transfer re-queue: a MID-JOURNEY rider that alights at a transfer room and
## needs another lift joins that room's queue AT ONCE — no fresh activation dwell,
## no BETWEEN wander. It walks straight (on the floor) from the dock to its queue
## slot and is boardable on arrival. main5.on_alight has already re-planned.
func start_transfer_walk(alight_cell: Vector2i) -> void:
	riding = null
	boarding_car = null
	activated = true
	between = false
	milled = false
	queue_cell = Grid5.room_queue(cur_room)
	game.queue_join(self) # sets queue_slot + stand_pos
	walk_kind = Walk.TRANSFER
	walk_total = Grid5.manhattan(alight_cell, queue_cell) * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = position
	walk_to = stand_pos
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


## Alight: step off the car and walk to a loose BACK spot in the room. The timer is
## the priced dock->queue walk time (finish_alight fires when it completes).
func start_alight_walk(alight_cell: Vector2i, room: int) -> void:
	boarding_car = null
	cur_room = room
	milled = false
	queue_cell = Grid5.room_queue(room)
	back_pos = _pick_back()
	walk_kind = Walk.ALIGHT
	walk_total = Grid5.manhattan(alight_cell, queue_cell) * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = position
	walk_to = back_pos
	riding = null
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


func _on_walk_done() -> void:
	match walk_kind:
		Walk.MILL, Walk.TRANSFER:
			milled = true # reached the queue slot; boardable
			walk_kind = Walk.NONE
		Walk.BOARD:
			if boarding_car != null:
				boarding_car._board_arrived(self)
		Walk.ALIGHT:
			walk_kind = Walk.NONE
			stand_pos = back_pos
			game.finish_alight(self)


## Post-arrival BETWEEN: dwell at the back spot (already there), no patience.
func begin_between() -> void:
	between = true
	activated = false
	milled = false
	stand_pos = back_pos
	between_left = BETWEEN_MIN + (BETWEEN_MAX - BETWEEN_MIN) * _r(5.0)




## Reset for a fresh trip to `new_dest` from the current room.
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


## Called by main5.queue_join / queue_leave when this figure's stable target moves
## (join, or the queue advanced). A standing figure eases there; one still walking
## in retargets its walk.
func set_stand(pos: Vector2) -> void:
	stand_pos = pos
	if walk_left > 0.0 and (walk_kind == Walk.MILL or walk_kind == Walk.TRANSFER):
		walk_to = pos


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
	elif walk_left > 0.0 and walk_total > 0.0:
		var f := clampf(1.0 - walk_left / walk_total, 0.0, 1.0)
		position = _ortho_point(walk_from, walk_to, f)
	else:
		# Standing: ease toward the stable target (a smooth step when it changes).
		position = position.move_toward(stand_pos, STAND_EASE * delta)
	# Depth sort: figures lower on screen (larger y) draw in front, so the back
	# row of a car stack (smaller y) sits behind the front, and room crowds layer
	# right. Render-only.
	z_index = clampi(int(position.y), -4096, 4096)
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
	# A small upright, person-proportioned rectangle (placeholder "little person"),
	# ~14 x 24, on the floor. Normal colour always (no recolour); the impatience bar
	# shows only while patience is running.
	var col: Color = PTYPES.get(ptype, PTYPES.visitor).color
	var body := Rect2(-7.0, -12.0, 14.0, 24.0)
	draw_rect(body, col)
	draw_rect(body, Color(0, 0, 0, 0.45), false, 2.0)
	draw_rect(Rect2(Vector2(-6.0, -9.0), Vector2(12.0, 13.0)), Color(1, 1, 1, 0.85))
	draw_string(ThemeDB.fallback_font, Vector2(-5.0, 2.0),
			Grid5.room_letter(dest_room),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, Color(0.1, 0.1, 0.1))
	if _patience_running():
		var w := 22.0
		var top := -22.0
		var frac := clampf(patience / patience_max, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, top, w, 4.0), Color(0, 0, 0, 0.55))
		var bar_col := Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac)
		draw_rect(Rect2(-w / 2.0, top, w * frac, 4.0), bar_col)
	if no_path and activated and not between and riding == null:
		var by := -32.0
		draw_circle(Vector2(0, by), 9.0, Color(1, 1, 1, 0.92))
		draw_string(ThemeDB.fallback_font, Vector2(-4.0, by + 5.0), "?",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 15, Color(0.1, 0.1, 0.1))
