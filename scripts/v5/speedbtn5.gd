extends Control
## A compact speed toggle drawn as a PLAY (1x) or FAST-FORWARD (5x, two triangles) icon —
## rounded triangles on a rounded panel. Self-contained: draws itself, handles its own tap,
## and highlights when it is the active speed. Used by hud5 for the 1x / 5x picker.

signal tapped

enum Kind { PLAY, FF }
var kind := Kind.PLAY
var active := false
var accent := Color(0.42, 0.62, 0.88)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


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
	var fg := Color(0.10, 0.11, 0.14) if active else Color(0.82, 0.85, 0.92)
	if kind == Kind.PLAY:
		_tri(r, 0.36, 0.66, fg)
	else:
		_tri(r, 0.20, 0.50, fg)
		_tri(r, 0.50, 0.80, fg)


## A right-pointing rounded triangle spanning x in [x0f, x1f] of the control, vertically centred.
func _tri(r: Vector2, x0f: float, x1f: float, col: Color) -> void:
	var x0 := r.x * x0f
	var x1 := r.x * x1f
	var yh := r.y * 0.22
	var cy := r.y * 0.5
	var pts := PackedVector2Array([
			Vector2(x0, cy - yh), Vector2(x1, cy), Vector2(x0, cy + yh)])
	draw_colored_polygon(pts, col)
	for p in pts:
		draw_circle(p, 2.5, col)  # round the corners


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
