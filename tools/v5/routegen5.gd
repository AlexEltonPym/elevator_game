extends RefCounted
## Route GENES for v5 (docs/v5-transition-spec.md §5.1 "route-genes rebuilt").
##
## v4 searched room-CELL stop sequences; v5's service atom is the DOCK CELL — a
## route serves a room iff its polyline passes one of that room's dock cells
## (Route5.served). So a v5 route gene is
##
##     {"stops": [dock cells, in visit order], "closed": bool}
##
## and DECODING lays cells down with BFS between consecutive docks over passable
## OPEN cells, never revisiting a cell already used by that route. The gene is
## INVALID (caller scores -INF, never crashes) when a leg cannot be laid, when
## the polyline fails Route5.validate, when it enters a corridor narrower than
## the car, or when it serves fewer than 2 rooms (the RUN gate).
##
## THE OVERLAP CAP (docs/v5-transition-spec.md §3.4). decode_genome threads a
## shared `cap_left: {cell -> remaining width}` across the cards in order: each
## card's BFS treats a capped cell whose remaining capacity is below THIS car's
## width as blocked (same code path as the self-revisit `used` set), so the
## decoder routes around exhausted tiles (the capacity-repair behaviour is
## inherent) and a leg that can only pass an exhausted tile makes the gene
## invalid. Because card 0 claims scarce capacity first, legality is
## order-dependent — so a reorder-cards mutation lets the search rearrange who
## gets it. Determinism is preserved (fixed neighbour + card order).
##
## Grid5 must already hold this level's maze (SimApi5.load_maze) before any call
## here: decoding reads Grid5.passable / dock_rooms / overlap_cap / corridors.

const NEIGHBORS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const MAX_STOPS := 8
const CAR_TYPES := {
	"pod": {"width": 1}, "standard": {"width": 2},
	"express": {"width": 2}, "cargo": {"width": 3},
}


# ---------------------------------------------------------------- level facts

## Widths of a level's cards (the boarding/overlap unit each route costs).
static func card_widths(level: Dictionary) -> Array:
	var out: Array = []
	for card in level.cards:
		var t: Dictionary = CAR_TYPES.get(str(card.get("type", "standard")), CAR_TYPES.standard)
		out.append(int(card.get("width", t.width)))
	return out


## Every dock cell on the loaded grid (an open cell an elevator can serve a room
## from), scanned deterministically in (y, x) order.
static func docks() -> Array:
	var out: Array = []
	for y in Grid5.ROWS:
		for x in Grid5.COLS:
			var c := Vector2i(x, y)
			if Grid5.is_dock(c):
				out.append(c)
	return out


## room_id -> Array of its dock cells (deterministic order).
static func room_docks() -> Dictionary:
	var out := {}
	for d in docks():
		for rid in Grid5.dock_rooms(d):
			if not out.has(rid):
				out[rid] = []
			out[rid].append(d)
	return out


## A fresh {capped cell -> remaining width} map for the loaded level.
static func _cap_map() -> Dictionary:
	var out := {}
	for y in Grid5.ROWS:
		for x in Grid5.COLS:
			var c := Vector2i(x, y)
			if Grid5.is_overlap_capped(c):
				out[c] = Grid5.overlap_cap(c)
	return out


## Rooms a polyline actually serves (distinct room ids reached via dock cells).
static func served_rooms_of_cells(cells: Array) -> Array:
	var seen := {}
	var out: Array = []
	for c in cells:
		for rid in Grid5.dock_rooms(c):
			if not seen.has(rid):
				seen[rid] = true
				out.append(rid)
	return out


# ---------------------------------------------------------------- decoding

## Shortest cell path from `a` to `b` inclusive over passable cells, never
## entering a `used` cell (except the target) nor a cell blocked for a car of
## `width`: a capped cell without `width` capacity left, or a corridor narrower
## than the car. Fixed neighbour order => deterministic. [] when unreachable.
static func _bfs(a: Vector2i, b: Vector2i, used: Dictionary, cap_left: Dictionary,
		width: int) -> Array:
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
			if prev.has(v) or not Grid5.passable(v):
				continue
			if v != b and used.has(v):
				continue
			if not _cell_open_for(v, cap_left, width):
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


