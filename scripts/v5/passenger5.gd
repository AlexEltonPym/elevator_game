class_name Passenger5
extends Node2D
## One v5 passenger. Spawns INSIDE a room (origin), wants another ROOM (dest),
## and waits rendered inside its current room. Holds a planned path (Array of
## legs, see pathfind5.gd) and a patience meter that drains only while waiting.
## Adapted from scripts/v3/passenger3.gd; the destination shown is a room
## letter, and boarding is a near-free in-room walk (no pedestrian sim).

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
	if riding == null:
		patience -= dt
		wait_time += dt
		if patience <= 0.0:
			active = false
			game.on_expired(self)


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
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
