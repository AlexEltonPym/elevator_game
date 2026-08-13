class_name Grid5
extends Node2D
## Grid data + all drawing for the v5 "Rooms" feel-prototype. Adapted from
## scripts/v3/grid.gd (cell math + the grid-fit view transform are reused
## wholesale) but the maze model is different:
##
##   * The grid is mostly EMPTY open cells. A few cells are BLOCKED walls.
##   * ROOMS are connected sets of cells (multi-cell). Room cells are NOT
##     routable — passable() is false for them, so a drawn route can only run
##     through open cells beside a room.
##   * Each room carries AUTHORED DROPOFF points: a room cell + a facing dir.
##     The open cell it faces into (cell + dir) is the DOCK CELL. An elevator
##     SERVES a room iff its route passes through one of that room's dock cells.
##
## Drawing reads live state from `game` (main5.gd): committed routes, the drag
## preview, selection.

const CELL := 90.0
const GRID_X := 720.0 # playfield width the grid centers in
const GRID_Y_TOP := 100.0 # grid area is y 100..1000 (below the top HUD)
const GRID_Y_H := 900.0

## Seconds of walk per tile of Manhattan distance (v5.1). Board = walk from a
## room's anchor cell to the boarding dock; alight = walk from the alighting dock
## back to the (next) room's anchor. Priced identically in Pathfind5 so planning
## stays honest against the sim. Tuned for feel (spec: ~0.3-0.6 s).
const WALK_PER_TILE := 0.45

const DEFAULT_CORRIDOR_WIDTH := 2 # a plain corridor cell = one normal lift

const ROOM_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

static var COLS := 5
static var ROWS := 7
static var ORIGIN := Vector2(45.0, 100.0)
static var view_scale := 1.0
static var view_offset := Vector2.ZERO

# Per-level derived data (rebuilt in load_level).
static var _blocked := {} # Vector2i -> true
static var _room_of := {} # Vector2i -> room_id (cells that belong to a room)
static var _rooms: Array = [] # room_id -> {type, cells, letter, drops, center, rect, anchor}
static var _dock_of := {} # dock cell -> Array[room_id] served from that cell
static var _dock_marks: Array = [] # {room_id, cell (room cell), dir, dock}

# Corridors (v5.1): open ROUTABLE cells that carry a width and form FIFO mutex
# groups (ported from v3 grid gates). A car may enter iff car.width <= width, and
# cars share while the sum of widths inside <= width. Default width 2 = one
# normal (width-2) lift at a time. Contiguous corridor cells = one group.
static var _corridor_width := {} # Vector2i -> corridor width (int)
static var _corridor_groups: Array = [] # gi -> Array[Vector2i]
static var _corridor_group_of := {} # Vector2i -> gi
static var _corridor_group_width: Array = [] # gi -> narrowest cell width in group
static var _corridors_dirty := true

var game = null # main5.gd

const ROOM_TINT := {
	"lobby": Color(0.28, 0.33, 0.40),
	"office": Color(0.24, 0.30, 0.36),
	"atrium": Color(0.34, 0.30, 0.42),
	"store": Color(0.36, 0.31, 0.26),
	"cafe": Color(0.34, 0.28, 0.30),
}


