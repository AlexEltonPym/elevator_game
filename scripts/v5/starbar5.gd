extends Control
## A row of Overcooked-style stars, drawn as polygons (no font glyph dependency).
## `earned` fills that many of `slots` gold stars; a 4th SECRET star (the optimal
## tier) only appears once earned, drawn in a distinct colour — it never shows as an
## empty slot, so its existence stays hidden until you hit it. Used on the result
## overlay and the level-select buttons.

var slots := 3        # visible normal star slots (1..3 = the reasonable-solution range)
var earned := 0       # 0..4; 4 == the secret optimal star
var star_px := 44.0
var gap := 12.0

const COL_ON := Color(1.0, 0.82, 0.25)
const COL_OFF := Color(1.0, 1.0, 1.0, 0.15)
const COL_SECRET := Color(1.0, 0.42, 0.85)
const COL_EDGE := Color(0.0, 0.0, 0.0, 0.55)


func setup(earned_v: int, px := 44.0, slots_v := 3) -> void:
	earned = clampi(earned_v, 0, slots_v + 1)
	slots = slots_v
	star_px = px
	var shown: int = slots + (1 if earned > slots else 0)
	custom_minimum_size = Vector2((star_px + gap) * shown - gap, star_px)
	queue_redraw()


func _draw() -> void:
	for i in slots:
		_star(i, COL_ON if i < earned else COL_OFF)
	if earned > slots:
		_star(slots, COL_SECRET)


func _star(idx: int, fill: Color) -> void:
	var c := Vector2(idx * (star_px + gap) + star_px * 0.5, star_px * 0.5)
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2.0 + float(k) * PI / 5.0
		var r: float = star_px * (0.5 if k % 2 == 0 else 0.22)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, COL_EDGE, 2.0, true)
