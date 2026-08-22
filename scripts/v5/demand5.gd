extends RefCounted
## DERIVED demand. Trips are NEVER hand-written — they are generated from the map's ROOM
## TYPES plus the level's fixed seed, so demand always fits the building and can't drift
## (no atrium destinations, no dead rooms, no walk-across-only pairs). main5 calls this at
## load; the headless solver drives the same main5, so game and solver agree exactly.
##
## Model: every pair of DEMAND rooms (all rooms except atrium + delivery) gets both-way
## trips weighted by a room-type AFFINITY, jittered by the seed. Atriums carry NO demand
## (they are transfer bridges — riders alight and walk across). Delivery bays are FREIGHT
## only: each ships to each cafe as a cargo run (type "delivery", returning empty to a
## lobby). Abutting rooms (a walk, not a lift ride) are skipped. Any demand room left with
## no trip is connected to its best partner, so nothing is ever stranded.

## Symmetric type-pair affinity. Keys are "typeA|typeB" with types sorted alphabetically.
const AFF := {
	"lobby|office": 1.0, "apartment|lobby": 1.0, "lobby|penthouse": 1.2, "cafe|lobby": 0.6,
	"cafe|office": 0.7, "apartment|cafe": 0.7, "cafe|penthouse": 0.4,
	"apartment|office": 0.5, "office|office": 0.35, "apartment|apartment": 0.25,
	"office|penthouse": 0.3, "apartment|penthouse": 0.25, "penthouse|penthouse": 0.2,
	"lobby|lobby": 0.3, "cafe|cafe": 0.2,
}
const DEFAULT_AFF := 0.3


static func _aff(a: String, b: String) -> float:
	var key := "%s|%s" % ([a, b] if a <= b else [b, a])
	return float(AFF.get(key, DEFAULT_AFF))


## Do rooms i and j touch orthogonally (a walk across, so no lift trip between them)?
static func _abut(rooms: Array, owner: Dictionary, i: int, j: int) -> bool:
	for c in rooms[i].cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if owner.get(c + d, -1) == j:
				return true
	return false


## Derive the trip list for a set of rooms, deterministic in `seed`.
static func derive(rooms: Array, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var owner := {}
	for i in rooms.size():
		for c in rooms[i].cells:
			owner[c] = i
	var letter := func(i: int) -> String: return char(65 + i)
	var demand: Array = []
	var cafes: Array = []
	var deliveries: Array = []
	for i in rooms.size():
		var t: String = rooms[i].type
		if t == "atrium":
			continue          # transfer bridge — no demand of its own
		if t == "delivery":
			deliveries.append(i)
			continue          # freight only (the cargo run below)
		demand.append(i)
		if t == "cafe":
			cafes.append(i)
	var trips: Array = []
	var used := {}
	# PEOPLE: every non-abutting demand pair, both ways, weighted by type affinity.
	for a in range(demand.size()):
		for b in range(a + 1, demand.size()):
			var i: int = demand[a]
			var j: int = demand[b]
			if _abut(rooms, owner, i, j):
				continue
			var aff := _aff(rooms[i].type, rooms[j].type)
			if aff <= 0.0:
				continue
			var w1: float = snappedf(aff * (0.75 + 0.5 * rng.randf()), 0.01)
			var w2: float = snappedf(aff * 0.8 * (0.75 + 0.5 * rng.randf()), 0.01)
			trips.append({"w": w1, "from": letter.call(i), "to": letter.call(j)})
			trips.append({"w": w2, "from": letter.call(j), "to": letter.call(i)})
			used[i] = true
			used[j] = true
	# FREIGHT: each delivery bay ships to each cafe (cargo run; returns empty to a lobby).
	var ret := -1
	for i in demand:
		if rooms[i].type == "lobby":
			ret = i
			break
	if ret < 0 and not demand.is_empty():
		ret = demand[0]
	# A whole room is a delivery bay, so freight is a PROMINENT share of demand (weight on
	# par with a strong commute), not a rounding error — else a "Freight" level barely
	# ships anything and the cargo lift has no reason to reach the bay.
	for d in deliveries:
		for cf in cafes:
			if _abut(rooms, owner, d, cf):
				continue
			var w: float = snappedf(1.2 * (0.75 + 0.5 * rng.randf()), 0.01)
			trips.append({"w": w, "from": letter.call(d), "to": letter.call(cf),
					"type": "delivery", "return": letter.call(ret)})
	# NO DEAD ROOMS: connect any unserved demand room to its best non-abutting partner.
	for i in demand:
		if used.has(i):
			continue
		var best := -1
		var best_aff := -1.0
		for j in demand:
			if j == i or _abut(rooms, owner, i, j):
				continue
			var aff := _aff(rooms[i].type, rooms[j].type)
			if aff > best_aff:
				best_aff = aff
				best = j
		if best >= 0:
			trips.append({"w": 0.15, "from": letter.call(i), "to": letter.call(best)})
			trips.append({"w": 0.12, "from": letter.call(best), "to": letter.call(i)})
	return trips
