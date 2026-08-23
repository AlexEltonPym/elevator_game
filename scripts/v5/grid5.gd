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

# Realism-pass framing: the building is fit into a REDUCED box that reserves a border on
# every side plus a permanent underground band, so it never touches a screen edge and there
# is always visible dirt below (room for a basement). The ground line is a FIXED screen y —
# every level shares one horizon (sky above, grass + dirt below).
const SIDE_MARGIN := 24.0        # min gap left & right of the building
const TOP_MARGIN := 30.0         # min sky above the building (under the top HUD)
const PLAY_TOP := 98.0           # bottom edge of the top HUD bar
const PLAY_BOTTOM := 1010.0      # top edge of the bottom card panel
const UNDERGROUND := 64.0        # thin dirt lip below the ground line (basement retired)
const DIRT_LIP := 18.0           # min dirt kept below a basement's lowest row
const GROUND_LINE := PLAY_BOTTOM - UNDERGROUND  # fixed street line (screen y)

## Seconds of walk per tile of Manhattan distance. Board = queue tile -> boarding
## dock; alight = alighting dock -> queue tile. Priced identically in Pathfind5 so
## planning stays honest against the sim. Slowed to read calm/deliberate (v5.1h).
const WALK_PER_TILE := 0.9

const DEFAULT_CORRIDOR_WIDTH := 2 # a plain corridor cell = one normal lift

const ROOM_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

static var COLS := 5
static var ROWS := 7
static var ORIGIN := Vector2(45.0, 100.0)
static var view_scale := 1.0
static var view_offset := Vector2.ZERO
# WORLD GROUND (realism pass): the building sits ON a ground line near the bottom of the
# play area instead of floating centred. GROUND_ROW is the grid row whose BOTTOM edge is
# street level (default 0 = the lowest row is the ground floor); rows below it are the
# BASEMENT (underground). GROUND_Y is that line in screen space, published so Background5
# can paint sky above / grass + dirt below and line the building up on it.
static var GROUND_ROW := 0
static var GROUND_Y := 1000.0

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

# Route-OVERLAP width cap (v5.1j, transition phase 1). A capped tile carries an
# `overlap_max` in {1,2,3}: the SUM of the car-widths of all committed routes drawn
# through it must be <= the cap. This is a STATIC, planning-time drawing limit
# (enforced at commit + felt while drawing) — SEPARATE from the runtime corridor
# mutex above (which caps car-widths physically PRESENT in a group each sim step).
# The two compose: a tile may be both an overlap-capped tile and a corridor cell.
# Default (un-annotated) tiles are uncapped, so all existing levels stay legal.
const OVERLAP_UNCAPPED := 99
static var _overlap_cap := {} # Vector2i -> overlap width cap (int)

var game = null # main5.gd

# PixelSpaces furniture textures per room type, loaded lazily & GRACEFULLY (null when the
# gitignored art packs aren't present → _draw_room falls back to the flat-tint look, so a
# clean clone still runs). texture_filter is forced NEAREST on this node in _ready.
var _furn_tex := {}
var _door_shut: Texture2D = null   # PixelSpaces landing door (dock), closed / open
var _door_open: Texture2D = null
var _tex_ready := false

