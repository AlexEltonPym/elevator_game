extends Control
## A demo-style route ARROW on the board: after an intro card dismisses, an arrowhead travels
## along the special lift's route (cargo storage->cafe in yellow; execs' path to the penthouse in
## orange), the line revealing behind it — teaching "connect these on THIS lift". Loops a few
## times, then frees itself. Non-blocking (mouse passes through).

var _pts: Array = []          # screen-space polyline (the special lift's route)
var _col := Color.WHITE
var _t := 0.0
var _loops := 0
const CYCLES := 3
const TRAVEL := 1.2
const HOLD := 0.5


func setup(pts: Array, col: Color) -> void:
	_pts = pts
	_col = col


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if _pts.size() < 2:
		queue_free(); return
	_t += dt
	if _t >= TRAVEL + HOLD:
		_t = 0.0
		_loops += 1
		if _loops >= CYCLES:
			queue_free(); return
	queue_redraw()


func _draw() -> void:
	var frac := clampf(_t / TRAVEL, 0.0, 1.0)
	var total := 0.0
	for i in _pts.size() - 1:
		total += _pts[i].distance_to(_pts[i + 1])
	var target := frac * total
	var line := PackedVector2Array([_pts[0]])
	var acc := 0.0
	var head: Vector2 = _pts[_pts.size() - 1]
	var prev: Vector2 = _pts[0]
	for i in _pts.size() - 1:
		var seg: float = _pts[i].distance_to(_pts[i + 1])
		if acc + seg >= target:
			head = _pts[i].lerp(_pts[i + 1], (target - acc) / maxf(seg, 0.001))
			prev = _pts[i]
			line.append(head)
			break
		line.append(_pts[i + 1])
		prev = _pts[i]
		acc += seg
	if line.size() >= 2:
		draw_polyline(line, Color(_col, 0.5), 12.0, true)   # soft under-glow
		draw_polyline(line, Color(_col, 0.95), 6.0, true)
		var dir := (head - prev).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
				head + dir * 18.0, head - dir * 12.0 + perp * 15.0,
				head - dir * 12.0 - perp * 15.0]), Color(_col, 0.98))
