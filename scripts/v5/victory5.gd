extends Control
## End-of-shift score screen: a panel pops in, the earned stars fill, then an ITEMISED tip
## breakdown reveals one group at a time (Passengers / Executives / Deliveries / Lost) while the
## running TOTAL counts up — stars pop as the total crosses their thresholds (synced). A rating
## stamp lands, a "next star" line shows how far off the next tier is, then the buttons fade in.
## Tap anywhere to fast-forward.

const StarRow5 := preload("res://scripts/v5/star_row5.gd")
const Ui5 := preload("res://scripts/v5/ui5.gd")

const RATING := {
	0: {"text": "FAIL :(", "col": Color(0.92, 0.42, 0.42)},
	1: {"text": "PASSED", "col": Color(0.75, 0.82, 0.95)},
	2: {"text": "GOOD", "col": Color(0.55, 0.9, 0.55)},
	3: {"text": "GREAT!", "col": Color(1.0, 0.86, 0.35)},
	4: {"text": "PERFECT!", "col": Color(1.0, 0.78, 0.16)},
}

var _game = null
var _tips_total := 0
var _served := 0
var _lost := 0
var _sc := 0            # star_count 0..4
var _earned := 0        # stars filled (0..3)
var _accent := Color(0.42, 0.62, 0.88)

var _groups: Array = []   # [{label, n, amt(int, signed), col, row, amt_label}]
var _popped := [false, false, false]

var _tips_label: Label
var _next_label: Label
var _star_row
var _rating_label: Label
var _rows_box: VBoxContainer
var _finished := false
var _master: Tween
var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _btns: HBoxContainer
var _catcher: Control


func show_result(cfg: Dictionary) -> void:
	_game = cfg.game
	_accent = cfg.get("accent", _accent)
	_tips_total = roundi(_game.tips)
	_served = _game.served
	_lost = _game.lost
	_sc = _game.star_count()
	_earned = clampi(_sc, 0, 3)
	_groups = _build_groups()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	_build(cfg)
	_animate()


## Aggregate the served log by category (+ lost) into signed breakdown groups.
func _build_groups() -> Array:
	var agg := {"pax": [0, 0.0], "exec": [0, 0.0], "cargo": [0, 0.0]}
	for e in _game.log_served:
		var c := str(e.get("cat", "pax"))
		if not agg.has(c):
			c = "pax"
		agg[c][0] += 1
		agg[c][1] += float(e.get("tip", 0.0))
	var out: Array = []
	var defs := [
		["pax", "Passengers", Color(0.80, 0.88, 0.96)],
		["exec", "Executives", Color(0.97, 0.62, 0.30)],
		["cargo", "Deliveries", Color(0.96, 0.82, 0.30)],
	]
	for d in defs:
		var a = agg[d[0]]
		if a[0] > 0:
			out.append({"label": d[1], "n": a[0], "amt": roundi(a[1]), "col": d[2]})
	if _lost > 0:
		out.append({"label": "Lost", "n": _lost, "amt": -_lost * int(_game.LOST_TIP),
				"col": Color(0.96, 0.5, 0.46)})
	return out


func _font(l: Control, sz: int, col: Color) -> void:
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	var f = Ui5.font()
	if f != null:
		l.add_theme_font_override("font", f)