## THE VISUAL LANGUAGE (docs: art-direction). Each room TYPE has a unique background
## COLOUR (the identity — once you learn it you know the room's behaviour), a matching
## outline, and a representative PixelSpaces furniture sprite. Colour is authoritative;
## shape is characteristic but may vary; furniture reinforces.
const ROOM_STYLE := {
	"lobby":     {"bg": Color(0.83, 0.75, 0.56), "line": Color(0.60, 0.48, 0.26), "furn": "Furniture/Door_opened.png"},
	"office":    {"bg": Color(0.56, 0.67, 0.81), "line": Color(0.30, 0.42, 0.60), "furn": "Furniture/Living Room/Bookshelf_1.png"},
	"apartment": {"bg": Color(0.60, 0.77, 0.57), "line": Color(0.32, 0.52, 0.32), "furn": "Furniture/Bedroom/Bed_red.png"},
	"cafe":      {"bg": Color(0.86, 0.63, 0.46), "line": Color(0.64, 0.38, 0.22), "furn": "Furniture/Kitchen/Refrigerator_large_white.png"},
	"store":     {"bg": Color(0.75, 0.61, 0.42), "line": Color(0.50, 0.36, 0.20), "furn": "Furniture/Living Room/Bookshelf_1.png"},
	"delivery":  {"bg": Color(0.61, 0.63, 0.67), "line": Color(0.38, 0.40, 0.46), "furn": "Objects/Bedroom/Box_blue_large.png"},
	"atrium":    {"bg": Color(0.73, 0.61, 0.83), "line": Color(0.48, 0.34, 0.60), "furn": "Objects/Living Room/Flora_daisy_4.png"},
	"penthouse": {"bg": Color(0.89, 0.79, 0.43), "line": Color(0.66, 0.52, 0.20), "furn": "Furniture/Living Room/Couch_large_red.png"},
}
## The building cross-section fill (concrete). The solid/shaft tiles are read relative to it.
const BUILDING_FILL := Color(0.22, 0.21, 0.25)
const _PS := "res://assets/pixel/pixelspaces/"
# Uniform art scale: 1 PixelSpaces pixel -> ART_K logical px, for EVERY sprite (furniture,
# people, doors, cart) so native art RATIOS are preserved (a 23px fridge stays taller than a
# 13px couch instead of both being forced to one cell fraction). ~2.2 keeps a 16px person at
# ~35px (the size the car-slot packing expects). passenger5 reads Grid5.ART_K too.
const ART_K := 2.2

# Legacy flat tint (fallback when a type has no ROOM_STYLE entry).
const ROOM_TINT := {
	"lobby": Color(0.28, 0.33, 0.40),
	"office": Color(0.24, 0.30, 0.36),
	"atrium": Color(0.34, 0.30, 0.42),
	"store": Color(0.36, 0.31, 0.26),
	"cafe": Color(0.34, 0.28, 0.30),
}

## Flow-Free pairing palette (draw-only). A store and the cafe it supplies share a
## `pair` id in the level data; both rooms get this colour + the pair number so the
## matching endpoints read at a glance ("connect the 1s, connect the 2s"). Indexed
## by pair id; id 1 -> PAIR_COLS[0]. Distinct, high-chroma, readable on the tints.
const PAIR_COLS := [
	Color(0.96, 0.42, 0.42), # 1 red
	Color(0.45, 0.82, 0.96), # 2 cyan
	Color(0.98, 0.78, 0.30), # 3 amber
	Color(0.62, 0.85, 0.45), # 4 green
	Color(0.82, 0.58, 0.96), # 5 violet
	Color(0.96, 0.60, 0.32), # 6 orange (spare)
	Color(0.55, 0.72, 0.98), # 7 blue (spare)
	Color(0.94, 0.52, 0.78), # 8 pink (spare)
]


