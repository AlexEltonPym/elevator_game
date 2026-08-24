extends CanvasLayer
## Minimal v5 HUD, built in code, driven by main5's phase machine. Adapted from
## scripts/v3/hud3.gd but pared to the prototype: a variable roster of card
## chips (1..3), CLEAR, one big RUN/ABORT button, a hint line, and the
## WIN / LOSE overlays. There is no BRIEFING screen — picking a level lands
## straight in PLAN. RUN gates on the level's ACTUAL roster.

const StarBar5 := preload("res://scripts/v5/starbar5.gd")
const Ui5 := preload("res://scripts/v5/ui5.gd")
const SpeedBtn5 := preload("res://scripts/v5/speedbtn5.gd")
const Coin5 := preload("res://scripts/v5/coin5.gd")
const GhostDemo5 := preload("res://scripts/v5/ghost_demo5.gd")

# Bottom panel: chips only, pinned to the very bottom (matches Grid5.PLAY_BOTTOM so the
# building drops down and more sky shows above it).
const PANEL_TOP := 1150.0
const CHIP_H := 116.0
const CHIP_Y := 1156.0

var game = null # main5.gd


## Nearest Kenney button colour for a card's route colour (chips read as their lift colour).
func _knearest(c: Color) -> String:
	var h := c.h
	if c.s < 0.2:
		return "Grey"
	if h < 0.05 or h > 0.92:
		return "Red"
	if h < 0.12:
		return "Yellow"
	if h < 0.20:
		return "Yellow"
	if h < 0.45:
		return "Green"
	if h < 0.70:
		return "Blue"
	return "Blue"  # purples map to blue (no purple in the pack)

var level_label: Label
var served_label: Label
var lost_label: Label
var menu_btn: Button
var back_btn: TextureButton   # revert to plan (only shown mid-run)
var speed_play: Control   # SpeedBtn5 (play / run at 1x)
var speed_ff: Control     # SpeedBtn5 (fast-forward / run at 5x)
var chip_buttons: Array = []
var chip_dels: Array = []   # per-chip "×" delete buttons
var _last_serves: Array = [] # per-card serve counts last shown on the chips
var _demo_playing := false
var _demo_done := false
var _demo_paths: Array = []   # per-card {chip, pts, color} or null
var _demo_ghost = null        # GhostDemo5 overlay
var overlay: Control = null
var _chips_built := false
var headless := false


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
	# PLAY (1x) + FAST-FORWARD (5x) are the RUN trigger now: a tap in PLAN starts the run at
	# that speed; in PLAYING it just switches speed. Green "go" buttons. 1x reads smooth thanks
	# to render interpolation (main5.render_alpha), so it's a real "slow, watch it" pace.
	speed_play = SpeedBtn5.new()
	speed_play.kind = SpeedBtn5.Kind.PLAY
	speed_play.position = Vector2(438, 18)
	speed_play.size = Vector2(60, 62)
	speed_play.tapped.connect(func(): _on_speed(1.0))
	add_child(speed_play)
	speed_ff = SpeedBtn5.new()
	speed_ff.kind = SpeedBtn5.Kind.FF
	speed_ff.position = Vector2(504, 18)
	speed_ff.size = Vector2(60, 62)
	speed_ff.tapped.connect(func(): _on_speed(5.0))
	add_child(speed_ff)
	# BACK-TO-PLAN (abort) replaces the old RUN/ABORT bar's abort role; shown only mid-run.
	# Its PLAN-time empty slot is the room reserved for a future reset / mute button.
	# Revert-to-plan: just the user-supplied icon (no red button behind it).
	back_btn = TextureButton.new()
	back_btn.texture_normal = load("res://assets/ui/ic_system_undo_01_128.png")
	back_btn.ignore_texture_size = true
	back_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	back_btn.custom_minimum_size = Vector2(56, 52)
	back_btn.size = Vector2(56, 52)
	back_btn.position = Vector2(366, 22)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.visible = false
	back_btn.pressed.connect(func():
		if game != null:
			game.abort_run())
	add_child(back_btn)
	menu_btn = Ui5.make_button("LEVELS", "Grey", 20)
	menu_btn.position = Vector2(574, 6)
	menu_btn.size = Vector2(132, 86)
	menu_btn.pressed.connect(func():
		if game != null:
			game.to_level_select())
	add_child(menu_btn)


