extends Control
## Interactive tutorial hint overlay. It does NOT auto-play a whole plan; the hud drives it
## from the player's real progress (see hud5._update_demo):
##   FULL - nothing picked yet: finger taps the lift chip THEN drags out its route (the whole
##          "click lift -> drag out lift" gesture), looping.
##   DRAW - a lift is selected: finger only drags out that lift's route (no chip tap).
##   IDLE - hidden (a lift connects A->B; the glowing play button takes over).
## It stays reactive the whole PLAN phase: clearing / deselecting returns it to the right stage.
## Non-blocking: the player taps/drags the real UI underneath the whole time.

var _mode := "idle"          # current cycle: "full" | "draw" | "idle"
var _chip := Vector2.ZERO
var _pts: Array = []
var _color := Color(1, 1, 1)
var _want = null             # {mode, chip, pts, color, key} desired next; picked up at boundaries
var _running := false
var _finger := Vector2(-500, -500)
var _rev := 0.0              # 0..1 draw reveal
var _ripple_at := Vector2.ZERO
var _ripple := 0.0
var _spin := 0.0
var _tw: Tween

const R := 40.0              # fingertip ring radius (2x the old 20)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # pass input through to the real UI


## FULL: tap the chip, then drag out the route (whole gesture). Used when no lift is picked yet.
func guide_full(chip: Vector2, pts: Array, color: Color) -> void:
	_want_cycle("full", chip, pts, color,
			"full:%d,%d:%d" % [int(chip.x), int(chip.y), pts.size()])


## DRAW: only drag out the route (no chip tap). Used once the player has selected the lift.
func guide_draw(pts: Array, color: Color) -> void:
	if pts.is_empty():
		guide_idle(); return
	_want_cycle("draw", Vector2.ZERO, pts, color,
			"draw:%d:%d,%d" % [pts.size(), int(pts[0].x), int(pts[0].y)])


## Request a mode/route. The change is NOT applied mid-stroke: the running cycle finishes, then
## the next cycle picks up this request. So tapping the lift while the finger is drawing the same
## line just drops the chip-tap next loop — it never teleports or restarts.
func _want_cycle(mode: String, chip: Vector2, pts: Array, color: Color, key: String) -> void:
	if pts.is_empty():
		guide_idle(); return
	if _want != null and _want.key == key:
		return
	_want = {"mode": mode, "chip": chip, "pts": pts, "color": color, "key": key}
	if not _running:
		_begin_cycle()


func guide_idle() -> void:
	_want = null
	if _mode == "idle" and not _running:
		return
	_mode = "idle"
	_running = false
	if _tw != null:
		_tw.kill(); _tw = null
	_finger = Vector2(-500, -500)
	_rev = 0.0
	queue_redraw()


