extends Control
## ALMANAC — the in-game field guide. Two families (PEOPLE / ROOMS), one tab each, a
## touch-scrolling list of collectible CARDS: an animated portrait (or a board-exact room
## emblem), the name, a one-line role in the game's voice, and a row of stat chips whose facts
## are read straight from the sim tables (Passenger5.PTYPES, Pathfind5.HUB_TYPES, main5's
## tip multipliers). An entry UNLOCKS once the player has cleared (>= 1 star) any level that
## FEATURES it; locked entries show a silhouette, "???" and a "CLEAR T-4" hint so the guide
## also works as a map of what is still out there.
##
## Static API (used by the main menu to label its ALMANAC button):
##   unlocked_counts() -> {"people": [got, total], "rooms": [got, total]}
## Dev: press U on the screen to toggle a NON-persisted reveal-all (never writes progress).

const Ui5 := preload("res://scripts/v5/ui5.gd")
const Passenger5 := preload("res://scripts/v5/passenger5.gd")
const Grid5 := preload("res://scripts/v5/grid5.gd")
const Pathfind5 := preload("res://scripts/v5/pathfind5.gd")
const Select5 := preload("res://scripts/v5/select5.gd")

const BG := Color(0.09, 0.09, 0.12)
const PANEL := Color(0.13, 0.14, 0.19)
const PLATE := Color(0.09, 0.10, 0.14)
const GOLD := Color(0.96, 0.85, 0.5)
const BODY := Color(0.93, 0.94, 0.98)
const DIM := Color(0.62, 0.64, 0.72)
const LOCK_INK := Color(0.17, 0.18, 0.24)      # silhouette colour for locked portraits
const COL_EXPRESS := Color(0.97, 0.58, 0.17)   # intro_card5's lift accents
const COL_CARGO := Color(0.96, 0.82, 0.26)
const COL_PAY := Color(0.5, 0.88, 0.55)
const COL_HUB := Color(0.73, 0.61, 0.83)       # the atrium's purple = "transfer" in this game
const COL_NOTE := Color(0.55, 0.58, 0.68)

## Pay multipliers as coded in main5.on_served (cargo loaded leg 5x, executives 2x).
const PAY_CARGO := 5
const PAY_EXEC := 2

## The guide. `id` is the passenger type (people) or the room type (rooms). Chips are
## [text, kind]; kind picks the accent colour. Patience / width chips are generated from
## Passenger5.PTYPES at build time so the numbers can't drift from the sim.
const ENTRIES := [
	{"family": "people", "id": "visitor", "name": "VISITOR",
		"role": "The everyday commuter. Lobby to office, office to cafe, and home again.",
		"chips": [["STANDARD TIP", "pay"]]},
	{"family": "people", "id": "patient", "name": "PATIENT",
		"role": "Here for an appointment and watching the clock. Don't keep them waiting.",
		"chips": [["STANDARD TIP", "pay"]]},
	{"family": "people", "id": "shopper", "name": "SHOPPER",
		"role": "Browsing, no rush. The most forgiving rider in the building.",
		"chips": [["STANDARD TIP", "pay"]]},
	{"family": "people", "id": "delivery", "name": "DELIVERY MAN",
		"role": "Pushes a two-box cart from the bay to the cafe, then walks back empty.",
		"chips": [["PAYS %dx LOADED" % PAY_CARGO, "pay"], ["2x SLOWER LOADED", "note"],
				["RETURNS TO BAY", "note"]]},
	{"family": "people", "id": "executive", "name": "EXECUTIVE",
		"role": "A VIP bound for the penthouse. Impatient, and tips big for a fast ride.",
		"chips": [["PAYS %dx" % PAY_EXEC, "pay"], ["EXPRESS IS THE PLAY", "express"]]},
	{"family": "rooms", "id": "lobby", "name": "LOBBY",
		"role": "The front door. Everyone starts here, and lifts can be switched here.",
		"chips": [["GROUND FLOOR", "note"]]},
	{"family": "rooms", "id": "office", "name": "OFFICE",
		"role": "Where the commuters work. Rides to the lobby, and out to the cafe for lunch.",
		"chips": [["COMMUTER DEMAND", "note"]]},
	{"family": "rooms", "id": "cafe", "name": "CAFE",
		"role": "The building's meeting point. Draws lunch traffic and takes every delivery.",
		"chips": [["FREIGHT DROP", "cargo"]]},
	{"family": "rooms", "id": "atrium", "name": "ATRIUM",
		"role": "A public floor. Riders walk across it to change lifts, and lose no patience waiting.",
		"chips": [["SHARED DROPOFF", "note"], ["PATIENCE PAUSED", "time"]]},
	{"family": "rooms", "id": "delivery", "name": "DELIVERY BAY",
		"role": "Where the freight starts. The delivery man loads up here and comes home here.",
		"chips": [["FREIGHT ORIGIN", "cargo"], ["CARGO LIFT", "cargo"]]},
	{"family": "rooms", "id": "penthouse", "name": "PENTHOUSE",
		"role": "The top floor, executives only. Get them up fast on the express.",
		"chips": [["EXECUTIVES", "note"], ["EXPRESS", "express"]]},
]