func _build_panel() -> void:
	# A thin panel that holds ONLY the lift chips (no hint text, no RUN bar). Everything sits
	# at the very bottom so the building drops down and more sky shows above it.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.14)
	bg.position = Vector2(0, PANEL_TOP)
	bg.size = Vector2(720, 1280 - PANEL_TOP)
	add_child(bg)
	# (No CLEAR button — each chip carries its own little "×" to clear its route.)


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
		btn.position = Vector2(14 + i * 172, CHIP_Y)
		btn.size = Vector2(cw, CHIP_H)
		btn.add_theme_font_size_override("font_size", 26)
		var cf = Ui5.font()
		if cf != null:
			btn.add_theme_font_override("font", cf)
		btn.focus_mode = Control.FOCUS_NONE   # no thin white focus rectangle on the chip
		var idx: int = i
		btn.pressed.connect(func(): game.select_card(idx))
		add_child(btn)
		chip_buttons.append(btn)
		# Round "×" delete bubble (top-right): a BORDERED red Kenney bubble + a clean drawn white
		# X (no outlined-sprite border). Shown only when placed; as a child button it eats its tap.
		var dsz := 40.0
		var del := TextureButton.new()
		del.texture_normal = Ui5.tex("Red/Default/button_round_flat.png")   # solid red bubble
		del.ignore_texture_size = true
		del.stretch_mode = TextureButton.STRETCH_SCALE
		del.custom_minimum_size = Vector2(dsz, dsz)
		del.size = Vector2(dsz, dsz)
		del.position = Vector2(cw - dsz + 2, -3)   # nudged up + right
		del.focus_mode = Control.FOCUS_NONE
		del.visible = false
		for ang in [45.0, -45.0]:
			var bar := ColorRect.new()
			bar.color = Color(1, 1, 1)
			bar.size = Vector2(dsz * 0.50, dsz * 0.145)
			bar.pivot_offset = bar.size * 0.5
			bar.position = Vector2(dsz * 0.5, dsz * 0.5) - bar.size * 0.5
			bar.rotation = deg_to_rad(ang)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			del.add_child(bar)
		var di: int = i
		del.pressed.connect(func(): if game != null: game.clear_route(di))
		btn.add_child(del)
		chip_dels.append(del)


## A PLAY / FAST-FORWARD tap: in PLAN it starts the run at that speed (once the plan is ready);
## mid-run it just switches speed.
func _on_speed(s: float) -> void:
	if game == null:
		return
	if game.state == game.State.PLAN:
		if game.ready_to_run():
			game.set_speed(s)
			game.start_run()
	elif game.state == game.State.PLAYING:
		game.set_speed(s)


## Keep the play/ff buttons and the mid-run BACK button in sync with the game state, and pulse
## the play button whenever there is a ready plan to run (the demo drives the pulse itself).
func _refresh_controls() -> void:
	if game == null or speed_play == null:
		return
	var planning: bool = game.state == game.State.PLAN
	var playing: bool = game.state == game.State.PLAYING
	var can_press: bool = playing or (planning and game.ready_to_run())
	speed_play.set_enabled(can_press)
	speed_ff.set_enabled(can_press)
	speed_play.set_active(playing and game.time_scale < 3.0)
	speed_ff.set_active(playing and game.time_scale >= 3.0)
	if back_btn != null:
		back_btn.visible = playing
	# The × delete bubbles are edit-only — hide them the moment the run starts (refresh_cards
	# might not fire on the state change if no serve-count changed).
	if not planning:
		for d in chip_dels:
			if is_instance_valid(d):
				d.visible = false
	# The play-button glow is a DEMO cue only — driven by _update_demo during the guided demo.
	# Outside the demo (all non-demo levels, and demo levels once seen) it never pulses.
	if not _demo_playing:
		speed_play.set_highlight(false)


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
		btn.text = str(card.name)
		var placed: bool = route != null
		var selected: bool = game.selected_card == i
		var sb := StyleBoxFlat.new()
		# DISCOLOUR to show "used": a placed lift desaturates toward grey; an unplaced one keeps
		# its full lift colour (inviting). Selected reads via the white border + a slight lift.
		var base := Color(card.color, 1.0).darkened(0.45)
		if placed:
			base = base.lerp(Color(0.24, 0.24, 0.27), 0.6)   # DISCOLOUR = used
		sb.bg_color = base
		sb.set_corner_radius_all(12)
		# Selected = ONLY a thick rounded border (no white fill rect, no bg tint change).
		if selected:
			sb.border_color = Color(0.98, 0.98, 1.0)
			sb.set_border_width_all(5)
		else:
			sb.border_color = card.color.darkened(0.35 if placed else 0.0)
			sb.set_border_width_all(2)
		for s in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(s, sb)
		# Chips stay clickable in PLAY too (to highlight the running line).
		btn.disabled = false
		if i < chip_dels.size():
			chip_dels[i].visible = placed and game.can_edit()


