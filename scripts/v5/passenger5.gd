class_name Passenger5
extends Node2D
## One v5 passenger. Spawns INSIDE a room (origin), wants another ROOM (dest),
## and waits rendered inside its current room. Holds a planned path (Array of
## legs, see pathfind5.gd) and a patience meter that drains only while it is
## waiting in the room. Adapted from scripts/v3/passenger3.gd.
##
## WALK TIME (v5.1). A waiting passenger stays at its in-room tile. It does NOT
## pre-walk to the dock. Only when the elevator it wants STOPS at the adjacent
## dock and opens its doors with space does the car ASSIGN the passenger, at which
## point it walks (orthogonally) from its tile to the dock and boards on arrival.
## The car holds the doors open long enough to cover its boarders' walks (see
## car5._assign_boarders). Alighting: the rider steps off onto the dock at door
## open, then walks dock->room and is served / replanned on arrival; the car does
## NOT wait for alighters. Walk duration = Manhattan tiles * Grid5.WALK_PER_TILE,
## the exact cost Pathfind5 prices; the board walk now lands inside the (extended)
## door exchange, so it is additive to journey time just as the planner assumes.
##
## The figure walks a right-angle TILE path (X axis then Y axis), never a diagonal
## lerp — `_process` reads the logical progress (`walk_left`) and places the figure
## along that orthogonal path. Visual only; it never writes back into the sim, so
## a headless run (where _process is off) is bit-identical to a windowed one.

const PTYPES := {
	"visitor": {"width": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"width": 1, "patience": 78.0, "color": Color(0.35, 0.6, 0.95)},
	"shopper": {"width": 1, "patience": 95.0, "color": Color(0.9, 0.6, 0.35)},
}

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
var boarding_car = null # Car5 that has assigned this passenger to board this stop
var no_path := false
var active := true
var vis_t := 0.0
var wait_time := 0.0
var rides := 0
var salt := 0.0

# Walk state (sim). walk_left > 0 => currently walking; walk_alight tells the
# completion handler whether this was a board walk (-> board the car) or an alight
# walk (-> served / transfer).
var walk_left := 0.0
var walk_total := 0.0
var walk_alight := false
# Visual endpoints (logical px) for the orthogonal tween — read by _process only.
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


## Waiting in the room with a plan, not yet walking or assigned: a boarder a
## stopped car may pick up. Patience drains only in this state.
func is_waiting_to_board() -> bool:
	return active and riding == null and boarding_car == null \
			and walk_left <= 0.0 and not legs.is_empty()


func tick(dt: float) -> void:
	if not active:
		return
	if riding != null:
		return # aboard: no walk, no patience drain
	var pure_wait := boarding_car == null and walk_left <= 0.0
	wait_time += dt
	if walk_left > 0.0:
		walk_left -= dt
		if walk_left <= 0.0:
			walk_left = 0.0
			_on_walk_done()
	elif pure_wait:
		patience -= dt
		if patience <= 0.0 and active:
			active = false
			game.on_expired(self)


## Begin the board walk (called by the car that assigned this passenger): from
## the passenger's in-room tile to the current leg's boarding dock. The duration
## is the tile distance the car must hold its doors for.
func start_board_walk() -> void:
	walk_alight = false
	if legs.is_empty():
		walk_left = 0.0
		walk_total = 0.0
		return
	var board: Vector2i = legs[0].board_cell
	var anchor := Grid5.room_anchor(cur_room)
	var tiles := Grid5.manhattan(anchor, board)
	walk_total = tiles * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = position # wherever it was standing in the room
	walk_to = Grid5.cell_center(board)
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


## Begin the alight walk: the alighting dock -> the room's anchor. Only when it
## finishes is the passenger served (or replanned onto the next leg).
func start_alight_walk(alight_cell: Vector2i, room: int) -> void:
	riding = null
	boarding_car = null
	walk_alight = true
	cur_room = room
	var anchor := Grid5.room_anchor(room)
	var tiles := Grid5.manhattan(alight_cell, anchor)
	walk_total = tiles * Grid5.WALK_PER_TILE
	walk_left = walk_total
	walk_from = Grid5.cell_center(alight_cell)
	walk_to = Grid5.cell_center(anchor)
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


func _on_walk_done() -> void:
	if walk_alight:
		game.finish_alight(self)
	elif boarding_car != null:
		boarding_car._board_arrived(self)


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
	elif walk_left > 0.0 and walk_total > 0.0:
		var f := clampf(1.0 - walk_left / walk_total, 0.0, 1.0)
		position = _ortho_point(walk_from, walk_to, f)
	queue_redraw()


## Right-angle path from a to b: cover the X axis first, then the Y axis, at a
## constant pace over the whole Manhattan length. Deterministic axis order.
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
