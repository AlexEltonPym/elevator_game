extends CanvasLayer
## HUD, built entirely in code:
## - top bar: level id, Served n/quota, Lost n/max, speed buttons (pause/1x/3x)
## - bottom panel: inventory card buttons, contextual hint, Remove button
## - overlays: level intro / win (reward choice) / lose (retry) / campaign done

var game = null # main.gd, set by main before first refresh

var level_label: Label
var served_label: Label
var lost_label: Label
var speed_buttons: Array = []
var hint_label: Label
var cards_box: HBoxContainer
var remove_btn: Button
var overlay: Control = null

const SPEEDS := [[0.0, "II"], [1.0, "1x"], [3.0, "3x"]]


func _ready() -> void:
	layer = 10
	_build_top()
	_build_panel()


# ---------------------------------------------------------------- top bar

func _build_top() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.position = Vector2.ZERO
	bg.size = Vector2(720, 92)
	add_child(bg)
	level_label = _make_label(Vector2(14, 24), 34, Color(0.95, 0.85, 0.5))
	served_label = _make_label(Vector2(130, 10), 24, Color(0.45, 0.95, 0.55))
	lost_label = _make_label(Vector2(130, 48), 24, Color(1.0, 0.5, 0.45))
	var menu_btn := Button.new()
	menu_btn.text = "MENU"
	menu_btn.position = Vector2(330, 6)
	menu_btn.size = Vector2(100, 80)
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	add_child(menu_btn)
	for i in SPEEDS.size():
		var btn := Button.new()
		btn.text = SPEEDS[i][1]
		btn.position = Vector2(438 + i * 94, 6)
		btn.size = Vector2(88, 80)
		btn.add_theme_font_size_override("font_size", 30)
		var s: float = SPEEDS[i][0]
		btn.pressed.connect(func(): _on_speed(s))
		add_child(btn)
		speed_buttons.append(btn)


func _on_speed(s: float) -> void:
	if game != null:
		game.set_speed(s)


# ---------------------------------------------------------------- bottom panel

func _build_panel() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.14)
	bg.position = Vector2(0, 1050)
	bg.size = Vector2(720, 230)
	add_child(bg)
	hint_label = _make_label(Vector2(14, 1056), 20, Color(1, 1, 1, 0.6))
	cards_box = HBoxContainer.new()
	cards_box.position = Vector2(14, 1092)
	cards_box.add_theme_constant_override("separation", 14)
	add_child(cards_box)
	remove_btn = Button.new()
	remove_btn.text = "REMOVE"
	remove_btn.position = Vector2(540, 1092)
	remove_btn.size = Vector2(166, 130)
	remove_btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.18, 0.16)
	sb.set_corner_radius_all(8)
	remove_btn.add_theme_stylebox_override("normal", sb)
	remove_btn.visible = false
	remove_btn.pressed.connect(_on_remove)
	add_child(remove_btn)


func _on_remove() -> void:
	if game != null and game.selected_column >= 0:
		game.remove_elevator(game.selected_column)


## Rebuild the card buttons; call on any inventory or selection change.
func refresh_inventory() -> void:
	if game == null:
		return
	for c in cards_box.get_children():
		c.queue_free()
	for i in game.inventory.size():
		var t: String = game.inventory[i]
		var btn := Button.new()
		btn.text = Levels.card_label(t)
		btn.custom_minimum_size = Vector2(170 if t == "large" else 122, 130)
		btn.add_theme_font_size_override("font_size", 19)
		var selected: bool = game.selected_card == i
		var sb := StyleBoxFlat.new()
		sb.bg_color = Levels.card_color(t).lightened(0.25 if selected else 0.0)
		sb.set_corner_radius_all(8)
		if selected:
			sb.border_color = Color.WHITE
			sb.set_border_width_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		var idx: int = i
		btn.pressed.connect(func(): game.select_card(idx))
		cards_box.add_child(btn)


## Cheap per-frame refresh of labels + contextual widgets.
func refresh_stats() -> void:
	if game == null:
		return
	level_label.text = str(game.level.get("id", ""))
	served_label.text = "Served %d/%d" % [game.served, game.level.get("quota", 0)]
	lost_label.text = "Lost %d/%d" % [game.lost, game.level.get("max_lost", 0)]
	for i in speed_buttons.size():
		var active: bool = is_equal_approx(game.time_scale, SPEEDS[i][0])
		speed_buttons[i].modulate = Color(1, 1, 1, 1.0) if active else Color(1, 1, 1, 0.45)
	remove_btn.visible = game.selected_column >= 0
	if game.selected_card >= 0:
		hint_label.text = "Tap an empty shaft column to install the card"
	elif game.selected_column >= 0:
		hint_label.text = "Tap floors in the column to toggle doors (min 2 ON)"
	elif not game.inventory.is_empty():
		hint_label.text = "Tap a card to select it - tap a car to edit its doors"
	else:
		hint_label.text = "Tap a car to edit its doors"


# ---------------------------------------------------------------- overlays

func show_intro(level: Dictionary) -> void:
	var body: String = str(level.flavor) + "\n\n" + str(level.whats_new)
	_show_overlay("LEVEL  " + str(level.id), body,
			[{"text": "START", "cb": func(): game.start_level()}])


func show_win(level: Dictionary, served: int, lost: int) -> void:
	var buttons: Array = []
	for t in level.rewards:
		var card: String = t
		buttons.append({
			"text": Levels.card_label(card).replace("\n", "  -  "),
			"color": Levels.card_color(card),
			"cb": func(): game.choose_reward(card),
		})
	_show_overlay(str(level.id) + "  COMPLETE",
			"Served %d, lost %d.\n\nChoose ONE reward card:" % [served, lost], buttons)


func show_lose(served: int, lost: int) -> void:
	_show_overlay("SHIFT FAILED",
			"Lost %d passengers (served %d).\nYour network stays as built - counters reset." % [lost, served],
			[{"text": "RETRY", "cb": func(): game.retry_level()}])


func show_complete(total_served: int, total_lost: int) -> void:
	_show_overlay("CAMPAIGN COMPLETE",
			"The hospital runs itself now.\n\nTotal served: %d\nTotal lost: %d" % [total_served, total_lost],
			[{"text": "RESTART CAMPAIGN", "cb": func(): game.restart_campaign()}])


func hide_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


func _show_overlay(title_text: String, body_text: String, buttons: Array) -> void:
	hide_overlay()
	overlay = Control.new()
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	overlay.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30)
	center.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", 23)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	for b in buttons:
		var btn := Button.new()
		btn.text = b.text
		btn.custom_minimum_size = Vector2(420, 100)
		btn.add_theme_font_size_override("font_size", 28)
		if b.has("color"):
			var sb := StyleBoxFlat.new()
			sb.bg_color = b.color
			sb.set_corner_radius_all(10)
			btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(b.cb)
		box.add_child(btn)


func _make_label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l
