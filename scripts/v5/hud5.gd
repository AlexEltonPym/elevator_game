extends CanvasLayer
## Minimal v5 HUD, built in code, driven by main5's phase machine. Adapted from
## scripts/v3/hud3.gd but pared to the prototype: a variable roster of card
## chips (1..3), CLEAR, one big RUN/ABORT button, a hint line, and the
## WIN / LOSE overlays. There is no BRIEFING screen — picking a level lands
## straight in PLAN. RUN gates on the level's ACTUAL roster.

const StarBar5 := preload("res://scripts/v5/starbar5.gd")

var game = null # main5.gd

var level_label: Label
var served_label: Label
var lost_label: Label
var menu_btn: Button
var speed_buttons: Array = []
var hint_label: Label
var chip_buttons: Array = []
var chip_pips: Array = []
var _last_serves: Array = [] # per-card serve counts last shown on the chips
var clear_btn: Button
var action_btn: Button
var overlay: Control = null
var _chips_built := false
var headless := false

# 5x is the default pace; 1x is a "slow down" for watching a tricky moment. No pause.
const SPEEDS := [[5.0, "5x"], [1.0, "1x"]]


func _ready() -> void:
	headless = Levels5.headless
	if headless:
		set_process(false)
		return
	layer = 10
	_build_top()
	_build_panel()


func _process(_delta: float) -> void:
	if game != null:
		refresh_stats()


func _build_top() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.size = Vector2(720, 98)
	add_child(bg)
	level_label = _make_label(Vector2(14, 28), 34, Color(0.95, 0.85, 0.5))
	level_label.text = "R-1"
	served_label = _make_label(Vector2(110, 12), 24, Color(0.45, 0.95, 0.55))
	lost_label = _make_label(Vector2(110, 52), 24, Color(1.0, 0.5, 0.45))
	menu_btn = Button.new()
	menu_btn.text = "LEVELS"
	menu_btn.position = Vector2(330, 4)
	menu_btn.size = Vector2(100, 90)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.pressed.connect(func():
		if game != null:
			game.to_level_select())
	add_child(menu_btn)
	for i in SPEEDS.size():
		var btn := Button.new()
		btn.text = SPEEDS[i][1]
		btn.position = Vector2(438 + i * 94, 4)
		btn.size = Vector2(88, 90)
		btn.add_theme_font_size_override("font_size", 30)
		var s: float = SPEEDS[i][0]
		btn.pressed.connect(func(): _on_speed(s))
		add_child(btn)
		speed_buttons.append(btn)


func _on_speed(s: float) -> void:
	if game != null:
		game.set_speed(s)


func _build_panel() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.14)
	bg.position = Vector2(0, 1010)
	bg.size = Vector2(720, 270)
	add_child(bg)
	hint_label = _make_label(Vector2(14, 1016), 20, Color(1, 1, 1, 0.6))
	clear_btn = Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.size = Vector2(150, 116)
	clear_btn.position = Vector2(546, 1046)
	clear_btn.add_theme_font_size_override("font_size", 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.18, 0.16)
	sb.set_corner_radius_all(8)
	clear_btn.add_theme_stylebox_override("normal", sb)
	clear_btn.visible = false
	clear_btn.pressed.connect(_on_clear)
	add_child(clear_btn)
	action_btn = Button.new()
	action_btn.position = Vector2(14, 1174)
	action_btn.size = Vector2(692, 96)
	action_btn.add_theme_font_size_override("font_size", 32)
	action_btn.pressed.connect(_on_action)
	add_child(action_btn)