## Screen-space centre of lift chip `i` (where the ghost-hand demo "taps"). Falls back to the
## known panel layout if the chip button isn't laid out yet.
func chip_center(i: int) -> Vector2:
	if i >= 0 and i < chip_buttons.size() and chip_buttons[i] != null:
		var b: Control = chip_buttons[i]
		return b.position + b.size * 0.5
	return Vector2(93.0 + i * 172.0, CHIP_Y + CHIP_H * 0.5)


## Start the INTERACTIVE guided demo (see ghost_demo5.gd). `paths` is per-card
## ({chip, pts, color} or null). Unlike the old passive loop, this reacts to the player:
## it shows a TAP hint on the lift to pick, then a DRAW hint for the selected lift, and once
## any lift connects A->B (ready_to_run) it hides the finger and lights the play button.
## Non-blocking — the player interacts with the real UI the whole time.
func start_guided_demo(paths: Array) -> void:
	if headless:
		return
	_demo_paths = paths
	_demo_playing = true
	_demo_done = false
	_demo_ghost = GhostDemo5.new()
	add_child(_demo_ghost)
	_update_demo()


## A demo lift is DONE once it forms any valid A->B connection (serves >= 2 rooms) — "close
## enough", regardless of direction or which exact rooms. We deliberately do NOT demand the demo
## route's full room count: a rebel who draws a shorter/backwards/different-but-valid route has
## learned the gesture, so the guide stops nagging it and the play cue stays lit.
func _demo_undrawn(i: int) -> bool:
	var r = game.routes[i]
	return r == null or r.served_rooms().size() < 2


## First card that still needs drawing (no route / serves < 2) and has a demo path.
func _first_demo_target() -> int:
	for i in _demo_paths.size():
		if _demo_paths[i] != null and _demo_undrawn(i):
			return i
	return -1


func _update_demo() -> void:
	if _demo_ghost == null or not is_instance_valid(_demo_ghost) or game == null:
		return
	# The demo runs the whole PLAN phase and stays reactive: only when the player actually RUNS
	# (leaves PLAN) is it finished and marked seen. Clearing / deselecting mid-plan just returns
	# it to the matching stage.
	if game.state != game.State.PLAN:
		Levels5.mark_demo_seen(str(game.level.get("id", "")))
		_end_demo()
		return
	# Pick which lift to guide. If the player has SELECTED an undrawn demo lift, follow THAT one
	# (they may pick green before blue) and show only its drag-out. Otherwise guide the first
	# undrawn lift with the full tap+drag gesture. Either way the other lift adapts: once one is
	# drawn it drops out of the target list. Play glows only when every demo lift is drawn.
	var sel: int = game.selected_card
	var target := -1
	var by_selection := false
	if sel >= 0 and sel < _demo_paths.size() and _demo_paths[sel] != null and _demo_undrawn(sel):
		target = sel
		by_selection = true
	else:
		target = _first_demo_target()
	if target < 0:
		speed_play.set_highlight(true)
		_demo_ghost.guide_idle()
		return
	speed_play.set_highlight(false)
	var p: Dictionary = _demo_paths[target]
	if by_selection:
		_demo_ghost.guide_draw(p.pts, p.color)
	else:
		_demo_ghost.guide_full(p.chip, p.pts, p.color)


func _end_demo(clear_glow := true) -> void:
	_demo_playing = false
	if _demo_ghost != null and is_instance_valid(_demo_ghost):
		_demo_ghost.queue_free()
	_demo_ghost = null
	if clear_glow and speed_play != null:
		speed_play.set_highlight(false)


