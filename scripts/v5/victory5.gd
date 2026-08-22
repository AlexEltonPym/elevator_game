extends Control
## Overcooked-style end-of-shift victory overlay: a panel pops in, the title lands, the
## earned stars fill one-by-one, a PERFECT! stamp hits if you topped the range, the tip
## total counts up with a served/lost breakdown, and finally the Next/Retry/Menu buttons
## fade in. The whole reveal is skippable (tap to jump to the end). Drawn stars + styled
## buttons — no art dependency; Kenney star/button sprites can be swapped in per slot later.

const StarRow5 := preload("res://scripts/v5/star_row5.gd")

var _game = null
var _tips_total := 0
var _served := 0
var _lost := 0
var _earned := 0        # stars filled (0..3)
var _perfect := false   # topped the range (the old secret 4th tier)
var _accent := Color(0.42, 0.62, 0.88)

var _tips_label: Label
var _star_row
var _perfect_label: Label
var _break_served: HBoxContainer
var _break_lost: HBoxContainer
var _buttons: Array = []
var _finished := false
var _master: Tween
var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _btns: HBoxContainer
var _catcher: Control


## `cfg`: {game, accent, is_last, on_next, on_retry, on_menu}
func show_result(cfg: Dictionary) -> void:
	_game = cfg.game
	_accent = cfg.get("accent", _accent)
	_tips_total = roundi(_game.tips)
	_served = _game.served
	_lost = _game.lost
	var sc: int = _game.star_count()  # 0..4
	_earned = clampi(sc, 0, 3)
	_perfect = sc >= 4
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp
	_build(cfg)
	_animate()


func _build(cfg: Dictionary) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.name = "dim"
	dim.color = Color(0, 0, 0, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.size = vp
	_dim = dim

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.size = vp

	var panel := PanelContainer.new()
	panel.name = "panel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.15, 0.98)
	sb.border_color = _accent
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(34)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	panel.pivot_offset = Vector2(230, 300)
	panel.scale = Vector2(0.6, 0.6)
	panel.modulate.a = 0.0
	_panel = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size.x = 460
	panel.add_child(box)

	var title := Label.new()
	title.name = "title"
	title.text = "SHIFT COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.97, 0.9, 0.6))
	title.modulate.a = 0.0
	box.add_child(title)
	_title = title

	# star row
	var star_wrap := CenterContainer.new()
	star_wrap.custom_minimum_size.y = 104
	box.add_child(star_wrap)
	_star_row = StarRow5.new()
	_star_row.setup(3, 84.0)
	star_wrap.add_child(_star_row)

	# PERFECT stamp (only used when topped the range)
	_perfect_label = Label.new()
	_perfect_label.text = "PERFECT!"
	_perfect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_perfect_label.add_theme_font_size_override("font_size", 46)
	_perfect_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_perfect_label.add_theme_color_override("font_outline_color", Color(0.5, 0.2, 0.0))
	_perfect_label.add_theme_constant_override("outline_size", 8)
	_perfect_label.pivot_offset = Vector2(230, 30)
	_perfect_label.scale = Vector2(2.4, 2.4)
	_perfect_label.modulate.a = 0.0
	box.add_child(_perfect_label)

	# big tips count-up
	_tips_label = Label.new()
	_tips_label.name = "tips"
	_tips_label.text = "$0"
	_tips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tips_label.add_theme_font_size_override("font_size", 56)
	_tips_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	_tips_label.modulate.a = 0.0
	box.add_child(_tips_label)

	# breakdown lines
	var served_tips := _tips_total + _lost * int(_game.LOST_TIP)
	_break_served = _make_break("%d riders served" % _served, "+%d" % served_tips,
			Color(0.7, 0.85, 0.7))
	box.add_child(_break_served)
	if _lost > 0:
		_break_lost = _make_break("%d lost" % _lost, "−%d" % (_lost * int(_game.LOST_TIP)),
				Color(0.95, 0.55, 0.5))
		box.add_child(_break_lost)

	# buttons
	var btn_row := HBoxContainer.new()
	btn_row.name = "btns"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.modulate.a = 0.0
	box.add_child(btn_row)
	_btns = btn_row
	if not cfg.get("is_last", false) and cfg.has("on_next"):
		btn_row.add_child(_make_button("NEXT", _accent.lightened(0.1), cfg.on_next))
	btn_row.add_child(_make_button("RETRY", Color(0.4, 0.42, 0.5), cfg.on_retry))
	btn_row.add_child(_make_button("MENU", Color(0.4, 0.42, 0.5), cfg.on_menu))

	# A transparent catcher on TOP: a tap anywhere fast-forwards the reveal. Removed once the
	# reveal is done so the buttons underneath become clickable.
	var catcher := Control.new()
	catcher.name = "catcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) \
				or (e is InputEventScreenTouch and e.pressed):
			_finalize())
	add_child(catcher)
	_catcher = catcher


func _make_break(left: String, right: String, col: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.modulate.a = 0.0
	var l := Label.new()
	l.text = left
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var r := Label.new()
	r.text = right
	r.add_theme_font_size_override("font_size", 20)
	r.add_theme_color_override("font_color", col)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(r)
	return h


func _make_button(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(132, 76)
	b.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.border_color = col.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", sbh)
	b.pressed.connect(cb)
	_buttons.append(b)
	return b


func _animate() -> void:
	_master = create_tween()
	_master.tween_property(_dim, "color", Color(0, 0, 0, 0.86), 0.25)
	_master.parallel().tween_property(_panel, "modulate:a", 1.0, 0.25)
	_master.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.42) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_master.tween_property(_title, "modulate:a", 1.0, 0.2)
	# stars, one by one
	for i in _earned:
		_master.tween_callback(_star_row.pop.bind(i))
		_master.tween_interval(0.26)
	# PERFECT stamp
	if _perfect:
		_master.tween_property(_perfect_label, "modulate:a", 1.0, 0.01)
		_master.parallel().tween_property(_perfect_label, "scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_master.tween_interval(0.15)
	# tips count-up
	_master.tween_property(_tips_label, "modulate:a", 1.0, 0.15)
	_master.tween_method(func(v): _tips_label.text = "$%d" % int(v),
			0.0, float(_tips_total), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_master.tween_property(_break_served, "modulate:a", 1.0, 0.15)
	if _break_lost != null:
		_master.tween_property(_break_lost, "modulate:a", 1.0, 0.15)
	# buttons
	_master.tween_property(_btns, "modulate:a", 1.0, 0.25)
	_master.tween_callback(_reveal_done)


## Reveal finished normally: drop the tap-catcher so the buttons become clickable.
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
	_tips_label.modulate.a = 1.0
	_tips_label.text = "$%d" % _tips_total
	_break_served.modulate.a = 1.0
	if _break_lost != null:
		_break_lost.modulate.a = 1.0
	if _perfect:
		_perfect_label.modulate.a = 1.0
		_perfect_label.scale = Vector2.ONE
	_btns.modulate.a = 1.0
	if is_instance_valid(_catcher):
		_catcher.queue_free()
	_finished = true