## Build one chip per card (roster size varies). Deferred until `game` is set,
## because the child HUD's _ready runs before main5 assigns it.
func _ensure_chips() -> void:
	if _chips_built or game == null:
		return
	_chips_built = true
	var n: int = game.CARDS.size()
	var cw := 160.0
	if n <= 3:
		cw = 160.0
	for i in n:
		var btn := Button.new()
		btn.position = Vector2(14 + i * 172, 1046)
		btn.size = Vector2(cw, 116)
		btn.add_theme_font_size_override("font_size", 18)
		var idx: int = i
		btn.pressed.connect(func(): game.select_card(idx))
		add_child(btn)
		chip_buttons.append(btn)
		var pip := ColorRect.new()
		pip.size = Vector2(22, 22)
		pip.position = Vector2(btn.size.x - 32, 10)
		pip.color = Color(0.42, 0.42, 0.48)
		btn.add_child(pip)
		chip_pips.append(pip)
	# CLEAR sits after the last chip.
	clear_btn.position = Vector2(14 + n * 172, 1046)
	if clear_btn.position.x + clear_btn.size.x > 706:
		clear_btn.position.x = 546


func _on_clear() -> void:
	if game != null and game.selected_card >= 0:
		game.clear_route(game.selected_card)


func _on_action() -> void:
	if game == null:
		return
	if game.state == game.State.PLAN:
		if game.ready_to_run():
			game.start_run()
	elif game.state == game.State.PLAYING:
		game.abort_run()


func _refresh_action() -> void:
	action_btn.visible = game.state == game.State.PLAN or game.state == game.State.PLAYING
	if not action_btn.visible:
		return
	var running: bool = game.state == game.State.PLAYING
	var ready: bool = running or game.ready_to_run()
	action_btn.text = "ABORT - BACK TO PLAN" if running else "RUN"
	action_btn.disabled = not ready
	var col := Color(0.55, 0.18, 0.16) if running else Color(0.16, 0.45, 0.26)
	if not ready:
		col = Color(0.22, 0.22, 0.26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.border_color = col.lightened(0.35)
	sb.set_border_width_all(3)
	for s in ["normal", "hover", "pressed", "disabled"]:
		action_btn.add_theme_stylebox_override(s, sb)
	action_btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))


func refresh_cards() -> void:
	if headless or game == null:
		return
	_ensure_chips()
	for i in chip_buttons.size():
		var btn: Button = chip_buttons[i]
		var card: Dictionary = game.CARDS[i]
		var route = game.routes[i]
		var served := 0
		if route != null:
			served = route.served_rooms().size()
		btn.text = "%s\nserves %d" % [card.name, served]
		var pip: ColorRect = chip_pips[i]
		if route == null:
			pip.color = Color(0.42, 0.42, 0.48)
		elif served < 2:
			pip.color = Color(0.90, 0.65, 0.20)
		else:
			pip.color = Color(0.35, 0.80, 0.42)
		var selected: bool = game.selected_card == i
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(card.color, 1.0).darkened(0.45).lightened(0.2 if selected else 0.0)
		sb.set_corner_radius_all(8)
		if selected:
			sb.border_color = Color.WHITE
			sb.set_border_width_all(4)
		else:
			sb.border_color = card.color
			sb.set_border_width_all(2)
		for s in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(s, sb)
		btn.disabled = not game.can_edit()


func refresh_stats() -> void:
	if headless or game == null:
		return
	level_label.text = str(game.level.get("id", "R-1"))
	if game.shift_len > 0.0:
		served_label.text = "Tips %d" % roundi(game.tips)
		var remain: float = maxf(0.0, game.shift_len - game.elapsed)
		lost_label.text = "Last orders" if game.shift_closed else "%ds left" % roundi(remain)
	else:
		served_label.text = "Served %d/%d" % [game.served, game.QUOTA]
		lost_label.text = "Lost %d/%d" % [game.lost, game.MAX_LOST]
	var running: bool = game.state == game.State.PLAYING
	for i in speed_buttons.size():
		var active: bool = is_equal_approx(game.time_scale, SPEEDS[i][0])
		speed_buttons[i].visible = running
		speed_buttons[i].modulate = Color(1, 1, 1, 1.0) if active else Color(1, 1, 1, 0.45)
	clear_btn.visible = game.can_edit() and game.selected_card >= 0 \
			and game.routes[game.selected_card] != null
	if _serves_changed():
		refresh_cards()
	_refresh_action()
	_refresh_hint()


