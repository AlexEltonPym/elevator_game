class_name Levels5
extends RefCounted
## Data-driven level table for the v5 "Rooms" feel-prototype. Four hand-made,
## feel-focused levels (NO axioms / verification — see docs/v5-rooms-spec.md).
##
## A v5 level is a mostly-EMPTY grid with a handful of multi-cell ROOMS placed
## in the open. Elevators never enter a room; they run in the open cells beside
## it. Each room carries AUTHORED dropoff points (like a door on a specific
## side): a dropoff is a room cell plus a facing direction, and the open cell it
## faces into (cell + dir) is the DOCK CELL. An elevator SERVES a room iff its
## drawn route passes through one of that room's dock cells — adjacency to a
## non-dropoff part of the room does nothing. A room with one dropoff is a real
## placement constraint; a room with several can be served from several spots
## and by several lifts (a transfer / hub). Rooms get letters A, B, C... in list
## order; trips reference those letters.
##
## Each entry:
##   id / name / thesis / intro   flavour + briefing text
##   cols / rows                  grid dimensions (y up, row 0 = bottom)
##   blocked                      optional Array[Vector2i] of walls (# cells)
##   rooms  Array of {type, cells:Array[Vector2i],
##                    drops:Array[{cell:Vector2i, dir:Vector2i}]}  letter = order
##   cards  Array of {name, type, color}             the ROSTER (1..3)
##   quota / max_lost             win / lose thresholds
##   spawn                        pulse spawner config (same shape as v3)
##   mix                          passenger type weights (Passenger5.PTYPES)
##   trips                        Array of {w, from, to} between room LETTERS

static var current := 0

## TRUE while a headless driver (the smoke test) runs the game, so the HUD
## builds no UI — a Control entering the tree queues deferred callables that
## only an engine frame drains. Mirrors Levels3.headless.
static var headless := false

const ROOM_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

## Dropoff facing shorthands (dir points from the room cell into open space).
const R := Vector2i(1, 0)
const L := Vector2i(-1, 0)
const U := Vector2i(0, 1)
const D := Vector2i(0, -1)

## Card colours reused so the roster reads at a glance.
const COL_A := Color(0.45, 0.68, 0.95)
const COL_B := Color(0.5, 0.88, 0.55)
const COL_C := Color(0.98, 0.68, 0.2)

