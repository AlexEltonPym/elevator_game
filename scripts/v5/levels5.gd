class_name Levels5
extends RefCounted
## Data-driven level table for the v5 "Rooms" game. A hand-made suite organized
## into WORLDS (LEARN / MECHANICS / GENERIC) — see docs/v5-suite-rework.md.
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
## THEMED DEMAND (docs/v5-suite-rework.md addendum): room TYPES carry the demand
## so a player reads the layout and infers who goes where and which lift serves
## it. Roles expressed through WHERE trips go + patience (no new passenger types):
##   lobby      = ground entrance / transfer hub (everyone passes through)
##   office     = commuter demand: office<->lobby (commute) AND office<->cafe (lunch)
##   apartment  = resident demand (home<->work, home<->cafe)
##   penthouse  = fast exec destination (lobby<->penthouse, impatient) — express's job
##   store/delivery + cafe = supply/freight demand (store->cafe) — cargo's job
##   cafe       = near-universal HUB: draws trips from offices, store, lobby
##
## Each entry:
##   id / world / name / thesis / intro   flavour + briefing text
##   cols / rows                  grid dimensions (y up, row 0 = bottom)
##   blocked                      optional Array[Vector2i] of walls (# cells)
##   corridors                    optional Array of {cells, width} (FIFO mutex)
##   overlaps                     optional Array of {cells, max} (draw-time cap)
##   rooms  Array of {type, cells:Array[Vector2i],
##                    drops:Array[{cell:Vector2i, dir:Vector2i}]}  letter = order
##   cards  Array of {name, type, color}             the ROSTER (1..3)
##   quota / max_lost             win / lose thresholds
##   patience                     optional {ptype: seconds} override
##   reactivate                   optional float, prob a served rider takes a new trip
##   spawn                        pulse spawner config
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
## display metadata only — the sim never reads it.
##   LEARN     — forgiving tutorial ramp, one concept per level
##   MECHANICS — thesis levels that prove/feature one mechanic
##   GENERIC   — middleground optimization: many legal plans, only some good
const WORLDS := ["LEARN", "MECHANICS", "GENERIC"]

