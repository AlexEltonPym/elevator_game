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

## Set by the level select BEFORE changing to the game scene:
## "" = normal PLAY (unseeded, editable); "naive" / "thesis" = watch mode
## (scenario routes pre-drawn from Scenarios3, canonical seed, no editing).
static var watch_strategy := ""

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
			"pent": [Vector2i(2, 9)],
			"side": [
				Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4),
				Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8),
			],
		},
		"trips": [
			{"w": 0.38, "from": "lobby", "to": "side"},
			{"w": 0.38, "from": "side", "to": "lobby"},
			{"w": 0.18, "from": "side", "to": "side"},
			{"w": 0.06, "from": "pent", "to": "lobby"}, # sparse trickle back down
		],
	},
	{
		"id": "L2",
		"name": "Detour",
		"thesis": "spend the gate on a cross shuttle; execs ride the perimeter express",
		"intro": "Two clusters of rooms - and between them a 3-cell GATE\nCORRIDOR: one car in the whole tunnel at a time.\nThe gate-free perimeter is the long way around.\n\nThe mid-cluster crowds (B,C <-> D,E) MUST cross - the\ntunnel is their only sane path. Execs (amber, hasty) pop\nup at the BOTTOM and want the TOP. Draw everything full\nheight and everyone just waits for the fast car - one\nstop-everywhere line through the tunnel. Instead: spend\nthe gate on a dedicated cross shuttle, keep a local low,\nand send the express the long way for the execs.",
		"rows": [
			"R.......", # row 9  top room (0,9) - on the perimeter
			"R.#####.", # row 8  upper room (0,8)
			"R.#####.", # row 7  upper room (0,7)
			"..#####.", # row 6
			"G######.", # row 5  gate corridor (0,3)..(0,5): ONE mutex
			"G######.", # row 4
			"G######.", # row 3
			"R.#####.", # row 2  lower room (0,2)
			"R.#####.", # row 1  lower room (0,1)
			"R.......", # row 0  bottom room (0,0) - on the perimeter
		],
		"cards": [
			{"name": "CAR A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "CAR B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 50,
		"max_lost": 6,
		"spawn": {"interval_start": 1.8, "interval_end": 1.4, "ramp": 120.0,
				"burst_min": 5, "burst_max": 8, "gap": 0.5},
		"mix": {"visitor": 0.42, "patient": 0.28, "exec": 0.30},
		"patience": {"exec": 20.0}, # dies queueing behind a stop-everywhere tunnel jam
		"exec_origins": [Vector2i(0, 0)],
		"exec_dests": [Vector2i(0, 9)],
		"groups": {
			"bottom": [Vector2i(0, 0)],
			"top": [Vector2i(0, 9)],
			"lower": [Vector2i(0, 1), Vector2i(0, 2)],
			"upper": [Vector2i(0, 7), Vector2i(0, 8)],
		},
		"trips": [
			# The heart of the level: mid-cluster <-> mid-cluster demand whose
			# honest best path is the gate corridor (the perimeter is ~5x the
			# ride from the middle rooms).
			{"w": 0.26, "from": "lower", "to": "upper"},
			{"w": 0.26, "from": "upper", "to": "lower"},
			{"w": 0.12, "from": "bottom", "to": "lower"},
			{"w": 0.12, "from": "lower", "to": "bottom"},
			{"w": 0.12, "from": "upper", "to": "top"},
			{"w": 0.12, "from": "top", "to": "upper"},
		],
	},
	{
		"id": "L3",
		"name": "Junction",
		"thesis": "feeders shuttle the hallway into the HUB; only the express climbs the loft",
		"intro": "An express spine (lobby - HUB - penthouse) and a hallway\nof rooms through the HUB junction: arms at the ends,\nstorage rooms beside the HUB. Execs (amber) appear at the\narms and want the penthouse, fast.\n\nEach arm also winds up the outside - but every climb ends\nin the SERVICE LOFT under the penthouse: one car in the\nwhole loft at a time. Direct routes all queue up there.\nOr: short feeder shuttles into the HUB, and only the\nexpress ever enters the loft. Watch riders transfer.",
		"rows": [
			"###R###", # row 9  penthouse (3,9)
			"#GGGGG#", # row 8  the service loft: ONE single-file gate corridor
			"#G#.#G#", # row 7  the climb tops belong to the loft...
			"#G#.#G#", # row 6  ...three floors deep on each side;
			"#G#.#G#", # row 5  the spine does not
			"#.#.#.#", # row 4
			"#RRRRR#", # row 3  arm (1,3), store (2,3), HUB (3,3), store (4,3), arm (5,3)
			"###.###", # row 2
			"###.###", # row 1
			"###R###", # row 0  lobby (3,0)
		],
		"cards": [
			{"name": "FEEDER A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "FEEDER B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			# The big fast car: 6 slots. The whole point of the level is who
			# gets to spend it - the spine (thesis) or one winding climb.
			{"name": "EXPRESS", "type": "express", "cap": 6, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 90,
		"max_lost": 6,
		"spawn": {"interval_start": 1.2, "interval_end": 0.65, "ramp": 90.0,
				"burst_min": 5, "burst_max": 7, "gap": 0.5},
		"mix": {"visitor": 0.30, "patient": 0.28, "exec": 0.42},
		"patience": {"exec": 14.0}, # dies queueing under the loft, lives on the hub hop
		"exec_origins": [Vector2i(1, 3), Vector2i(5, 3)],
		"exec_dests": [Vector2i(3, 9)],
		"groups": {
			"arms": [Vector2i(1, 3), Vector2i(5, 3)],
			"pent": [Vector2i(3, 9)],
			"lobby": [Vector2i(3, 0)],
			"hub": [Vector2i(3, 3)],
			"storage": [Vector2i(2, 3), Vector2i(4, 3)],
		},
		"trips": [
			# lobby<->arms and arm<->arm are two quick hub hops in the thesis;
			# direct winding networks haul them over the top instead. Penthouse
			# traffic keeps every direct route crossing the single-file loft.
			{"w": 0.22, "from": "lobby", "to": "arms"},
			{"w": 0.16, "from": "arms", "to": "lobby"},
			{"w": 0.10, "from": "arms", "to": "arms"},
			{"w": 0.16, "from": "lobby", "to": "pent"},
			{"w": 0.08, "from": "pent", "to": "lobby"},
			{"w": 0.08, "from": "pent", "to": "arms"},
			{"w": 0.06, "from": "arms", "to": "pent"},
			{"w": 0.06, "from": "storage", "to": "lobby"},
			{"w": 0.05, "from": "lobby", "to": "storage"},
			{"w": 0.02, "from": "lobby", "to": "hub"},
			{"w": 0.01, "from": "hub", "to": "lobby"},
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
