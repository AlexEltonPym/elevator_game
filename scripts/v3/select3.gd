extends Control
## v3 level select: one big button per Levels3 entry (id + name + one-line
## thesis), plus a back button to the boot menu. Picking a level sets
## Levels3.current and loads the game scene (main3 reads the index).

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
	box.add_theme_constant_override("separation", 26)
	center.add_child(box)
	var title := Label.new()
	title.text = "v3  PATH DRAWING - PICK A LEVEL"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for i in Levels3.LEVELS.size():
		var lv: Dictionary = Levels3.LEVELS[i]
		var btn := Button.new()
		btn.text = "%s  %s\n%s" % [lv.id, str(lv.name).to_upper(), lv.thesis]
		btn.custom_minimum_size = Vector2(620, 120)
		btn.add_theme_font_size_override("font_size", 24)
		var col := Color(0.93, 0.58, 0.16) if lv.id != "X-1" else Color(0.5, 0.55, 0.65)
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.55)
		sb.border_color = col
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", sb)
		var idx := i
		btn.pressed.connect(func():
			Levels3.current = idx
			get_tree().change_scene_to_file("res://scenes/v3_main.tscn"))
		box.add_child(btn)
	var back := Button.new()
	back.text = "BACK TO MENU"
	back.custom_minimum_size = Vector2(620, 80)
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	box.add_child(back)
