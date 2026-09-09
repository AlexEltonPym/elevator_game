extends Control
## MAIN MENU — the project's BOOT scene (project.godot run/main_scene). A living title card:
## Background5 runs a slow ambient dawn <-> dusk loop behind a primitive-drawn cutaway tower
## (the "ROOMS" logo, built from the real ROOM_STYLE colours, with two ambient lift cars) and
## the businessman commutes along the pavement. PLAY -> level select, ALMANAC -> almanac5.
## Pure render/UI: nothing here touches the sim or the fingerprint.

const Ui5 := preload("res://scripts/v5/ui5.gd")
const Grid5 := preload("res://scripts/v5/grid5.gd")
const Passenger5 := preload("res://scripts/v5/passenger5.gd")
const Background5 := preload("res://scripts/v5/background5.gd")
const ALMANAC_SCRIPT := "res://scripts/v5/almanac5.gd"
const ALMANAC_SCENE := "res://scenes/v5_almanac.tscn"

const VP := Vector2(720.0, 1280.0)
const GY := 900.0             # street line the tower stands on (published to Grid5.GROUND_Y)
const CELL := 46.0
const TOWER_COLS := 6         # [room][room][shaft][room][room][shaft]
const TOWER_ROWS := 9
const SHAFT_COLS := [2, 5]
const DAY_LOOP := 150.0       # seconds for one dawn -> dusk -> dawn ambient cycle

# Room pairs per floor (row 0 = ground). Each floor has a 2-cell room left of each shaft.
const FLOORS := [
	["lobby", "lobby"],
	["office", "cafe"],
	["office", "office"],
	["delivery", "office"],
	["atrium", "atrium"],
	["office", "cafe"],
	["office", "office"],
	["office", "atrium"],
	["penthouse", "penthouse"],
]
const CAR_COLS := [Color(0.45, 0.68, 0.95), Color(0.98, 0.68, 0.2)]   # Levels5 COL_A / COL_C


## Duck-typed shift clock for Background5 (it reads game.shift_len / game.elapsed). We drive it
## as a triangle wave so the sky eases dawn -> night -> dawn with no hard cut.
class DayClock:
	var shift_len := 150.0
	var elapsed := 0.0


var _clock := DayClock.new()
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _cars: Array = []       # {col, y (rows, float), target (int), wait, spd}
var _walkers: Array = []    # {x, dir, spd, frame, ft, h}
var _font = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = Ui5.font()
	_rng.seed = 5150
	Grid5.GROUND_Y = GY
	Passenger5._load_npc()
	# Living sky / skyline / ground behind everything (z -100 puts it under this Control's draw).
	var bg = Background5.new()
	bg.game = _clock
	add_child(bg)
	# Ambient lift cars, one per shaft.
	for i in SHAFT_COLS.size():
		_cars.append({"col": int(SHAFT_COLS[i]), "y": float(i * 3), "target": (i * 3 + 4) % TOWER_ROWS,
				"wait": 0.6 + 0.9 * float(i), "spd": 1.6})
	# Commuters on the pavement: one each way, offset phases.
	if Passenger5._bm_tex != null:
		_walkers.append({"x": 120.0, "dir": 1, "spd": 46.0, "frame": 0, "ft": 0.0, "h": 46.0})
		_walkers.append({"x": 600.0, "dir": -1, "spd": 40.0, "frame": 3, "ft": 0.05, "h": 44.0})
	_build_ui()