## Can a car of `width` legally thread `v` given the remaining overlap capacity?
## (The target of a leg is subject to this too — a full dock genuinely cannot be
## threaded.) Also rejects corridors narrower than the car.
static func _cell_open_for(v: Vector2i, cap_left: Dictionary, width: int) -> bool:
	if cap_left.has(v) and int(cap_left[v]) < width:
		return false
	var gi := Grid5.corridor_group_of(v)
	if gi != -1 and Grid5.corridor_group_width(gi) < width:
		return false
	return true


## One gene -> {"cells", "closed", "err"} against a live `cap_left` (NOT consumed
## here; decode_genome consumes after a successful decode). err == "" means legal.
static func decode_gene(gene: Dictionary, width: int, cap_left: Dictionary) -> Dictionary:
	var stops: Array = gene.get("stops", [])
	var closed: bool = bool(gene.get("closed", false))
	var out := {"cells": [], "closed": closed, "err": ""}
	if stops.size() < 2:
		out.err = "fewer than 2 stops"
		return out
	var seen := {}
	for s in stops:
		if not (s is Vector2i) or not Grid5.is_dock(s):
			out.err = "stop %s is not a dock of this level" % str(s)
			return out
		if seen.has(s):
			out.err = "stop %s repeated" % str(s)
			return out
		seen[s] = true
	if not _cell_open_for(stops[0], cap_left, width):
		out.err = "start dock %s over cap for this car" % str(stops[0])
		return out
	var cells: Array = [stops[0]]
	var used := {stops[0]: true}
	for k in range(1, stops.size()):
		var leg := _bfs(cells[cells.size() - 1], stops[k], used, cap_left, width)
		if leg.is_empty():
			out.err = "leg %s -> %s cannot be decoded" % [str(cells[cells.size() - 1]), str(stops[k])]
			return out
		for i in range(1, leg.size()):
			cells.append(leg[i])
			used[leg[i]] = true
	if closed and cells.size() >= 3:
		var back := _bfs(cells[cells.size() - 1], stops[0], used, cap_left, width)
		if back.is_empty():
			out.err = "closing leg cannot be decoded"
			return out
		for i in range(1, back.size() - 1):
			cells.append(back[i])
			used[back[i]] = true
	else:
		out.closed = false
	out.err = Route5.validate(cells, out.closed and cells.size() >= 4)
	if out.err != "":
		return out
	if served_rooms_of_cells(cells).size() < 2:
		out.err = "route serves fewer than 2 rooms"
		return out
	out.cells = cells
	return out


## genome (Array of genes) + per-card widths -> {"routes", "err"}. Threads the
## overlap cap across cards in the given order; consumes each card's capacity
## after a successful decode. First undecodable card fails the whole genome.
static func decode_genome(genome: Array, widths: Array) -> Dictionary:
	var cap_left := _cap_map()
	var routes: Array = []
	for gi in genome.size():
		var w: int = widths[gi] if gi < widths.size() else 2
		var d := decode_gene(genome[gi], w, cap_left)
		if d.err != "":
			return {"routes": [], "err": "card %d: %s" % [gi, d.err]}
		routes.append({"cells": d.cells, "closed": d.closed})
		for c in d.cells:
			if cap_left.has(c):
				cap_left[c] = int(cap_left[c]) - w
	return {"routes": routes, "err": ""}


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

## {from_room: {to_room: weight}} from the level's trip table (room letters ==
## room ids in list order). Reactivation (docs/v5-transition-spec.md §5.2) makes
## demand endogenous; as a FLAGGED first-order screen only, a p/(1-p) geometric
## bump is folded uniformly into every reachable pair's weight — the true sim
## always has the last word, so this only shapes primitive seeding, never a score.
static func demand(level: Dictionary) -> Dictionary:
	var d := {}
	var total := 0.0
	for row in level.trips:
		total += row.w
	for row in level.trips:
		if row.w <= 0.0:
			continue
		var a := int(Levels5.ROOM_LETTERS.find(str(row.from)))
		var b := int(Levels5.ROOM_LETTERS.find(str(row.to)))
		if a < 0 or b < 0 or a == b:
			continue
		if not d.has(a):
			d[a] = {}
		d[a][b] = d[a].get(b, 0.0) + row.w / maxf(total, 0.0001)
	return d


