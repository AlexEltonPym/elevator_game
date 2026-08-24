extends Control
## A one-time, dismissible "meet the passenger" card, shown as an overlay at PLAN start the
## first time a special mechanic appears (see main5._maybe_intro_cards). It shows the restyled
## passenger, one line of copy, and the lift to use — the same template for cargo and execs.
## Dismiss ("Got it") hands back to PLAN; the board route arrow then plays. Persisted per
## MECHANIC (not per level) via Levels5.demo_seen("mech:<name>").

signal dismissed

const Ui5 := preload("res://scripts/v5/ui5.gd")
const Passenger5 := preload("res://scripts/v5/passenger5.gd")
const Grid5 := preload("res://scripts/v5/grid5.gd")

var _anim := 0                     # walk-cycle frame (animated in place)
var _anim_t := 0.0
var mech := "executive"            # passenger cards: "executive"|"cargo"; concept cards: below
var _concept := false              # concept cards show a room emblem, not a passenger sprite
var _emblem := Color(0.4, 0.5, 0.9)
var _emblem_label := ""
var _room_type := ""               # concept cards: draw a real mini-room of this type (else a plain plate)
var _title := ""
var _copy := ""
var _lift := ""
var _lift_col := Color.WHITE
var _btn: Button
var _furn: Texture2D = null         # cached room furniture sprite for concept mini-rooms

const CARD := Rect2(70, 300, 580, 660)


## `val` carries the perfect-tip total for the finale card.
func setup(m: String, val: int = 0) -> void:
	mech = m
	match m:
		"cargo":
			_title = "CARGO"
			_copy = "Haul deliveries to the cafe on the CARGO lift for big tips!"
			_lift_col = Color(0.96, 0.82, 0.26)
		"executive":
			_title = "EXECUTIVES"
			_copy = "Rush executives to the penthouse on the EXPRESS for big tips!"
			_lift_col = Color(0.97, 0.58, 0.17)
		"offices":
			_concept = true; _title = "OFFICES"; _room_type = "office"
			_copy = "Connect passengers to their offices."
			_emblem = Grid5.ROOM_STYLE["office"].bg; _lift_col = _emblem
		"atrium":
			_concept = true; _title = "THE ATRIUM"; _room_type = "atrium"
			_copy = "Passengers can walk through public rooms like the atrium to switch lifts."
			_emblem = Grid5.ROOM_STYLE["atrium"].bg; _lift_col = _emblem
		"overlap":
			_concept = true; _title = "SHARE A DROPOFF"; _room_type = "atrium"
			_copy = "Two elevators can share one dropoff - use the atrium as an exchange."
			_emblem = Grid5.ROOM_STYLE["atrium"].bg; _lift_col = _emblem
		"finale":
			_concept = true; _title = "SHOWTIME"
			_copy = "Bring it all together - earn $%d in tips for a perfect score!" % val
			_emblem = Color(0.98, 0.82, 0.32); _emblem_label = "$"; _lift_col = _emblem


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # block the board while shown
	texture_filter = TEXTURE_FILTER_NEAREST    # crisp pixel-art sprite (no blur)
	var copy := Label.new()
	var kf = Ui5.font()
	if kf != null:
		copy.add_theme_font_override("font", kf)   # the display (Kenney) font
	copy.add_theme_font_size_override("font_size", 30)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.position = Vector2(CARD.position.x + 34, CARD.position.y + 300)
	copy.size = Vector2(CARD.size.x - 68, 224)
	copy.add_theme_color_override("font_color", Color(0.93, 0.94, 0.98))
	copy.text = _copy
	add_child(copy)
	_btn = Ui5.make_button("GOT IT", "Green", 28)
	_btn.size = Vector2(300, 92)
	_btn.position = Vector2(CARD.position.x + (CARD.size.x - 300) / 2.0, CARD.position.y + 544)
	_btn.pressed.connect(_finish)
	add_child(_btn)
	if _room_type != "":
		var fp: String = Grid5._PS + str(Grid5.ROOM_STYLE[_room_type].furn)
		if ResourceLoader.exists(fp):
			_furn = load(fp)


func _process(dt: float) -> void:
	_anim_t += dt
	if _anim_t >= 0.26:   # in-place walk cycle
		_anim_t = 0.0
		_anim = 1 - _anim
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# a tap anywhere (outside GOT IT, which handles itself) dismisses
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		accept_event()
		_finish()


func _finish() -> void:
	dismissed.emit()
	queue_free()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))          # dim the board
	_panel(CARD, Color(0.13, 0.14, 0.19), 18.0)
	_panel(CARD, Color(_lift_col, 0.85), 18.0, false, 4.0)              # accent border in lift colour
	# Portrait / emblem plate
	var pr := Rect2(CARD.position.x + (CARD.size.x - 240) / 2.0, CARD.position.y + 26, 240, 210)
	_panel(pr, Color(0.09, 0.10, 0.14), 12.0)
	if _concept:
		_draw_emblem(pr)
	else:
		_draw_portrait(pr)
	# Title (Kenney font, centred)
	var f = Ui5.font()
	if f != null:
		var ts: Vector2 = f.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
		draw_string(f, Vector2(CARD.position.x + (CARD.size.x - ts.x) / 2.0, CARD.position.y + 274),
				_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.96, 0.85, 0.5))


