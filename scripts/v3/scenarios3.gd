class_name Scenarios3
extends RefCounted
## Shared scenario route sets: per level, the "naive" strategy (the plausible
## thing a new player tries first) and the "thesis" strategy (the level's
## intended answer), each as one cell polyline per card - exactly what a
## player would draw.
##
## BOTH consumers read this table so they can never drift apart:
## - the in-game watch mode (level select's WATCH NAIVE / WATCH THESIS
##   pre-draws these routes with editing disabled), and
## - the balance harness (tests/scenarios3.gd adapts this into its scenario
##   list; tests/balance.gd asserts thesis wins where naive loses).
##
## SEEDS holds the canonical fixed RNG seed per level: watch runs and harness
## runs of the same level use the same seed, so naive and thesis always face
## the identical demand sequence. Normal PLAY stays unseeded.
##
## Routes are written as waypoint lists and expanded to full polylines with
## path(): consecutive waypoints must share a row or column, and the line is
## walked one cell at a time (validated again by the harness against the
## level's maze).

## The canonical WATCH / --quick seed per level. It is a DEMONSTRATION seed,
## not an assertion: watch mode exists so a player can see naive fail and the
## thesis work on the identical arrival sequence, so it must be a seed where
## both of those actually happen. (L4's 505 became one of the ~1-in-16 seeds
## the thesis loses once v4 acceleration slowed every car; 511 shows the
## comparison the level is about. The claim "the thesis wins" is made by
## tests/balance.gd over the 16 held-out SEEDS_ASSERT, never by this number.)
const SEEDS := {"L1": 101, "L2": 202, "L3": 303, "L4": 511, "X-1": 404}

## THE SEED SETS (v3.5 level-design pass). A level axiom asserted on ONE seed
## measures seed luck, not the level: the 2026-08-12 depth run held L3's
## "naive LOSES" claim out on 8 unseen seeds and naive WON 6 of them. So the
## balance suite now asserts over a SET, and the sets have disjoint jobs:
##
##   SEEDS          one canonical seed per level. WATCH mode only (naive and
##                  thesis must face the identical demand for the comparison
##                  to read), plus the harness's `--quick` iteration mode.
##   SEEDS_TUNE     16 seeds. The ONLY seeds level geometry/demand was tuned
##                  against while chasing the axioms.
##   SEEDS_ASSERT   16 HELD-OUT seeds. tests/balance.gd asserts on these and
##                  nothing was ever tuned against them, which is the whole
##                  point: "thesis wins 15/16" is then a measurement, not a
##                  memory. Never tune against these — if a level needs work,
##                  iterate on SEEDS_TUNE and re-run the gate.
##
## Both are also disjoint from the depth tools' SEEDS_TRAIN / SEEDS_TEST
## (tools/sim_api.gd), so the search experiment and the regression gate never
## share an arrival sequence either.
##
## 16 is the smallest set where "15/16" is a meaningful claim (a single bad
## seed is tolerated, two is a failure) and the whole 16-seed suite still runs
## in well under a minute — see tests/balance.gd's header for the timing.
const SEEDS_TUNE := [7001, 7013, 7027, 7039, 7057, 7069, 7079, 7103,
		7121, 7129, 7151, 7177, 7193, 7207, 7219, 7229]
const SEEDS_ASSERT := [9001, 9013, 9029, 9041, 9059, 9067, 9091, 9103,
		9127, 9133, 9151, 9161, 9173, 9187, 9199, 9203]


## Expand [w0, w1, w2, ...] waypoints into an inclusive cell polyline.
static func path(waypoints: Array) -> Array:
	var cells: Array = [waypoints[0]]
	for k in range(1, waypoints.size()):
		var a: Vector2i = waypoints[k - 1]
		var b: Vector2i = waypoints[k]
		var d := b - a
		assert(d.x == 0 or d.y == 0, "path(): waypoints must share a row or column")
		var step := Vector2i(signi(d.x), signi(d.y))
		var c := a
		while c != b:
			c += step
			cells.append(c)
	return cells


