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
## (scenario routes pre-drawn from Scenarios3, canonical seed, no editing);
## "best" = the same, with the route-set the depth search found (Discovered3).
static var watch_strategy := ""

## TRUE while a headless harness (tools/sim_api.gd) is driving the game, so the
## HUD builds no UI at all. It has to be a STATIC, not a field on main3: child
## _ready runs BEFORE the parent's, so hud3._ready has already built its ~23
## Controls by the time main3._ready could tell it not to.
##
## Why it matters (the full-run failure of 2026-08-12): every Control and
## CanvasItem that enters the tree pushes a deferred callable
## (Control::_update_minimum_size, _clear_size_warning, CanvasItem::
## _redraw_callback) onto the GLOBAL MessageQueue, which is only drained at the
## end of an engine frame. A search runs thousands of sessions inside ONE
## frame, so the queue only grows — and every message's target is freed by the
## next teardown. See tools/sim_api.gd for the full note.
static var headless := false

## A full level Dictionary to run INSTEAD of the table entry, or null. The
## search tools (tools/sim_api.gd) use this to simulate generated or
## parameterised levels without touching LEVELS (appending would make them
## show up in the level select and shift every `current` index). Always reset
## it to null after a run.
static var injected = null

const STANDARD_SPEED := 260.0
const EXPRESS_SPEED := 520.0