## Install a level (Levels5 entry). Builds bounds, the room / dock maps and the
## display fit transform. Cells stay CELL px in LOGICAL space; a grid larger
## than the grid area is scaled DOWN to fit (identity when it already fits).
static func load_level(level: Dictionary) -> void:
	COLS = int(level.cols)
	ROWS = int(level.rows)
	ORIGIN = Vector2((GRID_X - COLS * CELL) / 2.0,
			GRID_Y_TOP + (GRID_Y_H - ROWS * CELL) / 2.0)
	var bbox_w := COLS * CELL
	var bbox_h := ROWS * CELL
	view_scale = minf(1.0, minf(GRID_X / bbox_w, GRID_Y_H / bbox_h))
	var cx := ORIGIN.x + bbox_w / 2.0
	var cy := ORIGIN.y + bbox_h / 2.0
	view_offset = Vector2(GRID_X / 2.0 - view_scale * cx,
			(GRID_Y_TOP + GRID_Y_H / 2.0) - view_scale * cy)
	_blocked = {}
	for c in level.get("blocked", []):
		_blocked[c] = true
	# Corridors: each entry is {cells:Array[Vector2i], width:int?} (default 2).
	_corridor_width = {}
	_corridor_groups = []
	_corridor_group_of = {}
	_corridor_group_width = []
	_corridors_dirty = true
	for co in level.get("corridors", []):
		var cw := int(co.get("width", DEFAULT_CORRIDOR_WIDTH))
		for c in co.cells:
			_corridor_width[c] = cw
	_room_of = {}
	_rooms = []
	_dock_of = {}
	_dock_marks = []
	for i in level.rooms.size():
		var rm: Dictionary = level.rooms[i]
		var cells: Array = rm.cells
		for c in cells:
			_room_of[c] = i
		var drops: Array = []
		var door_cells := {}
		for d in rm.get("drops", []):
			var dock: Vector2i = d.cell + d.dir
			drops.append({"cell": d.cell, "dir": d.dir, "dock": dock})
			door_cells[d.cell] = d.dir
			if not _dock_of.has(dock):
				_dock_of[dock] = []
			if not _dock_of[dock].has(i):
				_dock_of[dock].append(i)
			_dock_marks.append({"room_id": i, "cell": d.cell, "dir": d.dir, "dock": dock})
		var ctr := _cells_center(cells)
		var qcell: Vector2i = _pick_queue(cells, door_cells, ctr)
		_rooms.append({
			"type": str(rm.type), "cells": cells, "letter": ROOM_LETTERS.substr(i, 1),
			"drops": drops, "center": ctr, "rect": _cells_rect(cells),
			"anchor": _closest_cell(cells, ctr),
			"queue": qcell,
			"queue_dir": door_cells.get(qcell, Vector2i(1, 0))})