func _build_ui() -> void:
	var play := Ui5.make_button("PLAY", "Green", 44)
	play.size = Vector2(420, 112)
	play.position = Vector2((VP.x - play.size.x) / 2.0, 972)
	play.pressed.connect(func():
		Levels5.autosolve = false
		get_tree().change_scene_to_file("res://scenes/v5_select.tscn"))
	add_child(play)

	var alm_txt := "ALMANAC"
	var alm_ok := ResourceLoader.exists(ALMANAC_SCENE) and ResourceLoader.exists(ALMANAC_SCRIPT)
	if alm_ok:
		var s = load(ALMANAC_SCRIPT)
		var has := false
		if s != null:
			for m in s.get_script_method_list():
				if str(m.name) == "unlocked_counts":
					has = true
		if has:
			var c: Dictionary = s.unlocked_counts()
			var got: int = int(c.people[0]) + int(c.rooms[0])
			var tot: int = int(c.people[1]) + int(c.rooms[1])
			alm_txt = "ALMANAC   %d / %d" % [got, tot]
	var alm := Ui5.make_button(alm_txt, "Yellow", 32)
	alm.size = Vector2(420, 92)
	alm.position = Vector2((VP.x - alm.size.x) / 2.0, 1102)
	alm.disabled = not alm_ok
	alm.pressed.connect(func(): get_tree().change_scene_to_file(ALMANAC_SCENE))
	add_child(alm)

	# Progress line under the buttons.
	var p := _progress()
	var lbl := Label.new()
	lbl.text = "%d / %d LEVELS CLEARED     %d STARS" % [p[0], p[1], p[2]]
	lbl.position = Vector2(0, 1214)
	lbl.size = Vector2(VP.x, 40)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.93, 0.94, 0.98, 0.85))
	if _font != null:
		lbl.add_theme_font_override("font", _font)
	add_child(lbl)


## [levels cleared, levels total, stars earned] from the persisted best-stars table.
func _progress() -> Array:
	var cleared := 0
	var stars := 0
	for lv in Levels5.LEVELS:
		var b: int = Levels5.best_stars(str(lv.id))
		if b > 0:
			cleared += 1
		stars += b
	return [cleared, Levels5.LEVELS.size(), stars]


func _process(dt: float) -> void:
	_t += dt
	# Triangle-wave day: 0 -> 1 -> 0 over DAY_LOOP seconds (no snap back to dawn).
	var u := fmod(_t, DAY_LOOP) / DAY_LOOP
	_clock.elapsed = _clock.shift_len * (1.0 - absf(1.0 - 2.0 * u))
	for c in _cars:
		if c.wait > 0.0:
			c.wait -= dt
			continue
		c.y = move_toward(c.y, float(c.target), c.spd * dt)
		if is_equal_approx(c.y, float(c.target)):
			c.wait = _rng.randf_range(1.0, 2.4)
			var nt: int = c.target
			while nt == c.target:
				nt = _rng.randi_range(0, TOWER_ROWS - 1)
			c.target = nt
	for w in _walkers:
		w.x += float(w.dir) * w.spd * dt
		if w.dir > 0 and w.x > VP.x + 40.0:
			w.x = -40.0
		elif w.dir < 0 and w.x < -40.0:
			w.x = VP.x + 40.0
		w.ft += dt
		if w.ft > 0.13:
			w.ft = 0.0
			w.frame = (w.frame + 1) % Passenger5.BM_COLS
	queue_redraw()


func _night() -> float:
	return smoothstep(0.72, 0.98, _clock.elapsed / _clock.shift_len)


func _draw() -> void:
	_draw_tower()
	_draw_walkers()
	_draw_title()
	# Soft plinth so the buttons sit on a calm band rather than raw dirt.
	var pl := Rect2(0.0, 940.0, VP.x, VP.y - 940.0)
	draw_rect(pl, Color(0.06, 0.06, 0.09, 0.55))