const CARD_W := 672.0
const MARGIN := 24.0
const SCROLL_TOP := 232.0

var family := "people"
var reveal := false                 # dev reveal-all; never persisted
var _scroll: ScrollContainer
var _list: VBoxContainer
var _tab_btn := {}


# ---------------------------------------------------------------- unlock rules (static)

## Does this level FEATURE the entry? Rooms: a room of that type. People: visitor is in every
## level; patient/shopper via the mix (weight > 0) or a manifest entry; delivery via a manifest
## entry, a delivery room or a cargo card; executive via a manifest entry or a penthouse room.
static func level_features(lv: Dictionary, fam: String, id: String) -> bool:
	var rooms: Array = lv.get("rooms", [])
	if fam == "rooms":
		for r in rooms:
			if str(r.get("type", "")) == id:
				return true
		return false
	if id == "visitor":
		return true
	var manifest: Array = lv.get("manifest", [])
	for m in manifest:
		if str(m.get("type", "")) == id:
			return true
	if id == "patient" or id == "shopper":
		var mix: Dictionary = lv.get("mix", {})
		return float(mix.get(id, 0.0)) > 0.0
	if id == "delivery":
		for r in rooms:
			if str(r.get("type", "")) == "delivery":
				return true
		for c in lv.get("cards", []):
			if str(c.get("type", "")) == "cargo":
				return true
		return false
	if id == "executive":
		for r in rooms:
			if str(r.get("type", "")) == "penthouse":
				return true
	return false


## The earliest featuring level (table order), or {} if none.
static func first_level(fam: String, id: String) -> Dictionary:
	for lv in Levels5.LEVELS:
		if level_features(lv, fam, id):
			return lv
	return {}


## Unlocked iff any featuring level has been cleared with >= 1 star.
static func is_unlocked(fam: String, id: String) -> bool:
	for lv in Levels5.LEVELS:
		if level_features(lv, fam, id) and Levels5.best_stars(str(lv.get("id", ""))) >= 1:
			return true
	return false


## {"people": [got, total], "rooms": [got, total]} — for the main menu's ALMANAC label.
static func unlocked_counts() -> Dictionary:
	var out := {"people": [0, 0], "rooms": [0, 0]}
	for e in ENTRIES:
		var fam: String = e.family
		out[fam][1] += 1
		if is_unlocked(fam, e.id):
			out[fam][0] += 1
	return out


# ---------------------------------------------------------------- screen

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Passenger5._load_npc()
	_rebuild()


## Dev reveal-all (U key / the shot tool). Purely in-memory: never touches the stars file.
func set_reveal(v: bool) -> void:
	reveal = v
	_rebuild()


func show_family(fam: String) -> void:
	family = fam
	_rebuild()


func scroll_to_end() -> void:
	if _scroll != null:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		_back()
	elif event.keycode == KEY_U:
		set_reveal(not reveal)


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/v5_menu.tscn")


func _kfont(l: Control) -> void:
	var f = Ui5.font()
	if f != null:
		l.add_theme_font_override("font", f)