## Demand pairs (room ids) heaviest first: [{"from", "to", "w"}, ...].
static func demand_pairs(level: Dictionary) -> Array:
	var d := demand(level)
	var out: Array = []
	for a in d:
		for b in d[a]:
			out.append({"from": a, "to": b, "w": d[a][b]})
	out.sort_custom(func(x, y):
		if is_equal_approx(x.w, y.w):
			return x.from < y.from if x.from != y.from else x.to < y.to
		return x.w > y.w)
	return out


## Total demand touching each room, heaviest first.
static func room_weight(level: Dictionary) -> Dictionary:
	var d := demand(level)
	var w := {}
	for a in d:
		for b in d[a]:
			w[a] = w.get(a, 0.0) + d[a][b]
			w[b] = w.get(b, 0.0) + d[a][b]
	return w


# ---------------------------------------------------------------- primitives

## Hand-built dock-sequence genes derived from LEVEL GEOMETRY + DEMAND (never
## from a thesis answer). The metaheuristic recombines these instead of starting
## from noise (docs/autodesign-research.md §0.2 / v5 §3.4 "primitive seeding must
## be capacity-aware" — assembly below decodes every genome cap-threaded).
static func primitive_genes(level: Dictionary) -> Array:
	var rdocks := room_docks()
	var rids: Array = rdocks.keys()
	rids.sort()
	if rids.size() < 2:
		return []
	var out: Array = []
	var first := func(rid: int) -> Vector2i: return rdocks[rid][0]
	# 1. Cover-all: one dock per room, ordered by dock position (the naive line).
	var cover: Array = []
	for rid in rids:
		cover.append(first.call(rid))
	cover.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	out.append({"stops": cover.duplicate(), "closed": false})
	# 2. Spine: the two rooms whose docks are furthest apart on y.
	var lo: int = rids[0]
	var hi: int = rids[0]
	for rid in rids:
		if first.call(rid).y < first.call(lo).y:
			lo = rid
		if first.call(rid).y > first.call(hi).y:
			hi = rid
	out.append({"stops": [first.call(lo), first.call(hi)], "closed": false})
	# 3/4. Ring over all room docks in angular order (open + closed).
	var ring := _angular_order(cover)
	out.append({"stops": ring.duplicate(), "closed": false})
	out.append({"stops": ring.duplicate(), "closed": true})
	# 5. Positional BANDS: split rooms into contiguous y-bands with a shared
	#    boundary room, one gene per band. This is the generic geometry heuristic
	#    that expresses a split-the-shaft cooperative plan (R-6) without knowing it.
	var by_y := cover.duplicate()
	by_y.sort_custom(func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x)
	for nb in [2, 3]:
		if by_y.size() < nb + 1:
			continue
		var per := int(ceil(float(by_y.size()) / float(nb)))
		var start := 0
		while start < by_y.size() - 1:
			var stop := mini(start + per, by_y.size())
			var band: Array = by_y.slice(start, stop)
			if band.size() >= 2:
				out.append({"stops": band.duplicate(), "closed": false})
			# overlap the next band by one (the shared transfer boundary)
			start = stop - 1
			if stop >= by_y.size():
				break
	# 6. Hub feeders: the busiest room wired to each other room, one line each.
	var rw := room_weight(level)
	var hub: int = rids[0]
	for rid in rids:
		if rw.get(rid, 0.0) > rw.get(hub, 0.0):
			hub = rid
	for rid in rids:
		if rid != hub:
			out.append({"stops": [first.call(hub), first.call(rid)], "closed": false})
	# 7. Direct lines over the heaviest demand pairs (+ a central room spliced in).
	var pairs := demand_pairs(level)
	for i in mini(6, pairs.size()):
		var a: int = pairs[i].from
		var b: int = pairs[i].to
		if rdocks.has(a) and rdocks.has(b):
			out.append({"stops": [first.call(a), first.call(b)], "closed": false})
	# Keep only genes that decode alone (fresh cap), deduped.
	var keep: Array = []
	var seen := {}
	var cap := _cap_map()
	for g in out:
		var k := genome_key([g])
		if seen.has(k):
			continue
		seen[k] = true
		if decode_gene(g, 2, cap.duplicate()).err == "":
			keep.append(g)
	return keep


