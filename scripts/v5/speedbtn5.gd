extends Control
## The PLAY (1x) / FAST-FORWARD (5x) button. It is now the RUN trigger too: in PLAN a tap
## starts the run at its speed; in PLAYING a tap just switches speed. Drawn as a green "go"
## panel with a Kenney play triangle (FF = two). Three visual states:
##   enabled     - can be pressed (PLAN: plan is ready; PLAYING: always). Greyed when not.
##   active      - this is the CURRENT speed during a run (brighter).
##   highlighted - pulse+glow to invite a press (the demo, and any ready-to-run plan).

signal tapped

const Ui5 := preload("res://scripts/v5/ui5.gd")
enum Kind { PLAY, FF }
var kind := Kind.PLAY
var active := false
var enabled := true
var highlighted := false
var accent := Color(0.36, 0.78, 0.46)
var _arrow: Texture2D
var _glow := 0.0
var _pulse: Tween

const GREEN_ON := Color(0.38, 0.82, 0.49)   # current speed
const GREEN_OFF := Color(0.23, 0.45, 0.31)  # enabled, not current
const GREY := Color(0.16, 0.17, 0.21)       # disabled


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size * 0.5
	_arrow = Ui5.arrow_tex("e")


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
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


func set_enabled(e: bool) -> void:
	if enabled != e:
		enabled = e
		queue_redraw()


## Pulse + glow to draw the eye to this button (played by the ghost demo when a route is drawn,
## and whenever a real plan is ready to run).
func set_highlight(h: bool) -> void:
	if highlighted == h:
		return
	highlighted = h
	pivot_offset = size * 0.5
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	if h:
		_pulse = create_tween().set_loops()
		_pulse.tween_method(func(v: float):
			_glow = v
			var s := 1.0 + 0.10 * v
			scale = Vector2(s, s)
			queue_redraw(), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		_pulse.tween_method(func(v: float):
			_glow = v
			var s := 1.0 + 0.10 * v
			scale = Vector2(s, s)
			queue_redraw(), 1.0, 0.0, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		_glow = 0.0
		scale = Vector2.ONE
		queue_redraw()


func _draw() -> void:
	var r := size
	# Glow halo behind the panel (only when highlighted): an expanding, fading green ring.
	if highlighted and _glow > 0.001:
		var grow := 5.0 + 12.0 * _glow
		_rrect(Rect2(-Vector2(grow, grow), r + Vector2(grow, grow) * 2.0), 14.0,
				Color(0.45, 0.95, 0.55, (1.0 - _glow) * 0.55), false, 4.0)
	# highlighted forces the "pressable" green even while disabled — the demo lights up the play
	# button to teach the gesture before the player has actually drawn a runnable plan.
	var bg := GREY
	if active or highlighted:
		bg = GREEN_ON
	elif enabled:
		bg = GREEN_OFF
	_rrect(Rect2(Vector2.ZERO, r), 12.0, bg)
	_rrect(Rect2(Vector2.ZERO, r), 12.0, Color(0, 0, 0, 0.30), false, 2.0)
	if _arrow == null:
		return
	var fg := Color(0.82, 0.95, 0.86)
	if active or highlighted:
		fg = Color(0.10, 0.16, 0.11)
	elif not enabled:
		fg = Color(0.5, 0.52, 0.56)
	var ah := r.y * 0.50
	var aw := ah * (float(_arrow.get_width()) / float(_arrow.get_height()))
	if kind == Kind.PLAY:
		_blit_arrow(Vector2(r.x * 0.52, r.y * 0.5), aw, ah, fg)
	else:
		_blit_arrow(Vector2(r.x * 0.38, r.y * 0.5), aw * 0.82, ah * 0.82, fg)
		_blit_arrow(Vector2(r.x * 0.64, r.y * 0.5), aw * 0.82, ah * 0.82, fg)


func _blit_arrow(c: Vector2, w: float, h: float, tint: Color) -> void:
	draw_texture_rect(_arrow, Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), false, tint)


## A filled or outlined rounded rectangle (corner discs + edge bars).
func _rrect(rect: Rect2, rad: float, col: Color, filled := true, w := 2.0) -> void:
	if filled:
		draw_rect(Rect2(rect.position + Vector2(rad, 0), rect.size - Vector2(2 * rad, 0)), col)
		draw_rect(Rect2(rect.position + Vector2(0, rad), rect.size - Vector2(0, 2 * rad)), col)
		for c in [rect.position + Vector2(rad, rad),
				Vector2(rect.end.x - rad, rect.position.y + rad),
				Vector2(rect.position.x + rad, rect.end.y - rad),
				rect.end - Vector2(rad, rad)]:
			draw_circle(c, rad, col)
	else:
		draw_rect(rect.grow(-1.0), col, false, w)
