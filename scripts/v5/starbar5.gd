extends Control
## A compact row of result stars for the level-select tiles, drawn as polygons (no art
## dependency). `earned` fills that many of 3 gold stars. Topping the range (earned == 4,
## the old secret tier) is now shown as a small gold "PERFECT" crown mark above the row,
## not a 4th star — matching the end-of-shift PERFECT! stamp.

var slots := 3
var earned := 0       # 0..3 stars; 4 == PERFECT (crown mark)
var star_px := 44.0
var gap := 12.0

const COL_ON := Color(1.0, 0.82, 0.25)
const COL_OFF := Color(1.0, 1.0, 1.0, 0.15)
const COL_CROWN := Color(1.0, 0.85, 0.3)
const COL_EDGE := Color(0.0, 0.0, 0.0, 0.55)


func setup(earned_v: int, px := 44.0, slots_v := 3) -> void:
	earned = clampi(earned_v, 0, slots_v + 1)
	slots = slots_v
	star_px = px
	var top: float = star_px * 0.34 if earned > slots else 0.0
	custom_minimum_size = Vector2((star_px + gap) * slots - gap, star_px + top)
	queue_redraw()


func _draw() -> void:
	var perfect: bool = earned > slots
	var top: float = star_px * 0.34 if perfect else 0.0
	var filled: int = mini(earned, slots)
	for i in slots:
		_star(Vector2(i * (star_px + gap) + star_px * 0.5, top + star_px * 0.5),
				star_px * 0.5, COL_ON if i < filled else COL_OFF)
	if perfect:
		# a small crown star centred above the row = topped the range (PERFECT).
		var cx: float = ((star_px + gap) * slots - gap) * 0.5
		_star(Vector2(cx, star_px * 0.28), star_px * 0.28, COL_CROWN)


func _star(c: Vector2, r: float, fill: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2.0 + float(k) * PI / 5.0
		var rr: float = r if k % 2 == 0 else r * 0.44
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, COL_EDGE, 2.0, true)