## static var (not const) so tools can swap the table wholesale for an
## experiment; the shipped game never writes it.
static var LEVELS := [
	{
		"id": "L1",
		"name": "Tower",
		"thesis": "one local per wing, and the express spine belongs to the execs",
		"intro": "A tower with TWO WINGS and a sealed EXPRESS SPINE. The\nwings only meet the spine down in the LOBBY, so nothing\ncan serve both a wing and the penthouse without driving\nthe whole tower.\n\nExecs (amber, hasty) appear in the LOBBY and want the\nPENTHOUSE. Visitors and patients shuttle between the\nlobby and their own wing; a few cross from wing to wing\nand have to change cars in the lobby.\n\nOne long line that reaches everything looks efficient and\nis the trap: it is the fastest plan on paper for every\nsingle rider, so EVERY rider queues for it. Give each\nwing its own car and leave the spine to the execs.",
		"rows": [
			"..#R#..", # row 9  penthouse (3,9) - spine only
			"R.#.#.R", # row 8  west wing (0,8) | east wing (6,8)
			"..#.#..", # row 7
			"R.#.#.R", # row 6  (0,6) | (6,6)
			"..#.#..", # row 5
			"R.#.#.R", # row 4  (0,4) | (6,4)
			"..#.#..", # row 3
			"R.#.#.R", # row 2  (0,2) | (6,2)
			"..#.#..", # row 1
			"...R...", # row 0  lobby (3,0) - the ONLY junction in the building
		],
		"cards": [
			{"name": "LOCAL A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "LOCAL B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 90,
		"max_lost": 5,
		"spawn": {"interval_start": 1.4, "interval_end": 1.0, "ramp": 100.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.6},
		"mix": {"visitor": 0.45, "patient": 0.30, "exec": 0.25},
		"patience": {"exec": 24.0}, # hasty enough that a locals-clogged tower loses them
		"exec_origins": [Vector2i(3, 0)],
		"exec_dests": [Vector2i(3, 9)],
		"groups": {
			"lobby": [Vector2i(3, 0)],
			"pent": [Vector2i(3, 9)],
			"west": [Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 6), Vector2i(0, 8)],
			"east": [Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 6), Vector2i(6, 8)],
		},
		"trips": [
			# Two self-contained wing commutes plus a wing-to-wing trickle whose
			# only honest plan is "ride down, change in the lobby, ride up".
			{"w": 0.22, "from": "lobby", "to": "west"},
			{"w": 0.22, "from": "west", "to": "lobby"},
			{"w": 0.22, "from": "lobby", "to": "east"},
			{"w": 0.22, "from": "east", "to": "lobby"},
			{"w": 0.05, "from": "west", "to": "east"},
			{"w": 0.05, "from": "east", "to": "west"},
			{"w": 0.02, "from": "pent", "to": "lobby"}, # sparse trickle back down
		],
	},
	{
		"id": "L2",
		"name": "Detour",
		"thesis": "spend the gate on a cross shuttle; execs ride the perimeter express",
		"intro": "Two CLUSTERS of rooms, two cells wide - and between them\na 4-cell GATE CORRIDOR: one car in the whole tunnel at a\ntime. The gate-free perimeter is the long way around.\n\nThe cluster crowds (B-E <-> F-I) MUST cross; the tunnel\nis their only sane path. Execs (amber, hasty) pop up at\nthe BOTTOM and want the TOP.\n\nThreading every room AND the tunnel with all three cars\nlooks thorough and is the trap - three cars queueing for\na single-file corridor. Instead: spend the gate on ONE\ndedicated cross shuttle, weave a local through the lower\ncluster, and send the express the long way round.",
		"rows": [
			"R.......", # row 9  top room (0,9) - on the perimeter
			"RR#####.", # row 8  upper cluster (0,8),(1,8)
			"RR#####.", # row 7  upper cluster (0,7),(1,7)
			"G######.", # row 6  gate corridor (0,3)..(0,6): ONE mutex, 4 cells
			"G######.", # row 5
			"G######.", # row 4
			"G######.", # row 3
			"RR#####.", # row 2  lower cluster (0,2),(1,2)
			"RR#####.", # row 1  lower cluster (0,1),(1,1)
			"R.......", # row 0  bottom room (0,0) - on the perimeter
		],
		"cards": [
			{"name": "CAR A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "CAR B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			# 6 seats: one perimeter lap is long enough that a 4-seat express
			# turns an ordinary burst into a second lap of waiting, which is
			# knife-edge rather than hard.
			{"name": "EXPRESS", "type": "express", "cap": 6, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 105,
		"max_lost": 6,
		"spawn": {"interval_start": 1.2, "interval_end": 0.82, "ramp": 95.0,
				"burst_min": 3, "burst_max": 6, "gap": 0.5},
		"mix": {"visitor": 0.42, "patient": 0.28, "exec": 0.30},
		# One perimeter lap is ~26 cells even at express speed, so 28 s is the
		# honest patience here: an exec survives a full lap of bad luck and
		# still dies queueing behind a stop-everywhere tunnel jam.
		"patience": {"exec": 28.0},
		"exec_origins": [Vector2i(0, 0)],
		"exec_dests": [Vector2i(0, 9)],
		"groups": {
			"bottom": [Vector2i(0, 0)],
			"top": [Vector2i(0, 9)],
			"lower": [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
			"upper": [Vector2i(0, 7), Vector2i(1, 7), Vector2i(0, 8), Vector2i(1, 8)],
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
		"thesis": "both feeders run arm->HUB->lobby; only the express climbs the loft",
		"intro": "An express spine (lobby - HUB - penthouse) and a hallway\nof rooms through the HUB junction: arms at the ends,\nstorage rooms beside the HUB. Execs (amber) appear at the\narms and want the penthouse, fast.\n\nEach arm also winds up the outside - but every climb ends\nin the SERVICE LOFT under the penthouse: one car in the\nwhole loft at a time. Three lines that all climb spend\ntheir day queueing under the penthouse, and an arm rider\nwho only wants the LOBBY gets taken over the roof.\n\nOr: run each feeder arm -> HUB -> lobby so it serves its\nown half of the building on its own, and let the express\nbe the only car that ever enters the loft. Watch riders\ntransfer at the HUB.",
		"rows": [
			"###R###", # row 9  penthouse (3,9)
			"#GGGGG#", # row 8  the service loft: ONE single-file gate corridor
			"#G#.#G#", # row 7  the climb tops belong to the loft...
			"#G#.#G#", # row 6  ...FOUR floors deep on each side, so a direct
			"#G#.#G#", # row 5  climb holds the whole tunnel for ~2.5 s a pass;
			"#G#.#G#", # row 4  the spine only clips its last cell
			"#RRRRR#", # row 3  arm (1,3), store (2,3), HUB (3,3), store (4,3), arm (5,3)
			"###.###", # row 2
			"###.###", # row 1
			"###R###", # row 0  lobby (3,0)
		],
		"cards": [
			# SIX seats each. The hallway crowd is the bulk of this building and
			# a feeder is a short line, so seats are what it converts into
			# throughput. A winding climb cannot: its limit is lap time and the
			# loft mutex, and no number of seats shortens either.
			{"name": "FEEDER A", "type": "standard", "cap": 6, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "FEEDER B", "type": "standard", "cap": 6, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			# Fast, but only FOUR slots. That is the level's real budget: the
			# spine is the one car that can cross the loft without queueing,
			# and it has four seats. A network that routes the whole hallway
			# over the roof spends every one of them on riders who only wanted
			# to go downstairs.
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 145,
		"max_lost": 5,
		"spawn": {"interval_start": 0.72, "interval_end": 0.46, "ramp": 85.0,
				"burst_min": 4, "burst_max": 6, "gap": 0.45},
		"mix": {"visitor": 0.43, "patient": 0.42, "exec": 0.15},
		# The hallway crowd is impatient here (55 / 48 s against a thesis that
		# holds average waits near 7 s - an 8x margin, not a knife edge). It
		# is what turns a network with a slowly growing backlog into a LOSS
		# instead of a slow win: a plan that cannot keep up does not merely
		# finish late, it starts dropping people.
		# Execs get 32 s: their honest plan is TWO legs (feeder to the HUB,
		# express up), and two legs means two headways - 22 s made the
		# INTENDED plan a coin flip, which is knife-edge, not hard. 32 s
		# still expires an exec who has to wait out a car queueing under
		# the loft.
		"patience": {"visitor": 55.0, "patient": 48.0, "exec": 32.0},
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
			# MOST of the building's traffic never wants the penthouse at all: it
			# is hallway <-> lobby, and that is deliberate. A feeder that runs
			# arm -> HUB -> lobby serves it in ONE leg. A winding climb serves it
			# by carrying the rider over the roof and handing them to the spine -
			# two legs, both of them the length of the building.
			{"w": 0.24, "from": "lobby", "to": "arms"},
			{"w": 0.22, "from": "arms", "to": "lobby"},
			{"w": 0.10, "from": "arms", "to": "arms"},
			{"w": 0.13, "from": "storage", "to": "lobby"},
			{"w": 0.12, "from": "lobby", "to": "storage"},
			{"w": 0.07, "from": "lobby", "to": "pent"},
			{"w": 0.05, "from": "pent", "to": "lobby"},
			{"w": 0.04, "from": "pent", "to": "arms"},
			{"w": 0.02, "from": "arms", "to": "pent"},
			{"w": 0.01, "from": "lobby", "to": "hub"},
			{"w": 0.01, "from": "hub", "to": "lobby"},
		],
	},
	{
		"id": "L4",
		"name": "Ring",
		"thesis": "weave the lane: a loop only swings outside for the rooms it serves",
		"intro": "A ring with TWO lanes: the OUTER lane runs past every\nroom, the INNER lane runs past none of them.\n\nEvery commute crosses the building - homes (bottom) to\ncanteen (top), offices (right) to lounge (left) - so half\na lap is the shortest trip anyone takes.\n\nDrag a route all the way around and back onto its FIRST\ncell to CLOSE it into a LOOP: closed routes run one-way\nforever (chevrons show the direction) instead of\nping-ponging. But a loop that hugs the outer lane stops\nat all EIGHT rooms every lap, and doors are slow. WEAVE:\nswing out for your own crowd, take the inner lane past\neverybody else's.",
		"rows": [
			"..R..R..", # row 7  canteen (2,7),(5,7)
			"........", # row 6  the INNER lane's top straight - no rooms
			"R.####.R", # row 5  lounge (0,5) | offices (7,5)
			"..####..", # row 4
			"..####..", # row 3
			"R.####.R", # row 2  lounge (0,2) | offices (7,2)
			"........", # row 1  the INNER lane's bottom straight
			"..R..R..", # row 0  homes (2,0),(5,0)
		],
		"cards": [
			{"name": "CAR A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "CAR B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 110,
		"max_lost": 4,
		"spawn": {"interval_start": 0.85, "interval_end": 0.55, "ramp": 80.0,
				"burst_min": 4, "burst_max": 6, "gap": 0.5},
		"mix": {"visitor": 0.6, "patient": 0.4},
		# Generous enough that a WEAVING network never loses anybody; tight
		# enough that the extra lap-time of stopping at all eight rooms every
		# lap (>= 1.8 s of doors each) turns into expiries.
		"patience": {"visitor": 70.0, "patient": 60.0},
		"exec_origins": [],
		"exec_dests": [],
		"groups": {
			"homes": [Vector2i(2, 0), Vector2i(5, 0)],
			"offices": [Vector2i(7, 2), Vector2i(7, 5)],
			"canteen": [Vector2i(2, 7), Vector2i(5, 7)],
			"lounge": [Vector2i(0, 2), Vector2i(0, 5)],
		},
		"trips": [
			# EVERY commute crosses the building: bottom <-> top and left <->
			# right are both HALF A LAP apart whichever way you go round. That is
			# the level. A short arc shuttle cannot serve a half-lap trip at all,
			# an open ping-pong line passes any room heading the right way only
			# once per DOUBLE lap - and a closed loop that hugs the outer lane
			# pays eight door cycles a lap to do it.
			{"w": 0.24, "from": "homes", "to": "canteen"},
			{"w": 0.24, "from": "canteen", "to": "homes"},
			{"w": 0.20, "from": "offices", "to": "lounge"},
			{"w": 0.20, "from": "lounge", "to": "offices"},
			# A quarter-lap trickle, so the two commutes are not two disjoint
			# levels and somebody has to carry the transfer.
			{"w": 0.06, "from": "homes", "to": "offices"},
			{"w": 0.06, "from": "lounge", "to": "homes"},
		],
	},
	{
		"id": "X-1",
		"name": "Sandbox",
		"thesis": "the original maze - no thesis, just the toys, at a pace that bites",
		"intro": "Draw each elevator's route as a line through the maze.\nRooms (lettered) on a route become its stops; passengers\ntransfer between routes at shared rooms automatically.\nStriped GATE cells let only one car through at a time.\n\nNo thesis here, just the toys - but the crowd is real.\nCovering all thirteen rooms is not the same as serving\nthem, and this maze charges you for every detour.",
		"rows": Grid3.MAZE,
		"cards": [
			{"name": "LOCAL A", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "LOCAL B", "type": "standard", "cap": 4, "speed": STANDARD_SPEED,
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "EXPRESS", "type": "express", "cap": 4, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 90,
		"max_lost": 6,
		"spawn": {"interval_start": 1.6, "interval_end": 1.1, "ramp": 110.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.6},
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
	if injected != null:
		return injected
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i].id == id:
			return i
	return -1
