class_name Route3
extends RefCounted
## One elevator's drawn route: an ordered polyline of grid cells (Vector2i),
## every consecutive pair orthogonally adjacent, no cell visited twice.
## Room cells along the polyline are the route's STOPS.
##
## `closed` (v3.4 loops): the stroke closed back onto its head, so cells[n-1]
## is also adjacent to cells[0] and the car travels FORWARD around the cycle
## forever (no ping-pong). Loops are one-way: a->b is quick in the travel
## direction and almost-a-full-lap the other way (see ride_dist).
##
## PERF (v3.5): stop_cells / stop_indices / index_of are memoized per route and
## invalidated whenever `cells` is assigned. Car3.running() calls stop_cells()
## once per car per game tick (measured: 63.5 of the 84 us/tick fixed
## overhead), and Pathfind3 calls index_of twice per stop pair per replan.
## The caches are pure derived data - identical results, just not recomputed.
## Cells must never be mutated in place (only whole-array assignment).

var cells: Array = []: set = _set_cells # Vector2i, in draw order
var closed := false # loop: cells[n-1] -> cells[0] is a real travel segment

var _stop_cells: Array = []
var _stop_indices: Array = []
var _index_of := {}
var _room_prefix: Array = [] # _room_prefix[i] = room cells in cells[0 .. i-1]
var _dirty := true


func _set_cells(v: Array) -> void:
	cells = v
	_dirty = true


## Rebuild the derived caches (room stops + cell -> first index).
func _ensure() -> void:
	if not _dirty:
		return
	_dirty = false
	_stop_cells = []
	_stop_indices = []
	_index_of = {}
	_room_prefix = [0]
	for i in cells.size():
		var c: Vector2i = cells[i]
		if not _index_of.has(c):
			_index_of[c] = i
		if Grid3.is_room(c):
			_stop_cells.append(c)
			_stop_indices.append(i)
		_room_prefix.append(_stop_cells.size())


func stop_cells() -> Array:
	_ensure()
	return _stop_cells


func stop_indices() -> Array:
	_ensure()
	return _stop_indices


func index_of(cell: Vector2i) -> int:
	_ensure()
	return _index_of.get(cell, -1)


## Ride distance in pixels between two cells of this route (path distance
## along the polyline; cells are unit steps of Grid3.CELL). DIRECTION-AWARE
## on closed routes: a -> b is measured forward-only, ((ib - ia) mod n)
## cells, so a "backward" trip prices as almost a full lap. Open routes are
## symmetric |ia - ib|.
func ride_dist(a: Vector2i, b: Vector2i) -> float:
	var ia := index_of(a)
	var ib := index_of(b)
	if closed:
		return float(posmod(ib - ia, cells.size())) * Grid3.CELL
	return absf(ia - ib) * Grid3.CELL


## How many of this route's OWN room stops lie strictly between a and b, in
## the direction the car would travel (forward-only on a closed route). Each
## one costs a door cycle and, since v4 phase 2, a whole braking-and-ramping-
## up-again - which is why Pathfind3 prices them (Car3.stop_penalty).
##
## Answered from the memoized room-count prefix, because Pathfind3 asks it for
## every ordered stop PAIR of every running route on every replan.
func stops_between(a: Vector2i, b: Vector2i) -> int:
	_ensure()
	var ia := index_of(a)
	var ib := index_of(b)
	if ia < 0 or ib < 0 or ia == ib:
		return 0
	var n := cells.size()
	if closed:
		if ib > ia:
			return _rooms_in(ia + 1, ib)
		return _rooms_in(ia + 1, n) + _rooms_in(0, ib)
	if ib > ia:
		return _rooms_in(ia + 1, ib)
	return _rooms_in(ib + 1, ia)


## Room cells in the half-open index range [lo, hi).
func _rooms_in(lo: int, hi: int) -> int:
	if hi <= lo:
		return 0
	return _room_prefix[hi] - _room_prefix[lo]


# ---------------------------------------------------------------- validation

## "" when `cells` (+ the `closed` flag) is a legal route on the CURRENTLY
## LOADED maze, else a human-readable reason. THE one route legality check:
## the UI's drag code enforces the same invariants constructively, the balance
## harness calls this on its scripted routes, main3.commit_route rejects
## anything that fails it, and the search tools validate every decoded gene.
##
## `car_width` (v4 phase 2) additionally rejects a route that runs a car down
## a corridor narrower than it is - the one route-legality rule that depends
## on WHICH card is being drawn. 0 (the default) skips the check, which is
## what a caller that has no card in hand wants (geometry-only validation).
##
## Requires Grid3.load_level() to have run for the level in question - i.e.
## call it AFTER the game scene is in the tree, never before.
static func validate(cells_in: Array, closed_in: bool, car_width: int = 0) -> String:
	if cells_in.size() < 2:
		return "fewer than 2 cells"
	if closed_in and cells_in.size() < 4:
		return "closed loop with fewer than 4 cells"
	var seen := {}
	for k in cells_in.size():
		if not (cells_in[k] is Vector2i):
			return "cell %d is not a Vector2i" % k
		var c: Vector2i = cells_in[k]
		if not Grid3.passable(c):
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
			return "closing link %s -> %s not adjacent" % [
					str(cells_in[cells_in.size() - 1]), str(cells_in[0])]
	if car_width > 0:
		var w := Grid3.route_min_gate_width(cells_in)
		if w < car_width:
			return "car is %d wide; the route's narrowest corridor is %d" % [
					car_width, w]
	return ""
