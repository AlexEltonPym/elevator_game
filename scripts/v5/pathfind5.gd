class_name Pathfind5
extends RefCounted
## Time-based Dijkstra over the ROOM graph for v5. Adapted from
## scripts/v3/pathfind3.gd, but nodes are ROOMS (room ids), not room cells.
##
## Nodes  = room ids.
## Edges  = for each running car E and each ordered pair of rooms (a, b) that E
##          serves, an edge a -> b with cost
##            ride time between their dock cells (dist / speed)
##          + intermediate dock stops x Car5.stop_penalty()   (acceleration)
##          + LEG_WAIT (expected wait for the car)
##          + WALK: real board+alight walk time, Grid5.WALK_PER_TILE per Manhattan
##            tile from room a's anchor to the boarding dock, plus from the
##            alighting dock back to room b's anchor. This is the SAME formula the
##            sim delays the passenger by, so the plan is priced against reality
##            (v5.1 replaced the old flat WALK constant).
## A room served by 2+ cars is where legs join — that is a TRANSFER room, and it
## emerges for free because both cars contribute edges through that node.
##
## A path is an ordered list of legs; each leg is a Dictionary
##   { "car": Car5, "from_room": int, "to_room": int,
##     "board_cell": Vector2i, "alight_cell": Vector2i }.

const LEG_WAIT := 6.0
const TIE_EPS := 0.5
const INF_T := 1.0e18


## Returns an Array of legs, or null if no path. `salt` (0..1) adds a
## deterministic sub-second per-car jitter so near-equal plans split load;
## negative salt = exact costs. `width` is the boarding rule (a party only ever
## plans onto cars it can fit through — so a width-3 delivery man never plans onto
## a width-2 lift). `walk_mult` scales the priced board+alight walk to MATCH the
## sim's per-passenger pace (a slow delivery man is priced slow in planning too).
static func find_path(start_room: int, dest_room: int, cars: Array,
		salt: float = -1.0, width: int = 1, walk_mult: float = 1.0) -> Variant:
	if start_room == dest_room:
		return []
	# Build the room adjacency fresh (tiny graphs; no caching needed here).
	var edges := {} # from_room -> Array of edge dicts
	for ci in cars.size():
		var car = cars[ci]
		if car == null or not car.running() or not car.fits(width):
			continue
		var route = car.route
		var served: Dictionary = route.served()
		var rooms: Array = served.keys()
		var pen: float = car.stop_penalty()
		var eps := 0.0
		if salt >= 0.0:
			eps = TIE_EPS * _hash01(salt, ci)
		for a in rooms:
			for b in rooms:
				if a == b:
					continue
				var ca: Vector2i = served[a]
				var cb: Vector2i = served[b]
				# Real walk: queue(a) -> board dock, then alight dock -> queue(b),
				# the SAME per-leg delay the sim imposes (the spawn dwell/mill is
				# route-independent, so it is NOT priced here).
				var walk: float = float(Grid5.manhattan(Grid5.room_queue(a), ca) \
						+ Grid5.manhattan(cb, Grid5.room_queue(b))) * Grid5.WALK_PER_TILE * walk_mult
				var cost: float = route.ride_dist(ca, cb) / car.speed \
						+ route.stops_between(ca, cb) * pen + LEG_WAIT + walk + eps
				if not edges.has(a):
					edges[a] = []
				edges[a].append({"to": b, "car": car, "board": ca, "alight": cb,
						"cost": cost})
	# Dijkstra (small graph; linear-scan extraction is fine).
	var best := {start_room: 0.0}
	var parent := {} # room -> {from, car, board, alight}
	var done := {}
	while true:
		var u = null
		var bu := INF_T
		for k in best:
			if not done.has(k) and best[k] < bu:
				bu = best[k]
				u = k
		if u == null:
			break
		done[u] = true
		if u == dest_room:
			break
		for e in edges.get(u, []):
			var nc: float = best[u] + e.cost
			if nc < best.get(e.to, INF_T):
				best[e.to] = nc
				parent[e.to] = {"from": u, "car": e.car, "board": e.board,
						"alight": e.alight}
	if not done.has(dest_room):
		return null
	var legs: Array = []
	var c := dest_room
	while c != start_room:
		var pr: Dictionary = parent[c]
		legs.push_front({"car": pr.car, "from_room": pr.from, "to_room": c,
				"board_cell": pr.board, "alight_cell": pr.alight})
		c = pr.from
	return legs


static func _hash01(salt: float, i: int) -> float:
	var v := sin(salt * 12.9898 + float(i) * 78.233) * 43758.5453
	return absf(v - floorf(v))
