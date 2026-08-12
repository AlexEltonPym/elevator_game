class_name Pathfind3
extends RefCounted
## Time-based Dijkstra over the STOP graph for v3.
##
## Nodes = room cells. For each running route, there is an edge between every
## pair of its room-stops with cost
##   ride time (path distance / route speed)
## + intermediate stops x Car3.stop_penalty()   (v4 phase 2: acceleration)
## + a flat LEG_WAIT expected wait.
## Every leg carries its own LEG_WAIT, so each transfer adds 7 s — this is what
## makes "ride the local to the express stop and switch" emerge when the
## express is genuinely faster. (7 s, up from 5 s, keeps plans honest against
## the slower door-phase stops of the balance pass.)
##
## THE STOP TERM is the planner's half of acceleration. Distance alone says a
## milk run and an express leg over the same ground cost the same; they do not,
## because every intermediate stop costs the car a brake and a ramp back up.
## The penalty is the car's OWN momentum loss (speed / 2accel + speed / 2decel),
## so it is largest exactly where it should be - a fast or heavy car pays most
## for stopping - and it is a static per-route number, never a simulation.
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
## `width` (v4 phase 2) is the planner's half of the boarding rule: a party
## only ever plans onto cars it can actually fit through the doors of, so a
## width-3 delivery routes over the cargo car's network and nothing else, and
## shows the "?" bubble when that network cannot reach its destination.
static func find_path(start: Vector2i, dest: Vector2i, cars: Array,
		salt: float = -1.0, width: int = 1) -> Variant:
	if start == dest:
		return []
	# The stop-graph STRUCTURE (which cars, which stop pairs, in which order) and
	# every edge's geometry-derived base cost are CONSTANT for a whole run, so the
	# whole adjacency is built once per width and cached (_adj_for, invalidated
	# when any car's route identity changes). Per call only the per-passenger salt
	# jitter is applied: each edge's cost is rewritten to base + eps in place - no
	# per-edge allocation. base + eps preserves the exact float association of the
	# original expression, and the adjacency is populated in the identical order,
	# so edge costs and Dijkstra tie-breaking are bit-identical.
	var entry: Dictionary = _adj_for(cars, width)
	var edges: Dictionary = entry.adj
	for g in entry.groups:
		var eps := 0.0
		if salt >= 0.0:
			eps = TIE_EPS * _hash01(salt, g.ci)
		for e in g.edges:
			e.cost = e.base + eps
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


## Cached stop-graph adjacency, one entry per width. Rebuilt only when the set
## of car routes changes (route identities differ from the snapshot), which
## never happens during a run - so within a run this is built at most 3 times
## (widths 1/2/3, as parties of each width first ask for a path).
##   entry.adj    : Vector2i from-cell -> Array of edge dicts {to, car, base, cost}
##   entry.groups : Array of {ci, edges} so the per-car salt jitter can rewrite
##                  every edge's cost in place, in car-index order.
## The edge dicts are SHARED with entry.adj (same objects), so writing e.cost in
## the groups pass is what Dijkstra then reads. find_path is synchronous and the
## returned legs are fresh dicts, so nothing aliases the cached edges.
static var _adj_cache := {}
static var _adj_sig: Array = []


static func _adj_for(cars: Array, width: int) -> Dictionary:
	if _adj_dirty(cars):
		_adj_cache = {}
		_adj_sig = []
		for c in cars:
			_adj_sig.append(c.route if c != null else null)
	if _adj_cache.has(width):
		return _adj_cache[width]
	var adj := {}
	var groups: Array = []
	for ci in cars.size():
		var car = cars[ci]
		if car == null or not car.running() or not car.fits(width):
			continue
		var gedges: Array = []
		for be in _car_base(car):
			var e := {"to": be[1], "car": car, "base": be[2], "cost": 0.0}
			var from: Vector2i = be[0]
			if not adj.has(from):
				adj[from] = []
			adj[from].append(e)
			gedges.append(e)
		groups.append({"ci": ci, "edges": gedges})
	var entry := {"adj": adj, "groups": groups}
	_adj_cache[width] = entry
	return entry


## The cached adjacency is stale if the number of cars changed or ANY car's
## route object identity differs from the snapshot taken when it was built.
## Comparing stale refs from a freed previous run is safe: they only ever fail
## the equality test, never get dereferenced.
static func _adj_dirty(cars: Array) -> bool:
	if _adj_sig.size() != cars.size():
		return true
	for i in cars.size():
		var r = cars[i].route if cars[i] != null else null
		if _adj_sig[i] != r:
			return true
	return false


## The per-car stop-graph base edges (Array of [from, to, base_cost]), built
## lazily and cached on the car until its `route` object changes. base_cost is
## ride time + stop penalties + LEG_WAIT for the ordered stop pair - the whole
## edge cost bar the per-passenger salt jitter, all of it constant for a run.
## The nested loop order matches the original exactly, so the edges dict is
## populated in the identical order (Dijkstra tie-breaking is unchanged).
static func _car_base(car) -> Array:
	if car.pf_base != null and car.pf_base_route == car.route:
		return car.pf_base
	var out: Array = []
	var route = car.route
	var pen: float = car.stop_penalty()
	var stops: Array = route.stop_cells()
	for i in stops.size():
		for j in stops.size():
			if i == j:
				continue
			var base: float = route.ride_dist(stops[i], stops[j]) / car.speed \
					+ route.stops_between(stops[i], stops[j]) * pen + LEG_WAIT
			out.append([stops[i], stops[j], base])
	car.pf_base = out
	car.pf_base_route = route
	return out


## Cheap deterministic hash of (salt, index) into [0, 1).
static func _hash01(salt: float, i: int) -> float:
	var v := sin(salt * 12.9898 + float(i) * 78.233) * 43758.5453
	return absf(v - floorf(v))


## Total planned time of a legs array (test/debug helper).
static func path_time(legs: Array) -> float:
	var t := 0.0
	for leg in legs:
		t += leg.car.route.ride_dist(leg.board, leg.alight) / leg.car.speed \
				+ leg.car.route.stops_between(leg.board, leg.alight) \
						* leg.car.stop_penalty() \
				+ LEG_WAIT
	return t
