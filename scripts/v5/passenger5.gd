class_name Passenger5
extends Node2D
## One v5 passenger. Spawns INSIDE a room (origin), wants another ROOM (dest),
## and waits rendered inside its current room. Holds a planned path (Array of
## legs, see pathfind5.gd) and a patience meter that drains only while waiting.
## Adapted from scripts/v3/passenger3.gd; the destination shown is a room letter.
##
## WALK TIME (v5.1). Boarding and alighting are no longer instant hops. Getting a
## plan starts a BOARD walk from the room's anchor cell to the leg's boarding
## dock; only when that walk finishes is the passenger `at_dock` (boardable). If the
## car's doors close before they arrive, they simply catch the next stop (like v4
## late arrivals). Alighting starts an ALIGHT walk from the dock back to the
## room's anchor; only when it finishes are they served (or replanned for a
## transfer). Walk duration = Manhattan tiles * Grid5.WALK_PER_TILE, the exact
## cost Pathfind5 prices — no collision, no congestion, fully deterministic.
##
## The figure TWEENS along the walk for legibility: `_process` reads the logical
## walk progress (`walk_left`) and interpolates position. That is VISUAL ONLY and
## never writes back into the sim, so a headless run (where _process is off) is
## bit-identical to a windowed one.

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
var no_path := false
var active := true
var vis_t := 0.0
var wait_time := 0.0
var rides := 0
var salt := 0.0

# Walk state (sim). walk_left > 0 => currently walking; walk_alight tells the
# completion handler whether this was a board walk (-> at_dock) or an alight walk
# (-> served / transfer). at_dock => board walk done, standing at the dock.
var walk_left := 0.0
var walk_total := 0.0
var walk_alight := false
var at_dock := false
# Visual endpoints (logical px) for the tween — read by _process only.
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


func tick(dt: float) -> void:
	if not active:
		return
	if riding != null:
		return # aboard: no walk, no patience drain
	# Not aboard: patience drains whether idling, walking, or waiting at the dock.
	patience -= dt
	wait_time += dt
	if walk_left > 0.0:
		walk_left -= dt
		if walk_left <= 0.0:
			walk_left = 0.0
			_on_walk_done()
	if patience <= 0.0 and active:
		active = false
		game.on_expired(self)


## Begin the board walk: room anchor -> the current leg's boarding dock. The tile
## distance is what delays boarding; the figure slides toward the car meanwhile.
func start_board_walk() -> void:
	at_dock = false
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
	walk_from = Grid5.cell_center(anchor)
	walk_to = Grid5.cell_center(board)
	if walk_left <= 0.0:
		walk_left = 0.0
		_on_walk_done()


## Begin the alight walk: the alighting dock -> the room's anchor. Only when it
## finishes is the passenger served (or replanned onto the next leg).
func start_alight_walk(alight_cell: Vector2i, room: int) -> void:
	riding = null
	at_dock = false
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
	else:
		at_dock = true # standing at the dock, now boardable


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
	elif walk_left > 0.0 and walk_total > 0.0:
		var f := clampf(1.0 - walk_left / walk_total, 0.0, 1.0)
		position = walk_from.lerp(walk_to, f)
	queue_redraw()


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
