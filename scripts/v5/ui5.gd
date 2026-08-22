extends RefCounted
## Kenney UI factory: shared loaders + builders so every screen uses the same button, star,
## panel and font art (assets/ui/kenney, CC0). Everything is load()-guarded and falls back
## to flat StyleBoxes / no texture if the pack is absent, so the game still runs without it.

const BASE := "res://assets/ui/kenney/PNG/"
const FONT_PATH := "res://assets/ui/kenney/Font/Kenney Future.ttf"
# Drop a preferred UI font here (any .ttf/.otf renamed to ui.ttf) and it's used everywhere;
# falls back to the Kenney font, then Godot's default.
const USER_FONT_CANDIDATES := [
	"res://assets/ui/font/ui.ttf", "res://assets/ui/font/ui.otf",
]

static var _cache := {}
static var _font = null
static var _font_loaded := false


static func tex(rel: String) -> Texture2D:
	if _cache.has(rel):
		return _cache[rel]
	var t: Texture2D = null
	if ResourceLoader.exists(BASE + rel):
		t = load(BASE + rel)
	_cache[rel] = t
	return t


static func font():
	if not _font_loaded:
		_font_loaded = true
		for p in USER_FONT_CANDIDATES:
			if ResourceLoader.exists(p):
				_font = load(p)
				return _font
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH)
	return _font


## Result star: Yellow filled or Grey outline.
static func star_tex(filled: bool) -> Texture2D:
	return tex("Yellow/Default/star.png") if filled else tex("Grey/Default/star_outline.png")


static func arrow_tex(dir: String) -> Texture2D:
	return tex("Grey/Default/arrow_basic_%s.png" % dir)  # "w" / "e"


## 9-slice stylebox from a Kenney button sprite. `variant` e.g. "depth_flat", "flat".
static func _box(color: String, variant: String, l := 20, r := 20, t := 18, b := 26) -> StyleBox:
	var tx := tex("%s/Default/button_rectangle_%s.png" % [color, variant])
	if tx == null:
		var f := StyleBoxFlat.new()
		f.bg_color = _flat_color(color)
		f.set_corner_radius_all(12)
		f.set_content_margin_all(10)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = tx
	sb.set_texture_margin_all(20)
	sb.texture_margin_left = l
	sb.texture_margin_right = r
	sb.texture_margin_top = t
	sb.texture_margin_bottom = b
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 16
	return sb


static func _flat_color(color: String) -> Color:
	match color:
		"Blue": return Color(0.30, 0.55, 0.85)
		"Green": return Color(0.35, 0.70, 0.40)
		"Red": return Color(0.80, 0.35, 0.35)
		"Yellow": return Color(0.90, 0.70, 0.25)
		_: return Color(0.40, 0.44, 0.52)


## Apply Kenney button skin (normal/hover/pressed + font) to a Button.
static func skin_button(b: Button, color := "Grey", font_size := 24) -> Button:
	b.add_theme_stylebox_override("normal", _box(color, "depth_flat"))
	b.add_theme_stylebox_override("hover", _box(color, "depth_gradient"))
	# pressed = the flat (no-depth) sprite so it reads as pushed down.
	b.add_theme_stylebox_override("pressed", _box(color, "flat", 20, 20, 22, 22))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", font_size)
	# Light Kenney buttons (grey/yellow) need DARK text; saturated ones take white.
	var fg := Color(0.18, 0.20, 0.26) if color in ["Grey", "Yellow"] else Color(1, 1, 1)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	var f = font()
	if f != null:
		b.add_theme_font_override("font", f)
	return b


static func make_button(text: String, color := "Grey", font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	skin_button(b, color, font_size)
	return b


## 9-slice panel background stylebox (grey rounded).
static func panel_box() -> StyleBox:
	var tx := tex("Grey/Default/button_square_depth_flat.png")
	if tx == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.10, 0.11, 0.15, 0.98)
		f.set_corner_radius_all(20)
		f.set_content_margin_all(30)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = tx
	sb.set_texture_margin_all(24)
	sb.set_content_margin_all(30)
	sb.modulate_color = Color(0.20, 0.22, 0.30)  # tint the light Kenney frame to a dark panel
	return sb
