extends Control
## A ghost-hand tutorial demo (textless): a translucent fingertip taps a lift chip, then
## drags a route through the building — one lift at a time — teaching tap -> draw -> repeat
## (and, on later tutorials, two lifts / a shared dock) purely by SHOWING. It's a cutscene
## overlay drawn over the (empty) board; when it ends it fades and hands control back and the
## player draws for real. Tap anywhere to skip. Nothing here touches the sim.

signal done

var _steps: Array = []      # [{color:Color, chip:Vector2, pts:Array[Vector2]}] (screen space)
var _routes: Array = []     # [{color, pts, rev:float}] — revealed progressively as it "draws"
var _finger := Vector2(-200, -200)
var _ripple_at := Vector2.ZERO
var _ripple := 0.0          # 0..1 expanding tap ring (0 = none)
var _active := false
var _tw: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## `steps`: one per lift to demonstrate, in order. Plays a chained cutscene that LOOPS (so the
## player can watch it as many times as they like); a tap anywhere stops it and hands over.
func play(steps: Array) -> void:
	_steps = steps
	_routes = []
	for s in steps:
		_routes.append({"color": s.color, "pts": s.pts, "rev": 0.0})
	if steps.is_empty() or (steps[0].pts as Array).is_empty():
		_finish(); return
	_finger = steps[0].chip
	_active = true
	modulate.a = 1.0
	_tw = create_tween().set_loops()   # ambient loop until the player taps to take over
	_tw.tween_callback(_reset_loop)
	_tw.tween_interval(0.5)
	for si in steps.size():
		var s: Dictionary = steps[si]
		_tw.tween_property(self, "_finger", s.chip, 0.72).set_trans(Tween.TRANS_SINE)   # to chip
		_tw.tween_callback(_do_ripple.bind(s.chip))                                     # tap
		_tw.tween_interval(0.55)
		_tw.tween_property(self, "_finger", s.pts[0], 0.72).set_trans(Tween.TRANS_SINE) # to start
		_tw.tween_callback(_do_ripple.bind(s.pts[0]))                                   # press
		_tw.tween_interval(0.22)
		var dur: float = clampf(0.19 * s.pts.size(), 0.85, 2.8)
		_tw.tween_method(_drag.bind(si), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)     # drag
		_tw.tween_callback(_do_ripple.bind(s.pts[s.pts.size() - 1]))                    # release
		_tw.tween_interval(0.7)
	_tw.tween_interval(1.3)   # hold the finished plan, then the loop restarts


## Clear the revealed routes + reset the finger so each loop redraws from scratch.
func _reset_loop() -> void:
	for r in _routes:
		r.rev = 0.0
	_finger = _steps[0].chip


func _drag(t: float, si: int) -> void:
	_routes[si].rev = t
	_finger = _point_at(_steps[si].pts, t)


func _do_ripple(at: Vector2) -> void:
	_ripple_at = at
	var rt := create_tween()
	rt.tween_method(func(v): _ripple = v, 0.001, 1.0, 0.4)
	rt.tween_callback(func(): _ripple = 0.0)


func _process(_dt: float) -> void:
	if _active:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _active and ((event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed)):
		accept_event()
		_finish()


func _finish() -> void:
	if not _active and _tw == null:
		return
	_active = false
	if _tw != null and _tw.is_running():
		_tw.kill()
	_tw = null
	done.emit()
	queue_free()


## Point at `frac` (0..1) of a polyline's total arc length.
func _point_at(pts: Array, frac: float) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var target := frac * total
	var acc := 0.0
	for i in pts.size() - 1:
		var seg: float = pts[i].distance_to(pts[i + 1])
		if acc + seg >= target:
			return pts[i].lerp(pts[i + 1], (target - acc) / maxf(seg, 0.001))
		acc += seg
	return pts[pts.size() - 1]


func _draw() -> void:
	# Revealed route lines (a completed lift stays full; the current one grows as it "draws").
	for r in _routes:
		if float(r.rev) <= 0.001:
			continue
		var pts: Array = r.pts
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		var target: float = float(r.rev) * total
		var line := PackedVector2Array([pts[0]])
		var acc := 0.0
		for i in pts.size() - 1:
			var seg: float = pts[i].distance_to(pts[i + 1])
			if acc + seg >= target:
				line.append(pts[i].lerp(pts[i + 1], (target - acc) / maxf(seg, 0.001)))
				break
			line.append(pts[i + 1])
			acc += seg
		if line.size() >= 2:
			draw_polyline(line, Color(r.color, 0.8), 7.0, true)
	# Tap ripple + fingertip (a big, soft "hand" so it reads clearly at a glance).
	if _ripple > 0.001:
		draw_arc(_ripple_at, 12.0 + 48.0 * _ripple, 0.0, TAU, 32,
				Color(1, 1, 1, (1.0 - _ripple) * 0.6), 4.0)
	draw_circle(_finger, 34.0, Color(1, 1, 1, 0.12))
	draw_circle(_finger, 21.0, Color(0.95, 0.97, 1.0, 0.90))
	draw_arc(_finger, 21.0, 0.0, TAU, 28, Color(0.2, 0.3, 0.45, 0.65), 3.0)
