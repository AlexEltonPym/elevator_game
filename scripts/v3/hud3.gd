extends CanvasLayer
## v3 HUD, built entirely in code, driven by main3's phase machine:
## - top bar: level id, Served n/quota, Lost n/max, LEVELS, speed buttons
##   (speed only matters while a run is on, so it only shows in PLAYING)
## - bottom panel: 3 route card chips (colored, route length + stop count),
##   CLEAR, a contextual hint line, and ONE big primary action button:
##     PLAN   -> "RUN", disabled until game.ready_to_run()
##     RUN    -> "ABORT" (back to PLAN)
##   Chips and CLEAR are disabled whenever game.can_edit() is false, so the
##   panel cannot even offer an edit during a run.
## - overlays: BRIEFING (roster + crowd + thesis, generated from the level
##   data by Levels3.briefing_body) / win (retry, next level, levels) /
##   lose (retry, levels)
## Watch mode (game.watch != ""): the LEVELS button reads EXIT, a colored
## WATCHING banner replaces the hint line, chips are display-only, there is no
## action button, and the win/lose overlays offer Watch Again / Level Select.

var game = null # main3.gd, set by main before first refresh

## Simulated run (Levels3.headless): build NOTHING and answer every call with a
## no-op. A Control entering the tree queues deferred callables that only an
## engine frame drains, and a search never reaches one — see levels3.gd
## `headless` and tools/sim_api.gd. Also just faster: no StyleBoxFlat churn.
var headless := false

var level_label: Label
var served_label: Label
var lost_label: Label
var menu_btn: Button
var speed_buttons: Array = []
var hint_label: Label
var chip_buttons: Array = []
var chip_pips: Array = [] # per chip: route-state pip (grey/amber/green)
var chip_homes: Array = [] # per chip: home glyph, shown when a home is set
var clear_btn: Button
var action_btn: Button # RUN in PLAN, ABORT during a run
var _action_key := "" # last phase/ready pair the action button was styled for
var watch_banner: ColorRect = null
var watch_label: Label = null
var overlay: Control = null

const SPEEDS := [[0.0, "II"], [1.0, "1x"], [3.0, "3x"]]
const WATCH_TONES := {
	"naive": Color(0.62, 0.24, 0.20), # the obvious plan, in warning red
	"thesis": Color(0.16, 0.45, 0.26), # the level's answer, in confident green
	"best": Color(0.30, 0.32, 0.60), # what the search found, in machine blue
}


func _ready() -> void:
	headless = Levels3.headless
	if headless:
		set_process(false)
		return
	layer = 10
	_build_top()
	_build_panel()


func _process(_delta: float) -> void:
	if game != null:
		refresh_stats()


# ---------------------------------------------------------------- top bar

func _build_top() -> void:
	# The bar fills the 0..100 band above the grid (Grid3.GRID_Y_TOP), which is
	# what lets every button in it clear the 90 px one-thumb floor.
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.10)
	bg.position = Vector2.ZERO
	bg.size = Vector2(720, 98)
	add_child(bg)
	level_label = _make_label(Vector2(14, 28), 34, Color(0.95, 0.85, 0.5))
	level_label.text = "X-1"
	served_label = _make_label(Vector2(110, 12), 24, Color(0.45, 0.95, 0.55))
	lost_label = _make_label(Vector2(110, 52), 24, Color(1.0, 0.5, 0.45))
	menu_btn = Button.new()
	menu_btn.text = "LEVELS" # reads EXIT in watch mode (see refresh_stats)
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


# ---------------------------------------------------------------- bottom panel

