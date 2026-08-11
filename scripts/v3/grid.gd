class_name Grid3
extends Node2D
## Maze data + all grid drawing for prototype v3 "Path Drawing".
## The maze is 7 columns x 10 rows (row 0 = bottom/lobby). Cell types:
##   "." open shaft, "#" blocked, "R" room (stop when a route passes it),
##   "G" gate (open, but a one-car mutex).
## All layout geometry lives here as statics so every v3 script shares one
## source of truth (mirrors v2's building.gd role). Drawing reads state from
## `game` (main3.gd): committed routes, the live drag preview, selection.

const COLS := 7
const ROWS := 10
const CELL := 90.0
const ORIGIN := Vector2(45.0, 100.0) # top-left corner of cell (0, 9)

## Spec layout, top row first (index 0 = row 9, index 9 = row 0), cols 0..6.
const MAZE := [
	"R..#R.R", # row 9 (penthouse)
	".#.#.#.", # row 8
	"R#.G.#R", # row 7
	".###G#.", # row 6
	"..R#R..", # row 5
	"##.#.##", # row 4
	"R..G..R", # row 3
	".#.#.#.", # row 2
	".#.#.#.", # row 1
	"R.R.R.R", # row 0 (lobby)
]

const ROOM_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

static var _rooms_cache: Array = []

var game = null # main3.gd


# ---------------------------------------------------------------- maze queries

static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


static func cell_char(c: Vector2i) -> String:
	if not in_bounds(c):
		return "#"
	return MAZE[ROWS - 1 - c.y].substr(c.x, 1)


static func passable(c: Vector2i) -> bool:
	return in_bounds(c) and cell_char(c) != "#"


static func is_room(c: Vector2i) -> bool:
	return cell_char(c) == "R"


static func is_gate(c: Vector2i) -> bool:
	return cell_char(c) == "G"


## All room cells, scanned bottom-up / left-right (stable letter order).
static func rooms() -> Array:
	if _rooms_cache.is_empty():
		for y in ROWS:
			for x in COLS:
				var c := Vector2i(x, y)
				if is_room(c):
					_rooms_cache.append(c)
	return _rooms_cache


static func gate_cells() -> Array:
	var out: Array = []
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if is_gate(c):
				out.append(c)
	return out


static func room_letter(c: Vector2i) -> String:
	var i := rooms().find(c)
	if i < 0:
		return "?"
	return ROOM_LETTERS.substr(i, 1)


# ---------------------------------------------------------------- geometry

static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(c.x * CELL, (ROWS - 1 - c.y) * CELL), Vector2(CELL, CELL))


static func cell_center(c: Vector2i) -> Vector2:
	return cell_rect(c).get_center()


## Cell under a screen position, or (-1, -1) when outside the grid area.
static func cell_at(pos: Vector2) -> Vector2i:
	var local := pos - ORIGIN
	if local.x < 0.0 or local.y < 0.0 or local.x >= COLS * CELL or local.y >= ROWS * CELL:
		return Vector2i(-1, -1)
	return Vector2i(int(local.x / CELL), ROWS - 1 - int(local.y / CELL))


# ---------------------------------------------------------------- drawing

func _process(_delta: float) -> void:
	queue_redraw() # cheap; keeps previews/pulses live


func _draw() -> void:
	# Facade behind the maze.
	draw_rect(Rect2(ORIGIN - Vector2(8, 8),
			Vector2(COLS * CELL + 16, ROWS * CELL + 16)), Color(0.16, 0.15, 0.20))
	for y in ROWS:
		for x in COLS:
			_draw_cell(Vector2i(x, y))
	if game == null:
		return
	# Committed routes (each nudged so overlaps stay readable).
	for i in game.routes.size():
		var route = game.routes[i]
		if route == null:
			continue
		_draw_route(route.cells, game.CARDS[i].color, i,
				game.selected_card == i, route.stop_cells().size() < 2)
	# Live drag preview on top.
	if game.drawing and game.stroke.size() > 0 and game.selected_card >= 0:
		_draw_stroke_preview(game.stroke, game.CARDS[game.selected_card].color)