## Install a level (Levels5 entry). Builds bounds, the room / dock maps and the
## display fit transform. Cells stay CELL px in LOGICAL space; a grid larger
## than the grid area is scaled DOWN to fit (identity when it already fits).
static func load_level(level: Dictionary) -> void:
	COLS = int(level.cols)
	ROWS = int(level.rows)
	GROUND_ROW = int(level.get("ground_row", 0))
	ORIGIN = Vector2((GRID_X - COLS * CELL) / 2.0,
			GRID_Y_TOP + (GRID_Y_H - ROWS * CELL) / 2.0)
	var bbox_w := COLS * CELL
	var bbox_h := ROWS * CELL
	# Fit into the reduced framing box: a border on every side + the underground band are
	# reserved, so a wide/tall level SHRINKS to fit rather than bleeding to the edges.
	var above_h := float(ROWS - GROUND_ROW) * CELL   # rows at/above the ground floor
	var below_h := float(GROUND_ROW) * CELL          # basement rows (below the ground line)
	var w_avail := GRID_X - 2.0 * SIDE_MARGIN
	var above_avail := GROUND_LINE - (PLAY_TOP + TOP_MARGIN)
	var below_avail := PLAY_BOTTOM - GROUND_LINE - DIRT_LIP
	view_scale = minf(1.0, w_avail / bbox_w)
	view_scale = minf(view_scale, above_avail / maxf(1.0, above_h))
	if below_h > 0.0:
		view_scale = minf(view_scale, below_avail / below_h)
	# Horizontal: centre across the full width (the width cap above guarantees the side border).
	view_offset.x = GRID_X / 2.0 - view_scale * (ORIGIN.x + bbox_w / 2.0)
	# Vertical: pin the BOTTOM edge of GROUND_ROW to the fixed street line — one shared horizon.
	view_offset.y = GROUND_LINE - view_scale * (ORIGIN.y + float(ROWS - GROUND_ROW) * CELL)
	GROUND_Y = GROUND_LINE
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
	# Overlap caps: each entry is {cells:Array[Vector2i], max:int} (default 2).
	_overlap_cap = {}
	for ov in level.get("overlaps", []):
		var om := int(ov.get("max", 2))
		for c in ov.cells:
			_overlap_cap[c] = om
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
			# Optional draw-only display label (background text); defaults to the type.
			"label": str(rm.get("label", rm.type)),
			"drops": drops, "center": ctr, "rect": _cells_rect(cells),
			"anchor": _closest_cell(cells, ctr),
			"queue": qcell,
			"queue_dir": door_cells.get(qcell, Vector2i(1, 0)),
			# Optional draw-only Flow-Free pairing tag (see _draw_room). 0 = no pair.
			"pair": int(rm.get("pair", 0))})


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


## The room's identity COLOUR (its ROOM_STYLE background) — used by the destination
## blob above a queued figure so "where are they headed" reads off the room palette.
## Falls back to the legacy tint, then a neutral grey.
static func room_color(id: int) -> Color:
	var t := room_type(id)
	if ROOM_STYLE.has(t):
		return ROOM_STYLE[t].bg
	return ROOM_TINT.get(t, Color(0.62, 0.64, 0.70))


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


# ------------------------------------------------------------ overlap caps

## The overlap width cap of a tile: the max SUM of car-widths of routes that may
## be drawn through it. OVERLAP_UNCAPPED (a large number) for un-annotated tiles.
static func overlap_cap(c: Vector2i) -> int:
	return int(_overlap_cap.get(c, OVERLAP_UNCAPPED))


static func is_overlap_capped(c: Vector2i) -> bool:
	return _overlap_cap.has(c)


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

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_tex()


## Load the per-type furniture textures once, tolerating a missing art pack (null entries).
func _ensure_tex() -> void:
	if _tex_ready:
		return
	_tex_ready = true
	for t in ROOM_STYLE:
		var p: String = _PS + ROOM_STYLE[t].furn
		if ResourceLoader.exists(p):
			_furn_tex[t] = load(p)
	if ResourceLoader.exists(_PS + "Furniture/Elevator_closed.png"):
		_door_shut = load(_PS + "Furniture/Elevator_closed.png")
		_door_open = load(_PS + "Furniture/Elevator_opened.png")