func _build_panel() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.14)
	bg.position = Vector2(0, 1010)
	bg.size = Vector2(720, 270)
	add_child(bg)
	hint_label = _make_label(Vector2(14, 1016), 20, Color(1, 1, 1, 0.6))
	for i in 3:
		var btn := Button.new()
		btn.position = Vector2(14 + i * 172, 1046)
		btn.size = Vector2(160, 116)
		btn.add_theme_font_size_override("font_size", 18)
		var idx: int = i
		btn.pressed.connect(func(): game.select_card(idx))
		add_child(btn)
		chip_buttons.append(btn)
		# Route-state pip in the chip's top-right corner: grey none / amber
		# invalid (<2 stops) / green valid. Set every refresh_cards.
		var pip := ColorRect.new()
		pip.size = Vector2(22, 22)
		pip.position = Vector2(btn.size.x - 32, 10)
		pip.color = Color(0.42, 0.42, 0.48)
		btn.add_child(pip)
		chip_pips.append(pip)
		# Home glyph in the chip's top-left corner, shown only when a home is set.
		var home := Label.new()
		home.text = "⌂" # house
		home.position = Vector2(8, 4)
		home.add_theme_font_size_override("font_size", 24)
		home.visible = false
		btn.add_child(home)
		chip_homes.append(home)
	clear_btn = Button.new()
	clear_btn.text = "CLEAR"
	clear_btn.position = Vector2(546, 1046)
	clear_btn.size = Vector2(160, 116)
	clear_btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.18, 0.16)
	sb.set_corner_radius_all(8)
	clear_btn.add_theme_stylebox_override("normal", sb)
	clear_btn.visible = false
	clear_btn.pressed.connect(_on_clear)
	add_child(clear_btn)
	# The phase's one big action: RUN (commit the plan) or ABORT (back to it).
	# Full width and 96 px tall - this is the button the thumb lives on.
	action_btn = Button.new()
	action_btn.position = Vector2(14, 1174)
	action_btn.size = Vector2(692, 96)
	action_btn.add_theme_font_size_override("font_size", 32)
	action_btn.pressed.connect(_on_action)
	add_child(action_btn)
	# WATCHING banner (watch mode only): sits where the hint line lives.
	# Watch banner: a two-line band that owns the top of the panel; the chips
	# drop below it in watch mode (see refresh_cards). The label is width-bounded
	# and word-wraps so a long scenario description can never run off the screen.
	watch_banner = ColorRect.new()
	watch_banner.position = Vector2(0, 1010)
	watch_banner.size = Vector2(720, 66)
	watch_banner.visible = false
	add_child(watch_banner)
	watch_label = Label.new()
	watch_label.position = Vector2(14, 1014)
	watch_label.size = Vector2(692, 58)
	watch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	watch_label.add_theme_font_size_override("font_size", 20)
	watch_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	watch_label.visible = false
	add_child(watch_label)


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


## Style the RUN/ABORT button for the current phase (and hide it where the
## phase's action lives on an overlay instead). Called every frame from
## refresh_stats, so it only rebuilds the StyleBox when the look changes.
func _refresh_action() -> void:
	var watching: bool = game.watch != ""
	action_btn.visible = not watching \
			and (game.state == game.State.PLAN or game.state == game.State.PLAYING)
	if not action_btn.visible:
		return
	var running: bool = game.state == game.State.PLAYING
	var ready: bool = running or game.ready_to_run()
	var key := "%d%s" % [game.state, str(ready)]
	if key == _action_key:
		return
	_action_key = key
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