## A CLOSED route (v3.4 loop): same waypoint expansion, but the last cell
## must end adjacent to the first (do NOT repeat the head) — the closing link
## is implied. Marked with {"closed": true} so consumers commit it as a loop.
static func loop(waypoints: Array) -> Dictionary:
	return {"cells": path(waypoints), "closed": true}


## Route-set entries are either a plain cell Array (open route) or a
## Dictionary from loop(). These two normalizers let every consumer (watch
## mode, harness, lints) handle both shapes.
static func cells_of(entry) -> Array:
	return entry.cells if entry is Dictionary else entry


static func closed_of(entry) -> bool:
	return bool(entry.get("closed", false)) if entry is Dictionary else false


## The route's HOME cell (v4 phase 2) or null. Part of the route-set data, so
## a scenario, a watch run and a depth-tool candidate can all express "and
## this car waits HERE when it has nothing to do".
static func home_of(entry):
	return entry.get("home", null) if entry is Dictionary else null


## {"naive": {"desc": String, "routes": Array}, "thesis": {...}} for a level.
## X-1 has no naive strategy - only "thesis" (the old smoke-test route set).
static func route_sets(level_id: String) -> Dictionary:
	match level_id:
		"L1":
			return {
				"naive": {
					"desc": "every card drawn as far as it reaches: two wing->penthouse U's + a cross sweep",
					"routes": [
						# The honest first instinct: draw each line as long as the
						# building allows, so every car reaches the penthouse and every
						# room is covered twice over. It fails for a reason that is
						# invisible until you watch it: the EXPRESS sweep below is the
						# cheapest plan ON PAPER for every wing rider in the building,
						# so all of them queue for its four seats while the two long
						# locals drive around half empty.
						path([Vector2i(0, 8), Vector2i(0, 0), Vector2i(3, 0),
								Vector2i(3, 9)]),
						path([Vector2i(6, 8), Vector2i(6, 0), Vector2i(3, 0),
								Vector2i(3, 9)]),
						path([Vector2i(0, 8), Vector2i(0, 0), Vector2i(6, 0),
								Vector2i(6, 8)]),
					],
				},
				"thesis": {
					"desc": "a local per wing, express dedicated to the lobby->penthouse spine",
					"routes": [
						path([Vector2i(3, 0), Vector2i(0, 0), Vector2i(0, 8)]),
						path([Vector2i(3, 0), Vector2i(6, 0), Vector2i(6, 8)]),
						path([Vector2i(3, 0), Vector2i(3, 9)]),
					],
				},
			}
		"L2":
			return {
				"naive": {
					"desc": "all 3 cars full height, weaving through every room and the tunnel",
					"routes": [
						# Honest and thorough: each car threads both clusters AND the
						# tunnel, so every room is covered three times over. Three cars
						# that all want the single-file corridor is exactly the jam the
						# level is about.
						path([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
								Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 7),
								Vector2i(1, 7), Vector2i(1, 8), Vector2i(0, 8),
								Vector2i(0, 9)]),
						path([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
								Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 7),
								Vector2i(1, 7), Vector2i(1, 8), Vector2i(0, 8),
								Vector2i(0, 9)]),
						path([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
								Vector2i(1, 2), Vector2i(0, 2), Vector2i(0, 7),
								Vector2i(1, 7), Vector2i(1, 8), Vector2i(0, 8),
								Vector2i(0, 9)]),
					],
				},
				"thesis": {
					"desc": "lower local + ONE gate shuttle + perimeter express, transferring at (0,2)",
					"routes": [
						# CAR A: the lower cluster and the bottom lobby. Never enters
						# the tunnel, so it never queues for it.
						path([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
								Vector2i(1, 2), Vector2i(0, 2)]),
						# CAR B: THE tunnel car - the only one that spends the gate.
						# It meets CAR A at (0,2) and the express at (0,7)/(0,8).
						path([Vector2i(0, 2), Vector2i(0, 8), Vector2i(1, 8),
								Vector2i(1, 7)]),
						# EXPRESS: the long way round the outside, for the execs and
						# the upper cluster's run to the top.
						path([Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 9),
								Vector2i(0, 9), Vector2i(0, 7)]),
					],
				},
			}
		"L3":
			return {
				"naive": {
					"desc": "two direct winding climbs (no shared hub) + spine",
					"routes": [
						# Direct is the obvious read: each arm gets its own line
						# straight up the outside to the penthouse. Both of them live
						# in the loft, and so does the spine.
						path([Vector2i(2, 3), Vector2i(1, 3), Vector2i(1, 8),
								Vector2i(3, 8), Vector2i(3, 9)]),
						path([Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 8),
								Vector2i(3, 8), Vector2i(3, 9)]),
						path([Vector2i(3, 0), Vector2i(3, 9)]),
					],
				},
				"thesis": {
					"desc": "each feeder runs its arm -> HUB -> lobby; express owns the spine",
					"routes": [
						# A feeder that carries on DOWN to the lobby serves its own
						# half of the building in one leg, and never touches the loft.
						path([Vector2i(1, 3), Vector2i(3, 3), Vector2i(3, 0)]),
						path([Vector2i(5, 3), Vector2i(3, 3), Vector2i(3, 0)]),
						# The only car in the loft, and the only fast one: penthouse
						# traffic only, boarding at the HUB or the lobby.
						path([Vector2i(3, 0), Vector2i(3, 9)]),
					],
				},
			}
		"L4":
			return {
				"naive": {
					"desc": "three full outer-lane loops, staggered a third of a lap apart",
					"routes": [
						# The honest thing a player does once they have learned to
						# CLOSE a route: ride the ring one-way, and cover every room
						# while you are at it. Correct mechanic, wrong network - each
						# lap pays eight door cycles for the two rooms it needed.
						loop([Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 7),
								Vector2i(0, 7), Vector2i(0, 1)]),
						loop([Vector2i(7, 3), Vector2i(7, 7), Vector2i(0, 7),
								Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 2)]),
						loop([Vector2i(3, 7), Vector2i(0, 7), Vector2i(0, 0),
								Vector2i(7, 0), Vector2i(7, 7), Vector2i(4, 7)]),
					],
				},
				"thesis": {
					"desc": "a weave per commute (express on the heavy one) + a ring catch-all",
					"routes": [
						# CAR A: the left<->right commute. Outer lane up the lounge side
						# and down the offices side, INNER lane along the top and bottom
						# straights, so it never opens its doors for homes or canteen.
						loop([Vector2i(0, 0), Vector2i(0, 6), Vector2i(7, 6),
								Vector2i(7, 1), Vector2i(1, 1), Vector2i(1, 0)]),
						# CAR B: the whole outer lane, one-way. The only car that touches
						# all eight rooms, so it carries the quarter-lap trickle and is
						# the transfer between the two commutes - which share no room.
						# It is deliberately the SLOW car: a fast car here would be the
						# cheapest plan for every pair on the board and would swallow
						# both commutes into one four-seat cabin.
						loop([Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 7),
								Vector2i(0, 7), Vector2i(0, 1)]),
						# EXPRESS: the heavier bottom<->top commute, woven the same way -
						# outer along the bottom and the top (homes, canteen), inner up
						# and down the sides.
						loop([Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 1),
								Vector2i(6, 1), Vector2i(6, 6), Vector2i(7, 6),
								Vector2i(7, 7), Vector2i(0, 7), Vector2i(0, 6),
								Vector2i(1, 6), Vector2i(1, 1), Vector2i(0, 1)]),
					],
				},
			}
		"X-1":
			return {
				"thesis": {
					"desc": "old smoke strategy: left winder + crossbar + artery express",
					"routes": [
						path([Vector2i(2, 0), Vector2i(2, 5), Vector2i(0, 5), Vector2i(0, 9)]),
						path([Vector2i(2, 0), Vector2i(0, 0), Vector2i(0, 3), Vector2i(6, 3),
								Vector2i(6, 0)]),
						path([Vector2i(2, 0), Vector2i(4, 0), Vector2i(4, 9), Vector2i(6, 9),
								Vector2i(6, 7)]),
					],
				},
			}
	return {}


## The routes array for one level + strategy ("naive" | "thesis").
static func route_set(level_id: String, strategy: String) -> Array:
	var sets := route_sets(level_id)
	if not sets.has(strategy):
		return []
	return sets[strategy].routes
