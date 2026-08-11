class_name Building
extends Node2D
## Hospital cutout for v2: 10 floors, 4 shaft columns, transfer bridges.
## Owns all layout geometry as constants/static helpers so every script shares
## one source of truth. Also draws door states, selection highlights, and the
## install glow, reading state from `game` (main.gd).

const FLOORS := 10
const FLOOR_H := 94.0
const TOP := 100.0
const BOTTOM := TOP + FLOORS * FLOOR_H # 1040
const LEFT := 8.0
const LABEL_W := 130.0
const RIGHT := 668.0

const COL_COUNT := 4
const COL_W := 104.0
const COL_X := [146.0, 282.0, 418.0, 554.0]

const CAR_H := 84.0

const ACCENT := Color(0.98, 0.78, 0.25)

var game = null # main.gd


static func floor_to_y(floor_i: int) -> float:
	return BOTTOM - floor_i * FLOOR_H


static func floor_name(floor_i: int) -> String:
	if floor_i == 0:
		return "LOBBY"
	if floor_i == 7:
		return "SURGERY"
	return "W%d" % (floor_i if floor_i < 7 else floor_i - 1)


static func column_at(x: float, y: float) -> int:
	if y < TOP or y > BOTTOM:
		return -1
	for i in COL_COUNT:
		if x >= COL_X[i] and x <= COL_X[i] + COL_W:
			return i
	return -1


static func floor_at(y: float) -> int:
	return clampi(int((BOTTOM - y) / FLOOR_H), 0, FLOORS - 1)


func _ready() -> void:
	for i in FLOORS:
		var label := Label.new()
		label.text = "%d %s" % [i, floor_name(i)]
		label.position = Vector2(LEFT + 6.0, floor_to_y(i) - FLOOR_H + 30.0)
		label.add_theme_font_size_override("font_size", 22)
		var col := Color(0.75, 0.78, 0.85)
		if i == 7:
			col = Color(0.95, 0.45, 0.4)
		label.add_theme_color_override("font_color", col)
		add_child(label)


func _process(_delta: float) -> void:
	queue_redraw() # cheap; keeps pulses/selection live


func _draw() -> void:
	# Facade + interior.
	draw_rect(Rect2(LEFT - 6.0, TOP - 8.0, RIGHT - LEFT + 12.0, BOTTOM - TOP + 16.0), Color(0.16, 0.15, 0.20))
	draw_rect(Rect2(LEFT, TOP, RIGHT - LEFT, BOTTOM - TOP), Color(0.22, 0.21, 0.26))
	var transfers: Array = []
	if game != null and game.level.has("transfers"):
		transfers = game.level.transfers
	# Transfer floor bands ("bridges").
	for f in transfers:
		var y: float = floor_to_y(f)
		draw_rect(Rect2(LEFT, y - FLOOR_H, RIGHT - LEFT, FLOOR_H), Color(ACCENT, 0.07))
		draw_rect(Rect2(LEFT, y - 10.0, RIGHT - LEFT, 10.0), Color(ACCENT, 0.35))
		for dash_x in range(int(LEFT) + 6, int(RIGHT) - 12, 28):
			draw_rect(Rect2(dash_x, y - 8.0, 16.0, 6.0), Color(ACCENT, 0.8))
	# Floor slabs.
	for i in FLOORS:
		var y := floor_to_y(i)
		draw_line(Vector2(LEFT, y), Vector2(RIGHT, y), Color(0.05, 0.05, 0.06), 4.0)
	# Columns.
	var pulse := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 200.0)
	for c in COL_COUNT:
		var rect := Rect2(COL_X[c], TOP, COL_W, BOTTOM - TOP)
		draw_rect(rect, Color(0.10, 0.10, 0.13))
		var elev = null if game == null else game.columns[c]
		if elev == null:
			if game != null and game.selected_card >= 0:
				# Empty column glows while a card is selected.
				draw_rect(rect, Color(ACCENT, pulse), false, 5.0)
				draw_string(ThemeDB.fallback_font, Vector2(COL_X[c] + COL_W / 2.0 - 12.0, TOP + 54.0),
						"+", HORIZONTAL_ALIGNMENT_CENTER, 24.0, 44, Color(ACCENT, pulse))
			else:
				draw_rect(rect, Color(1, 1, 1, 0.10), false, 2.0)
		else:
			_draw_doors(c, elev)
	# Selected column outline on top.
	if game != null and game.selected_column >= 0:
		var sc: int = game.selected_column
		draw_rect(Rect2(COL_X[sc] - 3.0, TOP - 3.0, COL_W + 6.0, BOTTOM - TOP + 6.0),
				Color(1, 1, 1, 0.9), false, 4.0)


func _draw_doors(c: int, elev) -> void:
	var selected: bool = game.selected_column == c
	var body: Color = Levels.card_color(elev.card_type)
	for f in FLOORS:
		var y := floor_to_y(f)
		var cell := Rect2(COL_X[c], y - FLOOR_H, COL_W, FLOOR_H)
		var on: bool = elev.doors[f]
		# Door marker on the left edge of the column (where queues stand).
		var door := Rect2(COL_X[c] + 2.0, y - 52.0, 10.0, 48.0)
		if on:
			draw_rect(door, Color(body, 0.95))
		else:
			draw_rect(door, Color(0.35, 0.12, 0.12))
			draw_line(door.position, door.position + door.size, Color(0.8, 0.25, 0.2), 3.0)
			draw_line(door.position + Vector2(door.size.x, 0), door.position + Vector2(0, door.size.y),
					Color(0.8, 0.25, 0.2), 3.0)
		if selected:
			# Obvious per-cell toggle affordance.
			draw_rect(cell.grow(-4.0), Color(1, 1, 1, 0.25), false, 2.0)
			var pill := Rect2(COL_X[c] + COL_W - 40.0, y - FLOOR_H / 2.0 - 12.0, 32.0, 24.0)
			if on:
				draw_rect(pill, Color(0.3, 0.75, 0.4, 0.9))
			else:
				draw_rect(pill, Color(0.6, 0.2, 0.2, 0.9))
			draw_string(ThemeDB.fallback_font, Vector2(pill.position.x + 2.0, pill.position.y + 18.0),
					"ON" if on else "OFF", HORIZONTAL_ALIGNMENT_LEFT, 30.0, 13, Color(1, 1, 1, 0.95))
