class_name Grid3
extends Node2D
## Maze data + all grid drawing for prototype v3 "Path Drawing".
## The maze is a per-level grid of cells (row 0 = bottom/lobby). Cell types:
##   "." open shaft, "#" blocked, "R" room (stop when a route passes it),
##   "G" gate (open, but a one-car mutex).
## All layout geometry lives here as statics so every v3 script shares one
## source of truth. Drawing reads state from
## `game` (main3.gd): committed routes, the live drag preview, selection.

const CELL := 90.0
const GRID_X := 720.0 # playfield width the grid centers in
const GRID_Y_TOP := 100.0 # grid area is y 100..1000 (below the top HUD)
const GRID_Y_H := 900.0

## X-1 layout, top row first (index 0 = row 9, index 9 = row 0), cols 0..6.
## Kept as the class const because it is the original/default maze; other
## levels swap the static maze via load_level() (see levels3.gd).
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

## Current level's maze (defaults to X-1). Levels are data-driven: the level
## select / main3 call load_level() with a rows array BEFORE the scene draws.
static var maze_rows: Array = MAZE
static var COLS := 7
static var ROWS := 10
static var ORIGIN := Vector2(45.0, 100.0) # top-left corner of the top-left cell

static var _rooms_cache: Array = []
static var _gate_groups: Array = [] # Array of Arrays of Vector2i (corridors)
static var _gate_group_of := {} # Vector2i -> index into _gate_groups
static var _gates_dirty := true

var game = null # main3.gd


## Install a level's maze (array of row strings, TOP row first, all the same
## length). Recomputes bounds/origin and invalidates caches. Cells stay CELL
## px; the grid is centered in the 720x900 grid area.
static func load_level(rows: Array) -> void:
	maze_rows = rows
	ROWS = rows.size()
	COLS = (rows[0] as String).length()
	ORIGIN = Vector2((GRID_X - COLS * CELL) / 2.0,
			GRID_Y_TOP + (GRID_Y_H - ROWS * CELL) / 2.0)
	_rooms_cache = []
	_gates_dirty = true


# ---------------------------------------------------------------- maze queries

static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


static func cell_char(c: Vector2i) -> String:
	if not in_bounds(c):
		return "#"
	return maze_rows[ROWS - 1 - c.y].substr(c.x, 1)


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


## Orthogonally contiguous G cells form ONE gate group = one corridor-wide
## mutex. Returns an Array of Arrays of cells (flood-filled at level load;
## a single isolated G is a group of 1, exactly the old per-cell behavior).
static func gate_groups() -> Array:
	_ensure_gate_groups()
	return _gate_groups


## Group index of a gate cell, or -1 for any non-gate cell.
static func gate_group_of(c: Vector2i) -> int:
	_ensure_gate_groups()
	return _gate_group_of.get(c, -1)


static func _ensure_gate_groups() -> void:
	if not _gates_dirty:
		return
	_gates_dirty = false
	_gate_groups = []
	_gate_group_of = {}
	for c in gate_cells():
		if _gate_group_of.has(c):
			continue
		var gi := _gate_groups.size()
		var group: Array = []
		var stack: Array = [c]
		_gate_group_of[c] = gi
		while not stack.is_empty():
			var u: Vector2i = stack.pop_back()
			group.append(u)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var v: Vector2i = u + d
				if is_gate(v) and not _gate_group_of.has(v):
					_gate_group_of[v] = gi
					stack.append(v)
		_gate_groups.append(group)


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
	# Faint retiring polylines under cars still driving home a recall.
	for car in game.cars:
		if car == null or car.car_state != Car3.CarState.RECALLING:
			continue
		if car.recall_route == null or car.recall_route.cells.size() < 2:
			continue
		var rp := PackedVector2Array()
		for c in car.recall_route.cells:
			rp.append(cell_center(c))
		if car.recall_route.closed:
			rp.append(cell_center(car.recall_route.cells[0]))
		draw_polyline(rp, Color(car.color, 0.16), 4.0)
	# Committed routes (each nudged so overlaps stay readable).
	for i in game.routes.size():
		var route = game.routes[i]
		if route == null:
			continue
		_draw_route(route.cells, game.CARDS[i].color, i,
				game.selected_card == i, route.stop_cells().size() < 2,
				route.closed)
	# Live drag preview on top.
	if game.drawing and game.stroke.size() > 0 and game.selected_card >= 0:
		_draw_stroke_preview(game.stroke, game.CARDS[game.selected_card].color,
				game.stroke_closed)


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
			# Whole-corridor occupied tint: while any car holds this cell's
			# group, every cell of the group glows faintly in its color.
			var gi := Grid3.gate_group_of(c)
			if game != null and gi != -1:
				var g: Dictionary = game.gates.get(gi, {})
				var holder = g.get("holder")
				if holder != null:
					draw_rect(rect, Color(holder.color, 0.20))
			_draw_hazard_border(rect, c)