## The serve-count (rooms reached via dock cells) each committed route reports
## right now, so refresh_stats can repaint the chips the instant it changes
## (guards the "serves 0" symptom against any path that skips refresh_cards).
func _serves_changed() -> bool:
	var cur: Array = []
	for i in game.CARDS.size():
		var route = game.routes[i]
		cur.append(route.served_rooms().size() if route != null else -1)
	if cur == _last_serves:
		return false
	_last_serves = cur
	return true

func _refresh_hint() -> void:
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	if game.state == game.State.PLAYING:
		hint_label.text = "Running - the network is locked. Watch it, then ABORT to replan."
		return
	if game.state != game.State.PLAN:
		hint_label.text = ""
		return
	if game.reject_msg != "" and Time.get_ticks_msec() < game.reject_until_ms:
		hint_label.text = game.reject_msg
		hint_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		return
	# Incomplete routes (serve <2 rooms) fail SILENTLY - no red/amber scold. RUN just
	# stays greyed until every lift is valid; the neutral guidance below tells the
	# player what to draw. (reject_msg above is different: an illegal action just tried.)
	var sel: int = game.selected_card
	if sel >= 0:
		if game.routes[sel] != null:
			hint_label.text = "Drag a route's end to extend or trim it; or draw a new one."
		else:
			hint_label.text = "Drag beside the rooms' door marks to serve them; release to commit."
	else:
		hint_label.text = "PLAN ready - tap a lift chip to draw, or press RUN."


# ---------------------------------------------------------------- overlays

func show_win(served: int, lost: int) -> void:
	if headless:
		return
	var buttons: Array = []
	if Levels5.current < Levels5.LEVELS.size() - 1:
		buttons.append({"text": "NEXT LEVEL", "cb": func(): game.next_level()})
	buttons.append({"text": "RETRY", "cb": func(): game.to_plan()})
	buttons.append({"text": "LEVEL SELECT", "cb": func(): game.to_level_select()})
	var earned := -1
	if game.shift_len > 0.0 and not (game.level.get("stars", []) as Array).is_empty():
		earned = game.star_count()
	_show_overlay("SHIFT COMPLETE" if game.shift_len > 0.0 else "QUOTA MET",
			_result_body(served, lost), buttons, 23, earned)


func show_lose(served: int, lost: int) -> void:
	if headless:
		return
	_show_overlay("SHIFT FAILED", _result_body(served, lost),
			[
				{"text": "RETRY", "cb": func(): game.to_plan()},
				{"text": "LEVEL SELECT", "cb": func(): game.to_level_select()},
			])


func _result_body(served: int, lost: int) -> String:
	var wait := 0.0
	for e in game.log_served:
		wait += e.wait
	if not game.log_served.is_empty():
		wait /= game.log_served.size()
	if game.shift_len > 0.0:
		return "Tips: %d\nServed %d, lost %d, avg wait %.0f s.\nRETRY keeps your routes." % [
				roundi(game.tips), served, lost, wait]
	return "Served %d of %d, lost %d of %d.\nAverage wait %.0f s over %.0f s of shift.\nRETRY keeps your routes." % [
			served, game.QUOTA, lost, game.MAX_LOST, wait, game.elapsed]


func hide_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null


func _show_overlay(title_text: String, body_text: String, buttons: Array,
		body_size := 23, earned := -1) -> void:
	hide_overlay()
	overlay = Control.new()
	add_child(overlay)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	overlay.position = Vector2.ZERO
	overlay.size = vp
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	overlay.add_child(dim)
	dim.size = vp
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.size = vp
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30 if body_size >= 23 else 18)
	center.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	if earned >= 0:
		var stars := StarBar5.new()
		stars.setup(earned, 56.0)
		var wrap := CenterContainer.new()
		wrap.custom_minimum_size.y = 60.0
		wrap.add_child(stars)
		box.add_child(wrap)
	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", body_size)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size.x = 680.0
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	for b in buttons:
		var btn := Button.new()
		btn.text = b.text
		btn.custom_minimum_size = Vector2(420, 100 if body_size >= 23 else 92)
		btn.add_theme_font_size_override("font_size", 28)
		btn.pressed.connect(b.cb)
		box.add_child(btn)


func _make_label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l
