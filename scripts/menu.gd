extends Control
## Boot menu: pick a prototype. Everything is built in code (programmer art).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.11)
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 34)
	center.add_child(box)
	var title := Label.new()
	title.text = "ELEVATOR PROTOTYPES"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Two experiments, one building.\nBoth run at 720x1280 portrait; mouse works like touch."
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_add_mode_button(box, "v2  NETWORK PLANNER",
			"place elevator cards, toggle doors, transfer floors",
			Color(0.42, 0.52, 0.68), "res://scenes/main.tscn")
	_add_mode_button(box, "v3  PATH DRAWING",
			"drag maze routes, gate mutexes, emergent transfers",
			Color(0.93, 0.58, 0.16), "res://scenes/v3_main.tscn")


func _add_mode_button(box: VBoxContainer, label: String, desc: String,
		col: Color, scene_path: String) -> void:
	var btn := Button.new()
	btn.text = label + "\n" + desc
	btn.custom_minimum_size = Vector2(560, 130)
	btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.35)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", sb)
	btn.pressed.connect(func(): get_tree().change_scene_to_file(scene_path))
	box.add_child(btn)