func _build(cfg: Dictionary) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.size = vp

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.size = vp

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui5.panel_box())
	center.add_child(_panel)
	_panel.pivot_offset = Vector2(230, 320)
	_panel.scale = Vector2(0.6, 0.6)
	_panel.modulate.a = 0.0

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 470
	_panel.add_child(box)

	_title = Label.new()
	_title.text = "SHIFT COMPLETE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_title, 32, Color(0.86, 0.9, 1.0))
	_title.modulate.a = 0.0
	box.add_child(_title)

	var star_wrap := CenterContainer.new()
	star_wrap.custom_minimum_size.y = 92
	box.add_child(star_wrap)
	_star_row = StarRow5.new()
	_star_row.setup(3, 80.0, _sc >= 4)
	star_wrap.add_child(_star_row)

	var rat: Dictionary = RATING[_sc]
	_rating_label = Label.new()
	_rating_label.text = str(rat.text)
	_rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_rating_label, 50, rat.col)
	_rating_label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.0, 0.9))
	_rating_label.add_theme_constant_override("outline_size", 8)
	_rating_label.pivot_offset = Vector2(235, 32)
	_rating_label.scale = Vector2(2.3, 2.3)
	_rating_label.modulate.a = 0.0
	box.add_child(_rating_label)

	# The running TOTAL (big).
	_tips_label = Label.new()
	_tips_label.text = "$0"
	_tips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_tips_label, 60, Color(0.55, 0.95, 0.55) if _tips_total >= 0 else Color(0.95, 0.5, 0.45))
	_tips_label.pivot_offset = Vector2(235, 36)
	_tips_label.modulate.a = 0.0
	box.add_child(_tips_label)

	# Itemised breakdown rows (bigger text), each hidden until its turn.
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	box.add_child(_rows_box)
	for g in _groups:
		var row := HBoxContainer.new()
		row.modulate.a = 0.0
		var left := Label.new()
		left.text = "%d × %s" % [g.n, g.label]
		_font(left, 28, g.col)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left)
		var right := Label.new()
		right.text = ("+%d" % g.amt) if g.amt >= 0 else ("−%d" % (-g.amt))
		_font(right, 28, g.col)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(right)
		_rows_box.add_child(row)
		g["row"] = row

	# Next-star line.
	_next_label = Label.new()
	_next_label.text = _next_star_text()
	_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_next_label, 22, Color(0.72, 0.78, 0.9))
	_next_label.modulate.a = 0.0
	box.add_child(_next_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.modulate.a = 0.0
	box.add_child(btn_row)
	_btns = btn_row
	if not cfg.get("is_last", false) and cfg.has("on_next"):
		var nb := Ui5.make_button("NEXT", "Green", 24)
		nb.custom_minimum_size = Vector2(140, 84)
		nb.pressed.connect(cfg.on_next)
		btn_row.add_child(nb)
	var rb := Ui5.make_button("RETRY", "Grey", 22)
	rb.custom_minimum_size = Vector2(140, 84)
	rb.pressed.connect(cfg.on_retry)
	btn_row.add_child(rb)
	var mb := Ui5.make_button("MENU", "Grey", 22)
	mb.custom_minimum_size = Vector2(140, 84)
	mb.pressed.connect(cfg.on_menu)
	btn_row.add_child(mb)

	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.size = vp
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) \
				or (e is InputEventScreenTouch and e.pressed):
			_finalize())
	add_child(_catcher)


func _next_star_text() -> String:
	var th: Array = _game.level.get("stars", []) if _game != null else []
	if _sc >= 4 or th.size() < 4:
		return ""   # perfect (or no thresholds): nothing to chase
	var need: int = int(th[_sc]) - _tips_total
	if need < 1:
		need = 1
	return "$%d more for the next star" % need


## Update the running total label + pop any newly-earned star it has crossed.
func _set_total(v: float) -> void:
	_tips_label.text = "$%d" % roundi(v)
	var th: Array = _game.level.get("stars", [])
	for i in mini(3, th.size()):
		if not _popped[i] and i < _earned and v >= float(th[i]):
			_popped[i] = true
			_star_row.pop(i)


func _animate() -> void:
	_master = create_tween()
	_master.tween_property(_dim, "color", Color(0, 0, 0, 0.86), 0.25)
	_master.parallel().tween_property(_panel, "modulate:a", 1.0, 0.25)
	_master.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.42) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_master.tween_property(_title, "modulate:a", 1.0, 0.18)
	_master.tween_property(_tips_label, "modulate:a", 1.0, 0.12)
	# Reveal each group in turn while the total counts up (stars pop as thresholds are crossed).
	var running := 0.0
	for g in _groups:
		_master.tween_property(g.row, "modulate:a", 1.0, 0.12)
		var target: float = running + float(g.amt)
		_master.tween_method(_set_total, running, target, 0.4) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# a satisfying pop on the total as the group lands
		_master.parallel().tween_property(_tips_label, "scale", Vector2(1.14, 1.14), 0.12)
		_master.tween_property(_tips_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
		running = target
		_master.tween_interval(0.14)
	_master.tween_callback(func(): _set_total(float(_tips_total)))
	# rating stamp
	_master.tween_property(_rating_label, "modulate:a", 1.0, 0.01)
	_master.parallel().tween_property(_rating_label, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_master.tween_interval(0.1)
	_master.tween_property(_next_label, "modulate:a", 1.0, 0.2)
	_master.tween_property(_btns, "modulate:a", 1.0, 0.25)
	_master.tween_callback(_reveal_done)


func _reveal_done() -> void:
	_finished = true
	if is_instance_valid(_catcher):
		_catcher.queue_free()


func _finalize() -> void:
	if _finished:
		return
	if _master != null and _master.is_running():
		_master.kill()
	_dim.color = Color(0, 0, 0, 0.86)
	_panel.modulate.a = 1.0
	_panel.scale = Vector2.ONE
	_title.modulate.a = 1.0
	for i in _earned:
		_popped[i] = true
		_star_row.pop(i)
	_rating_label.modulate.a = 1.0
	_rating_label.scale = Vector2.ONE
	_tips_label.modulate.a = 1.0
	_tips_label.scale = Vector2.ONE
	_tips_label.text = "$%d" % _tips_total
	for g in _groups:
		g.row.modulate.a = 1.0
	_next_label.modulate.a = 1.0
	_btns.modulate.a = 1.0
	if is_instance_valid(_catcher):
		_catcher.queue_free()
	_finished = true
