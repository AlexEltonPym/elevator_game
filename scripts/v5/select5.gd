extends Control
## v5 "Rooms" level select. The project's MAIN SCENE and the only level select
## (v4 is gone). Levels are grouped into WORLDS (Levels5.WORLDS): LEARN, MECHANICS,
## GENERIC. One world shows at a time; the arrows page between worlds. Picking a
## level sets Levels5.current and loads the v5 game scene. Reopens on the world of
## the level you last played (Levels5.current), so returning lands you where you were.

const WORLD_BLURB := {
	"LEARN": "One new idea per level. Forgiving - you can't really lose by trying.",
	"MECHANICS": "Each level proves one mechanic: transfers, corridors, caps, express, cargo.",
	"GENERIC": "Open optimization. Many legal plans - the craft is finding a good one.",
}
const WORLD_COL := {
	"LEARN": Color(0.42, 0.62, 0.88),
	"MECHANICS": Color(0.86, 0.62, 0.30),
	"GENERIC": Color(0.55, 0.78, 0.52),
}

var page := 0 # index into Levels5.WORLDS


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

	var title := Label.new()
	title.text = "ELEVATORS - ROOMS"
	title.position = Vector2(0, 20)
	title.size = Vector2(vp.x, 40)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# World pager: < WORLD (n/3) >
	var prev := Button.new()
	prev.text = "<"
	prev.position = Vector2(16, 72)
	prev.size = Vector2(64, 64)
	prev.add_theme_font_size_override("font_size", 32)
	prev.pressed.connect(func(): _flip(-1))
	add_child(prev)

	var next := Button.new()
	next.text = ">"
	next.position = Vector2(vp.x - 80, 72)
	next.size = Vector2(64, 64)
	next.add_theme_font_size_override("font_size", 32)
	next.pressed.connect(func(): _flip(1))
	add_child(next)

	var wlabel := Label.new()
	wlabel.text = "%s   (%d/%d)" % [world, page + 1, Levels5.WORLDS.size()]
	wlabel.position = Vector2(88, 76)
	wlabel.size = Vector2(vp.x - 176, 34)
	wlabel.add_theme_font_size_override("font_size", 26)
	wlabel.add_theme_color_override("font_color", accent)
	wlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(wlabel)

	var blurb := Label.new()
	blurb.text = str(WORLD_BLURB.get(world, ""))
	blurb.position = Vector2(24, 112)
	blurb.size = Vector2(vp.x - 48, 40)
	blurb.add_theme_font_size_override("font_size", 16)
	blurb.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(blurb)

	# Level buttons for this world.
	var items := _levels_in_page()
	var top := 168.0
	var gap := 16.0
	var n: int = maxi(1, items.size())
	var h := (vp.y - top - 40.0 - gap * (n - 1)) / float(n)
	h = clampf(h, 96.0, 168.0)
	for k in items.size():
		var index: int = items[k].index
		var lv: Dictionary = items[k].lv
		var b := Button.new()
		b.text = "%s  %s\n%s" % [lv.id, str(lv.name).to_upper(), lv.thesis]
		b.position = Vector2(20, top + k * (h + gap))
		b.size = Vector2(vp.x - 40, h)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 19)
		var sb := StyleBoxFlat.new()
		sb.bg_color = accent.darkened(0.6)
		sb.border_color = accent
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		b.add_theme_stylebox_override("normal", sb)
		var idx: int = index
		b.pressed.connect(func():
			Levels5.current = idx
			get_tree().change_scene_to_file("res://scenes/v5_main.tscn"))
		add_child(b)


func _flip(dir: int) -> void:
	page = posmod(page + dir, Levels5.WORLDS.size())
	_rebuild()