## Rebuild the chip visuals; call on any route or selection change.
func refresh_cards() -> void:
	if headless or game == null:
		return
	var watching: bool = game.watch != ""
	if watching:
		# One-time-ish banner setup (values never change mid-session).
		watch_banner.color = WATCH_TONES.get(game.watch, Color(0.3, 0.3, 0.3))
		var desc: String
		if game.watch == "best":
			desc = Discovered3.desc(game.level.id)
		else:
			var sets: Dictionary = Scenarios3.route_sets(game.level.id)
			desc = sets.get(game.watch, {}).get("desc", "")
		watch_label.text = "WATCHING: %s - %s" % [game.watch.to_upper(), desc]
	# In watch mode the chips sit BELOW the two-line watch banner; in PLAN/RUN
	# they sit under the hint line at the normal height.
	var chip_y: float = 1086.0 if watching else 1046.0
	for i in chip_buttons.size():
		var btn: Button = chip_buttons[i]
		btn.position.y = chip_y
		var card: Dictionary = game.CARDS[i]
		var route = game.routes[i]
		var car = game.cars[i]
		# TWO LINES ONLY (docs/ui-pass-spec.md §3): the card NAME, then a terse
		# spec `type · wN · C`. Route state moves off the text onto the pip and
		# the "needs 2 stops" wording stays on the hint line.
		var spec := "%s · w%d · %d" % [str(card.type),
				Levels3.card_width(card), Levels3.card_capacity(card)]
		btn.text = "%s\n%s" % [card.name, spec]
		# State pip: grey no route / amber drawn-but-invalid / green valid.
		var pip: ColorRect = chip_pips[i]
		if route == null:
			pip.color = Color(0.42, 0.42, 0.48)
		elif route.stop_cells().size() < 2:
			pip.color = Color(0.90, 0.65, 0.20)
		else:
			pip.color = Color(0.35, 0.80, 0.42)
		# Home glyph, tinted the card colour, shown only when a home is set.
		var home: Label = chip_homes[i]
		home.visible = car != null and car.home_cell != null
		if home.visible:
			home.add_theme_color_override("font_color",
					Color(card.color.lightened(0.3), 0.95))
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
		# Selectable in PLAN and nowhere else (watch mode, RUN, RESULT).
		btn.disabled = not game.can_edit()


## Cheap per-frame refresh of labels + contextual widgets.
func refresh_stats() -> void:
	if headless or game == null:
		return
	level_label.text = str(game.level.get("id", "X-1"))
	served_label.text = "Served %d/%d" % [game.served, game.QUOTA]
	lost_label.text = "Lost %d/%d" % [game.lost, game.MAX_LOST]
	if game.endless:
		served_label.text = "Served %d (endless)" % game.served
		lost_label.text = "Lost %d" % game.lost
	# Speed only means anything while the sim is running.
	var running: bool = game.state == game.State.PLAYING
	for i in speed_buttons.size():
		var active: bool = is_equal_approx(game.time_scale, SPEEDS[i][0])
		speed_buttons[i].visible = running
		speed_buttons[i].modulate = Color(1, 1, 1, 1.0) if active else Color(1, 1, 1, 0.45)
	var watching: bool = game.watch != ""
	menu_btn.text = "EXIT" if watching else "LEVELS"
	watch_banner.visible = watching
	watch_label.visible = watching
	hint_label.visible = not watching
	clear_btn.visible = game.can_edit() and game.selected_card >= 0 \
			and game.routes[game.selected_card] != null
	_refresh_action()
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
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	if game.state == game.State.PLAYING:
		hint_label.text = "Running - the network is locked. Watch it, then ABORT to replan."
		return
	if game.state != game.State.PLAN:
		hint_label.text = ""
		return
	# Corridor-rejection UX (v4): a refused commit surfaces its reason here in
	# the offending card's colour for a few seconds, over everything else.
	if game.reject_msg != "" and Time.get_ticks_msec() < game.reject_until_ms \
			and game.reject_card >= 0 and game.reject_card < game.CARDS.size():
		hint_label.text = game.reject_msg
		hint_label.add_theme_color_override("font_color",
				game.CARDS[game.reject_card].color.lightened(0.2))
		return
	var sel: int = game.selected_card
	if sel >= 0 and game.route_warning(sel):
		hint_label.text = "Route needs at least 2 room stops - drag again to redraw."
		hint_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		return
	var missing: Array = game.cards_not_ready()
	if not missing.is_empty():
		# The RUN button is disabled; say exactly which card is holding it up.
		hint_label.text = "PLAN - RUN needs a 2-stop route for: %s" % ", ".join(missing)
		hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
		return
	if game.drawing:
		hint_label.text = "Drag through open cells - release to commit the route"
	elif sel >= 0:
		hint_label.text = "Drag to redraw %s; TAP a cell of its route to set HOME" % game.CARDS[sel].name
	else:
		hint_label.text = "PLAN ready - tap a chip to redraw, or press RUN"