## The logo tower: a concrete cutaway with real-palette rooms, two shafts with roaming cars, a
## lobby door on the street and a roof cap. Windows warm up as the ambient day turns to night.
func _draw_tower() -> void:
	var night := _night()
	var w := CELL * TOWER_COLS
	var h := CELL * TOWER_ROWS
	var x0 := (VP.x - w) / 2.0
	var y0 := GY - h
	var wall := 10.0
	# Concrete shell + roof slab.
	draw_rect(Rect2(x0 - wall, y0 - wall, w + 2.0 * wall, h + wall), Grid5.BUILDING_FILL)
	draw_rect(Rect2(x0 - wall - 8.0, y0 - wall - 10.0, w + 2.0 * wall + 16.0, 12.0),
			Grid5.BUILDING_FILL.lightened(0.12))
	# Rooms + shafts, floor by floor (row 0 = street level).
	for r in TOWER_ROWS:
		var ry := GY - CELL * float(r + 1)
		var types: Array = FLOORS[r]
		var ci := 0
		for c in TOWER_COLS:
			var cx := x0 + CELL * float(c)
			if c in SHAFT_COLS:
				draw_rect(Rect2(cx, ry, CELL, CELL), Color(0.11, 0.11, 0.14))
				continue
			# a 2-cell room: this cell + the next (pair index from the column)
			var t: String = str(types[ci / 2]) if ci / 2 < types.size() else "office"
			ci += 1
			var style: Dictionary = Grid5.ROOM_STYLE.get(t, Grid5.ROOM_STYLE["office"])
			var bg: Color = style.bg
			var cr := Rect2(cx, ry, CELL, CELL).grow(-1.0)
			draw_rect(cr, bg)
			draw_rect(Rect2(cr.position + Vector2(0.0, cr.size.y - 5.0), Vector2(cr.size.x, 5.0)),
					bg.darkened(0.35))                         # floor slab
			draw_rect(Rect2(cr.position + Vector2(cr.size.x * 0.28, 3.0), Vector2(cr.size.x * 0.44, 4.0)),
					bg.lightened(0.30))                        # skylight
			if night > 0.02:                                   # lit window at night
				draw_rect(cr.grow(-6.0), Color(1.0, 0.83, 0.45, 0.35 * night))
	# Room-pair outlines in the type line colour (drawn after so they sit on top).
	for r in TOWER_ROWS:
		var ry := GY - CELL * float(r + 1)
		var types: Array = FLOORS[r]
		for p in 2:
			var t: String = str(types[p])
			var style: Dictionary = Grid5.ROOM_STYLE.get(t, Grid5.ROOM_STYLE["office"])
			var px := x0 + CELL * float(p * 3)
			draw_rect(Rect2(px, ry, CELL * 2.0, CELL), Color(style.line, 0.9), false, 2.0)
	# Cars: a coloured cabin with a door seam, riding the shaft.
	for c in _cars:
		var cx := x0 + CELL * float(c.col)
		var cy := GY - CELL * (float(c.y) + 1.0)
		var body := Rect2(cx + 4.0, cy + 4.0, CELL - 8.0, CELL - 8.0)
		var col: Color = CAR_COLS[SHAFT_COLS.find(int(c.col)) % CAR_COLS.size()]
		draw_rect(body, col)
		draw_rect(body, col.darkened(0.45), false, 2.0)
		draw_line(Vector2(body.get_center().x, body.position.y + 3.0),
				Vector2(body.get_center().x, body.end.y - 3.0), col.darkened(0.45), 2.0)
	# Street door on the lobby.
	var dx := x0 + CELL * 0.5
	draw_rect(Rect2(dx, GY - 30.0, 22.0, 30.0), Color(0.42, 0.30, 0.16))
	draw_rect(Rect2(dx, GY - 30.0, 22.0, 30.0), Color(0.25, 0.17, 0.09), false, 2.0)


func _draw_walkers() -> void:
	var tex: Texture2D = Passenger5._bm_tex
	if tex == null:
		return
	for w in _walkers:
		var bh: float = w.h
		var bw: float = bh * float(Passenger5.BM_CW) / float(Passenger5.BM_CH)
		var row := 1 if w.dir > 0 else 0
		var src := Rect2(w.frame * Passenger5.BM_CW, row * Passenger5.BM_CH,
				Passenger5.BM_CW, Passenger5.BM_CH)
		draw_texture_rect_region(tex, Rect2(w.x - bw / 2.0, GY - bh, bw, bh), src)


func _draw_title() -> void:
	var f = _font if _font != null else ThemeDB.fallback_font
	var gold := Color(0.96, 0.85, 0.5)
	var shadow := Color(0.05, 0.05, 0.08, 0.85)
	_centered(f, "ELEVATORS", 34, 208.0, Color(0.93, 0.94, 0.98, 0.9), shadow)
	_centered(f, "ROOMS", 132, 336.0, gold, shadow)


func _centered(f: Font, s: String, sz: int, baseline: float, col: Color, shadow: Color) -> void:
	var ts: Vector2 = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	var x := (VP.x - ts.x) / 2.0
	draw_string(f, Vector2(x + 4.0, baseline + 4.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, shadow)
	draw_string(f, Vector2(x, baseline), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
