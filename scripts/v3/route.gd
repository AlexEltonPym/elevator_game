class_name Route3
extends RefCounted
## One elevator's drawn route: an ordered polyline of grid cells (Vector2i),
## every consecutive pair orthogonally adjacent, no cell visited twice.
## Room cells along the polyline are the route's STOPS.

var cells: Array = [] # Vector2i, in draw order


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
## along the polyline; cells are unit steps of Grid3.CELL).
func ride_dist(a: Vector2i, b: Vector2i) -> float:
	return absf(index_of(a) - index_of(b)) * Grid3.CELL