## Start the next animation cycle from the latest request (called at each loop boundary).
func _begin_cycle() -> void:
	if _want == null:
		_running = false
		guide_idle()
		return
	_mode = _want.mode; _chip = _want.chip; _pts = _want.pts; _color = _want.color
	_running = true
	# Reset the reveal SYNCHRONOUSLY (not in the first tween callback) so a cycle that switched to a
	# new route never renders one frame of the new line fully drawn (the "blue flash"). The FINGER
	# is NOT snapped here — it travels (below), never teleports.
	_rev = 0.0
	var start: Vector2 = _chip if _mode == "full" else _pts[0]
	# Rule: the finger never teleports. If it's already on screen, it physically slides to the next
	# anchor (fast, but a real move); only its FIRST appearance may snap into place.
	var on_screen: bool = _finger.x > -100.0
	if not on_screen:
		_finger = start
	queue_redraw()
	if _tw != null:
		_tw.kill()
	var dur: float = clampf(0.16 * _pts.size(), 0.7, 2.4)
	var undur: float = clampf(0.09 * _pts.size(), 0.35, 1.1)   # undraw is quicker than the draw
	_tw = create_tween()  # ONE cycle; re-arms itself via _begin_cycle at the end
	# TRAVEL: move the finger from wherever it is to this cycle's start anchor — never a jump.
	if on_screen and _finger.distance_to(start) > 1.0:
		var travel: float = clampf(_finger.distance_to(start) / 2200.0, 0.12, 0.5)
		_tw.tween_property(self, "_finger", start, travel).set_trans(Tween.TRANS_SINE)
	if _mode == "full":
		# tap the chip (the finger has just arrived there), THEN drag out the route.
		_tw.tween_callback(_do_ripple.bind(_chip))                    # tap the chip
		_tw.tween_interval(0.35)
		_tw.tween_property(self, "_finger", _pts[0], 0.5).set_trans(Tween.TRANS_SINE)
		_tw.tween_callback(_do_ripple.bind(_pts[0]))                  # press at start
		_tw.tween_interval(0.2)
	else: # "draw" — only the drag, no chip tap
		_tw.tween_callback(_do_ripple.bind(_pts[0]))                  # press at start
		_tw.tween_interval(0.25)
	_tw.tween_method(_drag, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)  # draw
	_tw.tween_callback(_do_ripple.bind(_pts[_pts.size() - 1]))        # release
	_tw.tween_interval(0.65)                                          # brief hold, drawn
	# UNDRAW: the finger quickly retraces the line back to the start, erasing it — instead of the
	# line snapping away. Reads as "and back again", inviting the player to draw it themselves.
	_tw.tween_method(_undrag, 0.0, 1.0, undur).set_trans(Tween.TRANS_SINE)
	_tw.tween_interval(0.3)
	_tw.tween_callback(_begin_cycle)                                  # next cycle: latest request


func _drag(t: float) -> void:
	_rev = t
	_finger = _point_at(_pts, t)


## Reverse of _drag: erase the line from the head back to the start, finger following.
func _undrag(t: float) -> void:
	_rev = 1.0 - t
	_finger = _point_at(_pts, 1.0 - t)


func _do_ripple(at: Vector2) -> void:
	_ripple_at = at
	var rt := create_tween()
	rt.tween_method(func(v): _ripple = v, 0.001, 1.0, 0.45)
	rt.tween_callback(func(): _ripple = 0.0)


func _process(dt: float) -> void:
	if _mode != "idle":
		_spin += dt * 0.6
		queue_redraw()


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
	# The route line growing as the finger "draws" it (FULL and DRAW modes).
	if _mode != "idle" and _rev > 0.001 and _pts.size() >= 2:
		var total := 0.0
		for i in _pts.size() - 1:
			total += _pts[i].distance_to(_pts[i + 1])
		var target: float = _rev * total
		var line := PackedVector2Array([_pts[0]])
		var acc := 0.0
		for i in _pts.size() - 1:
			var seg: float = _pts[i].distance_to(_pts[i + 1])
			if acc + seg >= target:
				line.append(_pts[i].lerp(_pts[i + 1], (target - acc) / maxf(seg, 0.001)))
				break
			line.append(_pts[i + 1])
			acc += seg
		if line.size() >= 2:
			draw_polyline(line, Color(_color, 0.8), 8.0, true)
	if _mode == "idle":
		return
	# Tap ripple + a big NO-FILL dashed-border fingertip (two counter-rotating dashed rings).
	if _ripple > 0.001:
		draw_arc(_ripple_at, 20.0 + 70.0 * _ripple, 0.0, TAU, 40,
				Color(1, 1, 1, (1.0 - _ripple) * 0.6), 5.0)
	_dashed_ring(_finger, R, Color(0.97, 0.98, 1.0, 0.95), 5.0, 12, 0.55, _spin)
	_dashed_ring(_finger, R * 1.35, Color(1, 1, 1, 0.32), 3.0, 16, 0.5, -_spin * 0.7)


## A hollow ring of `segs` dashes (each covering `on` of its arc), rotated by `phase`.
func _dashed_ring(c: Vector2, rad: float, col: Color, w: float, segs: int, on: float, phase: float) -> void:
	var step := TAU / float(segs)
	for i in segs:
		var a0 := phase + i * step
		draw_arc(c, rad, a0, a0 + step * on, 6, col, w, true)