static func _angular_order(cells: Array) -> Array:
	var cx := 0.0
	var cy := 0.0
	for c in cells:
		cx += c.x
		cy += c.y
	cx /= cells.size()
	cy /= cells.size()
	var out := cells.duplicate()
	out.sort_custom(func(a, b):
		var aa := atan2(a.y - cy, a.x - cx)
		var bb := atan2(b.y - cy, b.x - cx)
		if is_equal_approx(aa, bb):
			return a.y < b.y if a.y != b.y else a.x < b.x
		return aa < bb)
	return out


## Seed population: themed genomes assembled from the primitive pool, then random
## draws, all deduped and decode-checked cap-threaded (so seeds are legal under
## the caps rather than mostly-invalid).
static func primitive_genomes(level: Dictionary, widths: Array,
		rng: RandomNumberGenerator, count: int) -> Array:
	var pool := primitive_genes(level)
	var n_cards := widths.size()
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
		if decode_genome(genome, widths).err != "":
			return
		seen[k] = true
		out.append(clone(genome))
	# Themed: every card the same primitive (cover / spine / ring).
	for i in mini(4, pool.size()):
		var same: Array = []
		for _c in n_cards:
			same.append(pool[i])
		add.call(same)
	# Banded: consecutive pool genes across cards (a split-the-shaft assembly for
	# R-6 pairs the two positional bands onto the two cards).
	if n_cards >= 2:
		for base in pool.size():
			var g: Array = []
			for c in n_cards:
				g.append(pool[(base + c) % pool.size()])
			add.call(g)
	# Random draws from the pool to fill.
	var idx := 0
	while out.size() < count and idx < pool.size() * 6:
		var genome: Array = []
		for _c in n_cards:
			genome.append(pool[rng.randi_range(0, pool.size() - 1)])
		add.call(genome)
		idx += 1
	return out


# ---------------------------------------------------------------- variation

static func random_gene(rng: RandomNumberGenerator, all_docks: Array) -> Dictionary:
	# Bias toward FEW stops: a long random dock sequence self-blocks (each leg's
	# BFS avoids the cells earlier legs used), so long genes rarely decode and
	# waste sampling budget. Short genes (2-4 docks) are both far more decodable
	# and the representative "plausible plan" the random probe should measure; the
	# EA's add-stop mutation still grows longer routes when they help.
	var n := rng.randi_range(2, mini(4, all_docks.size()))
	var pool := all_docks.duplicate()
	var stops: Array = []
	for _i in n:
		stops.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return {"stops": stops, "closed": rng.randf() < 0.2}


## A uniformly sampled DECODABLE route-set (the weak ladder rung / the classifier's
## random probe). [] if none found within `tries`.
static func random_genome(rng: RandomNumberGenerator, all_docks: Array, widths: Array,
		tries := 60) -> Array:
	for _t in tries:
		var genome: Array = []
		for _c in widths.size():
			genome.append(random_gene(rng, all_docks))
		if decode_genome(genome, widths).err == "":
			return genome
	return []


# ---------------------------------------------------------------- freer sampler

## The DRIFTED-SELF-AVOIDING-WALK sampler for the uniform-random difficulty probe
## ONLY (docs/v5-transition-spec.md §2; coordinator refinement 1). The gene decoder
## above lays SHORTEST paths between docks, which auto-cover intermediate rooms and
## auto-thread a level's cooperative split — so a "random" gene does the puzzle's
## reasoning for free and inflates a constraint level's random-win. This sampler
## instead connects random dock stops with a walk that only DRIFTS toward each
## target (prob DRIFT) and otherwise steps to a random legal neighbour, never
## revisiting a cell. The result is a genuinely varied legal route that frequently
## misses rooms and mis-threads the shaft — so on a real puzzle a random legal
## plan rarely wins, and the probe measures the level's difficulty, not the
## decoder's cleverness. The EA / greedy keep the smart decoder.
const DRIFT := 0.6


