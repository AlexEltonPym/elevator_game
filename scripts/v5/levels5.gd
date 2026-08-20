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
const WORLDS := ["LEARN", "MECHANICS", "GENERIC", "CROSSLINK"]

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
		"thesis": "wide delivery men wheel carts to the cafe - only the cargo lift fits them; commuters take the local",
		"intro": "The delivery BAY A is bottom-left; the rooftop CAFE B, the\nLOBBY C and the office floors D, E stack up the middle.\nDELIVERY MEN wheel wide carts (width 3) up from the bay - they\nONLY fit the CARGO lift, so run it up the left past the bay and\nthe doors. They drop the load at the cafe, then head back down\nEMPTY (width 1) to the lobby - any lift will take them. The\noffice crowd is width-1: commute lobby<->office and up to the\ncafe for lunch on the LOCAL up the right. The local can't take\na cart at all.",
		"cols": 7, "rows": 7,
		# GEOMETRY (delivery-man wiring): CARGO (x=2->3 snake) is the ONLY lift that
		# reaches every room. The delivery BAY A is cargo-only (its docks (2,0)/(2,1)
		# sit off the LOCAL's shaft), so freight PHYSICALLY cannot ride the local. The
		# people rooms C/D/E/B carry TWO doors — a LEFT door onto the cargo shaft (x=3)
		# and a RIGHT door onto the LOCAL shaft (x=6) — so commuters ride the faster
		# local. FICTION IS NOW EXACT (per-trip type binding, main5._spawn_random): the
		# supply run A<->B is bound to delivery men and the people trips to commuters, so
		# a delivery man ONLY ever wheels bay<->cafe (always on cargo, never stranded)
		# and a commuter ONLY ever rides a people trip — no off-fiction pairings.
		"rooms": [
			{"type": "delivery", "cells": [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [
						{"cell": Vector2i(1, 0), "dir": R},
						{"cell": Vector2i(1, 1), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(4, 6), Vector2i(5, 6)],
					"drops": [
						{"cell": Vector2i(4, 6), "dir": L},
						{"cell": Vector2i(5, 6), "dir": R}]},
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0)],
					"drops": [
						{"cell": Vector2i(4, 0), "dir": L},
						{"cell": Vector2i(5, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(4, 2), Vector2i(5, 2)],
					"drops": [
						{"cell": Vector2i(4, 2), "dir": L},
						{"cell": Vector2i(5, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(4, 4), Vector2i(5, 4)],
					"drops": [
						{"cell": Vector2i(4, 4), "dir": L},
						{"cell": Vector2i(5, 4), "dir": R}]},
		],
		"cards": [
			{"name": "CARGO", "type": "cargo", "color": COL_D},
			{"name": "LOCAL", "type": "standard", "color": COL_A},
		],
		"quota": 15, "max_lost": 8,
		# BALANCE (retuned for the ROUND-TRIP delivery man). A delivery man now runs a full
		# LOAD -> DELIVER -> RETURN-EMPTY itinerary (main5.resolve_between): he spawns in
		# the bay A carrying his cart at WIDTH 3, rides the slow CARGO lift up to the cafe
		# B (the only lift the cart fits) and DROPS OFF, then sheds the cart and rides back
		# down to the LOBBY C as a WIDTH-1 empty person — takeable by ANY lift, so the
		# empty leg naturally rides the faster LOCAL and adds a w1 load on it. Freight is
		# still cleared only by routing CARGO up through the bay (the natural, rewarded
		# plan); the local carries the commuters AND the empty returners. The spawn stays
		# CALM (slow interval) so the one slow cargo lift keeps comfortably ahead of the
		# outbound legs. A forgiving SOFT-BORDER — a broad basin of two-lift plans clear
		# the load — where covering the bay with cargo is the thing good plans do.
		"patience": {"delivery": 62.0},
		"spawn": {"interval_start": 3.4, "interval_end": 3.0, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.1},
		# EXACT FICTION via per-trip type binding (main5._spawn_random): the mix names the
		# type of every UNTYPED (people) trip — here all commuters — while the supply run
		# below carries an explicit `type: "delivery"` (overriding the mix) plus a `return`
		# letter that wires its round trip. So delivery men are spawned ONLY by the supply
		# run and commuters ONLY by the people trips.
		"mix": {"visitor": 1.0},
		# Commuters take exactly ONE bound trip (reactivate 0): a served commuter does not
		# wander into the bay. Delivery men are the exception — their round trip is a
		# DETERMINISTIC itinerary (return_room), not the probabilistic reactivate — so
		# they run bay -> cafe -> lobby and then stop, never wandering off-fiction.
		"reactivate": 0.0,
		# FREIGHT (type-bound, round trip): the supply run is a SINGLE bay -> cafe delivery
		# (`type: delivery`) whose `return: "C"` sends the emptied man back down to the
		# lobby. Outbound = w3 loaded on CARGO; return = w1 empty on the LOCAL. COMMUTE
		# (untyped -> the mix's commuters): offices<->lobby and offices->cafe (lunch) —
		# width-1 people on the faster LOCAL. Cafe B is the hub.
		"trips": [
			{"w": 0.32, "from": "A", "to": "B", "type": "delivery", "return": "C"},
			{"w": 0.12, "from": "D", "to": "C"},
			{"w": 0.10, "from": "C", "to": "D"},
			{"w": 0.10, "from": "E", "to": "C"},
			{"w": 0.08, "from": "C", "to": "E"},
			{"w": 0.09, "from": "D", "to": "B"},
			{"w": 0.09, "from": "E", "to": "B"},
			{"w": 0.08, "from": "C", "to": "B"},
			{"w": 0.08, "from": "B", "to": "C"},
		],
	},
	# ===================== GENERIC =====================
	{
		"id": "R-9",
		"world": "GENERIC",
		"name": "Cross-Dock",
		"thesis": "each store feeds only its own cafe - pair them up with two non-overlapping snakes",
		"intro": "A sorting depot: five loading STORES stacked down the LOWER\nleft, five CAFES stacked up the UPPER right, a three-wide aisle\nbetween them capped at 2 (routes can't share a tile). Each store\nsupplies ONLY its own cafe up top (A>B, C>D, ... , I>J), with no\ncentral kitchen to change lifts at - so ONE lift must run a store\nall the way up to its cafe. Both easy splits fail: stores-vs-cafes\nstrands every pair, and lower-half-vs-upper-half gives one lift\nall stores and no cafes. Weave two long snakes instead.",
		"cols": 7, "rows": 10,
		"blocked": [
			Vector2i(0, 5), Vector2i(1, 5), Vector2i(0, 6), Vector2i(1, 6),
			Vector2i(0, 7), Vector2i(1, 7), Vector2i(0, 8), Vector2i(1, 8),
			Vector2i(0, 9), Vector2i(1, 9),
			Vector2i(5, 0), Vector2i(6, 0), Vector2i(5, 1), Vector2i(6, 1),
			Vector2i(5, 2), Vector2i(6, 2), Vector2i(5, 3), Vector2i(6, 3),
			Vector2i(5, 4), Vector2i(6, 4)],
		"overlaps": [
			{"cells": [
				Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
				Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
				Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
				Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7),
				Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8), Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9)],
				"max": 2},
		],
		"rooms": [
			{"type": "store", "pair": 1, "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "cafe", "pair": 1, "cells": [Vector2i(5, 5), Vector2i(6, 5)],
					"drops": [{"cell": Vector2i(5, 5), "dir": L}]},
			{"type": "store", "pair": 2, "cells": [Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [{"cell": Vector2i(1, 1), "dir": R}]},
			{"type": "cafe", "pair": 2, "cells": [Vector2i(5, 6), Vector2i(6, 6)],
					"drops": [{"cell": Vector2i(5, 6), "dir": L}]},
			{"type": "store", "pair": 3, "cells": [Vector2i(0, 2), Vector2i(1, 2)],
					"drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "cafe", "pair": 3, "cells": [Vector2i(5, 7), Vector2i(6, 7)],
					"drops": [{"cell": Vector2i(5, 7), "dir": L}]},
			{"type": "store", "pair": 4, "cells": [Vector2i(0, 3), Vector2i(1, 3)],
					"drops": [{"cell": Vector2i(1, 3), "dir": R}]},
			{"type": "cafe", "pair": 4, "cells": [Vector2i(5, 8), Vector2i(6, 8)],
					"drops": [{"cell": Vector2i(5, 8), "dir": L}]},
			{"type": "store", "pair": 5, "cells": [Vector2i(0, 4), Vector2i(1, 4)],
					"drops": [{"cell": Vector2i(1, 4), "dir": R}]},
			{"type": "cafe", "pair": 5, "cells": [Vector2i(5, 9), Vector2i(6, 9)],
					"drops": [{"cell": Vector2i(5, 9), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 15, "max_lost": 10,
		"spawn": {"interval_start": 2.8, "interval_end": 2.4, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"shopper": 1.0},
		# Each store supplies ONLY its paired cafe (A<->B, C<->D, E<->F, G<->H, I<->J).
		# No transfer room, so each pair must be co-served by ONE lift - the tempting
		# all-stores vs all-cafes split carries none of the five pairs.
		"trips": [
			{"w": 0.12, "from": "A", "to": "B"},
			{"w": 0.08, "from": "B", "to": "A"},
			{"w": 0.11, "from": "C", "to": "D"},
			{"w": 0.08, "from": "D", "to": "C"},
			{"w": 0.11, "from": "E", "to": "F"},
			{"w": 0.08, "from": "F", "to": "E"},
			{"w": 0.11, "from": "G", "to": "H"},
			{"w": 0.08, "from": "H", "to": "G"},
			{"w": 0.12, "from": "I", "to": "J"},
			{"w": 0.11, "from": "J", "to": "I"},
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
	# ===================== CROSSLINK =====================
	# Numberlink / snake-fitting: disjoint routes threaded past each other. Open cells
	# cap at 3 (a width-2 LOCAL/EXPRESS can't share; a width-3 CARGO exactly fits), so
	# each committed route becomes walls the next must weave around. Dock cells cap at 6
	# (dropoffs may be shared). CARGO is deliberately sluggish (short bay<->cafe only);
	# EXPRESS is very fast + hard-accelerating so its long run banks momentum, and exec
	# demand (A<->D) is dominant so the express is essential.
	{
		"id": "XLINK",
		"world": "CROSSLINK",
		"name": "Crosslink",
		"thesis": "thread three disjoint snakes past each other",
		"intro": "",
		"cols": 10, "rows": 9,
		"blocked": [],
		"overlaps": [
			{"cells": [
				Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0),
				Vector2i(9, 0), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(9, 1),
				Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
				Vector2i(5, 2), Vector2i(6, 2), Vector2i(9, 2), Vector2i(3, 3), Vector2i(4, 3),
				Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3),
				Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(8, 4),
				Vector2i(9, 4), Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
				Vector2i(8, 5), Vector2i(9, 5), Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6),
				Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6),
				Vector2i(8, 6), Vector2i(9, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7),
				Vector2i(3, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8)],
				"max": 3},
			{"cells": [
				Vector2i(3, 0), Vector2i(6, 1), Vector2i(4, 4), Vector2i(7, 4), Vector2i(7, 7),
				Vector2i(2, 3), Vector2i(2, 8)],
				"max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
					Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
					"drops": [{"cell": Vector2i(2, 0), "dir": R}]},
			{"type": "delivery", "label": "storage",
					"cells": [Vector2i(7, 1), Vector2i(8, 1), Vector2i(7, 2), Vector2i(8, 2)],
					"drops": [{"cell": Vector2i(7, 1), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5),
					Vector2i(5, 4), Vector2i(6, 4)],
					"drops": [{"cell": Vector2i(5, 4), "dir": L}, {"cell": Vector2i(6, 4), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7),
					Vector2i(4, 8), Vector2i(5, 8)],
					"drops": [{"cell": Vector2i(6, 7), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(8, 7), Vector2i(9, 7)],
					"drops": [{"cell": Vector2i(8, 7), "dir": L}]},
			{"type": "apartment", "cells": [Vector2i(0, 3), Vector2i(1, 3)],
					"drops": [{"cell": Vector2i(1, 3), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(0, 8), Vector2i(1, 8)],
					"drops": [{"cell": Vector2i(1, 8), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 12,
		# shift/tip scoring: run a 90s shift, then last orders; the score is the tip total.
		# cover: round-robin demand so every room gets riders (abandon one and its riders
		# time out, costing tips) — the soft version of the old all-served rule.
		"shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.15, "from": "B", "to": "C", "type": "delivery"},
			{"w": 0.07, "from": "C", "to": "B", "type": "delivery"},
			{"w": 0.30, "from": "A", "to": "D"}, {"w": 0.16, "from": "D", "to": "A"},
			{"w": 0.12, "from": "A", "to": "C"}, {"w": 0.07, "from": "C", "to": "A"},
			{"w": 0.10, "from": "A", "to": "E"}, {"w": 0.05, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "F"}, {"w": 0.05, "from": "F", "to": "A"},
			{"w": 0.09, "from": "A", "to": "G"}, {"w": 0.05, "from": "G", "to": "A"},
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
