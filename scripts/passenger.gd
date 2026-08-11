class_name Passenger
extends Node2D
## One passenger. Holds a planned path (Array of legs, see pathfind.gd) and a
## patience meter that drains ONLY while waiting. Types per the spec table:
## visitor / patient / gurney (2 slots) / emergency (dest always SURGERY,
## red pulsing). Visuals are all draw primitives.
##
## Logic time comes from game.tick() calls (respects game time_scale/pause);
## _process is visuals only.

var game = null # main.gd
var ptype := "visitor"
var origin := 0
var dest := 0
var slots := 1
var patience_max := 90.0
var patience := 90.0
var cur_floor := 0 # floor where currently waiting (or last boarded from)
var legs: Array = [] # remaining legs; legs[0] is the current one
var riding = null # Elevator while on board, else null
var no_path := false
var active := true
var vis_t := 0.0 # real-time clock for pulsing (runs even while paused)


func setup(g, t: String, o: int, d: int) -> void:
	game = g
	ptype = t
	origin = o
	dest = d
	cur_floor = o
	var info: Dictionary = Levels.PTYPES[t]
	slots = info.slots
	patience_max = info.patience
	patience = patience_max


## Game-time tick from main. Patience drains only while waiting.
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


func body_color() -> Color:
	match ptype:
		"visitor":
			return Color(0.35, 0.85, 0.45)
		"patient":
			return Color(0.35, 0.6, 0.95)
		"gurney":
			return Color(0.95, 0.6, 0.2)
		"emergency":
			return Color(0.95, 0.22, 0.18)
	return Color.WHITE


func _draw() -> void:
	var col := body_color()
	if ptype == "emergency":
		# Red pulse ring.
		var pr := 12.0 + 4.0 * sin(vis_t * 7.0)
		draw_circle(Vector2(0, -11.0), pr, Color(col, 0.35))
	if ptype == "gurney":
		draw_rect(Rect2(-17.0, -18.0, 34.0, 16.0), col)
		draw_rect(Rect2(-17.0, -18.0, 34.0, 16.0), Color(0, 0, 0, 0.55), false, 2.0)
		# Wheels.
		draw_circle(Vector2(-11.0, -2.0), 3.0, Color(0.2, 0.2, 0.2))
		draw_circle(Vector2(11.0, -2.0), 3.0, Color(0.2, 0.2, 0.2))
	else:
		draw_circle(Vector2(0, -11.0), 10.0, col)
		draw_arc(Vector2(0, -11.0), 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 2.0)
	# Destination floor number.
	draw_string(ThemeDB.fallback_font, Vector2(-6.0, -5.0), str(dest),
			HORIZONTAL_ALIGNMENT_CENTER, 14.0, 13, Color(0, 0, 0, 0.9))
	if riding == null:
		# Patience bar.
		var w := 28.0
		var top := -30.0
		var frac := clampf(patience / patience_max, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, top, w, 5.0), Color(0, 0, 0, 0.55))
		var bar_col := Color(0.35, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - frac)
		draw_rect(Rect2(-w / 2.0, top, w * frac, 5.0), bar_col)
		# "?" bubble when the network offers no path.
		if no_path:
			var by := -46.0
			draw_circle(Vector2(0, by), 11.0, Color(1, 1, 1, 0.92))
			draw_string(ThemeDB.fallback_font, Vector2(-5.0, by + 7.0), "?",
					HORIZONTAL_ALIGNMENT_CENTER, 14.0, 18, Color(0.1, 0.1, 0.1))
