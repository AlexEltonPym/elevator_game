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

## TRANSFER RULE (user): a rider may only get off to CHANGE LIFTS at a HUB — a lobby, cafe,
## storage (delivery) or atrium. Transferring through an office/penthouse is nonsensical, so
## those are never used as intermediate transfer points (you can still ride straight to one as
## your destination; you just can't hop lifts there).
const HUB_TYPES := {"lobby": true, "cafe": true, "delivery": true, "atrium": true}

static func _is_hub(room_id: int) -> bool:
	return HUB_TYPES.has(Grid5.room_type(room_id))


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
	var d := _dijkstra(start_room, dest_room, cars, salt, width, walk_mult)
	var done: Dictionary = d.done
	if not done.has(dest_room):
		return null
	var parent: Dictionary = d.parent
	var legs: Array = []
	var c := dest_room
	while c != start_room:
		var pr: Dictionary = parent[c]
		legs.push_front({"car": pr.car, "from_room": pr.from, "to_room": c,
				"board_cell": pr.board, "alight_cell": pr.alight})
		c = pr.from
	return legs


## Time-based Dijkstra from `start_room`, returning {best, parent, done}. The edge
## model is the SAME as before (this is the extracted core of find_path); find_path,
## best_time and board_now all read it, so their costs stay mutually consistent.
static func _dijkstra(start_room: int, dest_room: int, cars: Array,
		salt: float, width: int, walk_mult: float) -> Dictionary:
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
		# TRANSFER RULE: you may only change lifts at a HUB. The start room is the origin
		# (boarding, not a transfer); any OTHER room reached mid-path is a transfer point, so a
		# non-hub intermediate is a dead end here — you can arrive (and if it's the destination
		# that was handled above), but you can't hop to another lift.
		if u != start_room and not _is_hub(u):
			continue
		for e in edges.get(u, []):
			var nc: float = best[u] + e.cost
			if nc < best.get(e.to, INF_T):
				best[e.to] = nc
				parent[e.to] = {"from": u, "car": e.car, "board": e.board,
						"alight": e.alight}
	return {"best": best, "parent": parent, "done": done}


## Best total travel time start_room -> dest_room on the committed network, or INF_T
## if unreachable. Same cost model as find_path (each first/transfer leg pays LEG_WAIT).
static func best_time(start_room: int, dest_room: int, cars: Array,
		salt: float = -1.0, width: int = 1, walk_mult: float = 1.0) -> float:
	if start_room == dest_room:
		return 0.0
	var d := _dijkstra(start_room, dest_room, cars, salt, width, walk_mult)
	if not d.done.has(dest_room):
		return INF_T
	return d.best[dest_room]


## OPPORTUNISTIC BOARDING. Should a (cur_room -> dest) passenger board `car`, which is
## stopped at dock `cell` RIGHT NOW, instead of waiting for its planned lift? Yes iff
## riding this car now — first leg priced with NO wait (it's here) — reaches dest by a
## total time no worse (within TIE_EPS) than the passenger's best plan (which prices a
## LEG_WAIT for its first leg). So: it grabs a here-now lift that's on a shortest-enough
## path, but a normal still refuses a slow lift whose ride costs more than the wait it
## would save, and a wide party only ever considers lifts it fits (width feeds best_time
## and the caller gates fits()). Returns {to_room, board_cell, alight_cell} or null.
static func board_now(car, cell: Vector2i, cur_room: int, dest_room: int, cars: Array,
		salt: float = -1.0, width: int = 1, walk_mult: float = 1.0) -> Variant:
	if cur_room == dest_room or car.route == null:
		return null
	var route = car.route
	var served: Dictionary = route.served()
	var pen: float = car.stop_penalty()
	var eps := 0.0
	if salt >= 0.0:
		eps = TIE_EPS * _hash01(salt, car.card_index)
	var plan := best_time(cur_room, dest_room, cars, salt, width, walk_mult)
	var best_total := INF_T
	var best_b := -1
	var best_alight := Vector2i.ZERO
	for b in served.keys():
		if b == cur_room:
			continue
		var cb: Vector2i = served[b]
		# Board at `cell` NOW (no LEG_WAIT); walk queue(cur)->cell and cb->queue(b).
		var walk: float = float(Grid5.manhattan(Grid5.room_queue(cur_room), cell) \
				+ Grid5.manhattan(cb, Grid5.room_queue(b))) * Grid5.WALK_PER_TILE * walk_mult
		var leg: float = route.ride_dist(cell, cb) / car.speed \
				+ route.stops_between(cell, cb) * pen + walk + eps
		var rest := best_time(b, dest_room, cars, salt, width, walk_mult)
		if rest >= INF_T:
			continue
		var total := leg + rest
		if total < best_total:
			best_total = total
			best_b = b
			best_alight = cb
	if best_b < 0 or best_total > plan + TIE_EPS:
		return null
	return {"to_room": best_b, "board_cell": cell, "alight_cell": best_alight}


static func _hash01(salt: float, i: int) -> float:
	var v := sin(salt * 12.9898 + float(i) * 78.233) * 43758.5453
	return absf(v - floorf(v))