## One drifted self-avoiding walk from a to b (cap/corridor/passability legal, no
## revisits). [] if it dead-ends or fails to arrive within max_steps.
static func _drifted_walk(a: Vector2i, b: Vector2i, used: Dictionary,
		cap_left: Dictionary, width: int, rng: RandomNumberGenerator, max_steps: int) -> Array:
	if a == b:
		return [a]
	var path: Array = [a]
	var local := used.duplicate()
	local[a] = true
	var cur := a
	var steps := 0
	while steps < max_steps:
		steps += 1
		var cands: Array = []
		for d in NEIGHBORS:
			var v: Vector2i = cur + d
			if local.has(v) or not Grid5.passable(v):
				continue
			if not _cell_open_for(v, cap_left, width):
				continue
			cands.append(v)
		if cands.is_empty():
			return [] # stuck
		var pick: Vector2i
		if rng.randf() < DRIFT:
			pick = cands[0]
			var bd := Grid5.manhattan(cands[0], b)
			for v in cands:
				var dd := Grid5.manhattan(v, b)
				if dd < bd:
					bd = dd
					pick = v
		else:
			pick = cands[rng.randi_range(0, cands.size() - 1)]
		cur = pick
		path.append(cur)
		local[cur] = true
		if cur == b:
			return path
	return []


## ONE raw attempt at a random legal route-set via drifted walks (the probe's
## unit). Returns {"routes", "legal"}: legal is false when any card dead-ends, is
## cap-blocked, or serves < 2 rooms (the RUN gate would refuse it) — so the probe
## can report the LEGALITY RATE (how constraining the caps + geometry are) and,
## among legal draws, the LEGAL-PLAN WIN RATE.
static func sample_random_routeset(rng: RandomNumberGenerator, all_docks: Array,
		widths: Array) -> Dictionary:
	var cap_left := _cap_map()
	var routes: Array = []
	var max_steps := Grid5.COLS * Grid5.ROWS * 3
	for ci in widths.size():
		var w: int = widths[ci]
		var k := rng.randi_range(2, mini(4, all_docks.size()))
		var pool := all_docks.duplicate()
		var stops: Array = []
		for _i in k:
			stops.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		if not _cell_open_for(stops[0], cap_left, w):
			return {"routes": [], "legal": false}
		var cells: Array = [stops[0]]
		var used := {stops[0]: true}
		var ok := true
		for si in range(1, stops.size()):
			var leg := _drifted_walk(cells[cells.size() - 1], stops[si], used, cap_left, w, rng, max_steps)
			if leg.is_empty():
				ok = false
				break
			for i in range(1, leg.size()):
				cells.append(leg[i])
				used[leg[i]] = true
		if not ok:
			return {"routes": [], "legal": false}
		if Route5.validate(cells, false) != "":
			return {"routes": [], "legal": false}
		if served_rooms_of_cells(cells).size() < 2:
			return {"routes": [], "legal": false}
		for c in cells:
			if cap_left.has(c):
				cap_left[c] = int(cap_left[c]) - w
		routes.append({"cells": cells, "closed": false})
	return {"routes": routes, "legal": true}


## One mutation from the operator set, retried until it changes the genome.
static func mutate(rng: RandomNumberGenerator, genome: Array, all_docks: Array,
		tries := 8) -> Array:
	var before := genome_key(genome)
	var out := _mutate_once(rng, genome, all_docks)
	var n := 1
	while n < tries and genome_key(out) == before:
		out = _mutate_once(rng, genome, all_docks)
		n += 1
	return out