## SOLID (un-routable) tile — the "wall" half of the tile standard. A raised concrete
## block: light top bevel + dark base so it reads as a solid, impassable mass. ~10% of
## walls (deterministic by cell) carry a lit window so the facade isn't a dead slab; the
## rest get one mortar course so they read as masonry rather than a flat swatch.
func _draw_solid(rect: Rect2, c: Vector2i) -> void:
	draw_rect(rect, Color(0.33, 0.32, 0.36))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4.0)), Color(0.41, 0.40, 0.45))
	draw_rect(Rect2(rect.position.x, rect.end.y - 4.0, rect.size.x, 4.0), Color(0.20, 0.19, 0.23))
	if posmod(c.x * 73 + c.y * 131, 10) < 6:
		_draw_window(rect)
	else:
		draw_rect(Rect2(rect.position.x, rect.get_center().y - 1.0, rect.size.x, 2.0),
				Color(0, 0, 0, 0.18))
	draw_rect(rect, Color(0, 0, 0, 0.30), false, 1.5)


## A lit glass window set into a wall tile (glass + frame + mullions). Used on ~10% of walls.
func _draw_window(rect: Rect2) -> void:
	var g := rect.grow(-11.0)
	draw_rect(g.grow(2.0), Color(0.16, 0.15, 0.18))            # frame
	draw_rect(g, Color(0.62, 0.78, 0.86))                       # lit glass
	draw_rect(g, Color(1.0, 0.96, 0.80, 0.18))                  # warm interior glow
	draw_rect(Rect2(g.get_center().x - 1.0, g.position.y, 2.0, g.size.y), Color(0.28, 0.30, 0.34))
	draw_rect(Rect2(g.position.x, g.get_center().y - 1.0, g.size.x, 2.0), Color(0.28, 0.30, 0.34))


## OPEN (routable) tile — the "you may draw here" half of the standard. A recessed shaft
## channel: distinctly darker and sunk-in vs a solid block, with a soft inner shadow.
func _draw_shaft(rect: Rect2) -> void:
	draw_rect(rect, Color(0.15, 0.16, 0.21))
	draw_rect(rect.grow(-5.0), Color(0.10, 0.11, 0.15))
	draw_rect(rect, Color(0, 0, 0, 0.22), false, 1.0)


## Draw a sprite centred in `rect` at the uniform ART_K scale (native ratios), nearest.
func _draw_centered(tex: Texture2D, rect: Rect2) -> void:
	if tex == null:
		return
	var sz := Vector2(tex.get_width(), tex.get_height()) * ART_K
	draw_texture_rect(tex, Rect2(rect.get_center() - sz * 0.5, sz), false)


## Place the room's theme furniture: uniform ART_K scale (native ratios), bottom-aligned to
## the room's floor, INSET from the walls, and pushed to the side OPPOSITE the dropoff (so it
## doesn't block the door — "furniture opposite the door"). May span more than one tile.
func _place_furniture(rm: Dictionary, _id: int, _bg: Color) -> void:
	var tex: Texture2D = _furn_tex.get(rm.type)
	if tex == null:
		return
	var fw := tex.get_width() * ART_K
	var fh := tex.get_height() * ART_K
	# The floor is the room's lowest ROW; place furniture WITHIN that row's actual cells
	# (never the whole bounding box) so it can't spill into the walls of a T/L shape.
	var min_cy: int = rm.cells[0].y
	for c in rm.cells:
		min_cy = mini(min_cy, c.y)
	var fx_min := INF
	var fx_max := -INF
	var floor_y := 0.0
	for c in rm.cells:
		if c.y == min_cy:
			var cr := cell_rect(c)
			fx_min = minf(fx_min, cr.position.x)
			fx_max = maxf(fx_max, cr.end.x)
			floor_y = cr.end.y - 1.0
	var avail := fx_max - fx_min
	var ddir: Vector2i = rm.drops[0].dir if not rm.drops.is_empty() else Vector2i(1, 0)
	var inset := 6.0
	var fx: float
	if fw >= avail - inset:
		fx = fx_min + (avail - fw) * 0.5                 # wider than the floor row: centre
	elif ddir.x > 0:
		fx = fx_min + inset                              # dropoff right -> furniture left
	elif ddir.x < 0:
		fx = fx_max - inset - fw                          # dropoff left -> furniture right
	else:
		fx = fx_min + (avail - fw) * 0.5
	draw_texture_rect(tex, Rect2(Vector2(fx, floor_y - 6.0 - fh), Vector2(fw, fh)), false)