const LEVELS := [
	{
		"id": "R-1",
		"name": "One Lift",
		"thesis": "one lift, three rooms - draw a line past them all",
		"intro": "Rooms are areas now, not dots. An elevator never enters a\nroom; it runs in the open cells BESIDE it. Draw one route\nup the shaft past all three rooms and press RUN - any cell\nnext to a room can drop people off there.",
		"cols": 5, "rows": 7,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 3), Vector2i(1, 3)],
					"drops": [{"cell": Vector2i(1, 3), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 6), Vector2i(1, 6)],
					"drops": [{"cell": Vector2i(1, 6), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
		],
		"quota": 10, "max_lost": 8,
		"spawn": {"interval_start": 3.0, "interval_end": 2.6, "ramp": 50.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.0},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.30, "from": "A", "to": "B"},
			{"w": 0.30, "from": "A", "to": "C"},
			{"w": 0.15, "from": "B", "to": "A"},
			{"w": 0.15, "from": "C", "to": "A"},
			{"w": 0.05, "from": "B", "to": "C"},
			{"w": 0.05, "from": "C", "to": "B"},
		],
	},
	{
		"id": "R-2",
		"name": "Double Duty",
		"thesis": "one column can serve two rooms at once - find the cell that touches both",
		"intro": "A route cell that sits BETWEEN two rooms serves them both.\nRun the shaft up the middle: the cell beside both offices\ndrops people at either one, so a single line covers the\nwhole building. One route, double duty.",
		"cols": 5, "rows": 6,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "office", "cells": [Vector2i(3, 4), Vector2i(4, 4)],
					"drops": [{"cell": Vector2i(3, 4), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
		],
		"quota": 12, "max_lost": 8,
		"spawn": {"interval_start": 2.8, "interval_end": 2.4, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 0.7, "patient": 0.3},
		"trips": [
			{"w": 0.30, "from": "A", "to": "B"},
			{"w": 0.30, "from": "A", "to": "C"},
			{"w": 0.15, "from": "B", "to": "A"},
			{"w": 0.15, "from": "C", "to": "A"},
			{"w": 0.05, "from": "B", "to": "C"},
			{"w": 0.05, "from": "C", "to": "B"},
		],
	},
	{
		"id": "R-3",
		"name": "Crossing",
		"thesis": "two lifts share the atrium - ride in, cross over, ride on",
		"intro": "The atrium (T) is a TRANSFER room: two different lifts run\nbeside it. Give the blue lift the left column past A and\nthe atrium; give the green lift the right column past the\natrium and B. A crowd rides in, crosses the atrium, and\nrides out on the other lift.",
		"cols": 7, "rows": 7,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(3, 3), Vector2i(4, 3)],
					"drops": [
						{"cell": Vector2i(3, 3), "dir": L},
						{"cell": Vector2i(4, 3), "dir": R}]},
			{"type": "office", "cells": [Vector2i(5, 6), Vector2i(6, 6)],
					"drops": [{"cell": Vector2i(5, 6), "dir": L}]},
		],
		"cards": [
			{"name": "BLUE", "type": "standard", "color": COL_A},
			{"name": "GREEN", "type": "standard", "color": COL_B},
		],
		# CROWD STRESS (v5.1g): spawn is cranked WAY up so the rooms overflow into
		# multiple isometric rows — a visual load test for the crowd packer. With so
		# many arrivals two lifts can't keep pace, so R-3 is NOT expected to win here
		# (max_lost is set high so it keeps running and piling instead of ending).
		"quota": 24, "max_lost": 400,
		"spawn": {"interval_start": 0.5, "interval_end": 0.4, "ramp": 20.0,
				"burst_min": 4, "burst_max": 8, "gap": 0.15},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.44, "from": "A", "to": "C"},
			{"w": 0.30, "from": "C", "to": "A"},
			{"w": 0.08, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.06, "from": "C", "to": "B"},
			{"w": 0.06, "from": "B", "to": "C"},
		],
	},
	{
		"id": "R-4",
		"name": "Big Store",
		"thesis": "a department store, offices and a cafe - lots of empty grid, route it your way",
		"intro": "The department store (D) is one big 2x3 room; a route beside\nANY of its cells serves it. Three lifts, plenty of open\nspace, no single right answer. Cover the lobby, the store,\nthe two offices and the cafe however you like.",
		"cols": 8, "rows": 8,
		"rooms": [
			{"type": "store", "cells": [
					Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1),
					Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)],
					"drops": [
						{"cell": Vector2i(1, 1), "dir": L},
						{"cell": Vector2i(2, 1), "dir": R},
						{"cell": Vector2i(2, 2), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0)],
					"drops": [
						{"cell": Vector2i(5, 0), "dir": L},
						{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "office", "cells": [Vector2i(6, 5), Vector2i(7, 5)],
					"drops": [{"cell": Vector2i(6, 5), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(3, 7), Vector2i(4, 7)],
					"drops": [{"cell": Vector2i(3, 7), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT A", "type": "standard", "color": COL_A},
			{"name": "LIFT B", "type": "standard", "color": COL_B},
			{"name": "LIFT C", "type": "standard", "color": COL_C},
		],
		"quota": 18, "max_lost": 10,
		"spawn": {"interval_start": 2.6, "interval_end": 2.1, "ramp": 65.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.8},
		"mix": {"visitor": 0.7, "patient": 0.3},
		"trips": [
			{"w": 0.20, "from": "B", "to": "A"},
			{"w": 0.16, "from": "A", "to": "B"},
			{"w": 0.12, "from": "B", "to": "C"},
			{"w": 0.10, "from": "C", "to": "B"},
			{"w": 0.12, "from": "B", "to": "D"},
			{"w": 0.10, "from": "D", "to": "B"},
			{"w": 0.10, "from": "A", "to": "E"},
			{"w": 0.10, "from": "E", "to": "B"},
		],
	},
	{
		"id": "R-5",
		"name": "Bottleneck",
		"thesis": "one width-2 corridor, two lifts - only one fits, so they take turns",
		"intro": "Walls pinch the middle to a single striped CORRIDOR. It is
width 2 - room for exactly ONE normal lift at a time. Both
lifts must thread it to reach the far side, so when they meet
one waits at the mouth while the other passes. Send BLUE up
the centre past A and B; send GREEN from C, through the
corridor, on to D.",
		"cols": 6, "rows": 7,
		"blocked": [Vector2i(0, 3), Vector2i(1, 3), Vector2i(3, 3), Vector2i(4, 3),
				Vector2i(5, 3)],
		"corridors": [
			{"cells": [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4)], "width": 2},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 6), Vector2i(1, 6)],
					"drops": [{"cell": Vector2i(1, 6), "dir": R}]},
			{"type": "office", "cells": [Vector2i(4, 0), Vector2i(5, 0)],
					"drops": [{"cell": Vector2i(4, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(4, 6), Vector2i(5, 6)],
					"drops": [{"cell": Vector2i(4, 6), "dir": L}]},
		],
		"cards": [
			{"name": "BLUE", "type": "standard", "color": COL_A},
			{"name": "GREEN", "type": "standard", "color": COL_B},
		],
		"quota": 12, "max_lost": 8,
		"spawn": {"interval_start": 3.2, "interval_end": 2.8, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.0},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.30, "from": "A", "to": "B"},
			{"w": 0.20, "from": "B", "to": "A"},
			{"w": 0.30, "from": "C", "to": "D"},
			{"w": 0.20, "from": "D", "to": "C"},
		],
	},
	{
		"id": "R-6",
		"name": "Squeeze",
		"thesis": "one shared column, cap 2 - two lifts can't both thread a tile, so snake around",
		"intro": "The centre column is CAPPED: the amber pips show how many lift-
widths a tile can carry (2 here). A and C want one lift; B and D
the other - but their doors interleave up the column, so the two
routes cannot both run straight. Thread one lift out into the
open right lane to squeeze past the other.",
		"cols": 5, "rows": 7,
		"overlaps": [
			{"cells": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
					Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6)], "max": 2},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 6), Vector2i(1, 6)],
					"drops": [{"cell": Vector2i(1, 6), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 10, "max_lost": 8,
		"spawn": {"interval_start": 2.8, "interval_end": 2.3, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.30, "from": "A", "to": "C"},
			{"w": 0.20, "from": "C", "to": "A"},
			{"w": 0.30, "from": "B", "to": "D"},
			{"w": 0.20, "from": "D", "to": "B"},
		],
	},
]


static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


static func letter(i: int) -> String:
	return ROOM_LETTERS.substr(i, 1)


## Room id (list index) for a level's room LETTER, or -1.
static func room_id_of_letter(level: Dictionary, ch: String) -> int:
	return ROOM_LETTERS.find(ch)


## Briefing body: thesis + intro + the roster + which rooms exist, all straight
## from the level data so it can never drift from what the sim runs.
static func briefing_body(level: Dictionary) -> String:
	var lines: Array = [level.intro, ""]
	var roster: Array = []
	for c in level.cards:
		roster.append(str(c.name))
	lines.append("Lifts: %s" % ", ".join(roster))
	var rnames: Array = []
	for i in level.rooms.size():
		rnames.append("%s %s" % [letter(i), str(level.rooms[i].type)])
	lines.append("Rooms: %s" % ", ".join(rnames))
	lines.append("Deliver %d, lose at %d." % [level.quota, level.max_lost])
	return "\n".join(lines)