## A served passenger sends a tip coin arcing from its spot (screen pos) up to the TIPS
## counter, which pops when the coin lands. Purely visual — makes "tips come from passengers"
## legible. `side` (deterministic, from the served count) just varies the arc left/right.
func fly_coin(from: Vector2, side: float, count := 1) -> void:
	if headless or served_label == null:
		return
	# count>1 = a cargo 5x burst: fan the coins out with a per-coin offset + stagger so it
	# visibly reads as five coins, not one.
	var n := maxi(count, 1)
	for i in n:
		var off := Vector2.ZERO
		var delay := 0.0
		if n > 1:
			var frac := float(i) / float(n - 1)
			off = Vector2((frac - 0.5) * 58.0, -float(i % 4) * 9.0)   # fan out, gentle vertical scatter
			delay = float(i) * clampf(0.5 / float(n), 0.02, 0.06)     # total stagger ~0.5s
		_fly_one(from + off, side * (1.0 if i % 2 == 0 else -1.0), delay, i == n - 1)


func _fly_one(from: Vector2, side: float, delay: float, bump: bool) -> void:
	var coin := Coin5.new()
	coin.position = from
	coin.modulate.a = 0.0
	add_child(coin)
	var to: Vector2 = served_label.global_position + Vector2(46.0, 16.0)
	var mid: Vector2 = from.lerp(to, 0.5) + Vector2(side * 30.0, -120.0)
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	# NOTE: the quadratic bezier is inlined — calling the static _qbez() from inside this lambda
	# failed ("base Nil") and silently aborted the callback, leaving every coin at alpha 0 (why
	# they were invisible). Inlining keeps the arc self-contained.
	tw.tween_method(func(t: float):
		var u := 1.0 - t
		coin.position = u * u * from + 2.0 * u * t * mid + t * t * to
		var s := lerpf(1.15, 0.6, t)
		coin.scale = Vector2(s, s)
		coin.modulate.a = 1.0 if t < 0.85 else lerpf(1.0, 0.0, (t - 0.85) / 0.15),
			0.0, 1.0, 0.72).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if is_instance_valid(coin):
			coin.queue_free()
		if bump:
			_bump_tips())


## A quick scale-pop on the Tips counter when a coin lands.
func _bump_tips() -> void:
	if served_label == null:
		return
	served_label.pivot_offset = served_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(served_label, "scale", Vector2(1.22, 1.22), 0.06)
	tw.tween_property(served_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)


static func _qbez(a: Vector2, m: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * m + t * t * b


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
	if _serves_changed():
		refresh_cards()
	_refresh_controls()
	if _demo_playing:
		_update_demo()


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



# ---------------------------------------------------------------- overlays

const Victory5 := preload("res://scripts/v5/victory5.gd")
const WORLD_ACCENT := {
	"TUTORIAL": Color(0.42, 0.62, 0.88),
	"CROSSLINK": Color(0.35, 0.74, 0.72),
}

func show_win(served: int, lost: int) -> void:
	if headless:
		return
	# Shift levels with stars get the animated Overcooked-style victory overlay.
	if game.shift_len > 0.0 and not (game.level.get("stars", []) as Array).is_empty():
		hide_overlay()
		var v := Victory5.new()
		overlay = v
		add_child(v)
		v.show_result({
			"game": game,
			"accent": WORLD_ACCENT.get(str(game.level.get("world", "")), Color(0.5, 0.6, 0.8)),
			"is_last": Levels5.current >= Levels5.LEVELS.size() - 1,
			"on_next": func(): game.next_level(),
			"on_retry": func(): game.to_plan(),
			"on_menu": func(): game.to_level_select(),
		})
		return
	# Fallback (classic quota mode, e.g. the smoke): the plain overlay.
	var buttons: Array = []
	if Levels5.current < Levels5.LEVELS.size() - 1:
		buttons.append({"text": "NEXT LEVEL", "cb": func(): game.next_level()})
	buttons.append({"text": "RETRY", "cb": func(): game.to_plan()})
	buttons.append({"text": "LEVEL SELECT", "cb": func(): game.to_level_select()})
	_show_overlay("QUOTA MET", _result_body(served, lost), buttons, 23)


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
	var f = Ui5.font()
	if f != null:
		l.add_theme_font_override("font", f)
	add_child(l)
	return l
