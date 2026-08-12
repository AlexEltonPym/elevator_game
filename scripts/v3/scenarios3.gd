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

const SEEDS := {"L1": 101, "L2": 202, "L3": 303, "X-1": 404}


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


## {"naive": {"desc": String, "routes": Array}, "thesis": {...}} for a level.
## X-1 has no naive strategy - only "thesis" (the old smoke-test route set).
static func route_sets(level_id: String) -> Dictionary:
	match level_id:
		"L1":
			return {
				"naive": {
					"desc": "all 3 cards full height (everyone serves everything)",
					"routes": [
						path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 9), Vector2i(2, 9)]),
						path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 9), Vector2i(2, 9)]),
						path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 9), Vector2i(2, 9)]),
					],
				},
				"thesis": {
					"desc": "express lobby->penthouse on the spine, locals low",
					"routes": [
						path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 8)]),
						path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 4)]),
						path([Vector2i(2, 0), Vector2i(2, 9)]),
					],
				},
			}
		"L2":
			return {
				"naive": {
					"desc": "all 3 cars full height through the gate tunnel",
					"routes": [
						path([Vector2i(0, 0), Vector2i(0, 9)]),
						path([Vector2i(0, 0), Vector2i(0, 9)]),
						path([Vector2i(0, 0), Vector2i(0, 9)]),
					],
				},
				"thesis": {
					"desc": "gate shuttle for the cross crowds + bottom local + perimeter express",
					"routes": [
						path([Vector2i(0, 0), Vector2i(0, 2)]),
						path([Vector2i(0, 1), Vector2i(0, 8)]),
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
						path([Vector2i(2, 3), Vector2i(1, 3), Vector2i(1, 8),
								Vector2i(3, 8), Vector2i(3, 9)]),
						path([Vector2i(4, 3), Vector2i(5, 3), Vector2i(5, 8),
								Vector2i(3, 8), Vector2i(3, 9)]),
						path([Vector2i(3, 0), Vector2i(3, 9)]),
					],
				},
				"thesis": {
					"desc": "two short feeder shuttles into the HUB + express spine",
					"routes": [
						path([Vector2i(1, 3), Vector2i(3, 3)]),
						path([Vector2i(5, 3), Vector2i(3, 3)]),
						path([Vector2i(3, 0), Vector2i(3, 9)]),
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
