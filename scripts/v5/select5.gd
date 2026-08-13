extends Control
## v5 "Rooms" prototype level select. A separate scene reached from the v4 level
## select via one additive button (scripts/v3/select3.gd), so v4's paged worlds
## are untouched. Lists the four hand-made R levels; picking one sets
## Levels5.current and loads the v5 game scene.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.text = "v5 ROOMS - PROTOTYPE"
	title.position = Vector2(0, 24)
	title.size = Vector2(vp.x, 44)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := Label.new()
	sub.text = "People want ROOMS. Lifts pass beside them and serve their door marks."
	sub.position = Vector2(20, 78)
	sub.size = Vector2(vp.x - 40, 40)
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	var top := 150.0
	var gap := 20.0
	var n: int = Levels5.LEVELS.size()
	var h := (vp.y - top - 120.0 - gap * (n - 1)) / float(n)
	h = clampf(h, 120.0, 200.0)
	for i in n:
		var lv: Dictionary = Levels5.LEVELS[i]
		var b := Button.new()
		b.text = "%s  %s\n%s" % [lv.id, str(lv.name).to_upper(), lv.thesis]
		b.position = Vector2(20, top + i * (h + gap))
		b.size = Vector2(vp.x - 40, h)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 20)
		var col := Color(0.42, 0.55, 0.85)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.55)
		sb.border_color = col
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override("normal", sb)
		var idx: int = i
		b.pressed.connect(func():
			Levels5.current = idx
			get_tree().change_scene_to_file("res://scenes/v5_main.tscn"))
		add_child(b)
	var back := Button.new()
	back.text = "BACK TO v4 LEVELS"
	back.position = Vector2(20, vp.y - 96)
	back.size = Vector2(vp.x - 40, 76)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/v3_select.tscn"))
	add_child(back)
