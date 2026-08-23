extends Control
## A compact speed toggle drawn as a PLAY (1x) or FAST-FORWARD (5x, two triangles) icon —
## rounded triangles on a rounded panel. Self-contained: draws itself, handles its own tap,
## and highlights when it is the active speed. Used by hud5 for the 1x / 5x picker.

signal tapped

const Ui5 := preload("res://scripts/v5/ui5.gd")
enum Kind { PLAY, FF }
var kind := Kind.PLAY
var active := false
var accent := Color(0.42, 0.62, 0.88)
var _arrow: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_arrow = Ui5.arrow_tex("e")  # the Kenney play triangle (FF = two of them)


func _gui_input(event: InputEvent) -> void:
	var hit: bool = (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if hit:
		tapped.emit()
		accept_event()


func set_active(a: bool) -> void:
	if active != a:
		active = a
		queue_redraw()


func _draw() -> void:
	var r := size
	var bg: Color = accent if active else Color(0.17, 0.18, 0.23)
	_rrect(Rect2(Vector2.ZERO, r), 10.0, bg)
	_rrect(Rect2(Vector2.ZERO, r), 10.0, Color(0, 0, 0, 0.35), false)
	var fg := Color(0.12, 0.13, 0.16) if active else Color(0.86, 0.89, 0.95)
	if _arrow == null:
		return
	# Kenney play triangle (arrow_basic_e), tinted. Play = one; fast-forward = two overlapping.
	var ah := r.y * 0.52
	var aw := ah * (float(_arrow.get_width()) / float(_arrow.get_height()))
	if kind == Kind.PLAY:
		_blit_arrow(Vector2(r.x * 0.5, r.y * 0.5), aw, ah, fg)
	else:
		_blit_arrow(Vector2(r.x * 0.37, r.y * 0.5), aw * 0.86, ah * 0.86, fg)
		_blit_arrow(Vector2(r.x * 0.63, r.y * 0.5), aw * 0.86, ah * 0.86, fg)


func _blit_arrow(c: Vector2, w: float, h: float, tint: Color) -> void:
	draw_texture_rect(_arrow, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false, tint)


## A filled or outlined rounded rectangle (corner discs + edge bars).
func _rrect(rect: Rect2, rad: float, col: Color, filled := true) -> void:
	if filled:
		draw_rect(Rect2(rect.position + Vector2(rad, 0), rect.size - Vector2(2 * rad, 0)), col)
		draw_rect(Rect2(rect.position + Vector2(0, rad), rect.size - Vector2(0, 2 * rad)), col)
		for c in [rect.position + Vector2(rad, rad),
				Vector2(rect.end.x - rad, rect.position.y + rad),
				Vector2(rect.position.x + rad, rect.end.y - rad),
				rect.end - Vector2(rad, rad)]:
			draw_circle(c, rad, col)
	else:
		draw_rect(rect.grow(-1.0), col, false, 2.0)
