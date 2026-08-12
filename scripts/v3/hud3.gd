extends CanvasLayer
## v3 HUD, built entirely in code:
## - top bar: level id, Served n/quota, Lost n/max, LEVELS, speed buttons
## - bottom panel: 3 route card chips (colored, route length + stop count),
##   CLEAR button, contextual hint line
## - overlays: intro / win (next level, level select, keep playing) /
##   lose (retry, level select)
## Watch mode (game.watch != ""): the LEVELS button reads EXIT, a colored
## WATCHING banner replaces the hint line, chips are display-only, and the
## win/lose overlays offer Watch Again / Level Select instead.

var game = null # main3.gd, set by main before first refresh

var level_label: Label
var served_label: Label
var lost_label: Label
var menu_btn: Button
var speed_buttons: Array = []
var hint_label: Label
var chip_buttons: Array = []
var clear_btn: Button
var watch_banner: ColorRect = null
var watch_label: Label = null
var overlay: Control = null

const SPEEDS := [[0.0, "II"], [1.0, "1x"], [3.0, "3x"]]
const WATCH_TONES := {
	"naive": Color(0.62, 0.24, 0.20), # the obvious plan, in warning red
	"thesis": Color(0.16, 0.45, 0.26), # the level's answer, in confident green
}


func _ready() -> void:
	layer = 10
	_build_top()
	_build_panel()


func _process(_delta: float) -> void:
	if game != null:
		refresh_stats()


# ---------------------------------------------------------------- top bar

func _build_top() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.position = Vector2.ZERO
	bg.size = Vector2(720, 92)
	add_child(bg)
	level_label = _make_label(Vector2(14, 24), 34, Color(0.95, 0.85, 0.5))
	level_label.text = "X-1"
	served_label = _make_label(Vector2(110, 10), 24, Color(0.45, 0.95, 0.55))
	lost_label = _make_label(Vector2(110, 48), 24, Color(1.0, 0.5, 0.45))
	menu_btn = Button.new()
	menu_btn.text = "LEVELS" # reads EXIT in watch mode (see refresh_stats)
	menu_btn.position = Vector2(330, 6)
	menu_btn.size = Vector2(100, 80)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.pressed.connect(func():
		if game != null:
			game.to_level_select())
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
	bg.position = Vector2(0, 1010)
	bg.size = Vector2(720, 270)
	add_child(bg)
	hint_label = _make_label(Vector2(14, 1018), 20, Color(1, 1, 1, 0.6))
	for i in 3:
		var btn := Button.new()
		btn.position = Vector2(14 + i * 172, 1056)
		btn.size = Vector2(160, 150)
		btn.add_theme_font_size_override("font_size", 19)
		var idx: int = i
		btn.pressed.connect(func(): game.select_card(idx))
		add_child(btn)
		chip_buttons.append(btn)
	clear_btn = Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.position = Vector2(546, 1056)
	clear_btn.size = Vector2(160, 150)
	clear_btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.18, 0.16)
	sb.set_corner_radius_all(8)
	clear_btn.add_theme_stylebox_override("normal", sb)
	clear_btn.visible = false
	clear_btn.pressed.connect(_on_clear)
	add_child(clear_btn)
	# WATCHING banner (watch mode only): sits where the hint line lives.
	watch_banner = ColorRect.new()
	watch_banner.position = Vector2(0, 1010)
	watch_banner.size = Vector2(720, 44)
	watch_banner.visible = false
	add_child(watch_banner)
	watch_label = Label.new()
	watch_label.position = Vector2(14, 1016)
	watch_label.add_theme_font_size_override("font_size", 21)
	watch_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	watch_label.visible = false
	add_child(watch_label)


func _on_clear() -> void:
	if game != null and game.selected_card >= 0:
		game.clear_route(game.selected_card)


## Rebuild the chip visuals; call on any route or selection change.
func refresh_cards() -> void:
	if game == null:
		return
	var watching: bool = game.watch != ""
	if watching:
		# One-time-ish banner setup (values never change mid-session).
		watch_banner.color = WATCH_TONES.get(game.watch, Color(0.3, 0.3, 0.3))
		var sets: Dictionary = Scenarios3.route_sets(game.level.id)
		var desc: String = sets.get(game.watch, {}).get("desc", "")
		watch_label.text = "WATCHING: %s - %s" % [game.watch.to_upper(), desc]
	for i in chip_buttons.size():
		var btn: Button = chip_buttons[i]
		var card: Dictionary = game.CARDS[i]
		var route = game.routes[i]
		var car = game.cars[i]
		var sub: String
		if car != null and car.car_state == Car3.CarState.RECALLING:
			sub = "recalling..."
		elif car != null and car.car_state == Car3.CarState.REDEPLOYING:
			sub = "deploys in %d" % ceili(maxf(car.redeploy_left, 0.001))
		elif route == null:
			sub = "no route"
		else:
			var stops: int = route.stop_cells().size()
			if route.closed:
				sub = "%d-cell loop - %d stops" % [route.cells.size(), stops]
			else:
				sub = "%d cells - %d stops" % [route.cells.size(), stops]
			if stops < 2:
				sub += "\nneeds 2 stops!"
		var kind: String = "fast express" if card.type == "express" else "4 slots"
		btn.text = "%s\n%s\n%s" % [card.name, kind, sub]
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
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("disabled", sb)
		btn.disabled = watching # watch mode: chips are display-only