# ---------------------------------------------------------------- overlays

## THE BRIEFING (v4 phase 1). Every word below the title is generated from the
## level data by Levels3.briefing_body — thesis, intro, the elevator roster
## (type / capacity / speed character) and the passenger mix that will actually
## spawn — so it cannot describe a level the simulation is not running.
func show_briefing() -> void:
	if headless:
		return
	var lv: Dictionary = game.level
	_show_overlay("%s  %s" % [lv.id, str(lv.name).to_upper()],
			Levels3.briefing_body(lv),
			[{"text": "PLAN", "cb": func(): game.to_plan()}], 18)


func show_win(served: int, lost: int) -> void:
	if headless:
		return
	if game.watch != "":
		_show_overlay("%s WINS" % game.watch.to_upper(),
				"Quota met: served %d, lost %d." % [served, lost], _watch_buttons())
		return
	var buttons: Array = []
	if Levels3.current < Levels3.LEVELS.size() - 1:
		buttons.append({"text": "NEXT LEVEL", "cb": func(): game.next_level()})
	buttons.append({"text": "RETRY", "cb": func(): game.to_plan()})
	buttons.append({"text": "LEVEL SELECT", "cb": func(): game.to_level_select()})
	_show_overlay("QUOTA MET", _result_body(served, lost), buttons)


func show_lose(served: int, lost: int) -> void:
	if headless:
		return
	if game.watch != "":
		_show_overlay("%s LOSES" % game.watch.to_upper(),
				"Lost %d passengers (served %d)." % [lost, served], _watch_buttons())
		return
	_show_overlay("SHIFT FAILED", _result_body(served, lost),
			[
				{"text": "RETRY", "cb": func(): game.to_plan()},
				{"text": "LEVEL SELECT", "cb": func(): game.to_level_select()},
			])


## What the run actually did — the "learn" half of plan/run/learn/retry.
func _result_body(served: int, lost: int) -> String:
	var wait := 0.0
	for e in game.log_served:
		wait += e.wait
	if not game.log_served.is_empty():
		wait /= game.log_served.size()
	return "Served %d of %d, lost %d of %d.\nAverage wait %.0f s over %.0f s of shift.\nRETRY keeps your routes - redraw and run again." % [
			served, game.QUOTA, lost, game.MAX_LOST, wait, game.elapsed]


func _watch_buttons() -> Array:
	return [
		{"text": "WATCH AGAIN", "cb": func(): game.watch_again()},
		{"text": "LEVEL SELECT", "cb": func(): game.to_level_select()},
	]


func hide_overlay() -> void:
	if headless:
		return
	if overlay != null:
		overlay.queue_free()
		overlay = null


func _show_overlay(title_text: String, body_text: String, buttons: Array,
		body_size := 23) -> void:
	hide_overlay()
	overlay = Control.new()
	add_child(overlay)
	# A Control parented to a CanvasLayer has no anchorable parent rect, so
	# PRESET_FULL_RECT resolved against 0x0: the dim wash covered nothing and
	# every overlay sat jammed in the top-left corner. Size all three to the
	# viewport by hand instead — measured, not assumed (tools/run_depth.gd
	# --smoke checks the result stays inside 720x1280).
	var vp: Vector2 = get_viewport().get_visible_rect().size
	overlay.position = Vector2.ZERO
	overlay.size = vp
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	overlay.add_child(dim)
	dim.position = Vector2.ZERO
	dim.size = vp
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.position = Vector2.ZERO
	center.size = vp
	var box := VBoxContainer.new()
	# The briefing is a tall block of text; 30 px gaps push its button off a
	# 1280-high screen, so long bodies get tighter spacing.
	box.add_theme_constant_override("separation", 30 if body_size >= 23 else 18)
	center.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", body_size)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Hold the text inside the 720 px screen: a fixed column plus word wrap, so
	# a level whose intro has a long line wraps instead of running off the edge.
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