## The room's QUEUE cell: the boardable waiting tile NEAR the dock — a room DOOR
## cell (the cell an elevator opens beside). People spawn on a far tile, then walk
## here to queue; boarding steps from here onto the dock. Nearest the centroid
## among door cells, deterministic. Board/alight walk time is priced from here in
## BOTH the sim and Pathfind5, so they match.
static func _pick_queue(cells: Array, doors: Dictionary, center: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in cells:
		if not doors.has(c):
			continue
		var d := cell_center(c).distance_squared_to(center)
		if d < bd - 0.001:
			bd = d
			best = c
	if best.x < 0:
		return _closest_cell(cells, center)
	return best


## The room cell nearest the room centroid: a deterministic "where people stand"
## anchor for walk-time distances (board = anchor -> dock, alight = dock ->
## anchor). Tie-break by list order so it never depends on float wobble.
static func _closest_cell(cells: Array, center: Vector2) -> Vector2i:
	var best: Vector2i = cells[0]
	var bd := INF
	for c in cells:
		var d := cell_center(c).distance_squared_to(center)
		if d < bd - 0.001:
			bd = d
			best = c
	return best


# ---------------------------------------------------------------- queries

static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS


## Routable open cell: in bounds, not a wall, not part of a room. A route can
## only run through these (rooms are beside the shaft, never on it).
static func passable(c: Vector2i) -> bool:
	return in_bounds(c) and not _blocked.has(c) and not _room_of.has(c)


static func is_room_cell(c: Vector2i) -> bool:
	return _room_of.has(c)


static func room_id_at(c: Vector2i) -> int:
	return int(_room_of.get(c, -1))


static func room_count() -> int:
	return _rooms.size()


static func room_letter(id: int) -> String:
	if id < 0 or id >= _rooms.size():
		return "?"
	return _rooms[id].letter


static func room_type(id: int) -> String:
	return _rooms[id].type if id >= 0 and id < _rooms.size() else ""


static func room_cells(id: int) -> Array:
	return _rooms[id].cells


static func room_center(id: int) -> Vector2:
	return _rooms[id].center


static func room_rect(id: int) -> Rect2:
	return _rooms[id].rect


## Room ids served from a dock cell (usually one; a corridor cell flanked by two
## rooms serves both — the "double duty" case). Empty for a non-dock cell.
static func dock_rooms(cell: Vector2i) -> Array:
	return _dock_of.get(cell, [])


static func is_dock(cell: Vector2i) -> bool:
	return _dock_of.has(cell)


## The room's anchor cell (where its people are treated as standing for walk-time
## distances). Deterministic; used by both the sim and Pathfind5 so board/alight
## walk costs match exactly.
static func room_anchor(id: int) -> Vector2i:
	if id < 0 or id >= _rooms.size():
		return Vector2i(-1, -1)
	return _rooms[id].anchor


## The boardable waiting tile (see _pick_queue). Board walk = queue -> dock,
## alight walk = dock -> queue; priced identically in Pathfind5.
static func room_queue(id: int) -> Vector2i:
	if id < 0 or id >= _rooms.size():
		return Vector2i(-1, -1)
	return _rooms[id].queue


## The direction from the queue tile toward its dock — the boarding queue lines up
## behind the queue tile along the opposite of this.
static func room_queue_dir(id: int) -> Vector2i:
	if id < 0 or id >= _rooms.size():
		return Vector2i(1, 0)
	return _rooms[id].queue_dir


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# ---------------------------------------------------------------- corridors

## Is this an open cell that carries a corridor width / mutex? (Still passable:
## corridors are routable cells, just width-limited and one-at-a-time by default.)
static func is_corridor(c: Vector2i) -> bool:
	return _corridor_width.has(c)


## Corridor width of a single CELL (0 if not a corridor cell).
static func corridor_width(c: Vector2i) -> int:
	return int(_corridor_width.get(c, 0))


## Orthogonally contiguous corridor cells form ONE mutex group (flood-filled at
## load). A lone corridor cell is a group of 1.
static func corridor_groups() -> Array:
	_ensure_corridor_groups()
	return _corridor_groups


static func corridor_group_of(c: Vector2i) -> int:
	_ensure_corridor_groups()
	return int(_corridor_group_of.get(c, -1))


## Width of a whole corridor = its NARROWEST cell. -1 for a non-group index.
static func corridor_group_width(gi: int) -> int:
	_ensure_corridor_groups()
	if gi < 0 or gi >= _corridor_group_width.size():
		return -1
	return _corridor_group_width[gi]


## The narrowest corridor a polyline enters, or a large number when it enters
## none. Behind the "this car is too wide for this route" commit check.
static func route_min_corridor_width(cells: Array) -> int:
	var w := 9999
	for c in cells:
		var gi := corridor_group_of(c)
		if gi != -1:
			w = mini(w, corridor_group_width(gi))
	return w


static func _ensure_corridor_groups() -> void:
	if not _corridors_dirty:
		return
	_corridors_dirty = false
	_corridor_groups = []
	_corridor_group_of = {}
	_corridor_group_width = []
	for c in _corridor_width:
		if _corridor_group_of.has(c):
			continue
		var gi := _corridor_groups.size()
		var group: Array = []
		var stack: Array = [c]
		var w := 9999
		_corridor_group_of[c] = gi
		while not stack.is_empty():
			var u: Vector2i = stack.pop_back()
			group.append(u)
			w = mini(w, corridor_width(u))
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var v: Vector2i = u + d
				if _corridor_width.has(v) and not _corridor_group_of.has(v):
					_corridor_group_of[v] = gi
					stack.append(v)
		_corridor_groups.append(group)
		_corridor_group_width.append(w)


# ---------------------------------------------------------------- geometry

static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(c.x * CELL, (ROWS - 1 - c.y) * CELL),
			Vector2(CELL, CELL))