## Concept cards. A room TYPE (office/atrium) draws a proper little 2x1 room — the real
## PixelSpaces furniture inside, a landing door on the dock side — so it reads like the room
## the player will actually see on the board (colour + shape + furniture, like Grid5._draw_room).
## Type-less concepts (the finale "$") fall back to a plain coloured plate + label.
func _draw_emblem(r: Rect2) -> void:
	if _room_type == "":
		_draw_plate(r); return
	var style: Dictionary = Grid5.ROOM_STYLE[_room_type]
	var bg: Color = style.bg
	var line: Color = style.line
	var c := r.get_center()
	var rw := 200.0
	var rh := 108.0
	var room := Rect2(c.x - rw / 2.0, c.y - rh / 2.0, rw, rh)
	var floor_y := room.end.y - 12.0
	_panel(room, bg, 10.0)                                                # room body (authoritative colour)
	draw_rect(Rect2(room.position.x, floor_y, room.size.x, 12.0), bg.darkened(0.20))  # floor band
	draw_line(Vector2(c.x, room.position.y + 8.0), Vector2(c.x, room.end.y - 8.0),
			Color(line, 0.35), 2.0)                                       # 2-tile seam
	_panel(room, line, 10.0, false, 4.0)                                  # outline
	# Landing door on the LEFT (the dock side), recessed into the wall.
	var dw := 30.0
	var dh := rh - 34.0
	var door := Rect2(room.position.x + 14.0, floor_y - dh, dw, dh)
	draw_rect(door.grow(3.0), line.darkened(0.15))                        # frame
	draw_rect(door, Color(0.14, 0.15, 0.19))                              # dark car mouth
	draw_line(Vector2(door.get_center().x, door.position.y),
			Vector2(door.get_center().x, door.end.y), Color(0.30, 0.32, 0.36), 2.0)  # seam
	# Furniture on the RIGHT (opposite the door), bottom-aligned on the floor.
	if _furn != null:
		var sz := Vector2(_furn.get_width(), _furn.get_height()) * 3.6
		var maxh := rh - 24.0
		if sz.y > maxh:
			sz *= maxh / sz.y
		draw_texture_rect(_furn, Rect2(Vector2(room.end.x - 20.0 - sz.x, floor_y - sz.y), sz), false)


## A plain coloured plate + centred label — the fallback emblem for a type-less concept
## (the finale "$").
func _draw_plate(r: Rect2) -> void:
	var s := 134.0
	var c := r.get_center()
	var em := Rect2(c.x - s / 2.0, c.y - s / 2.0, s, s)
	_panel(em, Color(_emblem, 0.92), 14.0)
	_panel(em, _emblem.darkened(0.35), 14.0, false, 4.0)
	var f = Ui5.font()
	if f != null and _emblem_label != "":
		var sz: int = 46 if _emblem_label == "$" else 22
		var ts: Vector2 = f.get_string_size(_emblem_label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
		draw_string(f, Vector2(c.x - ts.x / 2.0, c.y + sz * 0.36), _emblem_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, sz, _emblem.darkened(0.5))


func _draw_portrait(r: Rect2) -> void:
	Passenger5._load_npc()
	var arr: Array = Passenger5._npc_tex_green if mech == "cargo" else Passenger5._npc_tex_red
	if arr.is_empty() or arr[0] == null:
		return
	var tex: Texture2D = arr[0]
	var cols: Array = Passenger5.NPC_SIDE
	var src := Rect2(cols[_anim] * 16, 0, 16, 16)
	var feet := r.end.y - 22.0
	if mech == "cargo":
		# smaller man, left-offset, pushing his trolley — the pair fits inside the plate.
		var s := 100.0
		var manx := r.position.x + 60.0
		_draw_trolley(manx + s * 0.30, feet, s * 0.90)
		draw_texture_rect_region(tex, Rect2(manx - s / 2.0, feet - s, s, s), src)
	else:
		# exec scaled down only a little, so both cards read at a consistent size.
		var s := 118.0
		var cx := r.position.x + r.size.x / 2.0
		draw_texture_rect_region(tex, Rect2(cx - s / 2.0, feet - s, s, s), src)


## A hand trolley (height ~h) with two wheels, an upright handle and a stack of taped boxes.
func _draw_trolley(bx: float, by: float, h: float) -> void:
	var bed := Color(0.42, 0.30, 0.18)
	var bw := h * 0.82
	var bedy := by - h * 0.10
	draw_line(Vector2(bx, bedy + h * 0.06), Vector2(bx, by - h * 0.80), bed, maxf(3.0, h * 0.05))
	draw_rect(Rect2(bx, bedy, bw, h * 0.08), bed)
	draw_circle(Vector2(bx + bw * 0.26, by), h * 0.09, Color(0.1, 0.1, 0.12))
	draw_circle(Vector2(bx + bw * 0.80, by), h * 0.09, Color(0.1, 0.1, 0.12))
	for b in [Rect2(bx + h * 0.08, bedy - h * 0.50, h * 0.40, h * 0.50),
			Rect2(bx + h * 0.44, bedy - h * 0.32, h * 0.34, h * 0.32)]:
		draw_rect(b, Color(0.82, 0.72, 0.52))
		draw_rect(b, Color(0.45, 0.35, 0.2), false, 2.0)
		draw_line(Vector2(b.position.x, b.get_center().y), Vector2(b.end.x, b.get_center().y),
				Color(0.5, 0.4, 0.25), 2.0)


func _panel(rect: Rect2, col: Color, rad: float, filled := true, w := 2.0) -> void:
	if filled:
		draw_rect(Rect2(rect.position + Vector2(rad, 0), rect.size - Vector2(2 * rad, 0)), col)
		draw_rect(Rect2(rect.position + Vector2(0, rad), rect.size - Vector2(0, 2 * rad)), col)
		for c in [rect.position + Vector2(rad, rad), Vector2(rect.end.x - rad, rect.position.y + rad),
				Vector2(rect.position.x + rad, rect.end.y - rad), rect.end - Vector2(rad, rad)]:
			draw_circle(c, rad, col)
	else:
		draw_rect(rect.grow(-1.0), col, false, w)
