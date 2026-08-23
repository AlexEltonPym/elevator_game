extends Control
## Overcooked-style end-of-shift victory overlay: a panel pops in, the title lands, the
## earned stars fill one-by-one, a rating stamp hits (FAIL:( / PASSED / GOOD / GREAT! /
## PERFECT! for 0..4 tiers), the tip total counts up with a served/lost breakdown, then the
## Next/Retry/Menu buttons fade in. Tap anywhere to fast-forward. Skinned with the Kenney UI
## pack via Ui5 (falls back to flat styles if the pack is absent).

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

var _tips_label: Label
var _star_row
var _rating_label: Label
var _break_served: HBoxContainer
var _break_lost: HBoxContainer
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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	_build(cfg)
	_animate()


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
	_panel.pivot_offset = Vector2(230, 300)
	_panel.scale = Vector2(0.6, 0.6)
	_panel.modulate.a = 0.0

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.custom_minimum_size.x = 452
	_panel.add_child(box)

	_title = Label.new()
	_title.text = "SHIFT COMPLETE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_title, 34, Color(0.86, 0.9, 1.0))
	_title.modulate.a = 0.0
	box.add_child(_title)

	var star_wrap := CenterContainer.new()
	star_wrap.custom_minimum_size.y = 96
	box.add_child(star_wrap)
	_star_row = StarRow5.new()
	_star_row.setup(3, 82.0, _sc >= 4)
	_star_row.tooltip_text = _star_tooltip()
	star_wrap.add_child(_star_row)

	var rat: Dictionary = RATING[_sc]
	_rating_label = Label.new()
	_rating_label.text = str(rat.text)
	_rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_rating_label, 52, rat.col)
	_rating_label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.0, 0.9))
	_rating_label.add_theme_constant_override("outline_size", 8)
	_rating_label.pivot_offset = Vector2(226, 34)
	_rating_label.scale = Vector2(2.3, 2.3)
	_rating_label.modulate.a = 0.0
	box.add_child(_rating_label)

	_tips_label = Label.new()
	_tips_label.text = "$0"
	_tips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(_tips_label, 54, Color(0.55, 0.95, 0.55) if _tips_total > 0 else Color(0.95, 0.5, 0.45))
	_tips_label.modulate.a = 0.0
	box.add_child(_tips_label)

	var served_tips := _tips_total + _lost * int(_game.LOST_TIP)
	_break_served = _make_break("%d riders served" % _served, "+%d" % served_tips,
			Color(0.72, 0.86, 0.72))
	box.add_child(_break_served)
	if _lost > 0:
		_break_lost = _make_break("%d lost" % _lost, "−%d" % (_lost * int(_game.LOST_TIP)),
				Color(0.95, 0.55, 0.5))
		box.add_child(_break_lost)

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


## Tooltip listing the tip total each star needs (from the level's `stars` thresholds).
func _star_tooltip() -> String:
	var th: Array = _game.level.get("stars", []) if _game != null else []
	if th.size() < 3:
		return ""
	var s := "1 star  %d tips\n2 stars  %d tips\n3 stars  %d tips" % [int(th[0]), int(th[1]), int(th[2])]
	if th.size() >= 4:
		s += "\nperfect  %d tips" % int(th[3])
	return s


func _make_break(left: String, right: String, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.modulate.a = 0.0
	var l := Label.new()
	l.text = left
	_font(l, 20, col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var r := Label.new()
	r.text = right
	_font(r, 20, col)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(r)
	return h


func _animate() -> void:
	_master = create_tween()
	_master.tween_property(_dim, "color", Color(0, 0, 0, 0.86), 0.25)
	_master.parallel().tween_property(_panel, "modulate:a", 1.0, 0.25)
	_master.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.42) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_master.tween_property(_title, "modulate:a", 1.0, 0.2)
	for i in _earned:
		_master.tween_callback(_star_row.pop.bind(i))
		_master.tween_interval(0.26)
	# rating stamp
	_master.tween_property(_rating_label, "modulate:a", 1.0, 0.01)
	_master.parallel().tween_property(_rating_label, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_master.tween_interval(0.12)
	# tips count-up
	_master.tween_property(_tips_label, "modulate:a", 1.0, 0.15)
	_master.tween_method(func(v): _tips_label.text = "$%d" % int(v),
			0.0, float(_tips_total), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_master.tween_property(_break_served, "modulate:a", 1.0, 0.15)
	if _break_lost != null:
		_master.tween_property(_break_lost, "modulate:a", 1.0, 0.15)
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
	for i in _earned:
		_star_row.pop(i)
	_title.modulate.a = 1.0
	_rating_label.modulate.a = 1.0
	_rating_label.scale = Vector2.ONE
	_tips_label.modulate.a = 1.0
	_tips_label.text = "$%d" % _tips_total
	_break_served.modulate.a = 1.0
	if _break_lost != null:
		_break_lost.modulate.a = 1.0
	_btns.modulate.a = 1.0
	if is_instance_valid(_catcher):
		_catcher.queue_free()
	_finished = true