## A ladder up an interior-vertical stretch of a tall room (traversal read). A solid bar
## against the room's right wall with rung lines, so it clearly reads as a ladder.
func _draw_ladder(rect: Rect2, _bg: Color) -> void:
	var w := 16.0
	var x0 := rect.end.x - 4.0 - w
	draw_rect(Rect2(x0, rect.position.y, w, rect.size.y), Color(0.62, 0.48, 0.32))
	for k in 5:
		draw_rect(Rect2(x0, rect.position.y + (k + 0.5) * rect.size.y / 5.0, w, 3.0),
				Color(0.40, 0.30, 0.20))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# THE BUILDING is one solid cross-section sitting ON the world ground line (Background5
	# paints the sky above and the grass/dirt below and lines up on Grid5.GROUND_Y). A single
	# concrete mass with a roofline catching the light — never a floating facade.
	var bpanel := Rect2(ORIGIN - Vector2(8, 8),
			Vector2(COLS * CELL + 16, ROWS * CELL + 16))
	draw_rect(bpanel, BUILDING_FILL)
	draw_rect(Rect2(bpanel.position, Vector2(bpanel.size.x, 6.0)), BUILDING_FILL.lightened(0.14))
	draw_rect(bpanel, Color(0, 0, 0, 0.30), false, 2.0)
	# TILE STANDARD: every non-room, non-corridor cell is EXACTLY one of two things and reads
	# as one look each so the two never blur — a SOLID wall (raised concrete, can't route) or
	# an OPEN shaft (recessed dark channel, the space a lift snakes through).
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if Grid5.is_room_cell(c):
				continue
			var rect := cell_rect(c).grow(-1.0)
			if Grid5.is_corridor(c):
				_draw_corridor(rect, c)
			elif not Grid5.passable(c):
				_draw_solid(rect, c)
			else:
				_draw_shaft(rect)
			# Disjoint tiles are the DEFAULT and render blank; only SHAREABLE tiles (cap
			# lets >= 2 width-2 lifts overlap) get a subtle "you may double up here" tint.
			if Grid5.overlap_cap(c) >= 4:
				draw_rect(rect.grow(-3.0), Color(0.55, 0.78, 0.95, 0.14))
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
	# Dock cells where a car is currently stopped with its doors open — the landing door
	# opens IN SYNC with the car (IRL). game.cars are Car5 nodes.
	var open_docks := {}
	for car in game.cars:
		if car.on_grid() and car.door_frac() > 0.2:
			open_docks[car.current_cell()] = true
	for mark in Grid5._dock_marks:
		_draw_dock(mark, covered.get(mark.dock, []), open_docks.has(mark.dock))
	# Committed routes (nudged so overlaps stay readable). A FAST (express) lift draws
	# its line AS the acceleration heatmap — amber where it's ramping/braking, green
	# where it's up to speed — so the speed profile IS the line you laid down.
	for i in game.routes.size():
		var route = game.routes[i]
		if route == null:
			continue
		if i < game.cars.size() and game.cars[i].speed > Car5.STANDARD_SPEED:
			_draw_heatmap_line(route.cells, game.cars[i], route.closed,
					game.selected_card == i, false)
		else:
			_draw_route(route.cells, game.CARDS[i].color, i,
					game.selected_card == i, route.served_rooms().size() < 2, route.closed)
	# (dropoff capacity pips removed — they read as clutter on the docks; the shareable-tile
	# tint alone signals where routes may double up.)
	# Live drag preview on top — the express stroke previews as the heatmap line too.
	if game.drawing and game.stroke.size() > 0 and game.selected_card >= 0:
		if game.cars[game.selected_card].speed > Car5.STANDARD_SPEED:
			_draw_heatmap_line(game.stroke, game.cars[game.selected_card],
					game.stroke_closed, true, true)
		else:
			_draw_stroke_preview(game.stroke, game.CARDS[game.selected_card].color,
					game.stroke_closed)
	_draw_momentum_hints()


