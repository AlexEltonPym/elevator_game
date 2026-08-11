class_name Levels3
extends RefCounted
## Data-driven level table for v3. Each entry fully describes a level:
## grid rows (TOP row first, same legend as Grid3), the 3 elevator cards,
## quota / max_lost, pulse-spawn config, passenger type mix, exec
## origin/destination rooms, named room groups + a weighted trip table
## (which group spawns travel between), and intro/thesis text.
##
## `current` is the index the level select (or the harness) picked; main3
## reads it in _ready and calls Grid3.load_level with the rows.
##
## Spawning is PULSE based: every so often a burst of burst_min..burst_max
## passengers spawns `gap` seconds apart, then quiet. The per-passenger
## average interval lerps interval_start -> interval_end over ramp seconds;
## the pause after a burst of n is n * interval, so the average rate matches
## the interval while still reading as pulses (idle cars between bursts).

static var current := 0

const STANDARD_SPEED := 260.0
const EXPRESS_SPEED := 520.0

const LEVELS := [
	{
		"id": "L1",
		"name": "Tower",
		"thesis": "dedicate the express: spine for execs, locals for the side rooms",
		"intro": "A straight tower. Execs (amber, 40 s) pop up in the LOBBY\nand want the PENTHOUSE - nothing else.\nVisitors and patients shuffle between lobby and side rooms.\n\nAll routes look alike here; what matters is how LONG each\nline is. Try a pure lobby-to-penthouse express on the spine\n(it skips the side rooms) and keep the locals low.",
		"rows": [
			"..R..", # row 9  penthouse (2,9)
			".R...", # row 8  side rooms (1,1)..(1,8)
			".R...", # row 7
			".R...", # row 6
			".R...", # row 5
			".R...", # row 4
			".R...", # row 3
			".R...", # row 2
			".R...", # row 1
			"..R..", # row 0  lobby (2,0)
		],
		"cards": [
			{"name": "LOCAL A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "LOCAL B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 45,
		"max_lost": 5,
		"spawn": {"interval_start": 3.4, "interval_end": 2.6, "ramp": 150.0,
				"burst_min": 2, "burst_max": 4, "gap": 0.8},
		"mix": {"visitor": 0.45, "patient": 0.30, "exec": 0.25},
		"patience": {"exec": 24.0}, # hasty enough that a locals-clogged tower loses them
		"exec_origins": [Vector2i(2, 0)],
		"exec_dests": [Vector2i(2, 9)],
		"groups": {
			"lobby": [Vector2i(2, 0)],
			"side": [
				Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4),
				Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8),
			],
		},
		"trips": [
			{"w": 0.40, "from": "lobby", "to": "side"},
			{"w": 0.40, "from": "side", "to": "lobby"},
			{"w": 0.20, "from": "side", "to": "side"},
		],
	},
	{
		"id": "L2",
		"name": "Detour",
		"thesis": "the long way around beats a third car in the gate queue",
		"intro": "One gate on the short shaft between the lower and upper\nrooms - and a long, gate-free perimeter corridor.\n\nDemand is heavy. Two cars through the gate is company;\nthree is a queue. Try routing one car the long way around\nfor the end-to-end riders.",
		"rows": [
			"R.......", # row 7  upper room (0,7)
			"..#####.", # row 6
			"R.#####.", # row 5  upper room (0,5)
			"..#####.", # row 4
			"G######.", # row 3  gate (0,3); perimeter opening (7,3)
			"R.#####.", # row 2  lower room (0,2)
			"..#####.", # row 1
			"R.......", # row 0  lower room (0,0)
		],
		"cards": [
			{"name": "CAR A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "CAR B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "CAR C", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.8, 0.55, 0.95)},
		],
		"quota": 45,
		"max_lost": 8,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 150.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.7},
		"mix": {"visitor": 0.55, "patient": 0.45},
		"exec_origins": [],
		"exec_dests": [],
		"groups": {
			"bottom": [Vector2i(0, 0)],
			"top": [Vector2i(0, 7)],
			"lower": [Vector2i(0, 0), Vector2i(0, 2)],
			"upper": [Vector2i(0, 5), Vector2i(0, 7)],
			"mid_low": [Vector2i(0, 2)],
			"mid_high": [Vector2i(0, 5)],
		},
		"trips": [
			{"w": 0.18, "from": "bottom", "to": "top"},
			{"w": 0.17, "from": "top", "to": "bottom"},
			{"w": 0.13, "from": "mid_low", "to": "mid_high"},
			{"w": 0.12, "from": "mid_high", "to": "mid_low"},
			{"w": 0.20, "from": "lower", "to": "lower"},
			{"w": 0.20, "from": "upper", "to": "upper"},
		],
	},
	{
		"id": "L3",
		"name": "Junction",
		"thesis": "feeders + express sharing the HUB: transfers beat winding",
		"intro": "An express spine (lobby - HUB - penthouse) and two arm\nrooms beside the HUB junction. Execs (amber) appear at the\narms and want the penthouse, fast.\n\nEach arm has a winding outside climb to the top - past\nslow storage floors. Or: short feeder hops to the HUB and\nlet the express do the lifting. Watch riders transfer.",
		"rows": [
			"###R###", # row 9  penthouse (3,9)
			"#.R.R.#", # row 8  storage decoys (2,8) (4,8) on the ring
			"#.#.#.#", # row 7
			"#R#.#R#", # row 6  storage decoys (1,6) (5,6)
			"#R#.#R#", # row 5  storage decoys (1,5) (5,5)
			"#R#.#R#", # row 4  storage decoys (1,4) (5,4)
			"#R.R.R#", # row 3  arm A (1,3), HUB (3,3), arm B (5,3)
			"###.###", # row 2
			"###.###", # row 1
			"###R###", # row 0  lobby (3,0)
		],
		"cards": [
			{"name": "FEEDER A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "FEEDER B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 50,
		"max_lost": 8,
		"spawn": {"interval_start": 2.6, "interval_end": 2.0, "ramp": 150.0,
				"burst_min": 4, "burst_max": 6, "gap": 0.6},
		"mix": {"visitor": 0.35, "patient": 0.30, "exec": 0.35},
		"patience": {"exec": 18.0}, # dies to the winding climb, lives on the hub hop
		"exec_origins": [Vector2i(1, 3), Vector2i(5, 3)],
		"exec_dests": [Vector2i(3, 9)],
		"groups": {
			"arms": [Vector2i(1, 3), Vector2i(5, 3)],
			"pent": [Vector2i(3, 9)],
			"lobby": [Vector2i(3, 0)],
		},
		"trips": [
			{"w": 0.30, "from": "lobby", "to": "arms"},
			{"w": 0.25, "from": "arms", "to": "lobby"},
			{"w": 0.20, "from": "lobby", "to": "pent"},
			{"w": 0.10, "from": "pent", "to": "lobby"},
			{"w": 0.15, "from": "arms", "to": "arms"},
		],
	},
	{
		"id": "X-1",
		"name": "Sandbox",
		"thesis": "the original maze - no thesis, just the toys",
		"intro": "Draw each elevator's route as a line through the maze.\nRooms (lettered) on a route become its stops; passengers\ntransfer between routes at shared rooms automatically.\nStriped GATE cells let only one car through at a time.",
		"rows": Grid3.MAZE,
		"cards": [
			{"name": "LOCAL A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "LOCAL B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 30,
		"max_lost": 8,
		"spawn": {"interval_start": 5.5, "interval_end": 3.0, "ramp": 240.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.9},
		"mix": {"visitor": 0.55, "patient": 0.45},
		"exec_origins": [],
		"exec_dests": [],
		"groups": {
			"lobby": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)],
			"upper": [
				Vector2i(0, 3), Vector2i(6, 3), Vector2i(2, 5), Vector2i(4, 5),
				Vector2i(0, 7), Vector2i(6, 7), Vector2i(0, 9), Vector2i(4, 9),
				Vector2i(6, 9),
			],
		},
		"trips": [
			{"w": 0.30, "from": "lobby", "to": "upper"},
			{"w": 0.30, "from": "upper", "to": "lobby"},
			{"w": 0.40, "from": "upper", "to": "upper"},
		],
	},
]


static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i].id == id:
			return i
	return -1
