extends Control
## An animated row of result stars (Overcooked-style): grey slots that fill with a gold
## pop, one at a time, using the Kenney star sprites. `pop(i)` animates slot i filling; the
## victory overlay sequences the pops.

const Ui5 := preload("res://scripts/v5/ui5.gd")
const ASPECT := 60.0 / 64.0   # Kenney star.png is 64x60

var slots := 3
var perfect := false        # true = topped the range: the filled stars are BLUE (no 4th star)
var _fill: Array = []       # per-slot gold scale, 0 = empty, ~1 = filled (animated)
var star_px := 84.0
var gap := 18.0
var _empty: Texture2D
var _full: Texture2D
var _blue: Texture2D


func setup(count := 3, px := 84.0, perfect_v := false) -> void:
	slots = count
	star_px = px
	perfect = perfect_v
	_empty = Ui5.star_tex(false)
	_full = Ui5.star_tex(true)
	_blue = Ui5.star_blue_tex()
	_fill = []
	for i in slots:
		_fill.append(0.0)
	custom_minimum_size = Vector2((star_px + gap) * slots - gap, star_px * ASPECT)
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
	return Vector2(i * (star_px + gap) + star_px * 0.5, star_px * ASPECT * 0.5)


func _blit(c: Vector2, scale: float, t: Texture2D) -> void:
	if t == null or scale <= 0.01:
		return
	var w := star_px * scale
	var h := star_px * ASPECT * scale
	draw_texture_rect(t, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false)


func _draw() -> void:
	var fill_tex: Texture2D = _blue if perfect else _full
	for i in slots:
		_blit(_center(i), 1.0, _empty)
	for i in slots:
		if _fill[i] > 0.01:
			_blit(_center(i), _fill[i], fill_tex)