func _rebuild() -> void:
	var keep := 0
	if _scroll != null:
		keep = _scroll.scroll_vertical
	for c in get_children():
		c.queue_free()
	var vp: Vector2 = get_viewport().get_visible_rect().size

	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	# BACK (mirrors the select pager button) + title.
	var back := Ui5.make_button("", "Grey", 20)
	back.icon = Ui5.arrow_tex("w")
	back.position = Vector2(16, 26)
	back.size = Vector2(80, 76)
	back.pressed.connect(_back)
	add_child(back)

	var title := Label.new()
	title.text = "ALMANAC"
	title.position = Vector2(104, 26)
	title.size = Vector2(vp.x - 208, 56)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kfont(title)
	add_child(title)

	# Discovered count + a thin gold progress bar: the collectible pull.
	var counts := unlocked_counts()
	var got: int = counts.people[0] + counts.rooms[0]
	var total: int = counts.people[1] + counts.rooms[1]
	if reveal:
		got = total
	var sub := Label.new()
	sub.text = "FIELD GUIDE   %d / %d DISCOVERED" % [got, total]
	if reveal:
		sub.text += "   (REVEAL)"
	sub.position = Vector2(104, 82)
	sub.size = Vector2(vp.x - 208, 30)
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kfont(sub)
	add_child(sub)
	var bar := Progress.new()
	bar.frac = float(got) / float(maxi(1, total))
	bar.position = Vector2(MARGIN, 118)
	bar.size = Vector2(CARD_W, 6)
	add_child(bar)

	# PEOPLE / ROOMS tabs (>= 88 px tall touch targets; the active one is the yellow skin).
	var tw := (CARD_W - 10.0) / 2.0
	var k := 0
	for fam in ["people", "rooms"]:
		var n: Array = counts[fam]
		var shown: int = n[1] if reveal else n[0]
		var b := Ui5.make_button("%s  %d/%d" % [fam.to_upper(), shown, n[1]],
				"Yellow" if fam == family else "Grey", 26)
		b.position = Vector2(MARGIN + k * (tw + 10.0), 134)
		b.size = Vector2(tw, 88)
		var f2: String = fam
		b.pressed.connect(func(): show_family(f2))
		add_child(b)
		_tab_btn[fam] = b
		k += 1

	# The scrolling card list. Vertical only, no visible bar (touch drag / wheel); a fade at the
	# bottom hints there is more, and a spacer keeps the last card clear of it.
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(MARGIN, SCROLL_TOP)
	_scroll.size = Vector2(CARD_W, vp.y - SCROLL_TOP)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	_scroll.add_child(_list)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(CARD_W, 4)
	_list.add_child(top_pad)
	for e in ENTRIES:
		if e.family != family:
			continue
		var card := Card.new()
		card.setup(e, reveal or is_unlocked(e.family, e.id), first_level(e.family, e.id))
		_list.add_child(card)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CARD_W, 70)
	_list.add_child(pad)
	_scroll.scroll_vertical = keep

	var fade := Fade.new()
	fade.position = Vector2(0, vp.y - 72)
	fade.size = Vector2(vp.x, 72)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


# ---------------------------------------------------------------- helpers shared by cards

## Static drawing helpers in their own inner class so the Card / Progress / Fade inner
## classes can reach them (inner classes can't call the outer script's statics unqualified).
class Draw:
	static func font():
		var f = Ui5.font()
		return f if f != null else ThemeDB.fallback_font

	static func panel(ci: CanvasItem, rect: Rect2, col: Color, rad: float, filled := true, w := 2.0) -> void:
		if filled:
			ci.draw_rect(Rect2(rect.position + Vector2(rad, 0), rect.size - Vector2(2 * rad, 0)), col)
			ci.draw_rect(Rect2(rect.position + Vector2(0, rad), rect.size - Vector2(0, 2 * rad)), col)
			for c in [rect.position + Vector2(rad, rad), Vector2(rect.end.x - rad, rect.position.y + rad),
					Vector2(rect.position.x + rad, rect.end.y - rad), rect.end - Vector2(rad, rad)]:
				ci.draw_circle(c, rad, col)
		else:
			ci.draw_rect(rect.grow(-1.0), col, false, w)

	static func chip_color(kind: String) -> Color:
		match kind:
			"time": return GOLD
			"pay": return COL_PAY
			"hub": return COL_HUB
			"express": return COL_EXPRESS
			"cargo": return COL_CARGO
			"lift": return Color(0.45, 0.68, 0.95)
			_: return COL_NOTE


## The thin gold discovered-progress bar under the subtitle.
class Progress extends Control:
	var frac := 0.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.21, 0.28))
		if frac > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * frac, size.y)), GOLD)


## Bottom-of-screen fade (bg colour, alpha 0 -> 1) so the list reads as scrollable.
class Fade extends Control:
	func _draw() -> void:
		var c0 := Color(BG, 0.0)
		var c1 := Color(BG, 1.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y),
				Vector2(0, size.y)]), PackedColorArray([c0, c0, c1, c1]))


