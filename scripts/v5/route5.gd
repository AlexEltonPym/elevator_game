class_name Route5
extends RefCounted
## One elevator's drawn route for v5: an ordered polyline of open grid cells
## (Vector2i), every consecutive pair orthogonally adjacent, no cell twice.
## `closed` marks a loop (cells[n-1] adjacent to cells[0]; car travels forward
## around the cycle). Adapted from scripts/v3/route.gd.
##
## SERVICE (v5). A route SERVES a room iff it passes through one of that room's
## authored DOCK cells (Grid5.dock_rooms). The dock cells the route hits are its
## STOPS. served() maps each served room to the FIRST dock cell (in draw order)
## that reaches it, so ride distances are deterministic.

var cells: Array = [] : set = _set_cells
var closed := false
# The tile the car spawns/parks at (the ORIGINAL start, preserved across grab-edits
# from either end). Vector2i(-1,-1) = unset -> treat cells[0] as the spawn.
var spawn_cell := Vector2i(-1, -1)

var _served := {} # room_id -> dock cell (first in draw order)
var _dock_rooms := {} # dock cell on the route -> Array[room_id]
var _stop_indices: Array = [] # indices into cells that are dock cells
var _index_of := {}
var _drop_prefix: Array = [] # _drop_prefix[i] = dock cells in cells[0 .. i-1]
var _dirty := true


func _set_cells(v: Array) -> void:
	cells = v
	_dirty = true


func _ensure() -> void:
	if not _dirty:
		return
	_dirty = false
	_served = {}
	_dock_rooms = {}
	_stop_indices = []
	_index_of = {}
	_drop_prefix = [0]
	for i in cells.size():
		var c: Vector2i = cells[i]
		if not _index_of.has(c):
			_index_of[c] = i
		var rooms: Array = Grid5.dock_rooms(c)
		if not rooms.is_empty():
			_stop_indices.append(i)
			_dock_rooms[c] = rooms
			for rid in rooms:
				if not _served.has(rid):
					_served[rid] = c
		_drop_prefix.append(_stop_indices.size())


## room_id -> the dock cell this route uses to serve it.
func served() -> Dictionary:
	_ensure()
	return _served


## The room ids this route serves (nodes it contributes to the room graph).
func served_rooms() -> Array:
	_ensure()
	return _served.keys()


## Room ids served from a given (dock) cell of this route.
func rooms_of_cell(cell: Vector2i) -> Array:
	_ensure()
	return _dock_rooms.get(cell, [])


func is_dropoff(cell: Vector2i) -> bool:
	_ensure()
	return _dock_rooms.has(cell)


func index_of(cell: Vector2i) -> int:
	_ensure()
	return _index_of.get(cell, -1)


## Index into cells of the car's spawn/park tile. 0 when unset or the spawn tile is
## no longer on the route (e.g. a tail edit trimmed it away), so the car falls back
## to the current start end. For every scripted route (spawn = cells[0]) this is 0,
## keeping the sim — and the fingerprint — unchanged.
func spawn_index() -> int:
	if spawn_cell.x < 0:
		return 0
	var i: int = cells.find(spawn_cell)
	return i if i >= 0 else 0


## Ride distance in px between two cells of this route (path distance along the
## polyline). Direction-aware on closed routes (forward-only), symmetric open.
func ride_dist(a: Vector2i, b: Vector2i) -> float:
	var ia := index_of(a)
	var ib := index_of(b)
	if closed:
		return float(posmod(ib - ia, cells.size())) * Grid5.CELL
	return absf(ia - ib) * Grid5.CELL


## Dock cells strictly between a and b in travel direction (each is a door stop
## the car brakes for — Pathfind5 prices them via the car's stop penalty).
func stops_between(a: Vector2i, b: Vector2i) -> int:
	_ensure()
	var ia := index_of(a)
	var ib := index_of(b)
	if ia < 0 or ib < 0 or ia == ib:
		return 0
	var n := cells.size()
	if closed:
		if ib > ia:
			return _drops_in(ia + 1, ib)
		return _drops_in(ia + 1, n) + _drops_in(0, ib)
	if ib > ia:
		return _drops_in(ia + 1, ib)
	return _drops_in(ib + 1, ia)


func _drops_in(lo: int, hi: int) -> int:
	if hi <= lo:
		return 0
	return _drop_prefix[hi] - _drop_prefix[lo]


# ---------------------------------------------------------------- validation

## "" when `cells` (+ `closed`) is a legal open-cell polyline on the loaded
## level, else a human-readable reason. Geometry only; the "serves >= 2 rooms"
## rule is the RUN gate in main5, not here.
static func validate(cells_in: Array, closed_in: bool) -> String:
	if cells_in.size() < 2:
		return "fewer than 2 cells"
	if closed_in and cells_in.size() < 4:
		return "closed loop with fewer than 4 cells"
	var seen := {}
	for k in cells_in.size():
		if not (cells_in[k] is Vector2i):
			return "cell %d is not a Vector2i" % k
		var c: Vector2i = cells_in[k]
		if not Grid5.passable(c):
			return "cell %s not passable" % str(c)
		if seen.has(c):
			return "cell %s visited twice" % str(c)
		seen[c] = true
		if k > 0:
			var d: Vector2i = c - cells_in[k - 1]
			if absi(d.x) + absi(d.y) != 1:
				return "cells %s -> %s not adjacent" % [str(cells_in[k - 1]), str(c)]
	if closed_in:
		var dc: Vector2i = cells_in[0] - cells_in[cells_in.size() - 1]
		if absi(dc.x) + absi(dc.y) != 1:
			return "closing link not adjacent"
	return ""
