class_name Pathfind3
extends RefCounted
## Time-based Dijkstra over the STOP graph for v3.
##
## Nodes = room cells. For each running route, there is an edge between every
## pair of its room-stops with cost = ride time along the route between them
## (path distance / route speed) + a flat LEG_WAIT expected wait. Every leg
## carries its own LEG_WAIT, so each transfer adds 7 s — this is what makes
## "ride the local to the express stop and switch" emerge when the express is
## genuinely faster. (7 s, up from 5 s, keeps plans honest against the slower
## door-phase stops of the balance pass.)
##
## A path is an ordered list of legs; each leg is a Dictionary
## { "car": Car3, "board": Vector2i, "alight": Vector2i }.

const LEG_WAIT := 7.0
const TIE_EPS := 0.5 # max per-passenger jitter (s) - breaks exact-cost ties only
const INF_T := 1.0e18


## Returns an Array of legs, or null if no path exists.
##
## `salt` (0..1, from the passenger, drawn from the game RNG at spawn) adds a
## deterministic sub-second per-car jitter to leg costs. Identical or
## near-identical routes then split the load across their cars instead of
## every passenger deterministically picking the first card; genuinely
## different plans (> TIE_EPS apart) are unaffected. Pass a negative salt for
## exact costs (debug/tests).
static func find_path(start: Vector2i, dest: Vector2i, cars: Array,
		salt: float = -1.0) -> Variant:
	if start == dest:
		return []
	# Build the stop-graph edges from every running car.
	var edges := {} # Vector2i -> Array of {"to", "cost", "car"}
	for ci in cars.size():
		var car = cars[ci]
		if car == null or not car.running():
			continue
		var eps := 0.0
		if salt >= 0.0:
			eps = TIE_EPS * _hash01(salt, ci)
		var route = car.route
		var stops: Array = route.stop_cells()
		for i in stops.size():
			for j in stops.size():
				if i == j:
					continue
				var cost: float = route.ride_dist(stops[i], stops[j]) / car.speed \
						+ LEG_WAIT + eps
				if not edges.has(stops[i]):
					edges[stops[i]] = []
				edges[stops[i]].append({"to": stops[j], "cost": cost, "car": car})
	# Dijkstra (tiny graph; linear-scan extraction is fine).
	var best := {start: 0.0}
	var parent := {} # cell -> {"from": cell, "car": Car3}
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
		if u == dest:
			break
		for e in edges.get(u, []):
			var nc: float = best[u] + e.cost
			if nc < best.get(e.to, INF_T):
				best[e.to] = nc
				parent[e.to] = {"from": u, "car": e.car}
	if not done.has(dest):
		return null
	var legs: Array = []
	var c := dest
	while c != start:
		var pr: Dictionary = parent[c]
		legs.push_front({"car": pr.car, "board": pr.from, "alight": c})
		c = pr.from
	return legs


## Cheap deterministic hash of (salt, index) into [0, 1).
static func _hash01(salt: float, i: int) -> float:
	var v := sin(salt * 12.9898 + float(i) * 78.233) * 43758.5453
	return absf(v - floorf(v))


## Total planned time of a legs array (test/debug helper).
static func path_time(legs: Array) -> float:
	var t := 0.0
	for leg in legs:
		t += leg.car.route.ride_dist(leg.board, leg.alight) / leg.car.speed + LEG_WAIT
	return t
