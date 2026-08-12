class_name Passenger3
extends Node2D
## One v3 passenger. Spawns at a room cell, wants another room cell; holds a
## planned path (Array of legs, see pathfind3.gd) and a patience meter that
## drains ONLY while waiting. Types: visitor (green, 90 s), patient (blue,
## 75 s) and exec (amber, 40 s, briefcase tick - spawns only at
## level-designated origin rooms, wants only level-designated targets).
## Shows its destination room letter, and a "?" bubble while the network
## offers no path.
##
## Logic time comes from game tick() calls; _process is visuals only.

## WIDTH (v4 phase 2) is the one number that says how much doorway a party
## needs. It is BOTH the boarding rule (a party may board only a car at least
## that wide) and the capacity cost (a car's capacity is counted in
## width-units), so "who can carry this" and "how many fit" never drift apart.
## A width-2 party is ONE party: a couple boards together or not at all, and a
## delivery's crate cannot be left on the landing. That is what makes width a
## real constraint rather than a second capacity number.
const PTYPES := {
	"visitor": {"width": 1, "patience": 90.0, "color": Color(0.35, 0.85, 0.45)},
	"patient": {"width": 1, "patience": 75.0, "color": Color(0.35, 0.6, 0.95)},
	"exec": {"width": 1, "patience": 40.0, "color": Color(0.97, 0.72, 0.22)},
	"couple": {"width": 2, "patience": 85.0, "color": Color(0.88, 0.45, 0.72)},
	"gurney": {"width": 2, "patience": 70.0, "color": Color(0.72, 0.88, 0.96)},
	"delivery": {"width": 2, "patience": 110.0, "color": Color(0.85, 0.62, 0.30)},
	"big delivery": {"width": 3, "patience": 120.0, "color": Color(0.72, 0.47, 0.22)},
}

var game = null # main3.gd
var ptype := "visitor"
var origin_cell := Vector2i.ZERO
var dest_cell := Vector2i.ZERO
var width := 1 # doorway units: boarding rule AND capacity cost
var patience_max := 90.0
var patience := 90.0
var cur_cell := Vector2i.ZERO # room where currently waiting (or last boarded)
var legs: Array = [] # remaining legs; legs[0] is the current one
var riding = null # Car3 while on board, else null
var no_path := false
var active := true
var vis_t := 0.0
var wait_time := 0.0 # total game-seconds spent waiting (stats/harness)
var rides := 0 # boardings so far; rides - 1 = transfers (stats/harness)
var salt := 0.0 # per-passenger pathfinding tie-break (set from game rng)


func setup(g, t: String, o: Vector2i, d: Vector2i) -> void:
	game = g
	ptype = t
	origin_cell = o
	dest_cell = d
	cur_cell = o
	var info: Dictionary = PTYPES[t]
	width = int(info.width)
	patience_max = info.patience
	# Levels may tune per-type patience ({"patience": {"exec": 24.0}, ...}).
	if game.level is Dictionary and game.level.has("patience"):
		patience_max = game.level.patience.get(t, patience_max)
	patience = patience_max


## Game-time tick from main3. Patience drains only while waiting.
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


## How many px wide this party draws: 20 for one person, 44 for a pair, 68 for
## a courier with two crates. WIDTH IS THE SILHOUETTE - at phone size you read
## "that will not fit in the pod" from the shape alone, before any icon.
func body_w() -> float:
	return 20.0 + 24.0 * (width - 1)


func _draw() -> void:
	var col: Color = PTYPES[ptype].color
	var hw := body_w() / 2.0
	var dark := Color(0, 0, 0, 0.45)
	if width == 1:
		draw_circle(Vector2.ZERO, 10.0, col)
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, dark, 2.0)
	else:
		# A wide party is drawn as ONE body the full width it needs, so the
		# doorway it takes is literal rather than implied.
		draw_rect(Rect2(-hw, -10.0, hw * 2.0, 20.0), col)
		draw_rect(Rect2(-hw, -10.0, hw * 2.0, 20.0), dark, false, 2.0)
	match ptype:
		"exec":
			# Amber ring + tiny briefcase tick below: the hasty penthouse guys.
			draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color(col, 0.9), 2.0)
			draw_rect(Rect2(-5.0, 11.0, 10.0, 6.0), Color(0.25, 0.16, 0.05))
			draw_rect(Rect2(-2.0, 9.0, 4.0, 2.0), Color(0.25, 0.16, 0.05))
		"couple":
			# Two heads that never travel apart.
			for s in [-11.0, 11.0]:
				draw_circle(Vector2(s, 0.0), 7.0, Color(1, 1, 1, 0.85))
				draw_arc(Vector2(s, 0.0), 7.0, 0.0, TAU, 16, dark, 1.5)
		"gurney":
			# A trolley: bed rail plus a head, seen from above.
			draw_rect(Rect2(-hw + 4.0, -3.0, hw * 2.0 - 8.0, 6.0),
					Color(0.98, 0.98, 1.0, 0.9))
			draw_circle(Vector2(-hw + 9.0, 0.0), 6.0, Color(0.35, 0.6, 0.95))
			for s in [-hw + 6.0, hw - 10.0]:
				draw_circle(Vector2(s, 8.0), 3.0, Color(0.15, 0.15, 0.18))
		"delivery", "big delivery":
			# Courier at the left, then one crate per extra width unit.
			draw_circle(Vector2(-hw + 9.0, 0.0), 7.0, Color(1, 1, 1, 0.85))
			draw_arc(Vector2(-hw + 9.0, 0.0), 7.0, 0.0, TAU, 16, dark, 1.5)
			for k in width - 1:
				var bx := -hw + 20.0 + k * 24.0
				draw_rect(Rect2(bx, -8.0, 20.0, 16.0), Color(0.45, 0.31, 0.15))
				draw_rect(Rect2(bx, -8.0, 20.0, 16.0), Color(0.95, 0.85, 0.6, 0.7),
						false, 2.0)
				draw_line(Vector2(bx + 10.0, -8.0), Vector2(bx + 10.0, 8.0),
						Color(0.95, 0.85, 0.6, 0.5), 2.0)
	# Destination room letter (on a light chip when the body underneath it is
	# busy with crates or heads).
	# A couple's middle is bare body; a delivery's middle is a crate.
	var lp := Vector2.ZERO if width == 1 or ptype == "couple" \
			else Vector2(hw - 9.0, 0.0)
	if width > 1 and ptype != "couple":
		draw_rect(Rect2(lp - Vector2(8.0, 9.0), Vector2(16.0, 18.0)),
				Color(1, 1, 1, 0.88))
	draw_string(ThemeDB.fallback_font, lp + Vector2(-5.0, 5.0),
			Grid3.room_letter(dest_cell),
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 12, Color(0, 0, 0, 0.9))
	if riding == null:
		# Patience bar, as wide as the party is.
		var w := maxf(26.0, body_w())
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