static func _mutate_once(rng: RandomNumberGenerator, genome: Array, all_docks: Array) -> Array:
	var g := clone(genome)
	var c := rng.randi_range(0, g.size() - 1)
	var stops: Array = g[c].stops
	match rng.randi_range(0, 7):
		0: # add a dock
			var free := _not_in(all_docks, stops)
			if not free.is_empty() and stops.size() < MAX_STOPS:
				stops.insert(rng.randi_range(0, stops.size()),
						free[rng.randi_range(0, free.size() - 1)])
		1: # delete a dock
			if stops.size() > 2:
				stops.remove_at(rng.randi_range(0, stops.size() - 1))
		2: # swap two docks inside one route
			if stops.size() >= 2:
				var i := rng.randi_range(0, stops.size() - 1)
				var j := rng.randi_range(0, stops.size() - 1)
				var tmp = stops[i]; stops[i] = stops[j]; stops[j] = tmp
		3: # move a dock to another route
			var c2 := rng.randi_range(0, g.size() - 1)
			if c2 != c and stops.size() > 2:
				var s = stops.pop_at(rng.randi_range(0, stops.size() - 1))
				if not (g[c2].stops as Array).has(s):
					(g[c2].stops as Array).insert(
							rng.randi_range(0, (g[c2].stops as Array).size()), s)
		4: # replace a dock with one the route lacks
			var free2 := _not_in(all_docks, stops)
			if not free2.is_empty():
				stops[rng.randi_range(0, stops.size() - 1)] = free2[rng.randi_range(0, free2.size() - 1)]
		5: # toggle the loop bit
			g[c].closed = not g[c].closed
		6: # reverse a segment
			if stops.size() >= 3:
				var i2 := rng.randi_range(0, stops.size() - 2)
				var j2 := rng.randi_range(i2 + 1, stops.size() - 1)
				var seg: Array = stops.slice(i2, j2 + 1)
				seg.reverse()
				for k in seg.size():
					stops[i2 + k] = seg[k]
		7: # REORDER CARDS: rotate which card decodes first (who gets scarce cap).
			if g.size() >= 2:
				g.append(g.pop_front())
	return g


## Route-level crossover: the child is `a` with ONE card's whole route from `b`.
static func crossover(rng: RandomNumberGenerator, a: Array, b: Array) -> Array:
	var child := clone(a)
	var c := rng.randi_range(0, child.size() - 1)
	child[c] = {"stops": (b[c].stops as Array).duplicate(), "closed": b[c].closed}
	return child


static func _not_in(all_docks: Array, stops: Array) -> Array:
	var out: Array = []
	for d in all_docks:
		if not stops.has(d):
			out.append(d)
	return out


# ---------------------------------------------------------------- structure

## Jaccard distance between two route-sets, averaged per card, over the SERVED
## ROOM sets the polylines actually reach. 0 = the same service, 1 = disjoint.
static func structural_distance(routes_a: Array, routes_b: Array) -> float:
	var n := mini(routes_a.size(), routes_b.size())
	if n == 0:
		return 1.0
	var total := 0.0
	for i in n:
		var sa := {}
		var sb := {}
		for r in served_rooms_of_cells(routes_a[i].cells):
			sa[r] = true
		for r in served_rooms_of_cells(routes_b[i].cells):
			sb[r] = true
		var inter := 0
		for k in sa:
			if sb.has(k):
				inter += 1
		var uni := sa.size() + sb.size() - inter
		total += 1.0 if uni == 0 else 1.0 - float(inter) / float(uni)
	return total / n


## A structural signature of a WINNING route-set for K counting: the sorted
## per-card served-room set, plus loop / corridor / overlap-usage flags. Two
## winners with the same signature are the same solution.
static func win_signature(routes: Array) -> String:
	var parts: Array = []
	for r in routes:
		var rooms: Array = served_rooms_of_cells(r.cells)
		rooms.sort()
		var letters: Array = []
		for rid in rooms:
			letters.append(Grid5.room_letter(rid))
		var flags := "L" if r.get("closed", false) else "-"
		var over := 0
		for c in r.cells:
			if Grid5.is_overlap_capped(c):
				over += 1
		parts.append("%s%s%d" % ["".join(letters), flags, over])
	parts.sort()
	return "|".join(parts)


## Cheap structural summary for the report.
static func describe(routes: Array) -> Dictionary:
	var loops := 0
	var cells := 0
	var rooms := {}
	var overs := 0
	for r in routes:
		if r == null:
			continue
		if r.get("closed", false):
			loops += 1
		cells += r.cells.size()
		for rid in served_rooms_of_cells(r.cells):
			rooms[rid] = true
		for c in r.cells:
			if Grid5.is_overlap_capped(c):
				overs += 1
	return {"loops": loops, "cells": cells, "served_rooms": rooms.size(),
			"overlap_cells": overs}
