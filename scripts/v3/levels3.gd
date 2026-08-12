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
const POD_SPEED := 340.0
const CARGO_SPEED := 200.0

## THE CAR TYPE TABLE (v4 phase 2). One row per elevator kind; a level's card
## only has to name a `type` and everything else follows, so a card cannot
## claim a width its capacity does not match.
##
##   width    doorway units. Boarding rule (passenger.width <= car.width) AND
##            corridor rule (car.width <= corridor.width).
##   cap      capacity in WIDTH-UNITS. Default 2 * width (pod 2, standard 4,
##            cargo 6); a level may still override it explicitly - L2's and
##            L3's 6-seat width-2 cars predate this table and keep their number.
##   speed    max speed, px/s. SEPARATE axis from width: `express` is a fast
##            width-2 car, not a wider one, so speed and width can be ablated
##            independently (docs/v4-spec.md).
##   accel    px/s^2 the car ramps at; decel is DECEL_RATIO x that. Heavier =
##            wider = worse, which is what makes a stop cost momentum.
const CAR_TYPES := {
	"pod": {"width": 1, "speed": POD_SPEED, "accel": 560.0},
	"standard": {"width": 2, "speed": STANDARD_SPEED, "accel": 300.0},
	"express": {"width": 2, "speed": EXPRESS_SPEED, "accel": 300.0},
	"cargo": {"width": 3, "speed": CARGO_SPEED, "accel": 160.0},
}
const DECEL_RATIO := 1.25 # brakes bite a little harder than the motor pushes

## ACCELERATION MODEL (v4 ablation, docs/depth-report.md "Express ablation").
## How a car's ramp is derived, so accel-by-width can be compared against
## accel-by-speed-class WITHOUT editing the car table:
##   "width"       ramp is CAR_TYPES.accel (the shipped model). A width-2
##                 express and a width-2 standard share a ramp, so they differ
##                 only at cruise on a long leg.
##   "speed_slow"  faster car ramps SLOWER: accel = std_accel * STANDARD_SPEED
##                 / speed. The express (fast) crawls up to speed; the cargo
##                 (slow top speed) snaps to it. Decouples ramp from width.
##   "speed_fast"  faster car ramps FASTER: accel = std_accel * speed /
##                 STANDARD_SPEED. The express both tops out higher AND gets
##                 there quicker; the cargo is doubly sluggish.
## A card's explicit "accel" always wins; the shipped game leaves this "width".
static var accel_model := "width"

## RESTRICTED PLAY (v4 mechanic ablation, docs/depth-report.md). Forbid a
## mechanic so its best-achievable score can be measured with it vs without:
##   ""          nothing restricted (the shipped game).
##   "capacity"  every car is cut to the MINIMUM capacity that still lets its
##               widest legal party board (capacity = width, i.e. one "row"),
##               half the shipped 2*width. If the thesis still wins, the extra
##               capacity was chrome.
##   "accel"     acceleration is removed: cars snap to top speed (the pre-v4
##               instant model), so momentum costs nothing.
## Applied by card_capacity / card_accel below; the shipped game leaves it "".
static var restrict := ""


static func _card_type(card: Dictionary) -> Dictionary:
	return CAR_TYPES.get(str(card.get("type", "standard")), CAR_TYPES.standard)


static func card_width(card: Dictionary) -> int:
	return int(card.get("width", _card_type(card).width))


## Capacity in width-units: the card's own number, else 2 x width. Under the
## "capacity" restriction every car is cut to the minimum that still boards its
## widest legal party (= width), to measure whether the surplus mattered.
static func card_capacity(card: Dictionary) -> int:
	if restrict == "capacity":
		return card_width(card)
	return int(card.get("cap", 2 * card_width(card)))


static func card_speed(card: Dictionary) -> float:
	return float(card.get("speed", _card_type(card).speed))


static func card_accel(card: Dictionary) -> float:
	if restrict == "accel":
		return 1.0e5 # momentum removed: the car snaps to top speed (pre-v4)
	if card.has("accel"):
		return float(card.accel)
	var std_accel := float(CAR_TYPES.standard.accel)
	match accel_model:
		"speed_slow":
			return std_accel * STANDARD_SPEED / card_speed(card)
		"speed_fast":
			return std_accel * card_speed(card) / STANDARD_SPEED
		_:
			return float(_card_type(card).accel)


static func card_decel(card: Dictionary) -> float:
	return float(card.get("decel", card_accel(card) * DECEL_RATIO))