## Per-cell speed fraction along a lift's route: v = min(accel-from-the-last-stop,
## brake-to-the-next-stop, top speed), normalised to top speed. Stops are the route's
## dock cells; an open route's two ends are turnarounds (also stops).
func _speed_fracs(cells: Array, car, closed: bool) -> PackedFloat32Array:
	var n := cells.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var stops: Array = []
	for j in n:
		if Grid5.is_dock(cells[j]):
			stops.append(j)
	if not closed:
		if stops.is_empty() or stops[0] != 0:
			stops.push_front(0)
		if stops.back() != n - 1:
			stops.append(n - 1)
	if stops.size() < 2 or car.speed <= 0.0:
		for j in n:
			out[j] = 1.0
		return out
	for j in n:
		var dprev := 1 << 20
		var dnext := 1 << 20
		for s in stops:
			var db: int = posmod(j - s, n) if closed else j - s
			var df: int = posmod(s - j, n) if closed else s - j
			if db >= 0 and db < dprev:
				dprev = db
			if df >= 0 and df < dnext:
				dnext = df
		var v_acc := sqrt(2.0 * car.accel * float(dprev) * CELL)
		var v_brk := sqrt(2.0 * car.decel * float(dnext) * CELL)
		out[j] = clampf(minf(minf(v_acc, v_brk), car.speed) / car.speed, 0.0, 1.0)
	return out


## Draw a fast lift's route AS its acceleration heatmap: a thick polyline whose colour
## runs amber (ramping / braking) to green (up to speed) per segment. The amber length
## leaving a stop reads as "blocks until up to speed"; a segment that never greens is
## too tight to be worth skipping into. `head_pulse` marks the drawing end of a stroke.
func _draw_heatmap_line(cells: Array, car, closed: bool, selected: bool, head_pulse: bool) -> void:
	if cells.size() < 2:
		return
	var fr := _speed_fracs(cells, car, closed)
	var amber := Color(0.96, 0.53, 0.18)
	var green := Color(0.36, 0.96, 0.46)
	var pts: Array = []
	for c in cells:
		pts.append(cell_center(c))
	if selected:
		# Soft selection halo under the line.
		for j in pts.size() - 1:
			draw_line(pts[j], pts[j + 1], Color(1, 1, 1, 0.18), 13.0)
	var last := pts.size() - 1
	for j in last:
		var col := amber.lerp(green, (fr[j] + fr[j + 1]) * 0.5)
		draw_line(pts[j], pts[j + 1], Color(col, 0.96), 9.0)
	if closed:
		var col := amber.lerp(green, (fr[last] + fr[0]) * 0.5)
		draw_line(pts[last], pts[0], Color(col, 0.96), 9.0)
	for j in pts.size():
		draw_circle(pts[j], 3.5, Color(amber.lerp(green, fr[j]), 0.95))
	if head_pulse:
		var head: Vector2 = pts[0] if closed else pts[last]
		var pulse := 10.0 + 4.0 * sin(Time.get_ticks_msec() / 90.0)
		draw_arc(head, pulse, 0.0, TAU, 24, Color.WHITE, 3.0)


## MOMENTUM feedback: for a card that carries `min_hop`, ring in warning-red any stop
## that sits too close to the previous one — live on the stroke being drawn (so the
## constraint is felt as you draw), plus a lingering ring on the stop that just got a
## commit rejected. Pure rendering; cards without `min_hop` draw nothing.
func _draw_momentum_hints() -> void:
	if game.drawing and game.selected_card >= 0:
		var mh := int(game.CARDS[game.selected_card].get("min_hop", 0))
		if mh > 0:
			var prev_y := 0
			var have_prev := false
			for c in game.stroke:
				if not Grid5.is_dock(c):
					continue
				if have_prev and c.y != prev_y and absi(c.y - prev_y) < mh:
					_ring_warn(cell_center(c))
				prev_y = c.y
				have_prev = true
	if game.reject_stop.x >= 0 and Time.get_ticks_msec() < game.reject_until_ms:
		_ring_warn(cell_center(game.reject_stop))


