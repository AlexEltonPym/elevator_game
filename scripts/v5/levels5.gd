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
const COL_D := Color(0.80, 0.55, 0.92)

## The three WORLDS the level-select groups levels into (select5.gd). "world" is
## display metadata only — the sim never reads it, so adding it to a level dict
## leaves the simulation (and the fingerprint) byte-identical.
##   LEARN     — forgiving tutorial ramp, one concept per level
##   MECHANICS — thesis levels that prove/feature one mechanic
##   GENERIC   — middleground optimization: many legal plans, only some good
const WORLDS := ["LEARN", "MECHANICS", "GENERIC"]

const LEVELS := [
	{
		"id": "R-1",
		"world": "LEARN",
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
		"world": "LEARN",
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
		"world": "GENERIC",
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
		"world": "GENERIC",
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
		"world": "MECHANICS",
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
		"world": "MECHANICS",
		"name": "Squeeze",
		"thesis": "a capped shared shaft - two lifts must SPLIT it and hand off at the transfer",
		"intro": "One shaft, everyone's doors on it. The pips show its cap: 2 per\ntile - so two lifts can't both run the whole shaft. Split it:\none lift works the bottom (A, B), one the top (C, D). They can\nonly meet at the transfer E in the middle (cap 4), so a rider\ncrossing ends has to change lifts there. One lift can't keep up.",
		"cols": 5, "rows": 11,
		"overlaps": [
			{"cells": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
					Vector2i(2, 4), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8),
					Vector2i(2, 9), Vector2i(2, 10)], "max": 2},
			{"cells": [Vector2i(2, 5)], "max": 4},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 8), Vector2i(1, 8)],
					"drops": [{"cell": Vector2i(1, 8), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 10), Vector2i(1, 10)],
					"drops": [{"cell": Vector2i(1, 10), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [{"cell": Vector2i(1, 5), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 24, "max_lost": 8,
		# Short patience so a lift that can't keep up (one lift on the whole shaft) or
		# strands riders (disjoint, no transfer) actually loses them.
		"patience": {"visitor": 28.0},
		"spawn": {"interval_start": 0.8, "interval_end": 0.6, "ramp": 30.0,
				"burst_min": 3, "burst_max": 4, "gap": 0.35},
		"mix": {"visitor": 1.0},
		# HALF the demand is LOCAL at the two far-apart clusters (A,B bottom; C,D top)
		# and HALF is CROSS (A<->C, B<->D). One lift can't carry the volume across the
		# whole shaft; skipping the transfer strands the whole cross half.
		"trips": [
			{"w": 0.13, "from": "A", "to": "B"},
			{"w": 0.12, "from": "B", "to": "A"},
			{"w": 0.13, "from": "C", "to": "D"},
			{"w": 0.12, "from": "D", "to": "C"},
			{"w": 0.14, "from": "A", "to": "C"},
			{"w": 0.11, "from": "C", "to": "A"},
			{"w": 0.14, "from": "B", "to": "D"},
			{"w": 0.11, "from": "D", "to": "B"},
		],
	},
	{
		"id": "R-7",
		"world": "LEARN",
		"name": "Two Towers",
		"thesis": "two lifts, two stacks - give each lift its own half of the building",
		"intro": "Two separate towers, two lifts. One route can't reach both\nsides, so hand each lift a tower: BLUE up the left column\npast A and B, GREEN up the right column past C and D. Split\nthe building and both halves flow.",
		"cols": 7, "rows": 6,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0)],
					"drops": [{"cell": Vector2i(5, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(5, 5), Vector2i(6, 5)],
					"drops": [{"cell": Vector2i(5, 5), "dir": L}]},
		],
		"cards": [
			{"name": "BLUE", "type": "standard", "color": COL_A},
			{"name": "GREEN", "type": "standard", "color": COL_B},
		],
		"quota": 12, "max_lost": 10,
		"spawn": {"interval_start": 3.0, "interval_end": 2.6, "ramp": 50.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.0},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.25, "from": "A", "to": "B"},
			{"w": 0.25, "from": "B", "to": "A"},
			{"w": 0.25, "from": "C", "to": "D"},
			{"w": 0.25, "from": "D", "to": "C"},
		],
	},
	{
		"id": "R-8",
		"world": "LEARN",
		"name": "The Narrows",
		"thesis": "one striped corridor - a normal lift threads it to reach the far side",
		"intro": "Walls pinch the middle to a single striped CORRIDOR, width 2\n- just enough for one normal lift. Only one lift here, so no\nqueue: just thread the corridor with your route to reach the\nrooms above it. Draw up the centre past lobby A, cafe B and\noffice C.",
		"cols": 5, "rows": 7,
		"blocked": [Vector2i(0, 3), Vector2i(1, 3), Vector2i(3, 3), Vector2i(4, 3)],
		"corridors": [
			{"cells": [Vector2i(2, 3)], "width": 2},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 5), Vector2i(4, 5)],
					"drops": [{"cell": Vector2i(3, 5), "dir": L}]},
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
			{"w": 0.28, "from": "A", "to": "C"},
			{"w": 0.24, "from": "C", "to": "A"},
			{"w": 0.14, "from": "A", "to": "B"},
			{"w": 0.14, "from": "B", "to": "A"},
			{"w": 0.10, "from": "B", "to": "C"},
			{"w": 0.10, "from": "C", "to": "B"},
		],
	},
	{
		"id": "R-9",
		"world": "MECHANICS",
		"name": "Relay",
		"thesis": "the building is split in two - one atrium joins them, so lifts must hand off",
		"intro": "A wall splits the building; the only way across is the atrium\nC in the middle. BLUE works the left (A, B, C), GREEN the\nright (C, D, E). A rider crossing sides gets off at C and\ncatches the other lift - a relay. One lift can't do it alone.",
		"cols": 8, "rows": 5,
		"blocked": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(4, 1),
				Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)],
		"rooms": [
			{"type": "office", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(3, 2), Vector2i(4, 2)],
					"drops": [
						{"cell": Vector2i(3, 2), "dir": L},
						{"cell": Vector2i(4, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(6, 0), Vector2i(7, 0)],
					"drops": [{"cell": Vector2i(6, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(6, 4), Vector2i(7, 4)],
					"drops": [{"cell": Vector2i(6, 4), "dir": L}]},
		],
		"cards": [
			{"name": "BLUE", "type": "standard", "color": COL_A},
			{"name": "GREEN", "type": "standard", "color": COL_B},
		],
		"quota": 16, "max_lost": 12,
		"spawn": {"interval_start": 2.6, "interval_end": 2.2, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.20, "from": "A", "to": "D"},
			{"w": 0.16, "from": "D", "to": "A"},
			{"w": 0.18, "from": "B", "to": "C"},
			{"w": 0.14, "from": "C", "to": "B"},
			{"w": 0.08, "from": "A", "to": "B"},
			{"w": 0.08, "from": "B", "to": "A"},
			{"w": 0.08, "from": "C", "to": "D"},
			{"w": 0.08, "from": "D", "to": "C"},
		],
	},
	{
		"id": "R-10",
		"world": "MECHANICS",
		"name": "Threadneedle",
		"thesis": "a capped zig-zag shaft - split it and meet only at the transfer",
		"intro": "One shaft, doors zig-zagging off both sides, capped 2 per tile\n- two lifts can't both run the whole thing. Split it: LIFT 1\nworks the bottom (A, B, C), LIFT 2 the top (C, D, E). They may\nonly share the cap-4 transfer C in the middle, so cross-end\nriders change lifts there.",
		"cols": 5, "rows": 9,
		"overlaps": [
			{"cells": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
					Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8)], "max": 2},
			{"cells": [Vector2i(2, 4)], "max": 4},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(3, 2), Vector2i(4, 2)],
					"drops": [{"cell": Vector2i(3, 2), "dir": L}]},
			{"type": "atrium", "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "office", "cells": [Vector2i(3, 6), Vector2i(4, 6)],
					"drops": [{"cell": Vector2i(3, 6), "dir": L}]},
			{"type": "office", "cells": [Vector2i(0, 8), Vector2i(1, 8)],
					"drops": [{"cell": Vector2i(1, 8), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 20, "max_lost": 10,
		"patience": {"visitor": 34.0},
		"spawn": {"interval_start": 1.2, "interval_end": 1.0, "ramp": 32.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.4},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.13, "from": "A", "to": "B"},
			{"w": 0.12, "from": "B", "to": "A"},
			{"w": 0.13, "from": "C", "to": "D"},
			{"w": 0.12, "from": "D", "to": "C"},
			{"w": 0.14, "from": "A", "to": "C"},
			{"w": 0.11, "from": "C", "to": "A"},
			{"w": 0.14, "from": "B", "to": "D"},
			{"w": 0.11, "from": "D", "to": "B"},
		],
	},
	{
		"id": "R-11",
		"world": "MECHANICS",
		"name": "Express Run",
		"thesis": "a tall shaft - the express (double speed) earns its keep on the long haul",
		"intro": "A tall tower. The EXPRESS lift (chevrons, double speed) runs\nthe whole shaft and swallows the long A-to-top trips; the\nLOCAL lift shuttles the busy bottom pair. Draw the express\nfull-height and let the local cover A and B up close.",
		"cols": 5, "rows": 11,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 7), Vector2i(1, 7)],
					"drops": [{"cell": Vector2i(1, 7), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 10), Vector2i(1, 10)],
					"drops": [{"cell": Vector2i(1, 10), "dir": R}]},
		],
		"cards": [
			{"name": "EXPRESS", "type": "express", "color": COL_C},
			{"name": "LOCAL", "type": "standard", "color": COL_A},
		],
		"quota": 16, "max_lost": 10,
		"spawn": {"interval_start": 2.4, "interval_end": 2.0, "ramp": 60.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.22, "from": "A", "to": "D"},
			{"w": 0.16, "from": "D", "to": "A"},
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.18, "from": "A", "to": "B"},
			{"w": 0.18, "from": "B", "to": "A"},
		],
	},
	{
		"id": "R-12",
		"world": "MECHANICS",
		"name": "Freight",
		"thesis": "a wide cargo lift can't fit the narrow corridor - so it works the store, the local relays",
		"intro": "The CARGO lift is width 3 (cap 6) - it moves the busy store's\ncrowds but is TOO WIDE for the striped width-2 corridor. So\ncargo works the bottom (store A + lobby B); the LOCAL lift\nthreads the corridor to office C and cafe D up top. They share\nB, so upstairs trips hand off there.",
		"cols": 6, "rows": 7,
		"blocked": [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(4, 3),
				Vector2i(5, 3)],
		"corridors": [
			{"cells": [Vector2i(3, 3)], "width": 2},
		],
		"rooms": [
			{"type": "store", "cells": [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [
						{"cell": Vector2i(1, 0), "dir": R},
						{"cell": Vector2i(1, 1), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0)],
					"drops": [{"cell": Vector2i(4, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(0, 6), Vector2i(1, 6)],
					"drops": [{"cell": Vector2i(1, 6), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(4, 6), Vector2i(5, 6)],
					"drops": [{"cell": Vector2i(4, 6), "dir": L}]},
		],
		"cards": [
			{"name": "CARGO", "type": "cargo", "color": COL_D},
			{"name": "LOCAL", "type": "standard", "color": COL_A},
		],
		"quota": 18, "max_lost": 12,
		"spawn": {"interval_start": 2.2, "interval_end": 1.8, "ramp": 55.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.6},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.22, "from": "A", "to": "D"},
			{"w": 0.18, "from": "D", "to": "A"},
			{"w": 0.14, "from": "A", "to": "B"},
			{"w": 0.10, "from": "B", "to": "A"},
			{"w": 0.12, "from": "A", "to": "C"},
			{"w": 0.08, "from": "C", "to": "A"},
			{"w": 0.08, "from": "D", "to": "C"},
			{"w": 0.08, "from": "C", "to": "D"},
		],
	},
	{
		"id": "R-13",
		"world": "GENERIC",
		"name": "Regulars",
		"thesis": "regulars keep coming back - a plan tuned for one trip drowns under the return trips",
		"intro": "This crowd runs errands: most riders finish a trip and set off\nagain somewhere new (high reactivation). Two lifts share the\nshaft; split the five floors between them however you like -\nbut leave the network well-joined, because the return trips\ndouble the real demand.",
		"cols": 5, "rows": 9,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 6), Vector2i(1, 6)],
					"drops": [{"cell": Vector2i(1, 6), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(0, 8), Vector2i(1, 8)],
					"drops": [{"cell": Vector2i(1, 8), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 20, "max_lost": 12,
		"reactivate": 0.55,
		"spawn": {"interval_start": 2.4, "interval_end": 2.0, "ramp": 60.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.14, "from": "C", "to": "E"},
			{"w": 0.12, "from": "E", "to": "A"},
			{"w": 0.12, "from": "A", "to": "E"},
			{"w": 0.10, "from": "B", "to": "D"},
			{"w": 0.10, "from": "D", "to": "B"},
			{"w": 0.08, "from": "A", "to": "B"},
			{"w": 0.08, "from": "C", "to": "A"},
			{"w": 0.10, "from": "D", "to": "E"},
		],
	},
	{
		"id": "R-14",
		"world": "GENERIC",
		"name": "Interchange",
		"thesis": "a cap-4 trunk fits two lifts but not three - who doubles up where is the puzzle",
		"intro": "One trunk, capped 4 - room for TWO normal lifts on a tile, but\nnot all three at once. Three lifts, five floors: any two may\nshare a stretch to add capacity where it's busy, but somewhere\none has to peel off. Many plans are legal; only some keep every\nfloor moving. C in the middle is a transfer.",
		"cols": 5, "rows": 11,
		"overlaps": [
			{"cells": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
					Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7),
					Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10)], "max": 4},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 8), Vector2i(1, 8)],
					"drops": [{"cell": Vector2i(1, 8), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 10), Vector2i(1, 10)],
					"drops": [{"cell": Vector2i(1, 10), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
			{"name": "LIFT 3", "type": "standard", "color": COL_C},
		],
		"quota": 22, "max_lost": 12,
		"spawn": {"interval_start": 1.9, "interval_end": 1.5, "ramp": 60.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.6},
		"mix": {"visitor": 1.0},
		"trips": [
			{"w": 0.16, "from": "A", "to": "B"},
			{"w": 0.14, "from": "B", "to": "A"},
			{"w": 0.12, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.12, "from": "D", "to": "E"},
			{"w": 0.10, "from": "E", "to": "D"},
			{"w": 0.08, "from": "C", "to": "E"},
			{"w": 0.08, "from": "A", "to": "E"},
			{"w": 0.10, "from": "C", "to": "D"},
		],
	},
]


## An off-table level the headless depth tools (tools/v5/sim_api5.gd) can run
## without touching LEVELS. null (the default) => get_level returns the shipped
## table exactly, so the game and the fingerprint are unchanged by its presence.
static var injected = null


static func get_level(i: int) -> Dictionary:
	if injected != null:
		return injected
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
