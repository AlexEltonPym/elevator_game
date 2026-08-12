extends RefCounted
## Route GENES: representation, decoding, mutation, and hand-built primitives
## (docs/depth-tools-spec.md §3; docs/autodesign-research.md §5.1).
##
## We do NOT search raw cell polylines. A 7x10 grid has >10^20 self-avoiding
## walks and almost all of that variation is invisible to the simulation —
## what the sim consumes is which ROOMS are stops, in what order, how far
## apart they are, which gate groups the line crosses, and the `closed` bit.
## So (TRNDP framing) a route gene is
##
##     {"stops": [room cells, in visit order], "closed": bool}
##
## and DECODING lays cells down with BFS between consecutive stops over
## passable cells, never revisiting a cell already used by that route. A leg
## that cannot be laid down makes the gene INVALID — the caller scores it
## -INF, it never crashes the batch. A route-set genome is one gene per card;
## cards keep their level-defined type/capacity/speed, which is why gene i
## and card i are bound by position.
##
## Every decode ends at Route3.validate, the same check main3.commit_route
## and the balance harness use — the decoder cannot produce something the
## game would refuse.
##
## Grid3 must already hold this level's maze (SimApi.load_maze) before any
## call here: decoding reads Grid3.passable / is_room.

const NEIGHBORS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const MAX_STOPS := 10


# ---------------------------------------------------------------- decoding

## Shortest cell path from `a` to `b` inclusive, never entering a cell of
## `blocked` (the target is always allowed). [] when unreachable. Fixed
## neighbour order => deterministic, so the same gene always decodes to the
## same polyline.
static func _bfs(a: Vector2i, b: Vector2i, blocked: Dictionary) -> Array:
	if a == b:
		return [a]
	var prev := {a: a}
	var q: Array = [a]
	var head := 0
	while head < q.size():
		var u: Vector2i = q[head]
		head += 1
		for d in NEIGHBORS:
			var v: Vector2i = u + d
			if prev.has(v) or not Grid3.passable(v):
				continue
			if v != b and blocked.has(v):
				continue
			prev[v] = u
			if v == b:
				var path: Array = [b]
				var c := b
				while c != a:
					c = prev[c]
					path.push_front(c)
				return path
			q.append(v)
	return []


## gene -> {"cells", "closed", "err"}. err == "" means the cells are legal.
static func decode(gene: Dictionary) -> Dictionary:
	var stops: Array = gene.get("stops", [])
	var closed: bool = bool(gene.get("closed", false))
	var out := {"cells": [], "closed": closed, "err": ""}
	if stops.size() < 2:
		out.err = "fewer than 2 stops"
		return out
	var seen := {}
	for s in stops:
		if not (s is Vector2i) or not Grid3.is_room(s):
			out.err = "stop %s is not a room of this level" % str(s)
			return out
		if seen.has(s):
			out.err = "stop %s repeated" % str(s)
			return out
		seen[s] = true
	var cells: Array = [stops[0]]
	var used := {stops[0]: true}
	for k in range(1, stops.size()):
		var leg := _bfs(cells[cells.size() - 1], stops[k], used)
		if leg.is_empty():
			out.err = "leg %s -> %s cannot be decoded" % [
					str(cells[cells.size() - 1]), str(stops[k])]
			return out
		for i in range(1, leg.size()):
			cells.append(leg[i])
			used[leg[i]] = true
	if closed:
		var back := _bfs(cells[cells.size() - 1], stops[0], used)
		if back.is_empty():
			out.err = "closing leg %s -> %s cannot be decoded" % [
					str(cells[cells.size() - 1]), str(stops[0])]
			return out
		# The closing link is implied — do NOT repeat the head cell.
		for i in range(1, back.size() - 1):
			cells.append(back[i])
			used[back[i]] = true
	out.cells = cells
	out.err = Route3.validate(cells, closed)
	return out


## genome (Array of genes) -> Array of {"cells", "closed"} ready for
## SimApi.run, or {"err": ...} on the first undecodable gene.
static func decode_genome(genome: Array) -> Dictionary:
	var routes: Array = []
	for gi in genome.size():
		var d := decode(genome[gi])
		if d.err != "":
			return {"routes": [], "err": "card %d: %s" % [gi, d.err]}
		routes.append({"cells": d.cells, "closed": d.closed})
	return {"routes": routes, "err": ""}