func _draw_cell(c: Vector2i) -> void:
	var rect := cell_rect(c).grow(-1.0)
	match cell_char(c):
		"#":
			draw_rect(rect, Color(0.055, 0.055, 0.075))
			# Diagonal hatch = solid rock.
			for t in range(0, int(CELL), 22):
				draw_line(rect.position + Vector2(t, 0),
						rect.position + Vector2(0, t), Color(1, 1, 1, 0.05), 3.0)
		".":
			draw_rect(rect, Color(0.205, 0.20, 0.245))
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
		"R":
			draw_rect(rect, Color(0.23, 0.29, 0.35))
			draw_rect(rect, Color(0.55, 0.75, 0.9, 0.5), false, 2.0)
			# Door strip at the cell floor + room letter.
			draw_rect(Rect2(rect.position.x + 8.0, rect.end.y - 10.0,
					rect.size.x - 16.0, 6.0), Color(0.55, 0.75, 0.9, 0.7))
			draw_string(ThemeDB.fallback_font,
					rect.position + Vector2(8.0, 26.0), room_letter(c),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(0.75, 0.88, 1.0, 0.8))
		"G":
			draw_rect(rect, Color(0.22, 0.21, 0.20))
			_draw_hazard_border(rect)


## Alternating yellow/black dashes around the border = gate mutex.
func _draw_hazard_border(rect: Rect2) -> void:
	draw_rect(rect.grow(-2.0), Color(0.10, 0.10, 0.10), false, 7.0)
	var yellow := Color(0.95, 0.78, 0.20)
	var n := 0
	var step := 16.0
	var t := 0.0
	while t < rect.size.x:
		if n % 2 == 0:
			var w := minf(step * 0.6, rect.size.x - t)
			draw_rect(Rect2(rect.position.x + t, rect.position.y, w, 6.0), yellow)
			draw_rect(Rect2(rect.position.x + t, rect.end.y - 6.0, w, 6.0), yellow)
		t += step
		n += 1
	n = 0
	t = 0.0
	while t < rect.size.y:
		if n % 2 == 0:
			var h := minf(step * 0.6, rect.size.y - t)
			draw_rect(Rect2(rect.position.x, rect.position.y + t, 6.0, h), yellow)
			draw_rect(Rect2(rect.end.x - 6.0, rect.position.y + t, 6.0, h), yellow)
		t += step
		n += 1


func _draw_route(cells: Array, col: Color, index: int, selected: bool, warn: bool) -> void:
	var off := Vector2((index - 1) * 9.0, (index - 1) * 9.0)
	var alpha := 0.9 if selected else 0.55
	if cells.size() >= 2:
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(cell_center(c) + off)
		draw_polyline(pts, Color(col, alpha), 6.0)
	# Stop rings at room cells; squares at the two ends.
	for c in cells:
		if is_room(c):
			draw_arc(cell_center(c) + off, 12.0, 0.0, TAU, 24, Color(col, alpha), 4.0)
	for e in [cells[0], cells[cells.size() - 1]]:
		var p: Vector2 = cell_center(e) + off
		draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(col, alpha))
	if warn:
		# Parked: not enough room stops.
		var wp: Vector2 = cell_center(cells[0]) + off + Vector2(0, -26.0)
		draw_circle(wp, 12.0, Color(0.9, 0.3, 0.25, 0.9))
		draw_string(ThemeDB.fallback_font, wp + Vector2(-4.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 19, Color.WHITE)


func _draw_stroke_preview(cells: Array, col: Color) -> void:
	var bright := col.lightened(0.35)
	if cells.size() >= 2:
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(cell_center(c))
		draw_polyline(pts, Color(bright, 0.95), 10.0)
	for c in cells:
		draw_circle(cell_center(c), 6.0, Color(bright, 0.9))
	# Pulsing head marker where the finger is.
	var head: Vector2 = cell_center(cells[cells.size() - 1])
	var pulse := 10.0 + 4.0 * sin(Time.get_ticks_msec() / 90.0)
	draw_arc(head, pulse, 0.0, TAU, 24, Color.WHITE, 3.0)
