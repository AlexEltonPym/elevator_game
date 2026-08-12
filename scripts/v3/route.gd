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

var cells: Array = [] # Vector2i, in draw order
var closed := false # loop: cells[n-1] -> cells[0] is a real travel segment


func stop_cells() -> Array:
	var out: Array = []
	for c in cells:
		if Grid3.is_room(c):
			out.append(c)
	return out


func stop_indices() -> Array:
	var out: Array = []
	for i in cells.size():
		if Grid3.is_room(cells[i]):
			out.append(i)
	return out


func index_of(cell: Vector2i) -> int:
	return cells.find(cell)


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