## Cheap per-frame refresh of labels + contextual widgets.
func refresh_stats() -> void:
	if game == null:
		return
	level_label.text = str(game.level.get("id", "X-1"))
	served_label.text = "Served %d/%d" % [game.served, game.QUOTA]
	lost_label.text = "Lost %d/%d" % [game.lost, game.MAX_LOST]
	if game.endless:
		served_label.text = "Served %d (endless)" % game.served
		lost_label.text = "Lost %d" % game.lost
	for i in speed_buttons.size():
		var active: bool = is_equal_approx(game.time_scale, SPEEDS[i][0])
		speed_buttons[i].modulate = Color(1, 1, 1, 1.0) if active else Color(1, 1, 1, 0.45)
	var watching: bool = game.watch != ""
	menu_btn.text = "EXIT" if watching else "LEVELS"
	watch_banner.visible = watching
	watch_label.visible = watching
	hint_label.visible = not watching
	clear_btn.visible = not watching and game.selected_card >= 0 \
			and game.routes[game.selected_card] != null
	# Recall/redeploy chips carry a live countdown - rebuild them while any
	# car is in a pending state (cheap: 3 buttons).
	for c in game.cars:
		if c != null and (c.car_state == Car3.CarState.RECALLING
				or c.car_state == Car3.CarState.REDEPLOYING):
			refresh_cards()
			break
	if not watching:
		_refresh_hint()


func _refresh_hint() -> void:
	var sel: int = game.selected_card
	if sel >= 0 and game.route_warning(sel):
		hint_label.text = "Route needs at least 2 room stops - car is parked. Drag again to redraw."
		hint_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		return
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	if game.drawing:
		hint_label.text = "Drag through open cells - release to commit the route"
	elif sel >= 0:
		hint_label.text = "Drag on the grid to draw %s's route (redraw replaces; rooms become stops)" % game.CARDS[sel].name
	else:
		var warn := false
		for i in 3:
			if game.route_warning(i):
				warn = true
		if warn:
			hint_label.text = "A route needs at least 2 room stops - its car is parked (!)"
			hint_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		else:
			hint_label.text = "Tap a card chip, then drag its route through the maze"


# ---------------------------------------------------------------- overlays

func show_intro() -> void:
	var lv: Dictionary = game.level
	_show_overlay("%s  %s" % [lv.id, str(lv.name).to_upper()],
			str(lv.intro) +
			"\n\nServe %d before losing %d." % [game.QUOTA, game.MAX_LOST],
			[{"text": "START", "cb": func(): game.start_session()}])


func show_win(served: int, lost: int) -> void:
	if game.watch != "":
		_show_overlay("%s WINS" % game.watch.to_upper(),
				"Quota met: served %d, lost %d." % [served, lost], _watch_buttons())
		return
	var buttons: Array = []
	if Levels3.current < Levels3.LEVELS.size() - 1:
		buttons.append({"text": "NEXT LEVEL", "cb": func(): game.next_level()})
	buttons.append({"text": "LEVEL SELECT", "cb": func(): game.to_level_select()})
	buttons.append({"text": "KEEP PLAYING", "cb": func(): game.keep_playing()})
	_show_overlay("QUOTA MET",
			"Served %d, lost %d." % [served, lost], buttons)


func show_lose(served: int, lost: int) -> void:
	if game.watch != "":
		_show_overlay("%s LOSES" % game.watch.to_upper(),
				"Lost %d passengers (served %d)." % [lost, served], _watch_buttons())
		return
	_show_overlay("SHIFT FAILED",
			"Lost %d passengers (served %d).\nYour routes stay drawn - counters reset." % [lost, served],
			[
				{"text": "RETRY", "cb": func(): game.restart_session()},
				{"text": "LEVEL SELECT", "cb": func(): game.to_level_select()},
			])


func _watch_buttons() -> Array:
	return [
		{"text": "WATCH AGAIN", "cb": func(): game.watch_again()},
		{"text": "LEVEL SELECT", "cb": func(): game.to_level_select()},
	]


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
		btn.pressed.connect(b.cb)
		box.add_child(btn)


func _make_label(pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l