## Alternating yellow/black dashes = gate mutex. Edges shared with another
## cell of the SAME gate group are left open, so a contiguous corridor reads
## as one striped tunnel instead of a stack of boxes.
func _draw_hazard_border(rect: Rect2, c: Vector2i) -> void:
	var gi := Grid3.gate_group_of(c)
	# Screen-space top of the rect faces the grid cell ABOVE (y + 1).
	var edge_top := Grid3.gate_group_of(c + Vector2i(0, 1)) != gi
	var edge_bottom := Grid3.gate_group_of(c + Vector2i(0, -1)) != gi
	var edge_left := Grid3.gate_group_of(c + Vector2i(-1, 0)) != gi
	var edge_right := Grid3.gate_group_of(c + Vector2i(1, 0)) != gi
	var dark := Color(0.10, 0.10, 0.10)
	if edge_top:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 6.0)), dark)
	if edge_bottom:
		draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 6.0),
				Vector2(rect.size.x, 6.0)), dark)
	if edge_left:
		draw_rect(Rect2(rect.position, Vector2(6.0, rect.size.y)), dark)
	if edge_right:
		draw_rect(Rect2(Vector2(rect.end.x - 6.0, rect.position.y),
				Vector2(6.0, rect.size.y)), dark)
	var yellow := Color(0.95, 0.78, 0.20)
	var n := 0
	var step := 16.0
	var t := 0.0
	while t < rect.size.x:
		if n % 2 == 0:
			var w := minf(step * 0.6, rect.size.x - t)
			if edge_top:
				draw_rect(Rect2(rect.position.x + t, rect.position.y, w, 6.0), yellow)
			if edge_bottom:
				draw_rect(Rect2(rect.position.x + t, rect.end.y - 6.0, w, 6.0), yellow)
		t += step
		n += 1
	n = 0
	t = 0.0
	while t < rect.size.y:
		if n % 2 == 0:
			var h := minf(step * 0.6, rect.size.y - t)
			if edge_left:
				draw_rect(Rect2(rect.position.x, rect.position.y + t, 6.0, h), yellow)
			if edge_right:
				draw_rect(Rect2(rect.end.x - 6.0, rect.position.y + t, 6.0, h), yellow)
		t += step
		n += 1


func _draw_route(cells: Array, col: Color, index: int, selected: bool, warn: bool,
		closed := false) -> void:
	var off := Vector2((index - 1) * 9.0, (index - 1) * 9.0)
	var alpha := 0.9 if selected else 0.55
	if cells.size() >= 2:
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(cell_center(c) + off)
		if closed:
			pts.append(cell_center(cells[0]) + off) # the closing segment
		draw_polyline(pts, Color(col, alpha), 6.0)
	# Stop rings at room cells; squares at the two ends (open routes only —
	# a loop has no ends; it gets direction chevrons instead).
	for c in cells:
		if is_room(c):
			draw_arc(cell_center(c) + off, 12.0, 0.0, TAU, 24, Color(col, alpha), 4.0)
	if closed:
		_draw_loop_chevrons(cells, col, alpha, off)
	else:
		for e in [cells[0], cells[cells.size() - 1]]:
			var p: Vector2 = cell_center(e) + off
			draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(col, alpha))
	if warn:
		# Parked: not enough room stops.
		var wp: Vector2 = cell_center(cells[0]) + off + Vector2(0, -26.0)
		draw_circle(wp, 12.0, Color(0.9, 0.3, 0.25, 0.9))
		draw_string(ThemeDB.fallback_font, wp + Vector2(-4.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 19, Color.WHITE)


## Direction chevrons for CLOSED routes only: a small arrowhead on every 3rd
## segment (including the closing seam), pointing the way the car travels
## (= the order the player drew). Open ping-pong routes stay arrow-free.
func _draw_loop_chevrons(cells: Array, col: Color, alpha: float, off: Vector2) -> void:
	var n := cells.size()
	var bright := Color(col.lightened(0.2), minf(1.0, alpha + 0.3))
	for k in range(0, n, 3):
		var a: Vector2 = cell_center(cells[k]) + off
		var b: Vector2 = cell_center(cells[(k + 1) % n]) + off
		var d := (b - a).normalized()
		var mid := (a + b) / 2.0
		var perp := Vector2(-d.y, d.x)
		draw_polyline(PackedVector2Array([
				mid - d * 7.0 + perp * 8.0, mid + d * 7.0,
				mid - d * 7.0 - perp * 8.0]), bright, 4.0)


func _draw_stroke_preview(cells: Array, col: Color, closed := false) -> void:
	var bright := col.lightened(0.35)
	if cells.size() >= 2:
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(cell_center(c))
		if closed:
			pts.append(cell_center(cells[0])) # live closing segment
		draw_polyline(pts, Color(bright, 0.95), 10.0)
	for c in cells:
		draw_circle(cell_center(c), 6.0, Color(bright, 0.9))
	if closed:
		_draw_loop_chevrons(cells, bright, 0.95, Vector2.ZERO)
	# Pulsing head marker where the finger is (on the HEAD cell while closed —
	# that is where the finger sits after closing the loop).
	var head: Vector2 = cell_center(cells[0] if closed else cells[cells.size() - 1])
	var pulse := 10.0 + 4.0 * sin(Time.get_ticks_msec() / 90.0)
	draw_arc(head, pulse, 0.0, TAU, 24, Color.WHITE, 3.0)
