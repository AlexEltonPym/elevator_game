extends Control
## An animated row of result stars (Overcooked-style): three dim slots that fill with a
## gold pop, one at a time. Drawn as polygons so there's no art dependency; if a Kenney
## star sprite is dropped in later, swap `_star()` for a TextureRect per slot. `pop(i)`
## animates slot i filling; the victory overlay sequences the pops.

var slots := 3
var _fill: Array = []       # per-slot gold scale, 0 = empty, ~1 = filled (animated)
var star_px := 84.0
var gap := 22.0

const COL_ON := Color(1.0, 0.82, 0.25)
const COL_ON_EDGE := Color(0.75, 0.5, 0.08)
const COL_OFF := Color(1.0, 1.0, 1.0, 0.13)
const COL_OFF_EDGE := Color(1.0, 1.0, 1.0, 0.22)


func setup(count := 3, px := 84.0) -> void:
	slots = count
	star_px = px
	_fill = []
	for i in slots:
		_fill.append(0.0)
	custom_minimum_size = Vector2((star_px + gap) * slots - gap, star_px * 1.15)
	queue_redraw()


## Animate slot i filling in with a bounce. Returns the tween (so callers can await it).
func pop(i: int) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(v): _fill[i] = v; queue_redraw(), 0.0, 1.28, 0.16) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v): _fill[i] = v; queue_redraw(), 1.28, 1.0, 0.12) \
			.set_trans(Tween.TRANS_SINE)
	return tw


func _center(i: int) -> Vector2:
	return Vector2(i * (star_px + gap) + star_px * 0.5, star_px * 0.62)


func _draw() -> void:
	# dim empty bases first, then the gold fills on top.
	for i in slots:
		_star(_center(i), star_px * 0.5, COL_OFF, COL_OFF_EDGE)
	for i in slots:
		if _fill[i] > 0.01:
			_star(_center(i), star_px * 0.5 * _fill[i], COL_ON, COL_ON_EDGE)


func _star(c: Vector2, r: float, fill: Color, edge: Color) -> void:
	if r <= 0.5:
		return
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI / 2.0 + float(k) * PI / 5.0
		var rr: float = r if k % 2 == 0 else r * 0.44
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, edge, maxf(2.0, r * 0.06), true)
