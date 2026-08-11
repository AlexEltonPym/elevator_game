extends RefCounted
## Scenario data for the v3 balance harness (tests/balance.gd).
##
## A scenario = a level + a fixed RNG seed + a scripted route set (one cell
## polyline per card, exactly what a player would draw). "naive" sets are the
## obvious first attempt; "intended" sets are each level's thesis strategy.
## The harness asserts the intended strategy beats the naive one (see
## balance.gd for the per-level assertions).
##
## Routes are written as waypoint lists and expanded to full polylines with
## path(): consecutive waypoints must share a row or column, and the line is
## walked one cell at a time (validated again by the harness against the
## level's maze).


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


static func scenarios() -> Array:
	return [
		{
			"key": "L1_naive",
			"level": "L1",
			"seed": 101,
			"desc": "all 3 cards full height (everyone serves everything)",
			"routes": [
				path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 9), Vector2i(2, 9)]),
				path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 9), Vector2i(2, 9)]),
				path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 9), Vector2i(2, 9)]),
			],
		},
		{
			"key": "L1_intended",
			"level": "L1",
			"seed": 101,
			"desc": "express lobby->penthouse on the spine, locals low",
			"routes": [
				path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 8)]),
				path([Vector2i(2, 0), Vector2i(1, 0), Vector2i(1, 4)]),
				path([Vector2i(2, 0), Vector2i(2, 9)]),
			],
		},
		{
			"key": "L2_naive",
			"level": "L2",
			"seed": 202,
			"desc": "all 3 cars up the short shaft through the gate",
			"routes": [
				path([Vector2i(0, 0), Vector2i(0, 7)]),
				path([Vector2i(0, 0), Vector2i(0, 7)]),
				path([Vector2i(0, 0), Vector2i(0, 7)]),
			],
		},
		{
			"key": "L2_intended",
			"level": "L2",
			"seed": 202,
			"desc": "2 staggered gate cars + 1 gate-free perimeter car",
			"routes": [
				path([Vector2i(0, 0), Vector2i(0, 5)]),
				path([Vector2i(0, 2), Vector2i(0, 7)]),
				path([Vector2i(0, 0), Vector2i(7, 0), Vector2i(7, 7), Vector2i(0, 7)]),
			],
		},
		{
			"key": "L3_naive",
			"level": "L3",
			"seed": 303,
			"desc": "two direct winding climbs (no shared hub) + spine",
			"routes": [
				path([Vector2i(1, 3), Vector2i(1, 8), Vector2i(3, 8), Vector2i(3, 9)]),
				path([Vector2i(5, 3), Vector2i(5, 8), Vector2i(3, 8), Vector2i(3, 9)]),
				path([Vector2i(3, 0), Vector2i(3, 9)]),
			],
		},
		{
			"key": "L3_intended",
			"level": "L3",
			"seed": 303,
			"desc": "two feeder hops + express spine sharing the HUB stop",
			"routes": [
				path([Vector2i(1, 3), Vector2i(3, 3)]),
				path([Vector2i(5, 3), Vector2i(3, 3)]),
				path([Vector2i(3, 0), Vector2i(3, 9)]),
			],
		},
		{
			"key": "X1_smoke",
			"level": "X-1",
			"seed": 404,
			"desc": "old smoke strategy: left winder + crossbar + artery express",
			"routes": [
				path([Vector2i(2, 0), Vector2i(2, 5), Vector2i(0, 5), Vector2i(0, 9)]),
				path([Vector2i(2, 0), Vector2i(0, 0), Vector2i(0, 3), Vector2i(6, 3),
						Vector2i(6, 0)]),
				path([Vector2i(2, 0), Vector2i(4, 0), Vector2i(4, 9), Vector2i(6, 9),
						Vector2i(6, 7)]),
			],
		},
	]