static func cell_center(c: Vector2i) -> Vector2:
	return cell_rect(c).get_center()


static func cell_at(pos: Vector2) -> Vector2i:
	var logical := (pos - view_offset) / view_scale
	var local := logical - ORIGIN
	if local.x < 0.0 or local.y < 0.0 or local.x >= COLS * CELL or local.y >= ROWS * CELL:
		return Vector2i(-1, -1)
	return Vector2i(int(local.x / CELL), ROWS - 1 - int(local.y / CELL))


static func _cells_center(cells: Array) -> Vector2:
	var acc := Vector2.ZERO
	for c in cells:
		acc += cell_center(c)
	return acc / float(maxi(1, cells.size()))


static func _cells_rect(cells: Array) -> Rect2:
	var r := cell_rect(cells[0])
	for i in range(1, cells.size()):
		r = r.merge(cell_rect(cells[i]))
	return r


# ---------------------------------------------------------------- drawing

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Faint building facade behind everything.
	draw_rect(Rect2(ORIGIN - Vector2(8, 8),
			Vector2(COLS * CELL + 16, ROWS * CELL + 16)), Color(0.13, 0.13, 0.16))
	# Open + blocked cells first (recede), then rooms, then dock marks, routes.
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if Grid5.is_room_cell(c):
				continue
			var rect := cell_rect(c).grow(-1.0)
			if Grid5.is_corridor(c):
				_draw_corridor(rect, c)
			elif not Grid5.passable(c):
				draw_rect(rect, Color(0.10, 0.10, 0.12))
				draw_rect(rect, Color(0, 0, 0, 0.22), false, 1.0)
			else:
				draw_rect(rect, Color(0.175, 0.175, 0.21))
				draw_rect(rect, Color(0, 0, 0, 0.18), false, 1.0)
	for id in Grid5._rooms.size():
		_draw_room(id)
	if game == null:
		return
	# Which dock cells are covered by which committed routes (car colour).
	var covered := {} # dock cell -> Array[Color]
	for i in game.routes.size():
		var route = game.routes[i]
		if route == null:
			continue
		for cell in route.cells:
			if Grid5.is_dock(cell):
				if not covered.has(cell):
					covered[cell] = []
				covered[cell].append(game.CARDS[i].color)
	for mark in Grid5._dock_marks:
		_draw_dock(mark, covered.get(mark.dock, []))
	# Committed routes (nudged so overlaps stay readable).
	for i in game.routes.size():
		var route = game.routes[i]
		if route == null:
			continue
		_draw_route(route.cells, game.CARDS[i].color, i,
				game.selected_card == i, route.served_rooms().size() < 2, route.closed)
	# Live drag preview on top.
	if game.drawing and game.stroke.size() > 0 and game.selected_card >= 0:
		_draw_stroke_preview(game.stroke, game.CARDS[game.selected_card].color,
				game.stroke_closed)


func _draw_room(id: int) -> void:
	var rm: Dictionary = Grid5._rooms[id]
	var tint: Color = ROOM_TINT.get(rm.type, Color(0.26, 0.30, 0.36))
	for c in rm.cells:
		var rect := cell_rect(c).grow(-1.0)
		draw_rect(rect, tint)
	# One outline around the whole room footprint (cell edges on the boundary).
	for c in rm.cells:
		var rect := cell_rect(c)
		for e in [[Vector2i(0, 1), Rect2(rect.position, Vector2(rect.size.x, 3.0))],
				[Vector2i(0, -1), Rect2(Vector2(rect.position.x, rect.end.y - 3.0),
						Vector2(rect.size.x, 3.0))],
				[Vector2i(-1, 0), Rect2(rect.position, Vector2(3.0, rect.size.y))],
				[Vector2i(1, 0), Rect2(Vector2(rect.end.x - 3.0, rect.position.y),
						Vector2(3.0, rect.size.y))]]:
			if Grid5.room_id_at(c + e[0]) != id:
				draw_rect(e[1], Color(0.6, 0.72, 0.9, 0.5))
	# Letter + type label at the room centre.
	var ctr: Vector2 = rm.center
	draw_string(ThemeDB.fallback_font, ctr + Vector2(-26.0, -2.0), rm.letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 34, Color(0.85, 0.93, 1.0, 0.92))
	draw_string(ThemeDB.fallback_font, ctr + Vector2(2.0, 6.0), str(rm.type),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.8, 0.88, 0.98, 0.6))


