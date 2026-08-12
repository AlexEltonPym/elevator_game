class_name Grid3
extends Node2D
## Maze data + all grid drawing for prototype v3 "Path Drawing".
## The maze is a per-level grid of cells (row 0 = bottom/lobby). Cell types:
##   "." open shaft, "#" blocked, "R" room (stop when a route passes it),
##   "G" gate (a corridor of WIDTH 2 - see below),
##   "1".."9" gate of that WIDTH (so "2" is a synonym for "G").
##
## CORRIDOR WIDTH (v4 phase 2). A gate group is no longer a plain one-car
## mutex: it has a width, and
##   * a car may enter only if car.width <= corridor.width, and
##   * cars share it while the SUM of the widths inside is <= corridor.width.
## The default "G" is width 2, which reproduces the old behaviour exactly:
## every pre-v4 car is width 2 and 2 + 2 > 2, so the corridor stays a one-car
## mutex. A width-1 corridor is a pod-only passage; a width-2 one bars the
## width-3 cargo car; a width-3 one takes three pods, or one cargo, or a pod
## plus a standard.
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

const DEFAULT_GATE_WIDTH := 2 # what a plain "G" means

static var _rooms_cache: Array = []
static var _gate_groups: Array = [] # Array of Arrays of Vector2i (corridors)
static var _gate_group_of := {} # Vector2i -> index into _gate_groups
static var _gate_group_width: Array = [] # per group: the narrowest cell in it
static var _gates_dirty := true

## PERF (v3.5): cell-type lookup sets built once per load_level. cell_char()
## allocates a String per call via substr (measured 0.7 us), and is_room() is
## on the hottest path there is (Route3.stop_cells -> Car3.running, every car
## every game tick). Pure derived data from maze_rows - same answers.
static var _room_set := {} # Vector2i -> true
static var _gate_set := {} # Vector2i -> corridor width (int)
static var _blocked_set := {}
static var _cells_dirty := true

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
	_cells_dirty = true


# ---------------------------------------------------------------- maze queries

## Build the R / G / # cell sets for the current maze (lazy, so a maze
## installed by assigning maze_rows directly still works).
static func _ensure_cell_sets() -> void:
	if not _cells_dirty:
		return
	_cells_dirty = false
	_room_set = {}
	_gate_set = {}
	_blocked_set = {}
	for y in ROWS:
		var row: String = maze_rows[ROWS - 1 - y]
		for x in COLS:
			var ch := row.substr(x, 1)
			var c := Vector2i(x, y)
			match ch:
				"R":
					_room_set[c] = true
				"G":
					_gate_set[c] = DEFAULT_GATE_WIDTH
				"#":
					_blocked_set[c] = true
				_:
					if ch.is_valid_int(): # "1".."9": a gate of that width
						_gate_set[c] = int(ch)


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


## The RAW maze character. Prefer is_room / is_gate / passable: those read the
## cell SETS, so they treat a gate written as its width digit ("1", "3") the
## same as a plain "G", which this cannot.
static func cell_char(c: Vector2i) -> String:
	if not in_bounds(c):
		return "#"
	return maze_rows[ROWS - 1 - c.y].substr(c.x, 1)


static func passable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	_ensure_cell_sets()
	return not _blocked_set.has(c)


static func is_room(c: Vector2i) -> bool:
	_ensure_cell_sets()
	return _room_set.has(c)


static func is_gate(c: Vector2i) -> bool:
	_ensure_cell_sets()
	return _gate_set.has(c)


## Corridor width of a gate CELL (0 for anything that is not a gate).
static func gate_width(c: Vector2i) -> int:
	_ensure_cell_sets()
	return int(_gate_set.get(c, 0))


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


## Width of a whole corridor = its NARROWEST cell (a corridor is only as wide
## as its tightest squeeze). -1 for a non-group index.
static func gate_group_width(gi: int) -> int:
	_ensure_gate_groups()
	if gi < 0 or gi >= _gate_group_width.size():
		return -1
	return _gate_group_width[gi]


## The narrowest corridor a polyline enters, or a large number when it enters
## none. THE check behind "this car is too wide for this route".
static func route_min_gate_width(cells: Array) -> int:
	var w := 9999
	for c in cells:
		var gi := gate_group_of(c)
		if gi != -1:
			w = mini(w, gate_group_width(gi))
	return w


static func _ensure_gate_groups() -> void:
	if not _gates_dirty:
		return
	_gates_dirty = false
	_gate_groups = []
	_gate_group_of = {}
	_gate_group_width = []
	for c in gate_cells():
		if _gate_group_of.has(c):
			continue
		var gi := _gate_groups.size()
		var group: Array = []
		var stack: Array = [c]
		var w := 9999
		_gate_group_of[c] = gi
		while not stack.is_empty():
			var u: Vector2i = stack.pop_back()
			group.append(u)
			w = mini(w, gate_width(u))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var v: Vector2i = u + d
				if is_gate(v) and not _gate_group_of.has(v):
					_gate_group_of[v] = gi
					stack.append(v)
		_gate_groups.append(group)
		_gate_group_width.append(w)


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
				route.closed, game.cars[i].home_cell if game.cars[i] != null else null)
	# Live drag preview on top.
	if game.drawing and game.stroke.size() > 0 and game.selected_card >= 0:
		_draw_stroke_preview(game.stroke, game.CARDS[game.selected_card].color,
				game.stroke_closed)


