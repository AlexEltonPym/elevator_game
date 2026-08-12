extends Control
## Level select (the project's MAIN scene), redesigned as PAGED WORLDS
## (docs/ui-pass-spec.md §1). The old one-CenterContainer-of-eight-rows layout
## overflowed the screen and clipped its WATCH column off the right edge; this
## shows ONE world at a time (Levels3.WORLDS), each world's levels fitting on a
## single 720x1280 screen with big left/right arrow paging.
##
## Per level: a full-width PLAY card (id + name + one-line thesis) is the
## primary target; a compact strip of small N / T / B buttons sits UNDER it
## (naive / thesis / best), tinted red/green/blue. B appears only where
## Discovered3.has(id); N/T only where Scenarios3 has that strategy. A one-time
## legend at the bottom decodes the letters.
##
## Picking anything sets Levels3.current + Levels3.watch_strategy and loads the
## game scene (main3 reads both in _ready). "" = normal PLAY.

const MARGIN := 20.0
const ARROW := 96.0 # arrow buttons: >= 90 px square tap target
const HEADER_Y := 78.0
const STRIP_H := 92.0 # N/T/B button height (>= 90 px tap target)
const STRIP_W := 108.0 # N/T/B button width (>= 90 px)
const STRIP_GAP := 12.0
const CARD_STRIP_GAP := 6.0
const LEGEND_H := 46.0

const TONES := {
	"naive": Color(0.75, 0.35, 0.30),
	"thesis": Color(0.35, 0.72, 0.42),
	"best": Color(0.45, 0.48, 0.85),
}
const STRAT_LETTER := {"naive": "N", "thesis": "T", "best": "B"}

var world_idx := 0
var vp := Vector2(720, 1280)
var world_label: Label
var left_btn: Button
var right_btn: Button
var page: Control # holds the current world's level blocks; rebuilt on paging


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	vp = get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.11)
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.text = "PATH DRAWING - PICK A LEVEL"
	title.position = Vector2(0, 16)
	title.size = Vector2(vp.x, 40)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	# Header: < arrow >  with the world name + position between them.
	left_btn = _arrow("<", MARGIN)
	left_btn.pressed.connect(func(): _go(-1))
	add_child(left_btn)
	right_btn = _arrow(">", vp.x - MARGIN - ARROW)
	right_btn.pressed.connect(func(): _go(1))
	add_child(right_btn)
	world_label = Label.new()
	world_label.position = Vector2(MARGIN + ARROW, HEADER_Y)
	world_label.size = Vector2(vp.x - 2.0 * (MARGIN + ARROW), ARROW)
	world_label.add_theme_font_size_override("font_size", 30)
	world_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.98))
	world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(world_label)
	# Legend (once), at the very bottom.
	var legend := Label.new()
	legend.text = "N naive  ·  T thesis  ·  B best"
	legend.position = Vector2(0, vp.y - LEGEND_H)
	legend.size = Vector2(vp.x, LEGEND_H)
	legend.add_theme_font_size_override("font_size", 20)
	legend.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(legend)
	page = Control.new()
	page.position = Vector2.ZERO
	page.size = vp
	add_child(page)
	_rebuild()


func _arrow(text: String, x: float) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, HEADER_Y)
	b.size = Vector2(ARROW, ARROW)
	b.add_theme_font_size_override("font_size", 44)
	return b


## Page by `delta`, clamped (arrows disable at the ends rather than wrap).
func _go(delta: int) -> void:
	world_idx = clampi(world_idx + delta, 0, Levels3.WORLDS.size() - 1)
	_rebuild()


func _rebuild() -> void:
	# remove_child is immediate (queue_free alone would leave the old world's
	# buttons in the tree until frame end, so a same-frame paging read would see
	# both worlds at once).
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	left_btn.disabled = world_idx <= 0
	right_btn.disabled = world_idx >= Levels3.WORLDS.size() - 1
	var world: Dictionary = Levels3.WORLDS[world_idx]
	world_label.text = "%s   %d/%d" % [str(world.name), world_idx + 1,
			Levels3.WORLDS.size()]
	var ids: Array = world.levels
	var n: int = ids.size()
	# Fit n level blocks between the header and the legend with no scroll (max 5
	# today). A block is a full-width PLAY card with the N/T/B strip under it;
	# the card height flexes with how many levels the world holds so it always
	# fits, and each block is centred in its vertical slot.
	var top := HEADER_Y + ARROW + 18.0
	var avail := (vp.y - LEGEND_H - 8.0) - top
	var slot := avail / float(maxi(n, 1))
	var card_h := clampf(slot - STRIP_H - CARD_STRIP_GAP - 14.0, 100.0, 132.0)
	var block_h := card_h + CARD_STRIP_GAP + STRIP_H
	for k in n:
		var id: String = ids[k]
		var idx: int = Levels3.index_of(id)
		if idx < 0:
			continue
		var slot_top := top + k * slot
		var y := slot_top + (slot - block_h) / 2.0
		_make_block(Levels3.LEVELS[idx], idx, y, card_h)


func _make_block(lv: Dictionary, idx: int, y: float, card_h: float) -> void:
	var col := Color(0.93, 0.58, 0.16) if lv.id != "X-1" else Color(0.5, 0.55, 0.65)
	var play := Button.new()
	play.text = "%s  %s\n%s" % [lv.id, str(lv.name).to_upper(), lv.thesis]
	play.position = Vector2(MARGIN, y)
	play.size = Vector2(vp.x - 2.0 * MARGIN, card_h)
	# Button has no autowrap in 4.2; a modest font keeps every shipped thesis
	# inside the 680 px card, and clip_text guarantees text can never spill past
	# the card rect (so nothing can ever exceed the viewport width).
	play.clip_text = true
	play.add_theme_font_size_override("font_size", 18)
	play.add_theme_stylebox_override("normal", _style(col))
	play.pressed.connect(_start.bind(idx, ""))
	page.add_child(play)
	# The N / T / B strip, packed left under the card. Only the strategies that
	# actually exist for this level are shown.
	var sets: Dictionary = Scenarios3.route_sets(lv.id)
	var strategies: Array = ["naive", "thesis"]
	if Discovered3.has(lv.id):
		strategies.append("best")
	var sx := MARGIN
	var sy := y + card_h + CARD_STRIP_GAP
	for strat in strategies:
		if strat != "best" and not sets.has(strat):
			continue
		var wb := Button.new()
		wb.text = STRAT_LETTER[strat]
		wb.position = Vector2(sx, sy)
		wb.size = Vector2(STRIP_W, STRIP_H)
		wb.add_theme_font_size_override("font_size", 34)
		wb.add_theme_stylebox_override("normal", _style(TONES[strat]))
		wb.pressed.connect(_start.bind(idx, strat))
		page.add_child(wb)
		sx += STRIP_W + STRIP_GAP


func _start(index: int, strategy: String) -> void:
	Levels3.current = index
	Levels3.watch_strategy = strategy
	get_tree().change_scene_to_file("res://scenes/v3_main.tscn")


func _style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.darkened(0.55)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	return sb
