extends Control
## Compact result-star medals for the level-select tiles, using the Kenney star sprites.
## `earned` fills that many of 3 stars; topping the range (earned == 4) shows a small gold
## crown star above the row (matching the end-of-shift PERFECT! stamp), not a 4th star.

const Ui5 := preload("res://scripts/v5/ui5.gd")
const ASPECT := 60.0 / 64.0

var slots := 3
var earned := 0       # 0..3 stars; 4 == PERFECT (crown mark)
var star_px := 44.0
var gap := 8.0
var _empty: Texture2D
var _full: Texture2D


func setup(earned_v: int, px := 44.0, slots_v := 3) -> void:
	earned = clampi(earned_v, 0, slots_v + 1)
	slots = slots_v
	star_px = px
	_empty = Ui5.star_tex(false)
	_full = Ui5.star_tex(true)
	var top: float = star_px * 0.4 if earned > slots else 0.0
	custom_minimum_size = Vector2((star_px + gap) * slots - gap, star_px * ASPECT + top)
	queue_redraw()


func _blit(c: Vector2, px: float, t: Texture2D) -> void:
	if t == null:
		return
	var w := px
	var h := px * ASPECT
	draw_texture_rect(t, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false)


func _draw() -> void:
	var perfect: bool = earned > slots
	var top: float = star_px * 0.4 if perfect else 0.0
	var filled: int = mini(earned, slots)
	for i in slots:
		var c := Vector2(i * (star_px + gap) + star_px * 0.5, top + star_px * ASPECT * 0.5)
		_blit(c, star_px, _full if i < filled else _empty)
	if perfect:
		var cx: float = ((star_px + gap) * slots - gap) * 0.5
		_blit(Vector2(cx, star_px * 0.28), star_px * 0.6, _full)