func _draw_cell(c: Vector2i) -> void:
	var rect := cell_rect(c).grow(-1.0)
	# Drawn off the CELL SETS, not the raw character, so a gate written as its
	# width digit ("1", "3") renders exactly like a plain "G".
	if not Grid3.passable(c):
		# Blocked = "not here": a flat fill slightly darker than the facade
		# behind the maze, plus a thin subtle border. No hatch — the static maze
		# recedes so routes, cars and passengers read first (docs/ui-pass §3).
		draw_rect(rect, Color(0.11, 0.105, 0.13))
		draw_rect(rect, Color(0, 0, 0, 0.22), false, 1.0)
	elif Grid3.is_room(c):
		draw_rect(rect, Color(0.23, 0.29, 0.35))
		draw_rect(rect, Color(0.55, 0.75, 0.9, 0.4), false, 2.0)
		# Door strip at the cell floor + room letter (door lightened so it sits
		# under the route line, not over it).
		draw_rect(Rect2(rect.position.x + 8.0, rect.end.y - 9.0,
				rect.size.x - 16.0, 4.0), Color(0.55, 0.75, 0.9, 0.30))
		draw_string(ThemeDB.fallback_font,
				rect.position + Vector2(8.0, 26.0), room_letter(c),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(0.75, 0.88, 1.0, 0.8))
	elif Grid3.is_gate(c):
		draw_rect(rect, Color(0.22, 0.21, 0.20))
		# Whole-corridor occupied tint: while any car is inside this cell's
		# group, every cell of the group glows faintly in its color.
		var gi := Grid3.gate_group_of(c)
		if game != null and gi != -1:
			for holder in game.gates.get(gi, {}).get("holders", []):
				draw_rect(rect, Color(holder.color, 0.20))
		_draw_hazard_border(rect, c)
		_draw_gate_width(rect, c)
	else:
		draw_rect(rect, Color(0.205, 0.20, 0.245))
		draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)


## How wide the corridor is, as that many stacked bars down the cell's middle:
## one bar = pods only, two = the familiar single-file tunnel, three = wide
## enough for the cargo car. Readable at a glance without reading a number.
func _draw_gate_width(rect: Rect2, c: Vector2i) -> void:
	var w := Grid3.gate_width(c)
	if w <= 0:
		return
	var col := Color(0.90, 0.76, 0.28, 0.34)
	var bar := 7.0
	var gap := 5.0
	var total := w * bar + (w - 1) * gap
	var x0 := rect.position.x + (rect.size.x - total) / 2.0
	for i in w:
		draw_rect(Rect2(x0 + i * (bar + gap), rect.get_center().y - 13.0,
				bar, 26.0), col)


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
	# A THIN striped border keeps the hazard identity without the old bright
	# band (docs/ui-pass §3): the corridor still reads as striped, but recedes.
	var eb := 3.0
	var dark := Color(0.10, 0.10, 0.10, 0.85)
	if edge_top:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, eb)), dark)
	if edge_bottom:
		draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - eb),
				Vector2(rect.size.x, eb)), dark)
	if edge_left:
		draw_rect(Rect2(rect.position, Vector2(eb, rect.size.y)), dark)
	if edge_right:
		draw_rect(Rect2(Vector2(rect.end.x - eb, rect.position.y),
				Vector2(eb, rect.size.y)), dark)
	var yellow := Color(0.90, 0.76, 0.28, 0.85)
	var n := 0
	var step := 16.0
	var t := 0.0
	while t < rect.size.x:
		if n % 2 == 0:
			var w := minf(step * 0.6, rect.size.x - t)
			if edge_top:
				draw_rect(Rect2(rect.position.x + t, rect.position.y, w, eb), yellow)
			if edge_bottom:
				draw_rect(Rect2(rect.position.x + t, rect.end.y - eb, w, eb), yellow)
		t += step
		n += 1
	n = 0
	t = 0.0
	while t < rect.size.y:
		if n % 2 == 0:
			var h := minf(step * 0.6, rect.size.y - t)
			if edge_left:
				draw_rect(Rect2(rect.position.x, rect.position.y + t, eb, h), yellow)
			if edge_right:
				draw_rect(Rect2(rect.end.x - eb, rect.position.y + t, eb, h), yellow)
		t += step
		n += 1


func _draw_route(cells: Array, col: Color, index: int, selected: bool, warn: bool,
		closed := false, home = null) -> void:
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
	if home != null:
		_draw_home(cell_center(home) + off, col)
	if warn:
		# Parked: not enough room stops.
		var wp: Vector2 = cell_center(cells[0]) + off + Vector2(0, -26.0)
		draw_circle(wp, 12.0, Color(0.9, 0.3, 0.25, 0.9))
		draw_string(ThemeDB.fallback_font, wp + Vector2(-4.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 19, Color.WHITE)


## The card's HOME cell (v4 phase 2): a little house in the card's colour on
## the route cell an idle empty car deadheads back to. Drawn filled with a
## dark outline so it stays legible on top of the route polyline.
func _draw_home(p: Vector2, col: Color) -> void:
	var body := PackedVector2Array([
			p + Vector2(-11, 14), p + Vector2(-11, -2), p + Vector2(0, -13),
			p + Vector2(11, -2), p + Vector2(11, 14)])
	draw_colored_polygon(body, Color(col.lightened(0.25), 0.95))
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, Color(0.05, 0.05, 0.08, 0.9), 3.0)
	draw_rect(Rect2(p + Vector2(-4, 4), Vector2(8, 10)), Color(0.05, 0.05, 0.08, 0.85))


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
