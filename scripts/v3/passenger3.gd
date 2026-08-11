class_name Passenger3
extends Node2D
## One v3 passenger. Spawns at a room cell, wants another room cell; holds a
## planned path (Array of legs, see pathfind3.gd) and a patience meter that
## drains ONLY while waiting. Two types: visitor (green, 90 s) and patient
## (blue, 75 s), both 1 slot. Shows its destination room letter, and a "?"
## bubble while the network offers no path.
##
## Logic time comes from game tick() calls; _process is visuals only.

const PTYPES := {
	"visitor": {"slots": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"slots": 1, "patience": 75.0, "color": Color(0.35, 0.6, 0.95)},
}

var game = null # main3.gd
var ptype := "visitor"
var origin_cell := Vector2i.ZERO
var dest_cell := Vector2i.ZERO
var slots := 1
var patience_max := 90.0
var patience := 90.0
var cur_cell := Vector2i.ZERO # room where currently waiting (or last boarded)
var legs: Array = [] # remaining legs; legs[0] is the current one
var riding = null # Car3 while on board, else null
var no_path := false
var active := true
var vis_t := 0.0


func setup(g, t: String, o: Vector2i, d: Vector2i) -> void:
	game = g
	ptype = t
	origin_cell = o
	dest_cell = d
	cur_cell = o
	var info: Dictionary = PTYPES[t]
	slots = info.slots
	patience_max = info.patience
	patience = patience_max


## Game-time tick from main3. Patience drains only while waiting.
func tick(dt: float) -> void:
	if not active:
		return
	if riding == null:
		patience -= dt
		if patience <= 0.0:
			active = false
			game.on_expired(self)


func _process(delta: float) -> void:
	vis_t += delta
	if riding != null:
		position = riding.slot_position(self)
	queue_redraw()


func _draw() -> void:
	var col: Color = PTYPES[ptype].color
	draw_circle(Vector2.ZERO, 10.0, col)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 2.0)
	# Destination room letter.
	draw_string(ThemeDB.fallback_font, Vector2(-5.0, 5.0),
			Grid3.room_letter(dest_cell),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, Color(0, 0, 0, 0.9))
	if riding == null:
		# Patience bar.
		var w := 26.0
		var top := -20.0
		var frac := clampf(patience / patience_max, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, top, w, 4.0), Color(0, 0, 0, 0.55))
		var bar_col := Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac)
		draw_rect(Rect2(-w / 2.0, top, w * frac, 4.0), bar_col)
		# "?" bubble when the network offers no path.
		if no_path:
			var by := -34.0
			draw_circle(Vector2(0, by), 10.0, Color(1, 1, 1, 0.92))
			draw_string(ThemeDB.fallback_font, Vector2(-4.0, by + 6.0), "?",
					HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16, Color(0.1, 0.1, 0.1))
