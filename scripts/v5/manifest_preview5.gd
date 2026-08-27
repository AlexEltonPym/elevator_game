extends Control
## "Who's coming" preview (Tetris-style next-up). A vertical strip of the UPCOMING manifest
## passengers, top = next to spawn. At PLAN (index 0) it's the full roster you'll face; during
## the run it advances as each one spawns. Hidden for levels with no fixed manifest. Reads
## game._manifest / game._manifest_idx live; icons are shape+colour coded by passenger type
## (crate = cargo, diamond = executive, figure = regular commuter).
const Passenger5 := preload("res://scripts/v5/passenger5.gd")
const Ui5 := preload("res://scripts/v5/ui5.gd")

const MAX_SHOWN := 8
const CW := 56.0
const CH := 40.0
const GAP := 6.0
const TOP := 132.0
const VIEW_W := 720.0   # fixed viewport width (a Control under a CanvasLayer has no resolved size)

var game = null
var _last_key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

## Cheap change-detector so we only repaint when the roster or index actually moves.
func tick() -> void:
	if game == null:
		return
	var man: Array = game._manifest
	var key := "%d/%d/%d" % [man.size(), game._manifest_idx, game.state]
	if key != _last_key:
		_last_key = key
		queue_redraw()

func _type_color(t: String) -> Color:
	return (Passenger5.PTYPES.get(t, {}) as Dictionary).get("color", Color(0.6, 0.6, 0.6))

func _draw() -> void:
	if game == null:
		return
	var man: Array = game._manifest
	if man.is_empty():
		return
	# Only while planning or running, and only while riders remain to come.
	if game.state != game.State.PLAN and game.state != game.State.PLAYING:
		return
	var idx: int = game._manifest_idx
	var remaining: int = man.size() - idx
	if remaining <= 0:
		return
	var f = Ui5.font()
	var x := VIEW_W - CW - 12.0
	var y := TOP
	if f:
		draw_string(f, Vector2(x - 2, y - 10), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				Color(0.92, 0.92, 0.97, 0.85))
	var shown: int = mini(MAX_SHOWN, remaining)
	for k in shown:
		var m: Dictionary = man[idx + k]
		var t := str(m.get("type", "visitor"))
		var col := _type_color(t)
		var r := Rect2(x, y, CW, CH)
		draw_rect(r, Color(0.10, 0.10, 0.14, 0.82), true)
		draw_rect(r, Color(1, 1, 1, 0.12 if k > 0 else 0.55), false, 1.0 if k > 0 else 2.0)
		_draw_icon(t, col, r)
		y += CH + GAP
	if remaining > MAX_SHOWN and f:
		draw_string(f, Vector2(x + 8, y + 20), "+%d" % (remaining - MAX_SHOWN),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.85, 0.9))

func _draw_icon(t: String, col: Color, r: Rect2) -> void:
	var c := r.get_center()
	if t == "delivery":                      # cargo crate
		var br := Rect2(c.x - 14, c.y - 10, 28, 20)
		draw_rect(br, col, true)
		draw_rect(br, col.darkened(0.35), false, 2.0)
		draw_line(Vector2(br.position.x, c.y), Vector2(br.end.x, c.y), col.darkened(0.35), 2.0)
		draw_line(Vector2(c.x, br.position.y), Vector2(c.x, br.end.y), col.darkened(0.35), 2.0)
	elif t == "executive":                   # VIP diamond
		var s := 13.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x, c.y - s), Vector2(c.x + s, c.y), Vector2(c.x, c.y + s), Vector2(c.x - s, c.y)]), col)
	else:                                    # regular commuter: head + body
		draw_circle(Vector2(c.x, c.y - 6), 6.5, col)
		draw_rect(Rect2(c.x - 7, c.y + 1, 14, 12), col, true)