func _ring_warn(at: Vector2) -> void:
	var col := Color(0.98, 0.35, 0.35)
	var pulse := 18.0 + 4.0 * sin(Time.get_ticks_msec() / 110.0)
	draw_arc(at, pulse, 0.0, TAU, 28, col, 4.0)
	draw_arc(at, pulse - 6.0, 0.0, TAU, 28, Color(col, 0.4), 2.0)


func _draw_room(id: int) -> void:
	var rm: Dictionary = Grid5._rooms[id]
	# THE VISUAL LANGUAGE: per-type background colour + outline + theme furniture. Falls
	# back to the legacy flat tint if the type has no style (or the art pack is absent).
	var style: Dictionary = ROOM_STYLE.get(rm.type, {})
	var bg: Color = style.get("bg", ROOM_TINT.get(rm.type, Color(0.26, 0.30, 0.36)))
	var line: Color = style.get("line", Color(0.6, 0.72, 0.9, 0.5))
	# FLOW-FREE PAIRING (draw-only): a room with a `pair` id shares a vivid colour +
	# number with the ONE other room it pairs with, so "connect the matching pairs" reads.
	var pair: int = int(rm.get("pair", 0))
	var has_pair: bool = pair > 0 and pair <= PAIR_COLS.size()
	var pair_col: Color = PAIR_COLS[pair - 1] if has_pair else line
	# Room body. A multi-cell room is ONE space: the floor slab is drawn only on the room's
	# BOTTOM edge (not between stacked cells), so a tall room reads as an extra-tall room with
	# a skylight at the top — never split into "floors". A ladder marks interior vertical
	# stretches (so a genuinely tall room reads as traversable, not just a high ceiling).
	for c in rm.cells:
		var rect := cell_rect(c).grow(-1.0)
		draw_rect(rect, bg)
		if Grid5.room_id_at(c + Vector2i(0, -1)) != id:  # bottom edge of the room
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 6.0),
					Vector2(rect.size.x, 6.0)), bg.darkened(0.35))
		if Grid5.room_id_at(c + Vector2i(0, 1)) != id:   # top edge -> roof / skylight
			draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.28, 3.0),
					Vector2(rect.size.x * 0.44, 5.0)), bg.lightened(0.30))
		if has_pair:
			draw_rect(rect, Color(pair_col, 0.12))
	for c in rm.cells:  # ladder on interior-vertical cells (same room above AND below)
		if Grid5.room_id_at(c + Vector2i(0, 1)) == id and Grid5.room_id_at(c + Vector2i(0, -1)) == id:
			_draw_ladder(cell_rect(c), bg)
	_place_furniture(rm, id, bg)
	# One outline around the whole room footprint (type colour; pair colour if paired).
	var ow := 4.0 if has_pair else 3.0
	var ocol: Color = Color(pair_col, 0.95) if has_pair else Color(line, 0.9)
	for c in rm.cells:
		var rect := cell_rect(c)
		for e in [[Vector2i(0, 1), Rect2(rect.position, Vector2(rect.size.x, ow))],
				[Vector2i(0, -1), Rect2(Vector2(rect.position.x, rect.end.y - ow),
						Vector2(rect.size.x, ow))],
				[Vector2i(-1, 0), Rect2(rect.position, Vector2(ow, rect.size.y))],
				[Vector2i(1, 0), Rect2(Vector2(rect.end.x - ow, rect.position.y),
						Vector2(ow, rect.size.y))]]:
			if Grid5.room_id_at(c + e[0]) != id:
				draw_rect(e[1], ocol)
	# Background TYPE LABEL (temporary readability aid — later the furniture + shape carry
	# the identity). Faint, centred across the room's footprint.
	var lrect: Rect2 = rm.rect
	draw_string(ThemeDB.fallback_font, lrect.position + Vector2(0.0, lrect.size.y * 0.5 + 8.0),
			str(rm.get("label", rm.type)).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, lrect.size.x, 22,
			Color(0.12, 0.12, 0.14, 0.55))
	# Pair badge: a filled disc in the pair colour with the pair NUMBER, in the room's
	# top-left corner (away from the door mark) — the "endpoint marker" both rooms share.
	if has_pair:
		var rrect: Rect2 = rm.rect
		var bc := rrect.position + Vector2(20.0, 20.0)
		draw_circle(bc, 15.0, Color(0.08, 0.08, 0.10, 0.9))
		draw_circle(bc, 13.0, pair_col)
		var num := str(pair)
		draw_string(ThemeDB.fallback_font, bc + Vector2(-6.0, 7.0), num,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.10, 0.10, 0.12))