## A dropoff: a door notch on the room cell's facing edge + a chevron pointing
## into its dock cell. The dock cell gets a dashed outline so the player can see
## where a lift must reach; when a route covers it, the outline fills in the
## covering car's colour(s).
func _draw_dock(mark: Dictionary, cover: Array) -> void:
	var rc := cell_rect(mark.cell)
	var dir: Vector2i = mark.dir
	var door_col := Color(0.95, 0.85, 0.45, 0.9)
	# Door strip on the facing edge.
	var t := 8.0
	var strip: Rect2
	if dir == Vector2i(1, 0):
		strip = Rect2(rc.end.x - t, rc.position.y + 14.0, t, rc.size.y - 28.0)
	elif dir == Vector2i(-1, 0):
		strip = Rect2(rc.position.x, rc.position.y + 14.0, t, rc.size.y - 28.0)
	elif dir == Vector2i(0, 1): # room-space up = screen up
		strip = Rect2(rc.position.x + 14.0, rc.position.y, rc.size.x - 28.0, t)
	else:
		strip = Rect2(rc.position.x + 14.0, rc.end.y - t, rc.size.x - 28.0, t)
	draw_rect(strip, door_col)
	# Dock cell outline.
	var dock := cell_rect(mark.dock).grow(-6.0)
	if cover.is_empty():
		# Not yet served: faint dashed square (drawn as four short ticks).
		var col := Color(0.95, 0.85, 0.45, 0.33)
		var s := 14.0
		for corner in [dock.position, Vector2(dock.end.x, dock.position.y),
				Vector2(dock.position.x, dock.end.y), dock.end]:
			var sx := -1.0 if corner.x > dock.get_center().x else 1.0
			var sy := -1.0 if corner.y > dock.get_center().y else 1.0
			draw_line(corner, corner + Vector2(sx * s, 0.0), col, 2.0)
			draw_line(corner, corner + Vector2(0.0, sy * s), col, 2.0)
	else:
		for k in cover.size():
			draw_rect(dock.grow(-k * 3.0), Color(cover[k], 0.7), false, 3.0)



