class_name Pathfind
extends RefCounted
## Path search over the elevator network.
##
## A path is an ordered list of legs; each leg is a Dictionary
## { "elev": Elevator, "board": int, "alight": int }.
## Elevator E connects any two floors where its doors are ON. A passenger may
## only alight mid-journey on a TRANSFER floor (final destination is always a
## legal alight). Boarding mid-journey is likewise only possible on a transfer
## floor (the origin is always a legal board).
##
## Minimizes leg count first, then rough travel distance (floors moved).

const LEG_COST := 100000
const INF_COST := 1 << 60


## Returns an Array of legs, or null if no path exists.
static func find_path(start: int, dest: int, elevators: Array, transfers: Array) -> Variant:
	if start == dest:
		return []
	var cost := {}
	var parent := {} # floor -> [prev_floor, elevator]
	var visited := {}
	for f in Building.FLOORS:
		cost[f] = INF_COST
	cost[start] = 0
	while true:
		# Pick unvisited floor with the lowest cost (tiny graph; linear scan is fine).
		var u := -1
		var best: int = INF_COST
		for f in Building.FLOORS:
			if not visited.has(f) and cost[f] < best:
				best = cost[f]
				u = f
		if u == -1:
			break
		visited[u] = true
		if u == dest:
			break
		# Departing from u is only legal at the origin or on a transfer floor.
		if u != start and not transfers.has(u):
			continue
		for e in elevators:
			if e == null or not e.doors[u]:
				continue
			for v in Building.FLOORS:
				if v == u or not e.doors[v]:
					continue
				# Alighting at v is only legal at the destination or a transfer floor.
				if v != dest and not transfers.has(v):
					continue
				var c: int = cost[u] + LEG_COST + absi(v - u)
				if c < cost[v]:
					cost[v] = c
					parent[v] = [u, e]
	if cost[dest] >= INF_COST:
		return null
	var legs: Array = []
	var f := dest
	while f != start:
		var pr: Array = parent[f]
		legs.push_front({"elev": pr[1], "board": pr[0], "alight": f})
		f = pr[0]
	return legs