## A dropoff: a door notch on the room cell's facing edge + a chevron pointing
## into its dock cell. The dock cell gets a dashed outline so the player can see
## where a lift must reach; when a route covers it, the outline fills in the
## covering car's colour(s).
func _draw_dock(mark: Dictionary, cover: Array, is_open := false) -> void:
	var rc := cell_rect(mark.cell)
	var dir: Vector2i = mark.dir
	var door_col := Color(0.95, 0.85, 0.45, 0.9)
	# A thin exit notch on the ROOM's drop edge (so you see where the room connects out).
	var t := 6.0
	var strip: Rect2
	if dir == Vector2i(1, 0):
		strip = Rect2(rc.end.x - t, rc.position.y + 16.0, t, rc.size.y - 32.0)
	elif dir == Vector2i(-1, 0):
		strip = Rect2(rc.position.x, rc.position.y + 16.0, t, rc.size.y - 32.0)
	elif dir == Vector2i(0, 1):
		strip = Rect2(rc.position.x + 16.0, rc.position.y, rc.size.x - 32.0, t)
	else:
		strip = Rect2(rc.position.x + 16.0, rc.end.y - t, rc.size.x - 32.0, t)
	draw_rect(strip, Color(door_col, 0.5))
	# LANDING DOOR: a PixelSpaces elevator door in the DOCK cell (the open cell the car
	# reaches), opening IN SYNC with a parked car. It never covers the room; the car (a
	# Node2D child) draws over it when present. Falls back to just the notch without art.
	var door_tex: Texture2D = _door_open if is_open else _door_shut
	if door_tex != null:
		_draw_centered(door_tex, cell_rect(mark.dock))
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





func _draw_route(cells: Array, col: Color, index: int, selected: bool, _warn: bool,
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
	# Grabbable-end affordance (v5 UX): a faint, gentle pulse ON the route's grabbable
	# END CELLS, in the card's colour, so the player sees where to drag to extend/trim.
	# The rings must sit EXACTLY on the endpoints (same points as the polyline ends,
	# nudged by `off`): an OPEN route pulses its head cell (cells.back()) and tail cell
	# (cells[0]); a LOOP has a single grabbable loop point (cells[0], where it closes),
	# so it pulses there once — not two rings floating along the ring. Draw-only.
	if cells.size() >= 2:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
		var ends: Array = [cells[0]] if closed else [cells[0], cells[cells.size() - 1]]
		for e in ends:
			var gp: Vector2 = cell_center(e) + off
			draw_arc(gp, 15.0 + 3.0 * pulse, 0.0, TAU, 24,
					Color(col, 0.10 + 0.16 * pulse), 3.0)
	# An incomplete route (serves <2 rooms) SILENTLY fails: no exclaim, no scold. The
	# greyed-out RUN button is the only quiet signal; the neutral hint line guides.


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