## A corridor cell: the calm v4 hazard identity (thin striped border on the group
## boundary + width bars down the middle) plus a whole-corridor occupied tint that
## glows faintly in the colour of any car currently inside the group.
func _draw_corridor(rect: Rect2, c: Vector2i) -> void:
	draw_rect(rect, Color(0.22, 0.21, 0.20))
	var gi := Grid5.corridor_group_of(c)
	if game != null and gi != -1 and game.corridors.has(gi):
		for holder in game.corridors[gi].holders:
			draw_rect(rect, Color(holder.color, 0.20))
	# Width bars: one bar = pod-only, two = one normal lift, three = cargo-wide.
	var w := Grid5.corridor_width(c)
	if w > 0:
		var col := Color(0.90, 0.76, 0.28, 0.34)
		var bar := 7.0
		var gap := 5.0
		var total := w * bar + (w - 1) * gap
		var x0 := rect.position.x + (rect.size.x - total) / 2.0
		for i in w:
			draw_rect(Rect2(x0 + i * (bar + gap), rect.get_center().y - 13.0, bar, 26.0), col)
	# Thin hazard stripe only on edges shared with a non-corridor neighbour, so a
	# contiguous corridor reads as one striped tunnel (docs/ui-pass calm band).
	var eb := 3.0
	var dark := Color(0.10, 0.10, 0.10, 0.85)
	var yellow := Color(0.90, 0.76, 0.28, 0.85)
	var e_top := Grid5.corridor_group_of(c + Vector2i(0, 1)) != gi
	var e_bot := Grid5.corridor_group_of(c + Vector2i(0, -1)) != gi
	var e_left := Grid5.corridor_group_of(c + Vector2i(-1, 0)) != gi
	var e_right := Grid5.corridor_group_of(c + Vector2i(1, 0)) != gi
	if e_top:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, eb)), dark)
	if e_bot:
		draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - eb), Vector2(rect.size.x, eb)), dark)
	if e_left:
		draw_rect(Rect2(rect.position, Vector2(eb, rect.size.y)), dark)
	if e_right:
		draw_rect(Rect2(Vector2(rect.end.x - eb, rect.position.y), Vector2(eb, rect.size.y)), dark)
	var step := 16.0
	var n := 0
	var t := 0.0
	while t < rect.size.x:
		if n % 2 == 0:
			var dw := minf(step * 0.6, rect.size.x - t)
			if e_top:
				draw_rect(Rect2(rect.position.x + t, rect.position.y, dw, eb), yellow)
			if e_bot:
				draw_rect(Rect2(rect.position.x + t, rect.end.y - eb, dw, eb), yellow)
		t += step
		n += 1
	n = 0
	t = 0.0
	while t < rect.size.y:
		if n % 2 == 0:
			var dh := minf(step * 0.6, rect.size.y - t)
			if e_left:
				draw_rect(Rect2(rect.position.x, rect.position.y + t, eb, dh), yellow)
			if e_right:
				draw_rect(Rect2(rect.end.x - eb, rect.position.y + t, eb, dh), yellow)
		t += step
		n += 1


func _draw_route(cells: Array, col: Color, index: int, selected: bool, warn: bool,
		closed := false) -> void:
	var off := Vector2((index - 1) * 8.0, (index - 1) * 8.0)
	var alpha := 0.92 if selected else 0.6
	if cells.size() >= 2:
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(cell_center(c) + off)
		if closed:
			pts.append(cell_center(cells[0]) + off)
		draw_polyline(pts, Color(col, alpha), 6.0)
	# Dock stops the route actually reaches (ring), squared ends on open routes.
	for c in cells:
		if Grid5.is_dock(c):
			draw_arc(cell_center(c) + off, 13.0, 0.0, TAU, 24, Color(col, alpha), 4.0)
	if not closed and cells.size() >= 1:
		for e in [cells[0], cells[cells.size() - 1]]:
			var p: Vector2 = cell_center(e) + off
			draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(col, alpha))
	if warn:
		var wp: Vector2 = cell_center(cells[0]) + off + Vector2(0, -26.0)
		draw_circle(wp, 12.0, Color(0.9, 0.3, 0.25, 0.9))
		draw_string(ThemeDB.fallback_font, wp + Vector2(-4.0, 7.0), "!",
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, 19, Color.WHITE)


func _draw_stroke_preview(cells: Array, col: Color, closed := false) -> void:
	var bright := col.lightened(0.35)
	if cells.size() >= 2:
		var pts := PackedVector2Array()
		for c in cells:
			pts.append(cell_center(c))
		if closed:
			pts.append(cell_center(cells[0]))
		draw_polyline(pts, Color(bright, 0.95), 10.0)
	for c in cells:
		draw_circle(cell_center(c), 6.0, Color(bright, 0.9))
	var head: Vector2 = cell_center(cells[0] if closed else cells[cells.size() - 1])
	var pulse := 10.0 + 4.0 * sin(Time.get_ticks_msec() / 90.0)
	draw_arc(head, pulse, 0.0, TAU, 24, Color.WHITE, 3.0)