## Room cells a polyline actually stops at (a leg can pass THROUGH a room the
## gene never asked for — that room is a real stop, and structural distance
## must see it).
static func stops_of_cells(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		if Grid3.is_room(c):
			out.append(c)
	return out


## Stable text key for caching / dedupe.
static func genome_key(genome: Array) -> String:
	var s := ""
	for g in genome:
		s += "|"
		for c in g.stops:
			s += "%d,%d;" % [c.x, c.y]
		s += "C" if g.closed else "O"
	return s


static func clone(genome: Array) -> Array:
	var out: Array = []
	for g in genome:
		out.append({"stops": (g.stops as Array).duplicate(), "closed": g.closed})
	return out


# ---------------------------------------------------------------- demand

## {from_cell: {to_cell: weight}} from the level's trip table + exec flows.
## Group-to-group weight is spread evenly over the room pairs it covers, which
## is exactly how main3._spawn_random picks (uniform room inside the group).
static func demand(level: Dictionary) -> Dictionary:
	var d := {}
	var mix: Dictionary = level.mix
	var mix_total := 0.0
	for t in mix:
		mix_total += mix[t]
	var exec_share: float = mix.get("exec", 0.0) / maxf(mix_total, 0.0001)
	if exec_share > 0.0 and not level.exec_origins.is_empty() \
			and not level.exec_dests.is_empty():
		_spread(d, level.exec_origins, level.exec_dests, exec_share)
	var rest := 1.0 - exec_share
	var trip_total := 0.0
	for row in level.trips:
		trip_total += row.w
	for row in level.trips:
		if row.w <= 0.0:
			continue
		_spread(d, level.groups[row.from], level.groups[row.to],
				rest * row.w / maxf(trip_total, 0.0001))
	return d


static func _spread(d: Dictionary, from_cells: Array, to_cells: Array, w: float) -> void:
	var pairs: Array = []
	for a in from_cells:
		for b in to_cells:
			if a != b:
				pairs.append([a, b])
	if pairs.is_empty():
		return
	var each := w / pairs.size()
	for p in pairs:
		if not d.has(p[0]):
			d[p[0]] = {}
		d[p[0]][p[1]] = d[p[0]].get(p[1], 0.0) + each


## Demand pairs sorted heaviest first: [{"from", "to", "w"}, ...].
static func demand_pairs(level: Dictionary) -> Array:
	var d := demand(level)
	var out: Array = []
	for a in d:
		for b in d[a]:
			out.append({"from": a, "to": b, "w": d[a][b]})
	out.sort_custom(func(x, y):
		if is_equal_approx(x.w, y.w):
			return _cell_before(x.from, y.from)
		return x.w > y.w)
	return out


## Total demand touching each room, heaviest first.
static func room_weight(level: Dictionary) -> Dictionary:
	var d := demand(level)
	var w := {}
	for r in Grid3.rooms():
		w[r] = 0.0
	for a in d:
		for b in d[a]:
			w[a] = w.get(a, 0.0) + d[a][b]
			w[b] = w.get(b, 0.0) + d[a][b]
	return w


static func _cell_before(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


# ---------------------------------------------------------------- primitives

## The route-generation phase of the TRNDP two-phase architecture: a pool of
## hand-built lines that a metaheuristic recombines, rather than starting from
## noise (docs/autodesign-research.md §0.2). All are derived from the LEVEL
## DATA (geometry + demand), never from our thesis answers — otherwise
## "did the optimizer beat the thesis" would be begging the question.
static func primitive_genes(level: Dictionary) -> Array:
	var rooms: Array = Grid3.rooms()
	var out: Array = []
	if rooms.size() < 2:
		return out
	var lowest: Vector2i = rooms[0]
	var highest: Vector2i = rooms[0]
	for r in rooms:
		if r.y < lowest.y:
			lowest = r
		if r.y > highest.y:
			highest = r
	# 1. Express spine: the two extreme floors, nothing between.
	out.append({"stops": [lowest, highest], "closed": false})
	# 2. Stop-everywhere line (the naive shape; a useful baseline gene).
	out.append({"stops": rooms.duplicate(), "closed": false})
	# 3/4. Ring over all rooms, ordered by angle around their centroid —
	#      open and closed. The closed one is the only way to express
	#      "ride the one-way tide".
	var ring := _angular_order(rooms)
	out.append({"stops": ring.duplicate(), "closed": true})
	out.append({"stops": ring.duplicate(), "closed": false})
	# 5. Per-group shuttles (a cluster's own rooms, plus its heaviest partner).
	var d := demand(level)
	for gname in level.groups:
		var g: Array = level.groups[gname]
		var stops: Array = []
		for c in g:
			if Grid3.is_room(c) and not stops.has(c):
				stops.append(c)
		if stops.size() >= 2:
			out.append({"stops": stops.duplicate(), "closed": false})
		# ...and the same cluster wired to its top demand partner.
		var best_to = null
		var best_w := -1.0
		for c in g:
			for b in d.get(c, {}):
				if not g.has(b) and d[c][b] > best_w:
					best_w = d[c][b]
					best_to = b
		if best_to != null and not stops.has(best_to):
			var s2 := stops.duplicate()
			s2.append(best_to)
			if s2.size() >= 2:
				out.append({"stops": s2, "closed": false})
	# 6. Hub feeders: the busiest room wired to every other room, one line each.
	var w := room_weight(level)
	var hub: Vector2i = rooms[0]
	for r in rooms:
		if w.get(r, 0.0) > w.get(hub, 0.0):
			hub = r
	for r in rooms:
		if r != hub:
			out.append({"stops": [hub, r], "closed": false})
	# 7. Direct lines over the heaviest demand pairs, and the same with the
	#    most central room spliced in (the cheapest "k-shortest-paths" stand-in).
	var pairs := demand_pairs(level)
	for i in mini(6, pairs.size()):
		var a: Vector2i = pairs[i].from
		var b: Vector2i = pairs[i].to
		out.append({"stops": [a, b], "closed": false})
		var mid = _nearest_room_to(rooms, Vector2((a.x + b.x) / 2.0, (a.y + b.y) / 2.0),
				[a, b])
		if mid != null:
			out.append({"stops": [a, mid, b], "closed": false})
	# Drop anything that does not decode on this maze.
	var keep: Array = []
	var seen := {}
	for g in out:
		var k := genome_key([g])
		if seen.has(k):
			continue
		seen[k] = true
		if decode(g).err == "":
			keep.append(g)
	return keep


static func _angular_order(rooms: Array) -> Array:
	var cx := 0.0
	var cy := 0.0
	for r in rooms:
		cx += r.x
		cy += r.y
	cx /= rooms.size()
	cy /= rooms.size()
	var out := rooms.duplicate()
	out.sort_custom(func(a, b):
		var aa := atan2(a.y - cy, a.x - cx)
		var bb := atan2(b.y - cy, b.x - cx)
		if is_equal_approx(aa, bb):
			return _cell_before(a, b)
		return aa < bb)
	return out


static func _nearest_room_to(rooms: Array, p: Vector2, exclude: Array):
	var best = null
	var bd := 1.0e18
	for r in rooms:
		if exclude.has(r):
			continue
		var dd := Vector2(r.x, r.y).distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = r
	return best


## Seed population: themed genomes assembled from the primitive pool, then
## random draws from the pool, all deduped and decode-checked.
static func primitive_genomes(level: Dictionary, n_cards: int, rng: RandomNumberGenerator,
		count: int) -> Array:
	var pool := primitive_genes(level)
	var out: Array = []
	var seen := {}
	if pool.is_empty():
		return out
	var add := func(genome: Array) -> void:
		if genome.size() != n_cards:
			return
		var k: String = genome_key(genome)
		if seen.has(k):
			return
		if decode_genome(genome).err != "":
			return
		seen[k] = true
		out.append(clone(genome))
	# Themed sets first: every card the same primitive (spine / cover / ring),
	# then a mixed spine+feeders set, then the top demand pairs one per card.
	for i in mini(4, pool.size()):
		var same: Array = []
		for _c in n_cards:
			same.append(pool[i])
		add.call(same)
	var idx := 0
	while out.size() < count and idx < pool.size() * 4:
		var genome: Array = []
		for _c in n_cards:
			genome.append(pool[rng.randi_range(0, pool.size() - 1)])
		add.call(genome)
		idx += 1
	return out


# ---------------------------------------------------------------- variation

static func random_gene(rng: RandomNumberGenerator, rooms: Array) -> Dictionary:
	var n := rng.randi_range(2, mini(MAX_STOPS, rooms.size()))
	var pool := rooms.duplicate()
	var stops: Array = []
	for _i in n:
		stops.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return {"stops": stops, "closed": rng.randf() < 0.25}


## A uniformly sampled DECODABLE route-set (the weak ladder rung). Returns []
## if it could not find one within `tries`.
static func random_genome(rng: RandomNumberGenerator, rooms: Array, n_cards: int,
		tries := 60) -> Array:
	for _t in tries:
		var genome: Array = []
		for _c in n_cards:
			genome.append(random_gene(rng, rooms))
		if decode_genome(genome).err == "":
			return genome
	return []


## One mutation from the transit-network-design operator set, RETRIED until it
## actually changes the genome (up to `tries`).
##
## Several operators are legitimately no-ops on some genomes — "delete a stop"
## on a 2-stop route, "add a stop" on a full one, "swap" picking i == j — and a
## child identical to its parent is pure waste: it is a guaranteed cache hit,
## so it costs no budget but also carries no information, and it lets a
## converged population spin generations without moving. Measured before this
## retry loop: only 27 % of mutations changed the score at all, with 72 % of
## all EA proposals served from cache (docs/depth-report.md, EA instrumentation).
static func mutate(rng: RandomNumberGenerator, genome: Array, rooms: Array,
		tries := 8) -> Array:
	var before := genome_key(genome)
	var out := _mutate_once(rng, genome, rooms)
	var n := 1
	while n < tries and genome_key(out) == before:
		out = _mutate_once(rng, genome, rooms)
		n += 1
	return out


static func _mutate_once(rng: RandomNumberGenerator, genome: Array, rooms: Array) -> Array:
	var g := clone(genome)
	var c := rng.randi_range(0, g.size() - 1)
	var stops: Array = g[c].stops
	match rng.randi_range(0, 6):
		0: # add a stop at a random position
			var free := _not_in(rooms, stops)
			if not free.is_empty() and stops.size() < MAX_STOPS:
				stops.insert(rng.randi_range(0, stops.size()),
						free[rng.randi_range(0, free.size() - 1)])
		1: # delete a stop
			if stops.size() > 2:
				stops.remove_at(rng.randi_range(0, stops.size() - 1))
		2: # swap two stops inside one route
			if stops.size() >= 2:
				var i := rng.randi_range(0, stops.size() - 1)
				var j := rng.randi_range(0, stops.size() - 1)
				var tmp = stops[i]
				stops[i] = stops[j]
				stops[j] = tmp
		3: # move a stop to another route
			var c2 := rng.randi_range(0, g.size() - 1)
			if c2 != c and stops.size() > 2:
				var s = stops.pop_at(rng.randi_range(0, stops.size() - 1))
				if not (g[c2].stops as Array).has(s):
					(g[c2].stops as Array).insert(
							rng.randi_range(0, (g[c2].stops as Array).size()), s)
		4: # replace a stop with a room the route does not have
			var free2 := _not_in(rooms, stops)
			if not free2.is_empty():
				stops[rng.randi_range(0, stops.size() - 1)] = \
						free2[rng.randi_range(0, free2.size() - 1)]
		5: # toggle the loop bit
			g[c].closed = not g[c].closed
		6: # reverse a segment (TRNDP's segment-reversal operator)
			if stops.size() >= 3:
				var i2 := rng.randi_range(0, stops.size() - 2)
				var j2 := rng.randi_range(i2 + 1, stops.size() - 1)
				var seg: Array = stops.slice(i2, j2 + 1)
				seg.reverse()
				for k in seg.size():
					stops[i2 + k] = seg[k]
	return g


## Route-level crossover: the child is `a` with ONE card's whole route taken
## from `b`. Route-level (not stop-level) crossover is the standard TRNDP
## choice because a route is the unit that carries meaning.
static func crossover(rng: RandomNumberGenerator, a: Array, b: Array) -> Array:
	var child := clone(a)
	var c := rng.randi_range(0, child.size() - 1)
	child[c] = {"stops": (b[c].stops as Array).duplicate(), "closed": b[c].closed}
	return child


static func _not_in(rooms: Array, stops: Array) -> Array:
	var out: Array = []
	for r in rooms:
		if not stops.has(r):
			out.append(r)
	return out


# ---------------------------------------------------------------- structure

## Jaccard distance between two route-sets, averaged per card, over the stop
## sets the polylines ACTUALLY visit. 0 = the same lines, 1 = nothing shared.
static func structural_distance(routes_a: Array, routes_b: Array) -> float:
	var n := mini(routes_a.size(), routes_b.size())
	if n == 0:
		return 1.0
	var total := 0.0
	for i in n:
		var sa := {}
		var sb := {}
		for c in stops_of_cells(routes_a[i].cells):
			sa[c] = true
		for c in stops_of_cells(routes_b[i].cells):
			sb[c] = true
		var inter := 0
		for k in sa:
			if sb.has(k):
				inter += 1
		var uni := sa.size() + sb.size() - inter
		total += 1.0 if uni == 0 else 1.0 - float(inter) / float(uni)
	return total / n


## Cheap structural summary of a route-set for the report's "used differently?"
## note: loops, stop counts, cells, gate groups crossed.
static func describe(routes: Array) -> Dictionary:
	var loops := 0
	var cells := 0
	var stops := 0
	var gates := {}
	for r in routes:
		if r == null:
			continue
		if r.get("closed", false):
			loops += 1
		cells += r.cells.size()
		stops += stops_of_cells(r.cells).size()
		for c in r.cells:
			var gi := Grid3.gate_group_of(c)
			if gi != -1:
				gates[gi] = true
	return {"loops": loops, "cells": cells, "stops": stops,
			"gate_groups": gates.size()}