## One almanac card: portrait plate on the left (animated), name / role / chips on the right.
## Locked = silhouette + "???" + the "CLEAR T-4" hint chip.
class Card extends Control:
	const PAD := 14.0
	const PLATE_S := 168.0
	const TEXT_X := 198.0
	const CHIP_H := 34.0
	const CHIP_FS := 18
	const CHIP_GAP := 6.0
	const CHIPS_Y := 126.0

	var entry := {}
	var unlocked := true
	var first := {}
	var chips: Array = []          # [{text, col, rect}]
	var accent := Color.WHITE
	var _anim := 0
	var _anim_t := 0.0
	var _furn: Texture2D = null
	var _role: Label

	func setup(e: Dictionary, unl: bool, first_lv: Dictionary) -> void:
		entry = e
		unlocked = unl
		first = first_lv
		var f = Draw.font()
		var seen_col: Color = Select5.WORLD_COL.get(str(first.get("world", "")), DIM)
		var raw: Array = []
		if unlocked:
			if e.family == "people":
				var pt: Dictionary = Passenger5.PTYPES.get(e.id, {})
				raw.append(["PATIENCE %ds" % int(pt.get("patience", 0.0)), "time"])
				if int(pt.get("width", 1)) >= 3:
					raw.append(["WIDTH 3: CARGO LIFT ONLY", "cargo"])
				else:
					raw.append(["FITS ANY LIFT", "lift"])
			elif Pathfind5.HUB_TYPES.has(e.id):
				raw.append(["TRANSFER HUB", "hub"])
			else:
				raw.append(["NO TRANSFERS", "note"])
			for c in e.chips:
				raw.append(c)
			if not first.is_empty():
				raw.append(["FIRST SEEN %s" % str(first.id), "seen"])
		else:
			if first.is_empty():
				raw.append(["NOT IN ANY LEVEL YET", "note"])
			else:
				raw.append(["CLEAR %s TO UNLOCK" % str(first.id), "seen"])
		# Lay the chips out in wrapped rows now, so the card knows its own height.
		var avail := CARD_W - TEXT_X - PAD
		var x := TEXT_X
		var y := CHIPS_Y
		for c in raw:
			var text: String = c[0]
			var col: Color = seen_col if c[1] == "seen" else Draw.chip_color(c[1])
			var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FS).x + 26.0
			if x + w > TEXT_X + avail and x > TEXT_X:
				x = TEXT_X
				y += CHIP_H + CHIP_GAP
			chips.append({"text": text, "col": col, "rect": Rect2(x, y, w, CHIP_H)})
			x += w + CHIP_GAP
		var h: float = maxf(PLATE_S + 2.0 * PAD, y + CHIP_H + PAD + 2.0)
		custom_minimum_size = Vector2(CARD_W, h)
		size_flags_horizontal = Control.SIZE_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS   # a drag over a card scrolls the list
		# Identity accent: the room's board colour, or the passenger type colour.
		if e.family == "rooms":
			accent = Grid5.ROOM_STYLE[e.id].bg
			var fp: String = Grid5._PS + str(Grid5.ROOM_STYLE[e.id].furn)
			if ResourceLoader.exists(fp):
				_furn = load(fp)
		else:
			accent = Passenger5.PTYPES[e.id].color
		if not unlocked:
			accent = Color(0.3, 0.31, 0.38)
		# Pixel art stays crisp; the hi-res businessman sheet is downscaled, so keep it smooth.
		var hires: bool = e.family == "people" and e.id != "executive" and e.id != "delivery"
		texture_filter = TEXTURE_FILTER_LINEAR if hires else TEXTURE_FILTER_NEAREST
		# Role copy (autowrapped Label).
		_role = Label.new()
		var kf = Ui5.font()
		if kf != null:
			_role.add_theme_font_override("font", kf)
		_role.add_theme_font_size_override("font_size", 20)
		_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_role.position = Vector2(TEXT_X, 54)
		_role.size = Vector2(avail, 68)
		_role.add_theme_color_override("font_color", BODY if unlocked else DIM)
		var hidden := "Not yet discovered. Someone new is out there in the tower." \
				if e.family == "people" else "Not yet discovered. There's a floor you haven't seen yet."
		_role.text = str(e.role) if unlocked else hidden
		_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_role)

	func _process(dt: float) -> void:
		if not unlocked:
			return
		_anim_t += dt
		var period := 0.13 if texture_filter == TEXTURE_FILTER_LINEAR else 0.26
		if _anim_t >= period:
			_anim_t -= period
			_anim += 1
			queue_redraw()

	func _draw() -> void:
		var f = Draw.font()
		var r := Rect2(Vector2.ZERO, size)
		Draw.panel(self, r, PANEL if unlocked else Color(0.11, 0.115, 0.15), 16.0)
		Draw.panel(self, r, Color(accent, 0.75 if unlocked else 0.35), 16.0, false, 3.0)
		# Portrait plate with a soft identity glow behind the figure.
		var pr := Rect2(PAD, (size.y - PLATE_S) / 2.0, PLATE_S, PLATE_S)
		Draw.panel(self, pr, PLATE, 12.0)
		if unlocked:
			draw_circle(pr.get_center() + Vector2(0, 8), 62.0, Color(accent, 0.13))
			draw_circle(pr.get_center() + Vector2(0, 8), 40.0, Color(accent, 0.10))
		if entry.family == "rooms":
			_draw_emblem(pr)
		else:
			_draw_portrait(pr)
		if not unlocked:
			_draw_lock(Vector2(pr.end.x - 24.0, pr.position.y + 24.0))
		# Name
		var name_s: String = str(entry.name) if unlocked else "???"
		draw_string(f, Vector2(TEXT_X, 46), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32,
				GOLD if unlocked else DIM)
		# Chips
		for c in chips:
			var cr: Rect2 = c.rect
			var col: Color = c.col
			Draw.panel(self, cr, Color(col, 0.16), 10.0)
			Draw.panel(self, cr, Color(col, 0.85), 10.0, false, 2.0)
			draw_string(f, Vector2(cr.position.x + 13.0, cr.position.y + CHIP_H * 0.5 + CHIP_FS * 0.36),
					c.text, HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FS, col.lightened(0.25))

	func _draw_lock(c: Vector2) -> void:
		var col := Color(0.42, 0.44, 0.52)
		draw_arc(c + Vector2(0, -6), 8.0, PI, TAU, 12, col, 3.0)
		draw_rect(Rect2(c + Vector2(-11, -6), Vector2(22, 17)), col)
		draw_circle(c + Vector2(0, 2), 2.6, PLATE)

	## Floor shadow so figures stand on something.
	func _floor(cx: float, feet: float, w: float) -> void:
		draw_set_transform(Vector2(cx, feet), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, w, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_portrait(pr: Rect2) -> void:
		var id: String = entry.id
		var feet := pr.end.y - 22.0
		var cx := pr.get_center().x
		var ink := Color.WHITE if unlocked else LOCK_INK
		if id == "executive" or id == "delivery":
			var arr: Array = Passenger5._npc_tex_red if id == "executive" else Passenger5._npc_tex_green
			var tex: Texture2D = arr[0] if not arr.is_empty() else null
			var cols: Array = Passenger5.NPC_SIDE
			var src := Rect2(cols[_anim % 2] * 16, 0, 16, 16)
			if id == "delivery":
				var s := 96.0
				var manx := pr.position.x + 52.0
				_floor(manx + s * 0.55, feet, 62.0)
				_draw_trolley(manx + s * 0.30, feet, s * 0.90, ink)
				if tex != null:
					draw_texture_rect_region(tex, Rect2(manx - s / 2.0, feet - s, s, s), src, ink)
				else:
					_fallback_person(manx, feet, ink)
			else:
				var s := 118.0
				_floor(cx, feet, 40.0)
				if tex != null:
					draw_texture_rect_region(tex, Rect2(cx - s / 2.0, feet - s, s, s), src, ink)
				else:
					_fallback_person(cx, feet, ink)
			return
		# Regular people: the hi-res 8-frame businessman walk, row 1 = facing RIGHT.
		_floor(cx, feet, 34.0)
		var bm: Texture2D = Passenger5._bm_tex
		var bh := 134.0
		var bw := bh * float(Passenger5.BM_CW) / float(Passenger5.BM_CH)
		var tint := ink
		var col: Color = Passenger5.PTYPES[id].color
		if bm != null:
			var src := Rect2((_anim % Passenger5.BM_COLS) * Passenger5.BM_CW, Passenger5.BM_CH,
					Passenger5.BM_CW, Passenger5.BM_CH)
			draw_texture_rect_region(bm, Rect2(cx - bw / 2.0, feet - bh, bw, bh), src, tint)
		else:
			_fallback_person(cx, feet, ink if not unlocked else col)
		if not unlocked:
			return
		if id == "shopper":
			# a shopping bag in the trailing hand
			var bx := cx - bw * 0.42
			var by := feet - bh * 0.30
			draw_rect(Rect2(bx - 13, by, 26, 30), col)
			draw_rect(Rect2(bx - 13, by, 26, 30), col.darkened(0.4), false, 2.0)
			draw_arc(Vector2(bx, by), 8.0, PI, TAU, 10, col.darkened(0.4), 2.5)
		elif id == "patient":
			# a small clock over the shoulder: "watching the clock"
			var cc := Vector2(cx + bw * 0.48, feet - bh * 0.86)
			draw_circle(cc, 15.0, Color(0.97, 0.97, 1.0))
			draw_arc(cc, 15.0, 0.0, TAU, 24, col, 3.0)
			draw_line(cc, cc + Vector2(0, -9), col.darkened(0.3), 2.5)
			draw_line(cc, cc + Vector2(7, 3), col.darkened(0.3), 2.5)

	func _fallback_person(cx: float, feet: float, col: Color) -> void:
		var body := Rect2(cx - 16.0, feet - 70.0, 32.0, 70.0)
		draw_rect(body, col)
		draw_rect(body, Color(0, 0, 0, 0.45), false, 2.0)

	## intro_card5._draw_trolley, with an ink colour so it silhouettes when locked.
	func _draw_trolley(bx: float, by: float, h: float, ink: Color) -> void:
		var bed := Color(0.42, 0.30, 0.18) * ink
		var box := Color(0.82, 0.72, 0.52) * ink
		var edge := Color(0.45, 0.35, 0.2) * ink
		var wheel := Color(0.1, 0.1, 0.12) * ink
		var bw := h * 0.82
		var bedy := by - h * 0.10
		draw_line(Vector2(bx, bedy + h * 0.06), Vector2(bx, by - h * 0.80), bed, maxf(3.0, h * 0.05))
		draw_rect(Rect2(bx, bedy, bw, h * 0.08), bed)
		draw_circle(Vector2(bx + bw * 0.26, by), h * 0.09, wheel)
		draw_circle(Vector2(bx + bw * 0.80, by), h * 0.09, wheel)
		for b in [Rect2(bx + h * 0.08, bedy - h * 0.50, h * 0.40, h * 0.50),
				Rect2(bx + h * 0.44, bedy - h * 0.32, h * 0.34, h * 0.32)]:
			draw_rect(b, box)
			draw_rect(b, edge, false, 2.0)
			draw_line(Vector2(b.position.x, b.get_center().y), Vector2(b.end.x, b.get_center().y),
					Color(0.5, 0.4, 0.25) * ink, 2.0)

	## intro_card5._draw_emblem: a board-exact 2-cell room (floor slab, skylight, the real
	## furniture pushed away from the dock, type-colour outline, faint type label), scaled to
	## the plate. Locked: the same shape in flat dark greys, no furniture, no label.
	func _draw_emblem(pr: Rect2) -> void:
		var style: Dictionary = Grid5.ROOM_STYLE[entry.id]
		var bg: Color = style.bg if unlocked else Color(0.19, 0.20, 0.26)
		var line: Color = style.line if unlocked else Color(0.28, 0.29, 0.36)
		var cell := 74.0
		var k: float = Grid5.ART_K * cell / Grid5.CELL
		var rw := cell * 2.0
		var c := pr.get_center()
		var room := Rect2(c.x - rw / 2.0, c.y - cell / 2.0 + 4.0, rw, cell)
		for i in 2:
			var cr := Rect2(room.position.x + i * cell, room.position.y, cell, cell).grow(-1.0)
			draw_rect(cr, bg)
			draw_rect(Rect2(cr.position + Vector2(0.0, cr.size.y - 5.0), Vector2(cr.size.x, 5.0)),
					bg.darkened(0.35))
			draw_rect(Rect2(cr.position + Vector2(cr.size.x * 0.28, 3.0), Vector2(cr.size.x * 0.44, 4.0)),
					bg.lightened(0.30))
		if _furn != null and unlocked:
			var fw := _furn.get_width() * k
			var fh := _furn.get_height() * k
			var floor_y := room.end.y - 1.0
			draw_texture_rect(_furn, Rect2(Vector2(room.end.x - 5.0 - fw, floor_y - 5.0 - fh),
					Vector2(fw, fh)), false)
		draw_rect(room, Color(line, 0.9), false, 3.0)
		if unlocked:
			draw_string(ThemeDB.fallback_font, room.position + Vector2(0.0, room.size.y * 0.5 + 7.0),
					str(entry.id).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, room.size.x, 18,
					Color(0.12, 0.12, 0.14, 0.55))