const LEVELS := [
	# ===================== LEARN =====================
	{
		"id": "R-1",
		"world": "LEARN",
		"name": "First Run",
		"thesis": "draw one route past the rooms - and one cell between two rooms serves both",
		"intro": "Rooms are areas, not dots. A lift never enters a room; it runs\nin the open cells BESIDE it. Draw one line up the shaft from\nthe lobby: it passes the door marks and drops people off. The\ntop cell sits BETWEEN two offices, so that single cell serves\nBOTH at once - one route, the whole building.",
		"cols": 5, "rows": 5,
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
		"quota": 10, "max_lost": 8,
		"spawn": {"interval_start": 3.0, "interval_end": 2.6, "ramp": 50.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.0},
		"mix": {"visitor": 1.0},
		# Office workers commute to/from the ground lobby.
		"trips": [
			{"w": 0.25, "from": "A", "to": "B"},
			{"w": 0.20, "from": "B", "to": "A"},
			{"w": 0.25, "from": "A", "to": "C"},
			{"w": 0.20, "from": "C", "to": "A"},
			{"w": 0.05, "from": "B", "to": "C"},
			{"w": 0.05, "from": "C", "to": "B"},
		],
	},
	{
		"id": "R-2",
		"world": "LEARN",
		"name": "Two Towers",
		"thesis": "a wall splits the building - one lift can't cover both towers, so you need two",
		"intro": "Two apartment towers over two lobbies, with a solid WALL down\nthe middle - no lift can cross it. So one lift can't do the\nwhole building: give BLUE the left tower and GREEN the right.\nEach tower's residents just ride up and down their own side.",
		"cols": 7, "rows": 6,
		"blocked": [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3),
				Vector2i(3, 4), Vector2i(3, 5)],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0)],
					"drops": [{"cell": Vector2i(5, 0), "dir": L}]},
			{"type": "apartment", "cells": [Vector2i(5, 5), Vector2i(6, 5)],
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
		# Residents commute between each tower's apartment and its own lobby.
		"trips": [
			{"w": 0.25, "from": "A", "to": "B"},
			{"w": 0.25, "from": "B", "to": "A"},
			{"w": 0.25, "from": "C", "to": "D"},
			{"w": 0.25, "from": "D", "to": "C"},
		],
	},
	{
		"id": "R-3",
		"world": "LEARN",
		"name": "Handoff",
		"thesis": "two wings joined only by the lobby - cross the building by changing lifts there",
		"intro": "An apartment wing and an office wing, joined only through the\ncentral LOBBY. BLUE works the left (A and the lobby B), GREEN\nthe right (the lobby B and office C). A resident commuting to\nthe office rides to the lobby, steps across, and catches the\nother lift - a handoff. The lobby B is the transfer.",
		"cols": 8, "rows": 3,
		"blocked": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 2), Vector2i(4, 2)],
		"rooms": [
			{"type": "apartment", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(3, 1), Vector2i(4, 1)],
					"drops": [
						{"cell": Vector2i(3, 1), "dir": L},
						{"cell": Vector2i(4, 1), "dir": R}]},
			{"type": "office", "cells": [Vector2i(6, 0), Vector2i(7, 0)],
					"drops": [{"cell": Vector2i(6, 0), "dir": L}]},
		],
		"cards": [
			{"name": "BLUE", "type": "standard", "color": COL_A},
			{"name": "GREEN", "type": "standard", "color": COL_B},
		],
		"quota": 12, "max_lost": 10,
		"spawn": {"interval_start": 2.8, "interval_end": 2.4, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
		# Residents commute across the building (A<->C) via the lobby transfer.
		"trips": [
			{"w": 0.28, "from": "A", "to": "C"},
			{"w": 0.24, "from": "C", "to": "A"},
			{"w": 0.12, "from": "A", "to": "B"},
			{"w": 0.12, "from": "B", "to": "A"},
			{"w": 0.12, "from": "C", "to": "B"},
			{"w": 0.12, "from": "B", "to": "C"},
		],
	},
	# ===================== MECHANICS =====================
	{
		"id": "R-4",
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
		"id": "R-5",
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
		"id": "R-6",
		"world": "MECHANICS",
		"name": "Squeeze",
		"thesis": "a capped shaft that STEPS across - split it, hand off at the atrium in the bend",
		"intro": "One shaft, but it STEPS from the left stack to the right one.\nThe pips show its cap: 2 per tile, so two lifts can't both run\nthe whole thing. LIFT 1 works the lower-left (A, B, atrium C),\nLIFT 2 the upper-right (C, D, E). They meet only at the cap-4\natrium C in the bend, so cross-building riders change there.",
		"cols": 6, "rows": 9,
		"overlaps": [
			{"cells": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
					Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7),
					Vector2i(3, 8)], "max": 2},
			{"cells": [Vector2i(2, 4)], "max": 4},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "office", "cells": [Vector2i(4, 6), Vector2i(5, 6)],
					"drops": [{"cell": Vector2i(4, 6), "dir": L}]},
			{"type": "apartment", "cells": [Vector2i(4, 8), Vector2i(5, 8)],
					"drops": [{"cell": Vector2i(4, 8), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 20, "max_lost": 8,
		# Short patience so a lift that can't keep up (one lift on the whole shaft) or
		# strands riders (disjoint, no transfer) actually loses them.
		"patience": {"visitor": 32.0},
		"spawn": {"interval_start": 0.9, "interval_end": 0.7, "ramp": 30.0,
				"burst_min": 3, "burst_max": 4, "gap": 0.35},
		"mix": {"visitor": 1.0},
		# HALF the demand is LOCAL to each stack; HALF is CROSS (A<->D, B<->E) and must
		# hand off at the atrium C. One lift can't carry the whole stepped shaft.
		"trips": [
			{"w": 0.13, "from": "A", "to": "B"},
			{"w": 0.12, "from": "B", "to": "A"},
			{"w": 0.13, "from": "D", "to": "E"},
			{"w": 0.12, "from": "E", "to": "D"},
			{"w": 0.14, "from": "A", "to": "D"},
			{"w": 0.11, "from": "D", "to": "A"},
			{"w": 0.14, "from": "B", "to": "E"},
			{"w": 0.11, "from": "E", "to": "B"},
		],
	},
	{
		"id": "R-7",
		"world": "MECHANICS",
		"name": "Express Line",
		"thesis": "give the express its own long channel to the penthouse; the local does the office stops",
		"intro": "Two channels. The left shaft is a clean non-stop run to the\nPENTHOUSE B - put the EXPRESS there (double speed, chevrons):\nexecutives want the lobby-to-top haul fast. The right shaft is\nstop-heavy - the LOCAL serves the office floors C, D, E off the\nlobby A. Long haul = express; lots of stops = local.",
		"cols": 7, "rows": 11,
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(2, 0), Vector2i(3, 0)],
					"drops": [
						{"cell": Vector2i(2, 0), "dir": L},
						{"cell": Vector2i(3, 0), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(2, 10), Vector2i(3, 10)],
					"drops": [{"cell": Vector2i(2, 10), "dir": L}]},
			{"type": "office", "cells": [Vector2i(5, 3), Vector2i(6, 3)],
					"drops": [{"cell": Vector2i(5, 3), "dir": L}]},
			{"type": "office", "cells": [Vector2i(5, 6), Vector2i(6, 6)],
					"drops": [{"cell": Vector2i(5, 6), "dir": L}]},
			{"type": "office", "cells": [Vector2i(5, 8), Vector2i(6, 8)],
					"drops": [{"cell": Vector2i(5, 8), "dir": L}]},
		],
		"cards": [
			{"name": "EXPRESS", "type": "express", "color": COL_C},
			{"name": "LOCAL", "type": "standard", "color": COL_A},
		],
		"quota": 16, "max_lost": 10,
		# Execs are impatient about the penthouse haul - the express is the way to keep
		# the long trips inside patience.
		"patience": {"visitor": 62.0},
		"spawn": {"interval_start": 2.4, "interval_end": 2.0, "ramp": 60.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
		# EXEC: lobby<->penthouse (A<->B), the fast haul. OFFICE-WORKER: offices<->lobby
		# (commute) and offices->penthouse (up to the exec floor, via the lobby transfer).
		"trips": [
			{"w": 0.18, "from": "A", "to": "B"},
			{"w": 0.14, "from": "B", "to": "A"},
			{"w": 0.12, "from": "C", "to": "A"},
			{"w": 0.09, "from": "A", "to": "C"},
			{"w": 0.11, "from": "D", "to": "A"},
			{"w": 0.08, "from": "A", "to": "D"},
			{"w": 0.10, "from": "E", "to": "A"},
			{"w": 0.08, "from": "A", "to": "E"},
			{"w": 0.05, "from": "C", "to": "B"},
			{"w": 0.05, "from": "D", "to": "B"},
		],
	},
	{
		"id": "R-8",
		"world": "MECHANICS",
		"name": "Freight",
		"thesis": "the cafe needs supplies from the store - a wide cargo lift on the wide freight shaft",
		"intro": "The rooftop CAFE B needs supplies from the DELIVERY BAY A down\nbelow. That's the CARGO lift's job: width 3, it runs the wide\nleft FREIGHT shaft straight up, store to cafe. The narrow right\ncorridor (width 2) is for PEOPLE - the LOCAL carries office\nworkers to the lobby and up to the cafe for lunch. Cargo's too\nwide for the people corridor; the local's too narrow to be freight.",
		"cols": 8, "rows": 7,
		"corridors": [
			{"cells": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3),
					Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6)], "width": 3},
			{"cells": [Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3),
					Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)], "width": 2},
		],
		"rooms": [
			{"type": "delivery", "cells": [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [
						{"cell": Vector2i(1, 0), "dir": R},
						{"cell": Vector2i(1, 1), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 6), Vector2i(4, 6)],
					"drops": [
						{"cell": Vector2i(3, 6), "dir": L},
						{"cell": Vector2i(4, 6), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(6, 0), Vector2i(7, 0)],
					"drops": [{"cell": Vector2i(6, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(6, 2), Vector2i(7, 2)],
					"drops": [{"cell": Vector2i(6, 2), "dir": L}]},
			{"type": "office", "cells": [Vector2i(6, 4), Vector2i(7, 4)],
					"drops": [{"cell": Vector2i(6, 4), "dir": L}]},
		],
		"cards": [
			{"name": "CARGO", "type": "cargo", "color": COL_D},
			{"name": "LOCAL", "type": "standard", "color": COL_A},
		],
		"quota": 16, "max_lost": 12,
		"spawn": {"interval_start": 2.4, "interval_end": 2.0, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
		# FREIGHT: delivery bay -> cafe supplies (cargo). COMMUTE: offices<->lobby, and
		# the cafe is the hub - offices and lobby all send trips there for lunch (local).
		"trips": [
			{"w": 0.22, "from": "A", "to": "B"},
			{"w": 0.12, "from": "B", "to": "A"},
			{"w": 0.12, "from": "D", "to": "C"},
			{"w": 0.10, "from": "C", "to": "D"},
			{"w": 0.10, "from": "E", "to": "C"},
			{"w": 0.08, "from": "C", "to": "E"},
			{"w": 0.08, "from": "D", "to": "B"},
			{"w": 0.08, "from": "E", "to": "B"},
			{"w": 0.10, "from": "C", "to": "B"},
		],
	},
	# ===================== GENERIC =====================
	{
		"id": "R-9",
		"world": "GENERIC",
		"name": "Depot",
		"thesis": "serve every dock of the big store WITHOUT the two routes overlapping - a snake puzzle",
		"intro": "The DEPARTMENT STORE A has three loading docks up its side, and\nthere's a delivery bay B, the lobby C and the cafe D around it.\nEvery open tile is capped at 2 - so the two lifts' routes can\nNEVER cross the same tile. Thread two non-overlapping SNAKES\nthat between them touch every dock. Finding a legal pair is the\npuzzle; finding the fast pair is the game.",
		"cols": 7, "rows": 7,
		"overlaps": [
			{"cells": [
				Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
				Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1),
				Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
				Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
				Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4),
				Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5),
				Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6)],
				"max": 2},
		],
		"rooms": [
			{"type": "store", "cells": [
					Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2),
					Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 4),
					Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [
						{"cell": Vector2i(1, 1), "dir": R},
						{"cell": Vector2i(1, 3), "dir": R},
						{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "delivery", "cells": [Vector2i(5, 0), Vector2i(6, 0)],
					"drops": [{"cell": Vector2i(5, 0), "dir": L}]},
			{"type": "lobby", "cells": [Vector2i(5, 3), Vector2i(6, 3)],
					"drops": [{"cell": Vector2i(5, 3), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(5, 6), Vector2i(6, 6)],
					"drops": [{"cell": Vector2i(5, 6), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 18, "max_lost": 12,
		"spawn": {"interval_start": 2.2, "interval_end": 1.8, "ramp": 60.0,
				"burst_min": 2, "burst_max": 3, "gap": 0.7},
		"mix": {"shopper": 1.0},
		# Store is the hub: delivery restocks it, shoppers come from the lobby, and it
		# supplies the cafe. The cafe also draws the lobby (coffee run).
		"trips": [
			{"w": 0.15, "from": "B", "to": "A"},
			{"w": 0.14, "from": "A", "to": "D"},
			{"w": 0.16, "from": "C", "to": "A"},
			{"w": 0.12, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "D"},
			{"w": 0.08, "from": "D", "to": "A"},
			{"w": 0.08, "from": "A", "to": "B"},
			{"w": 0.07, "from": "D", "to": "C"},
		],
	},
	{
		"id": "R-10",
		"world": "GENERIC",
		"name": "Rounds",
		"thesis": "residents keep cycling home->work->cafe - the return trips are the real load",
		"intro": "A live-work block: apartments A, B on the left, office C and\ncafe D on the right, open courtyard between. People don't take\none trip - they cycle (home to work, out for coffee, back\nagain), so a served rider usually sets off again. Run LIFT 1\nas a big horseshoe past all four; add LIFT 2 where the churn\npiles up. The return trips are half the work.",
		"cols": 6, "rows": 7,
		"rooms": [
			{"type": "apartment", "cells": [Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [{"cell": Vector2i(1, 1), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(0, 5), Vector2i(1, 5)],
					"drops": [{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "office", "cells": [Vector2i(4, 1), Vector2i(5, 1)],
					"drops": [{"cell": Vector2i(4, 1), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(4, 5), Vector2i(5, 5)],
					"drops": [{"cell": Vector2i(4, 5), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 20, "max_lost": 12,
		"reactivate": 0.55,
		"spawn": {"interval_start": 2.6, "interval_end": 2.2, "ramp": 60.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
		# Residents cycle: home (A/B) <-> office C, and everyone visits the cafe D. High
		# reactivation makes the return legs the bulk of the demand.
		"trips": [
			{"w": 0.14, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.12, "from": "B", "to": "C"},
			{"w": 0.10, "from": "C", "to": "B"},
			{"w": 0.10, "from": "A", "to": "D"},
			{"w": 0.08, "from": "D", "to": "A"},
			{"w": 0.10, "from": "B", "to": "D"},
			{"w": 0.08, "from": "D", "to": "B"},
			{"w": 0.08, "from": "C", "to": "D"},
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
