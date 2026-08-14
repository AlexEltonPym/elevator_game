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

## Per-type data. `walk_mult` scales WALK_PER_TILE for THIS type in BOTH the sim
## walk time and Pathfind5's priced legs, so a slow type stays honest in planning.
## Un-listed => 1.0 (normal pace). `width` is the boarding rule: a party only fits
## a car with car.width >= width (Car5.fits), so a width-3 party ONLY boards the
## width-3 cargo car — the legible reason a level needs the freight lift.
const PTYPES := {
	"visitor": {"width": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"width": 1, "patience": 78.0, "color": Color(0.35, 0.6, 0.95)},
	"shopper": {"width": 1, "patience": 95.0, "color": Color(0.9, 0.6, 0.35)},
	# DELIVERY MAN (v5): a WIDE, SLOW freight figure. width 3 = himself + a 2-box
	# cart, so he needs 3 slots in the car and only fits a width-3 CARGO lift.
	# walk_mult 2.0 = he pushes a HEAVY cart, so every LOADED walk leg takes 2x as long
	# (priced the same in Pathfind5) AND a visual quadratic ease-in ramps him up from
	# rest (see _process) — the loaded man is even slower and starts slowly. Once he
	# DROPS OFF he becomes a width-1, walk_mult-1.0 empty person (become_empty_return),
	# so the 2.0 mult and the ramp only ever apply to the loaded outbound leg. Patience
	# generous — freight isn't in a rush.
	"delivery": {"width": 3, "patience": 130.0, "walk_mult": 2.0,
			"color": Color(0.74, 0.53, 0.30)},
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

# PixelSpaces side-NPC animation. The pre-made NPC sheet is a 4x3 grid of 16x16 frames;
# FRONT idle/walk on columns {0,2}, side (RIGHT) walk on {1,3}; LEFT is RIGHT mirrored.
# Rendered ~34px tall, bottom-aligned to the figure's feet. Loaded once & GRACEFULLY
# (null => _draw falls back to the placeholder rectangle, so a clean clone still runs).
const NPC_FRONT := [0, 2]
const NPC_SIDE := [1, 3]
const NPC_H := 34.0
const _NPC_PATH := ["res://assets/pixel/pixelspaces/Pre-made NPCs/Male.png",
		"res://assets/pixel/pixelspaces/Pre-made NPCs/Female.png"]
static var _npc_tex: Array = []
static var _npc_loaded := false

static func _load_npc() -> void:
	if _npc_loaded:
		return
	_npc_loaded = true
	for p in _NPC_PATH:
		_npc_tex.append(load(p) if ResourceLoader.exists(p) else null)

var _sheet := 0
var _anim_i := 0
var _anim_t := 0.0
var _facing := 0        # 0 front, 1 right, -1 left
var _cols: Array = NPC_FRONT
var _prev_pos := Vector2.ZERO

var game = null # main5.gd
var ptype := "visitor"
var origin_room := 0
var dest_room := 0
var cur_room := 0 # room currently in (or last alighted at)
var width := 1
var walk_mult := 1.0 # per-type WALK_PER_TILE multiplier (delivery man walks slower)
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
# ITINERARY (round-trip delivery man). return_room >= 0 means "after this trip is
# served, run one deterministic RETURN leg toward return_room, then vanish" — set at
# spawn from a typed trip's `return` letter (main5). `returning` is true once he has
# DROPPED OFF and become the width-1 empty person on that return leg (drawn without a
# cart, normal speed, boardable by any lift). Un-set for every non-itinerary figure,
# so their lifecycle (and every non-R-8 fingerprint) is untouched.
var return_room := -1
var returning := false

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


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_npc()


func setup(g, t: String, o: int, d: int) -> void:
	game = g
	ptype = t
	origin_room = o
	dest_room = d
	cur_room = o
	_sheet = (o + d) % _NPC_PATH.size()   # deterministic male/female variety
	var info: Dictionary = PTYPES.get(t, PTYPES.visitor)
	width = int(info.width)
	walk_mult = float(info.get("walk_mult", 1.0))
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
	walk_total = Grid5.manhattan(spawn_cell, queue_cell) * Grid5.WALK_PER_TILE * walk_mult
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
	walk_total = Grid5.manhattan(queue_cell, board) * Grid5.WALK_PER_TILE * walk_mult
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
	walk_total = Grid5.manhattan(alight_cell, queue_cell) * Grid5.WALK_PER_TILE * walk_mult
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
	walk_total = Grid5.manhattan(alight_cell, queue_cell) * Grid5.WALK_PER_TILE * walk_mult
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




## ITINERARY TRANSITION: a delivery man who has just DROPPED OFF his cargo sheds the
## cart and becomes a WIDTH-1, empty-handed, NORMAL-speed person for the return leg —
## no cart (the _draw cart is gated on width >= 3), boardable by ANY lift, and priced
## by Pathfind5 as w1/normal because width and walk_mult now read 1 (both feed the sim
## walk time and the planner's per-leg cost). Called once, in main5.resolve_between,
## immediately before reactivate() sends him toward return_room. The loaded 2.0 mult +
## the heavy visual ramp (see _process) therefore only ever apply to the OUTBOUND leg.
func become_empty_return() -> void:
	width = 1
	walk_mult = 1.0
	returning = true


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
		# HEAVY EASE-IN (visual only): a LOADED delivery man (width >= 3, pushing the
		# cart) accelerates up from REST — a quadratic f is exactly a constant-
		# acceleration ramp, so he starts slow and builds speed into the dock. The
		# LOGICAL walk time (walk_left / walk_total, driven by WALK_PER_TILE * walk_mult)
		# is untouched, so Pathfind5's priced total still matches the sim to the tick and
		# determinism holds — this only reshapes WHERE he is drawn along the leg, never
		# WHEN it completes. An empty (w1) figure walks linearly, at normal speed.
		if width >= 3:
			f = f * f
		position = _ortho_point(walk_from, walk_to, f)
	else:
		# Standing: ease toward the stable target (a smooth step when it changes).
		position = position.move_toward(stand_pos, STAND_EASE * delta)
	# Facing + walk animation from actual velocity (render-only). Riding = stand front;
	# moving horizontally = side walk facing travel; moving vertically = front walk.
	if riding != null:
		_facing = 0
		_cols = NPC_FRONT
		_anim_i = 0
	else:
		var vel := position - _prev_pos
		if vel.length() > 0.4:
			_anim_t += delta
			if _anim_t > 0.13:
				_anim_t = 0.0
				_anim_i = (_anim_i + 1) % 2
			if absf(vel.x) >= absf(vel.y):
				_facing = 1 if vel.x >= 0.0 else -1
				_cols = NPC_SIDE
			else:
				_facing = 0
				_cols = NPC_FRONT
		else:
			_anim_i = 0
			_facing = 0
			_cols = NPC_FRONT
	_prev_pos = position
	# Depth sort: figures lower on screen (larger y) draw in front. Render-only.
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
	# The delivery man (width >= 3) still pushes his programmer-art 2-box cart (drawn
	# first, under the body). Everyone renders as a PixelSpaces side-NPC; the type is
	# read from the destination BADGE colour (the sprite is one shared character).
	if width >= 3:
		_draw_cart(col)
	var tex: Texture2D = _npc_tex[_sheet] if _sheet < _npc_tex.size() else null
	if tex != null:
		var scale := NPC_H / 16.0
		var w := 16.0 * scale
		var dest := Rect2(-w / 2.0, 12.0 - NPC_H, w, NPC_H)  # feet on the floor line
		var src := Rect2(_cols[_anim_i] * 16, 0, 16, 16)
		if _facing < 0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
			draw_texture_rect_region(tex, dest, src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(tex, dest, src)
	else:
		# Fallback placeholder person (no art pack).
		var bw := 18.0 if width >= 3 else 14.0
		var body := Rect2(-bw / 2.0, -12.0, bw, 24.0)
		draw_rect(body, col)
		draw_rect(body, Color(0, 0, 0, 0.45), false, 2.0)
		draw_rect(Rect2(Vector2(-bw / 2.0 + 1.0, -9.0), Vector2(bw - 2.0, 13.0)),
				Color(1, 1, 1, 0.85))
	# Destination badge above the head: a type-coloured disc with the dest room letter.
	var badge_y := -30.0
	draw_circle(Vector2(0, badge_y), 8.5, Color(0.08, 0.08, 0.10, 0.85))
	draw_circle(Vector2(0, badge_y), 7.0, col)
	draw_string(ThemeDB.fallback_font, Vector2(-4.0, badge_y + 4.5),
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


## The delivery man's hand-cart: a low wheeled bed carrying 2 taped boxes, drawn to
## his right on the same floor line (the reason he takes 3 slots). Programmer-art in
## the type colour; render-only, no sim meaning.
func _draw_cart(col: Color) -> void:
	var cart_col := Color(col.darkened(0.2), 0.95)
	var box_col := Color(0.82, 0.72, 0.52) # cardboard tan
	# Handle from the man's hands to the cart bed (drawn first, under the boxes).
	draw_line(Vector2(6.0, -4.0), Vector2(13.0, 3.0), cart_col, 3.0)
	# Cart bed + two wheels.
	draw_rect(Rect2(11.0, 6.0, 26.0, 5.0), cart_col)
	draw_circle(Vector2(16.0, 13.0), 3.0, Color(0.1, 0.1, 0.12))
	draw_circle(Vector2(32.0, 13.0), 3.0, Color(0.1, 0.1, 0.12))
	# Two stacked boxes with tape, sitting on the bed.
	for b in [Rect2(12.0, -8.0, 13.0, 14.0), Rect2(25.0, -2.0, 10.0, 8.0)]:
		draw_rect(b, box_col)
		draw_rect(b, Color(0.45, 0.35, 0.2, 0.9), false, 1.5)
		draw_line(Vector2(b.position.x, b.get_center().y),
				Vector2(b.end.x, b.get_center().y), Color(0.5, 0.4, 0.25, 0.85), 1.5)