## static var (not const) so tools can swap the table wholesale for an
## experiment; the shipped game never writes it.
##
## v4 PHASE 2 RETUNE. Acceleration made every car slower - a standard loses
## ~0.8 s of momentum per stop, an express ~1.6 s - so the quotas, spawn
## intervals and patience numbers below were all re-measured against
## Scenarios3.SEEDS_TUNE until each level's axioms held again on the held-out
## SEEDS_ASSERT. L1 is the one level that needed NO retune: its thesis is
## already "few stops, long runs", which is exactly what acceleration rewards.
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
			# 8 seats. One perimeter lap is long enough that a small express
			# turns an ordinary burst into a second lap of waiting, which is
			# knife-edge rather than hard - and v4 acceleration made the lap
			# longer still (it brakes for every stop and for both ends of the
			# ping-pong), so the cabin has to hold a whole burst of execs. Six
			# seats measured as structurally short of the exec arrival rate:
			# the level then turned on which seeds bunched their bursts.
			{"name": "EXPRESS", "type": "express", "cap": 8, "speed": EXPRESS_SPEED,
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 95,
		"max_lost": 6,
		"spawn": {"interval_start": 1.45, "interval_end": 1.0, "ramp": 95.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.5},
		"mix": {"visitor": 0.42, "patient": 0.28, "exec": 0.30},
		# One perimeter lap is ~26 cells even at express speed - and since v4
		# acceleration, the express also brakes for every one of its stops and
		# for both ends of the ping-pong, which pushes a round trip past 35 s.
		# 50 s is the honest patience against THAT: an exec survives a full lap
		# of bad luck and still dies queueing behind a stop-everywhere tunnel
		# jam. (It was 28 s when a lap was ~26 s.)
		"patience": {"exec": 50.0},
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
		"quota": 116,
		"max_lost": 5,
		"spawn": {"interval_start": 0.88, "interval_end": 0.59, "ramp": 85.0,
				"burst_min": 4, "burst_max": 6, "gap": 0.45},
		"mix": {"visitor": 0.43, "patient": 0.42, "exec": 0.15},
		# The hallway crowd is impatient here (72 / 64 s against a thesis that
		# holds average waits near 12 s - a 6x margin, not a knife edge). It
		# is what turns a network with a slowly growing backlog into a LOSS
		# instead of a slow win: a plan that cannot keep up does not merely
		# finish late, it starts dropping people.
		# Execs get 44 s: their honest plan is TWO legs (feeder to the HUB,
		# express up), and two legs means two headways, both of which got
		# longer when v4 acceleration made every stop cost momentum. It still
		# expires an exec who has to wait out a car queueing under the loft.
		# (Was 55 / 48 / 32 s when cars reached top speed instantly; every
		# number here was re-measured against SEEDS_TUNE for the v4 physics.)
		"patience": {"visitor": 72.0, "patient": 64.0, "exec": 44.0},
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
		"spawn": {"interval_start": 0.98, "interval_end": 0.64, "ramp": 80.0,
				"burst_min": 4, "burst_max": 6, "gap": 0.5},
		"mix": {"visitor": 0.6, "patient": 0.4},
		# Generous enough that a WEAVING network never loses anybody; tight
		# enough that the extra lap-time of stopping at all eight rooms every
		# lap (>= 1.8 s of doors EACH, plus ~0.8 s of momentum since v4
		# acceleration - which is why the outer-lane loop got worse, not
		# better, and why these went 70/60 -> 76/64 with the crowd thinned).
		"patience": {"visitor": 76.0, "patient": 64.0},
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
		"id": "W-1",
		"name": "Freight",
		"thesis": "dedicate the cargo car to a freight shuttle; locals take the wings",
		"intro": "Two WINGS of rooms and a central FREIGHT SHAFT. Big\ndeliveries (three crates wide) ride the DOCK at the\nbottom up to the DELIVERY floor at the top and back -\nand ONLY the cargo car is wide enough to take them.\n\nThe honest first plan is three general lines that each\nsweep the whole building. It covers every room and it\nstrands the freight: the one cargo car spends its day\ncrawling a ten-stop milk run, so the crates pile up at\nthe dock and time out.\n\nGive the cargo car ONE job - the dock-to-delivery\nshuttle - and let the two locals run the wings.",
		"rows": [
			"R.R.R", # row6  W(0,6)  DELIVERY(2,6)  E(4,6)
			".....", # row5
			"R...R", # row4  (0,4) | (4,4)
			".....", # row3
			"R...R", # row2  (0,2) | (4,2)
			".....", # row1
			"R.R.R", # row0  W(0,0)  DOCK(2,0)  E(4,0)
		],
		"cards": [
			{"name": "LOCAL A", "type": "standard",
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "LOCAL B", "type": "standard",
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "FREIGHT", "type": "cargo",
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 80,
		"max_lost": 5,
		"spawn": {"interval_start": 1.5, "interval_end": 1.1, "ramp": 90.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.6},
		"mix": {"visitor": 0.34, "patient": 0.28, "big delivery": 0.38},
		# Big deliveries are patient on their own; what dooms the naive plan is
		# that its shared cargo car serves them slower than they arrive, so the
		# dock queue grows without bound until it times them out no matter the
		# patience. The dedicated shuttle serves them faster than they arrive.
		"patience": {"big delivery": 95.0},
		"exec_origins": [],
		"exec_dests": [],
		# Big deliveries run the dock<->delivery freight lane and nothing else.
		"type_rooms": {"big delivery": {
				"from": [Vector2i(2, 0), Vector2i(2, 6)],
				"to": [Vector2i(2, 6), Vector2i(2, 0)]}},
		"groups": {
			"west": [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 6)],
			"east": [Vector2i(4, 0), Vector2i(4, 2), Vector2i(4, 4), Vector2i(4, 6)],
			"dock": [Vector2i(2, 0)],
			"delivery": [Vector2i(2, 6)],
		},
		"trips": [
			# Each wing is its own commute; the freight lane is the type_rooms
			# above. No wing-to-wing demand - the wings share no car in the
			# thesis, so a cross trip would be unservable there.
			{"w": 0.5, "from": "west", "to": "west"},
			{"w": 0.5, "from": "east", "to": "east"},
		],
	},
	{
		"id": "W-2",
		"name": "Narrows",
		"thesis": "run the pod through the narrows; send the wide cars the long way",
		"intro": "The centre of the building is a NARROWS - a single-file\nshaft one cell wide, so only the slim POD fits it. It is\nthe short, fast line between the lobby and the roof.\n\nAmber commuters (hasty) rush LOBBY<->ROOF up the middle;\nCOUPLES (two-wide, they board only a full-size car)\ncommute the corners and can never use the narrows.\n\nThe safe-looking plan sends all three cars the long way\nround the perimeter - nobody times out on the couples,\nbut the middle rush dies waiting for a full lap. Instead:\nput the POD on the narrows for the rush, and weave the\ntwo wide cars round the outside for the couples.",
		"rows": [
			"R..R..R", # row6  UL(0,6)  UC(3,6)  UR(6,6)
			"...1...", # row5  narrows (3,5)
			"...1...", # row4  narrows (3,4)
			"...1...", # row3  narrows (3,3)
			"...1...", # row2  narrows (3,2)
			"...1...", # row1  narrows (3,1)
			"R..R..R", # row0  LL(0,0)  LC(3,0)  LR(6,0)
		],
		"cards": [
			{"name": "POD", "type": "pod",
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "CAR B", "type": "standard",
					"color": Color(0.5, 0.88, 0.55)},
			{"name": "CAR C", "type": "standard",
					"color": Color(0.98, 0.68, 0.2)},
		],
		"quota": 78,
		"max_lost": 5,
		"spawn": {"interval_start": 1.4, "interval_end": 1.0, "ramp": 90.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.55},
		"mix": {"exec": 0.34, "couple": 0.66},
		# The rush is hasty (the narrows shortcut is ~a third of a perimeter
		# lap): 30 s survives one pod turnaround but not a full outer lap.
		# Couples are patient - the two wide cars keep up with them either way,
		# so the couples are NOT the differentiator; the middle rush is.
		"patience": {"exec": 30.0, "couple": 95.0},
		# The lobby<->roof rush uses ONLY the central narrows lane.
		"exec_origins": [Vector2i(3, 0), Vector2i(3, 6)],
		"exec_dests": [Vector2i(3, 6), Vector2i(3, 0)],
		"groups": {
			"low": [Vector2i(0, 0), Vector2i(6, 0)],
			"high": [Vector2i(0, 6), Vector2i(6, 6)],
			"mid_low": [Vector2i(3, 0)],
			"mid_high": [Vector2i(3, 6)],
		},
		"trips": [
			# The couples cross the building corner-to-corner (perimeter only).
			{"w": 0.5, "from": "low", "to": "high"},
			{"w": 0.5, "from": "high", "to": "low"},
		],
	},
	{
		"id": "W-3",
		"name": "Momentum",
		"thesis": "give the hauler one long nonstop run; let the pods do the local hops",
		"intro": "A tall tower with a clear EXPRESS SHAFT beside the rooms.\nMost of the crowd rides LOBBY<->PENTHOUSE end to end; the\nrest are short local hops between neighbouring floors.\n\nThe HAULER is heavy: it takes an age to get moving and an\nage to stop, so every extra stop costs it dearly. Run all\nthree cars stopping at every floor and the hauler never\ngets up to speed, and the end-to-end crowd crawls.\n\nInstead: send the hauler up the express shaft in ONE\nunbroken run, lobby to penthouse, where its momentum\nfinally pays - and let the sharp little pods dart between\nthe local floors.",
		"rows": [
			"R..", # row10  PENTHOUSE (0,10)
			"...", # row9
			"R..", # row8  (0,8)
			"...", # row7
			"R..", # row6  (0,6)
			"...", # row5
			"R..", # row4  (0,4)
			"...", # row3
			"R..", # row2  (0,2)
			"...", # row1
			"R..", # row0  LOBBY (0,0)
		],
		"cards": [
			{"name": "HAULER", "type": "cargo",
					"color": Color(0.98, 0.68, 0.2)},
			{"name": "POD A", "type": "pod",
					"color": Color(0.45, 0.68, 0.95)},
			{"name": "POD B", "type": "pod",
					"color": Color(0.5, 0.88, 0.55)},
		],
		"quota": 78,
		"max_lost": 5,
		"spawn": {"interval_start": 1.35, "interval_end": 1.0, "ramp": 90.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.55},
		"mix": {"visitor": 0.58, "patient": 0.42},
		# The end-to-end crowd is what a stop-everywhere plan starves: on the
		# nonstop express leg they arrive inside 25 s, on a six-stop crawl they
		# do not. Locals are patient - the pods clear them either way.
		"patience": {"visitor": 46.0, "patient": 40.0},
		"exec_origins": [],
		"exec_dests": [],
		"groups": {
			"lobby": [Vector2i(0, 0)],
			"pent": [Vector2i(0, 10)],
			"lower": [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 4)],
			"upper": [Vector2i(0, 6), Vector2i(0, 8), Vector2i(0, 10)],
		},
		"trips": [
			# The heavy end-to-end tide the express leg is FOR...
			{"w": 0.26, "from": "lobby", "to": "pent"},
			{"w": 0.26, "from": "pent", "to": "lobby"},
			# ...and the local hops the pods pick up, split into two halves that
			# never cross (so the pods never need to meet in the middle).
			{"w": 0.24, "from": "lower", "to": "lower"},
			{"w": 0.24, "from": "upper", "to": "upper"},
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
		"quota": 75,
		"max_lost": 6,
		"spawn": {"interval_start": 2.15, "interval_end": 1.5, "ramp": 110.0,
				"burst_min": 3, "burst_max": 5, "gap": 0.6},
		"mix": {"visitor": 0.55, "patient": 0.45},
		# The sandbox's lines are long and stop at everything, and since
		# acceleration every one of those stops costs momentum: a room can go
		# two slow laps between visits. The crowd is patient enough to survive
		# that, and the level's difficulty lives in the queue it builds instead.
		"patience": {"visitor": 130.0, "patient": 115.0},
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


## PAGED WORLDS ("superlevels") for the level select. Each world is a title
## plus the ids it contains, IN PLAY ORDER — an explicit table so the select
## never has to guess a grouping from id prefixes. select3.gd shows ONE world
## at a time and pages between them. Every LEVELS id must appear in exactly one
## world (X-1 closes out PATH).
const WORLDS := [
	{"name": "PATH", "levels": ["L1", "L2", "L3", "L4", "X-1"]},
	{"name": "WIDTH", "levels": ["W-1", "W-2", "W-3"]},
]


static func get_level(i: int) -> Dictionary:
	if injected != null:
		return injected
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


# ------------------------------------------------------ briefing (v4 phase 1)
#
# The BRIEFING screen is GENERATED from the very fields the simulation reads —
# `cards` for the roster, `mix` + `patience` + `exec_*` for the crowd, `spawn`
# for the pace, `quota`/`max_lost` for the goal. Nothing about a level is
# described twice, so a briefing cannot drift from what actually spawns; the
# only hand-written string it shows is the level's own thesis line.
# tests/balance.gd lints every level against this (see _briefing_check).
#
# The UI pass (docs/ui-pass-spec.md §2) made these COMPACT: the multi-paragraph
# `intro` is no longer rendered (the field survives in the data for anything
# that still wants it), the roster is one terse line per car that only names a
# trait when it differs from standard, and the crowd/pace lines are shortened
# to ~10-12 total. The balance-suite briefing lint checks the SHORT text, so it
# cannot rot into a no-op: every card name, spawnable type and goal number must
# still appear.

## Speed trait, only when it differs from the standard car (else ""). Derived
## from the card's own number so it can never claim a class the car is not.
static func speed_tag(speed: float) -> String:
	var r := speed / STANDARD_SPEED
	if r >= 1.5:
		return "fast"
	if r <= 0.75:
		return "slow"
	return ""


## Ramp trait, only when it differs from a standard ramp (else ""). Derived
## from the card's own acceleration.
static func accel_tag(a: float) -> String:
	var std := float(CAR_TYPES.standard.accel)
	if a >= std * 1.5:
		return "sharp"
	if a <= std * 0.7:
		return "sluggish"
	return ""


## One terse roster line per car: `NAME · type · wN · C · <trait(s)>`. Speed
## and ramp only surface when non-default, so a plain standard reads `CAR A ·
## standard · w2 · 4` and the express reads `EXPRESS · express · w2 · 4 · fast`.
## Every number is read back through the same accessors Car3.setup uses.
static func roster_line_short(c: Dictionary) -> String:
	var bits: Array = [str(c.name), str(c.type), "w%d" % card_width(c),
			str(card_capacity(c))]
	var st := speed_tag(card_speed(c))
	if st != "":
		bits.append(st)
	var at := accel_tag(card_accel(c))
	if at != "":
		bits.append(at)
	return " · ".join(bits)


static func roster_lines_short(lv: Dictionary) -> Array:
	var out: Array = []
	for c in lv.cards:
		out.append(roster_line_short(c))
	return out


## One terse crowd line per spawnable type: `visitor 43% · w1 · 72s`, with a
## routing tail only where a type is pinned to its own rooms (execs, or a v4
## `type_rooms` freight lane): `exec 15% · w1 · 44s · B/F→G`. A type with an
## exec weight but no exec rooms degrades to a visitor at spawn time, so it is
## not advertised here either.
static func people_lines_short(lv: Dictionary) -> Array:
	var mix: Dictionary = lv.mix
	var total := 0.0
	for t in mix:
		total += maxf(0.0, float(mix[t]))
	var out: Array = []
	for t in mix:
		if float(mix[t]) <= 0.0 or total <= 0.0:
			continue
		if t == "exec" and (lv.exec_origins.is_empty() or lv.exec_dests.is_empty()):
			continue
		var pat := float(Passenger3.PTYPES.get(t, {}).get("patience", 90.0))
		if lv.has("patience"):
			pat = float(lv.patience.get(t, pat))
		var line := "%s %.0f%% · w%d · %.0fs" % [t, 100.0 * float(mix[t]) / total,
				int(Passenger3.PTYPES.get(t, {}).get("width", 1)), pat]
		var tr: Dictionary = lv.get("type_rooms", {})
		if tr.has(t):
			line += " · %s→%s" % [_rooms_letters(tr[t].from), _rooms_letters(tr[t].to)]
		elif t == "exec":
			line += " · %s→%s" % [
					_rooms_letters(lv.exec_origins), _rooms_letters(lv.exec_dests)]
		out.append(line)
	return out


## Room cells as their bare on-grid letters ("B/F"). Needs the maze loaded.
static func _rooms_letters(cells: Array) -> String:
	var parts: Array = []
	for c in cells:
		parts.append(Grid3.room_letter(c))
	return "/".join(parts)


## Average spawn pace, short: `Bursts of 4-6, every 0.9s→0.6s`.
static func pace_line_short(lv: Dictionary) -> String:
	var s: Dictionary = lv.spawn
	return "Bursts of %d-%d, every %.1fs→%.1fs" % [int(s.burst_min), int(s.burst_max),
			float(s.interval_start), float(s.interval_end)]


## The whole briefing body (hud3.show_briefing renders this verbatim). Compact:
## thesis + roster + crowd + pace + goal, no flavour paragraph. ~10-12 lines.
static func briefing_body(lv: Dictionary) -> String:
	var L: Array = []
	if str(lv.get("thesis", "")) != "":
		L.append("\"%s\"" % lv.thesis)
		L.append("")
	L.append("YOUR ELEVATORS")
	L.append_array(roster_lines_short(lv))
	L.append("")
	L.append("WHO SHOWS UP")
	L.append_array(people_lines_short(lv))
	L.append(pace_line_short(lv))
	L.append("")
	L.append("GOAL: serve %d before losing %d." % [int(lv.quota), int(lv.max_lost)])
	return "\n".join(L)


static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i].id == id:
			return i
	return -1
