extends Control
## v5 "Rooms" level select. The project's MAIN SCENE and the only level select
## (v4 is gone). Levels are grouped into WORLDS (Levels5.WORLDS): LEARN, MECHANICS,
## GENERIC. One world shows at a time; the arrows page between worlds. Picking a
## level sets Levels5.current and loads the v5 game scene, which lands DIRECTLY in
## PLAN — there is no briefing screen between the select and playing. Reopens on the
## world of the level you last played (Levels5.current), so returning lands you where
## you were.

const WORLD_COL := {
	"TUTORIAL": Color(0.42, 0.62, 0.88),
	"CROSSLINK": Color(0.35, 0.74, 0.72),
}

const StarBar5 := preload("res://scripts/v5/starbar5.gd")
const Ui5 := preload("res://scripts/v5/ui5.gd")
const WORLD_KCOL := {"TUTORIAL": "Blue", "CROSSLINK": "Green"}

var page := 0 # index into Levels5.WORLDS
var _hovered := -1  # LEVELS index currently moused-over (for the 1-4 tier shortcut)


func _kfont(l: Control) -> void:
	var f = Ui5.font()
	if f != null:
		l.add_theme_font_override("font", f)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	page = _world_of_current()
	_rebuild()


## The world page of the level last played, so the select reopens there.
func _world_of_current() -> int:
	var lv: Dictionary = Levels5.get_level(Levels5.current)
	var w: String = str(lv.get("world", Levels5.WORLDS[0]))
	var i: int = Levels5.WORLDS.find(w)
	return maxi(0, i)


## Levels (index + data) belonging to the world at `page`, in table order.
func _levels_in_page() -> Array:
	var world: String = Levels5.WORLDS[page]
	var out: Array = []
	for i in Levels5.LEVELS.size():
		if str(Levels5.LEVELS[i].get("world", Levels5.WORLDS[0])) == world:
			out.append({"index": i, "lv": Levels5.LEVELS[i]})
	return out


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var world: String = Levels5.WORLDS[page]
	var accent: Color = WORLD_COL.get(world, Color(0.5, 0.6, 0.8))

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	# World pager: < WORLD (n/2) > with Kenney arrow buttons (dark arrows on grey via skin).
	var prev := Ui5.make_button("", "Grey", 20)
	prev.icon = Ui5.arrow_tex("w")
	prev.position = Vector2(16, 26)
	prev.size = Vector2(80, 76)
	prev.disabled = page == 0
	prev.pressed.connect(func(): _flip(-1))
	add_child(prev)

	var next := Ui5.make_button("", "Grey", 20)
	next.icon = Ui5.arrow_tex("e")
	next.position = Vector2(vp.x - 96, 26)
	next.size = Vector2(80, 76)
	next.disabled = page == Levels5.WORLDS.size() - 1
	next.pressed.connect(func(): _flip(1))
	add_child(next)

	var wlabel := Label.new()
	wlabel.text = "%s   %d/%d" % [world, page + 1, Levels5.WORLDS.size()]
	wlabel.position = Vector2(104, 34)
	wlabel.size = Vector2(vp.x - 208, 60)
	wlabel.add_theme_font_size_override("font_size", 40)
	wlabel.add_theme_color_override("font_color", accent)
	wlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kfont(wlabel)
	add_child(wlabel)

	# Level buttons for this world (generous margins; the border was reading tight).
	var items := _levels_in_page()
	var margin := 40.0
	var top := 130.0
	var gap := 20.0
	var n: int = maxi(1, items.size())
	var h := (vp.y - top - margin - gap * (n - 1)) / float(n)
	h = clampf(h, 96.0, 176.0)
	for k in items.size():
		var index: int = items[k].index
		var lv: Dictionary = items[k].lv
		var idx: int = index
		var kcol: String = WORLD_KCOL.get(world, "Blue")
		var b := Ui5.make_button("%s   %s" % [lv.id, str(lv.name).to_upper()], kcol, 30)
		b.position = Vector2(margin, top + k * (h + gap))
		b.size = Vector2(vp.x - 2.0 * margin, h)
		b.clip_text = true
		b.pressed.connect(func():
			Levels5.autosolve = false
			Levels5.current = idx
			get_tree().change_scene_to_file("res://scenes/v5_main.tscn"))
		# Secret dev shortcut: hover a tile, press 1-4 to launch with that star-tier plan.
		b.mouse_entered.connect(_on_hover.bind(idx))
		b.mouse_exited.connect(_on_unhover.bind(idx))
		add_child(b)
		# Earned medals, vertically centered on the right of the tile.
		if not (lv.get("stars", []) as Array).is_empty():
			var got: int = Levels5.best_stars(str(lv.id))
			var sbar := StarBar5.new()
			sbar.setup(got, 24.0)
			sbar.position = Vector2(vp.x - margin - 118.0, top + k * (h + gap) + h * 0.5 - 13.0)
			add_child(sbar)


func _on_hover(idx: int) -> void:
	_hovered = idx


func _on_unhover(idx: int) -> void:
	if _hovered == idx:
		_hovered = -1


## Secret dev shortcut: while hovering a level, press 1-4 to launch it pre-solved to that
## star tier (1 = a 1-star plan ... 4 = the perfect plan).
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var tier := -1
	match event.keycode:
		KEY_1: tier = 1
		KEY_2: tier = 2
		KEY_3: tier = 3
		KEY_4: tier = 4
	if tier < 0 or _hovered < 0:
		return
	var lv: Dictionary = Levels5.LEVELS[_hovered]
	if (lv.get("sols", []) as Array).size() >= tier:
		Levels5.autosolve = true
		Levels5.autosolve_tier = tier
		Levels5.current = _hovered
		get_tree().change_scene_to_file("res://scenes/v5_main.tscn")


func _flip(dir: int) -> void:
	# CLAMP, don't wrap: the pager stops at the first/last world instead of looping back to
	# the tutorial from the end (user: the arrows shouldn't wrap around).
	page = clampi(page + dir, 0, Levels5.WORLDS.size() - 1)
	_rebuild()
