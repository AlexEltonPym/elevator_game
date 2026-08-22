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

## Set by the select screen's "solution" button: the next game load auto-commits the
## level's stored `solution` routes (the expert plan) so you can inspect/run it. One-shot;
## main5 clears it after applying.
static var autosolve := false

## TRUE while a headless driver (the smoke test) runs the game, so the HUD
## builds no UI — a Control entering the tree queues deferred callables that
## only an engine frame drains. Mirrors Levels3.headless.
static var headless := false

## STAR SYSTEM (Overcooked-style). A level's optional `stars` field is an ASCENDING
## array of tip thresholds [t1, t2, t3, t4]: t1 = one star, t3 = three stars (the
## range of reasonable solutions, novice->expert), and an optional t4 = the SECRET
## fourth star for an optimal plan. Thresholds are derived from the MAP-Elites solve
## (novice / adept / expert / optimal tips), rounded up to a clean number. Best result
## per level is persisted to user:// so the select screen can show your medals.
const STARS_PATH := "user://v5_stars.json"
static var _stars_cache = null  # Dictionary id -> best earned int, lazily loaded


## Stars earned for a tip total on a level: count of thresholds met (0..4, 4 = secret).
static func stars_for(lv: Dictionary, tip_total: float) -> int:
	var th: Array = lv.get("stars", [])
	var n := 0
	for t in th:
		if tip_total >= float(t):
			n += 1
	return n


static func _load_stars() -> void:
	if _stars_cache != null:
		return
	_stars_cache = {}
	if FileAccess.file_exists(STARS_PATH):
		var f := FileAccess.open(STARS_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				for k in d:
					_stars_cache[k] = int(d[k])


## Best stars ever earned on a level id (0 if never cleared / no medal).
static func best_stars(id: String) -> int:
	_load_stars()
	return int(_stars_cache.get(id, 0))


## Record a run's stars, keeping only the best. Writes user:// on improvement.
static func record_stars(id: String, n: int) -> void:
	if id == "":
		return
	_load_stars()
	if n <= int(_stars_cache.get(id, 0)):
		return
	_stars_cache[id] = n
	var f := FileAccess.open(STARS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_stars_cache))
		f.close()

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
const WORLDS := ["TUTORIAL", "CROSSLINK"]

const LEVELS := [
	# ===================== TUTORIAL =====================
	{
		"id": "T-1", "world": "TUTORIAL", "name": "First Run",
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
		"quota": 10, "max_lost": 8, "shift": 90.0,
		"stars": [170, 250, 310, 350],
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]],
		"spawn": {"interval_start": 3.0, "interval_end": 2.6, "ramp": 50.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.0},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-2", "world": "TUTORIAL", "name": "Handoff",
		"cols": 8, "rows": 3,
		"blocked": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 2), Vector2i(4, 2)],
		"rooms": [
			{"type": "apartment", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"drops": [{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(3, 1), Vector2i(4, 1)],
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
		"quota": 12, "max_lost": 10, "shift": 90.0,
		"stars": [160, 240, 300, 330],
		"solution": [[[5, 1], [5, 0]], [[2, 1], [2, 0]]],
		"spawn": {"interval_start": 2.8, "interval_end": 2.4, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-3", "world": "TUTORIAL", "name": "Freight",
		"cols": 7, "rows": 7,
		"rooms": [
			{"type": "delivery", "cells": [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [
						{"cell": Vector2i(1, 0), "dir": R}]},
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
		"quota": 15, "max_lost": 8, "shift": 90.0,
		"stars": [140, 210, 260, 290],
		"solution": [[[3, 2], [3, 1], [3, 0], [2, 0], [2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [3, 6]], [[3, 6], [3, 5], [3, 4], [3, 3], [3, 2], [3, 1], [3, 0], [2, 0]]],
		"patience": {"delivery": 62.0},
		"spawn": {"interval_start": 3.4, "interval_end": 3.0, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.1},
		"mix": {"visitor": 1.0},
		"reactivate": 0.0,
	},
	{
		"id": "T-4", "world": "TUTORIAL", "name": "Express Line",
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
		"quota": 16, "max_lost": 10, "shift": 90.0,
		"stars": [200, 290, 370, 410],
		"solution": [[[4, 6], [4, 7], [4, 8], [4, 9], [3, 9], [2, 9], [1, 9], [1, 10], [0, 10], [0, 9], [0, 8], [1, 8], [1, 7], [1, 6], [1, 5], [1, 4], [1, 3], [1, 2], [1, 1], [1, 0]], [[4, 8], [4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [4, 0]]],
		"patience": {"visitor": 62.0},
		"spawn": {"interval_start": 2.4, "interval_end": 2.0, "ramp": 60.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-5", "world": "TUTORIAL", "name": "Relay",
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
		"quota": 16, "max_lost": 12, "shift": 90.0,
		"stars": [180, 260, 330, 370],
		"solution": [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4]], [[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]]],
		"spawn": {"interval_start": 2.6, "interval_end": 2.2, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-6", "world": "TUTORIAL", "name": "Loading & Lift",
		"cols": 9, "rows": 9, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 6), Vector2i(1, 8), Vector2i(2, 2), Vector2i(2, 6), Vector2i(3, 2), Vector2i(3, 5), Vector2i(3, 6), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 8), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 8), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 7), Vector2i(6, 8), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 8), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(0, 0), Vector2i(5, 3), Vector2i(2, 3), Vector2i(5, 7), Vector2i(6, 6), Vector2i(0, 5)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0), Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(4, 3), Vector2i(3, 3)], "drops": [{"cell": Vector2i(4, 3), "dir": R}, {"cell": Vector2i(3, 3), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(2, 8), Vector2i(3, 8)], "drops": [{"cell": Vector2i(4, 7), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(8, 6), Vector2i(7, 6), Vector2i(8, 7), Vector2i(7, 7)], "drops": [{"cell": Vector2i(7, 6), "dir": L}]},
			{"type": "apartment", "cells": [Vector2i(2, 5), Vector2i(1, 5)], "drops": [{"cell": Vector2i(1, 5), "dir": L}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [220, 330, 410, 450],
		"solution": [[[0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [6, 7], [5, 7]], [[0, 5], [0, 4], [1, 4], [1, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]], [[6, 6], [6, 5], [6, 4], [6, 3], [5, 3]]],
		"spawn": {"interval_start": 2.80, "interval_end": 2.30, "ramp": 45.00, "burst_min": 1, "burst_max": 2, "gap": 1.00},
		"mix": {"visitor": 1.00},
		"patience": {"delivery": 60.00, "visitor": 55.00},
	},
	{
		"id": "T-7", "world": "TUTORIAL", "name": "Squeeze",
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
		"quota": 20, "max_lost": 8, "shift": 90.0,
		"stars": [130, 190, 230, 260],
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[3, 8], [3, 7], [3, 6], [3, 5], [3, 4], [2, 4]]],
		"patience": {"visitor": 32.0},
		"spawn": {"interval_start": 0.9, "interval_end": 0.7, "ramp": 30.0,
				"burst_min": 3, "burst_max": 4, "gap": 0.35},
		"mix": {"visitor": 1.0},
	},
	# ===================== CROSSLINK =====================
	# Numberlink / snake-fitting: disjoint routes threaded past each other. Open cells
	# cap at 3 (a width-2 LOCAL/EXPRESS can't share; a width-3 CARGO exactly fits), so
	# each committed route becomes walls the next must weave around. Dock cells cap at 6
	# (dropoffs may be shared). CARGO is deliberately sluggish (short bay<->cafe only);
	# EXPRESS is very fast + hard-accelerating so its long run banks momentum, and exec
	# demand (A<->D) is dominant so the express is essential.
	{
		"id": "XL1",
		"world": "CROSSLINK",
		"name": "Crosslink",
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
		"stars": [260, 380, 470, 520],
		"solution": [[[3, 0], [3, 1], [3, 2], [3, 3], [2, 3], [2, 4], [2, 5], [2, 6], [2, 7], [2, 8]], [[7, 7], [7, 6], [8, 6], [8, 5], [8, 4], [7, 4], [7, 3], [6, 3], [6, 2], [6, 1], [6, 0], [5, 0], [4, 0], [3, 0]], [[6, 1], [5, 1], [5, 2], [5, 3], [4, 3], [4, 4]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL2", "world": "CROSSLINK", "name": "Foyer",
		"cols": 9, "rows": 9, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 8), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 8), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 2), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 2), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(5, 7), Vector2i(8, 7), Vector2i(4, 6), Vector2i(5, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(6, 7), Vector2i(7, 7)], "drops": [{"cell": Vector2i(6, 7), "dir": L}, {"cell": Vector2i(7, 7), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(1, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(3, 6), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(3, 3), Vector2i(4, 3)], "drops": [{"cell": Vector2i(4, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [260, 380, 470, 530],
		"solution": [[[5, 3], [6, 3], [7, 3], [7, 2], [7, 1], [7, 0]], [[5, 3], [5, 4], [5, 5], [5, 6], [4, 6], [4, 7], [5, 7]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL3", "world": "CROSSLINK", "name": "Dumbwaiter",
		"cols": 9, "rows": 9, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 4), Vector2i(1, 7), Vector2i(1, 8), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 4), Vector2i(2, 7), Vector2i(2, 8), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(4, 7), Vector2i(7, 7), Vector2i(3, 5), Vector2i(3, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(5, 7), Vector2i(6, 7)], "drops": [{"cell": Vector2i(5, 7), "dir": L}, {"cell": Vector2i(6, 7), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(1, 5), Vector2i(2, 5), Vector2i(1, 6), Vector2i(2, 6)], "drops": [{"cell": Vector2i(2, 5), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(1, 3), Vector2i(2, 3)], "drops": [{"cell": Vector2i(2, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [230, 330, 420, 460],
		"solution": [[[4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [3, 3], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]], [[4, 7], [3, 7], [3, 6], [3, 5], [3, 4], [3, 3]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL4", "world": "CROSSLINK", "name": "Loading Dock",
		"cols": 9, "rows": 11, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(4, 0), Vector2i(3, 9), Vector2i(6, 9), Vector2i(6, 7), Vector2i(4, 4), Vector2i(2, 7)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "drops": [{"cell": Vector2i(3, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(4, 9), Vector2i(5, 9)], "drops": [{"cell": Vector2i(4, 9), "dir": L}, {"cell": Vector2i(5, 9), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(4, 7), Vector2i(5, 7), Vector2i(4, 8), Vector2i(5, 8)], "drops": [{"cell": Vector2i(5, 7), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(2, 4), Vector2i(3, 4)], "drops": [{"cell": Vector2i(3, 4), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(0, 7), Vector2i(1, 7)], "drops": [{"cell": Vector2i(1, 7), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [210, 310, 390, 430],
		"solution": [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [3, 6], [3, 7], [3, 8], [3, 9]], [[2, 7], [2, 8], [2, 9], [3, 9]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL5", "world": "CROSSLINK", "name": "Skybridge",
		"cols": 9, "rows": 11, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 1), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(8, 0), Vector2i(3, 9), Vector2i(6, 9), Vector2i(6, 7), Vector2i(4, 4), Vector2i(8, 2), Vector2i(4, 2)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)], "drops": [{"cell": Vector2i(7, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(4, 9), Vector2i(5, 9)], "drops": [{"cell": Vector2i(4, 9), "dir": L}, {"cell": Vector2i(5, 9), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(4, 7), Vector2i(5, 7), Vector2i(4, 8), Vector2i(5, 8)], "drops": [{"cell": Vector2i(5, 7), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(2, 4), Vector2i(3, 4)], "drops": [{"cell": Vector2i(3, 4), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(7, 2), Vector2i(6, 2), Vector2i(5, 2)], "drops": [{"cell": Vector2i(7, 2), "dir": R}, {"cell": Vector2i(5, 2), "dir": L}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [250, 360, 450, 500],
		"solution": [[[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [7, 4], [6, 4], [5, 4], [4, 4], [4, 3], [4, 2]], [[4, 4], [4, 5], [4, 6], [3, 6], [3, 7], [3, 8], [3, 9]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL6", "world": "CROSSLINK", "name": "Bay Window",
		"cols": 9, "rows": 11, "blocked": [Vector2i(2, 5)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 7), Vector2i(2, 9), Vector2i(2, 10), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 5), Vector2i(3, 7), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 5), Vector2i(4, 7), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 9), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(8, 0), Vector2i(2, 3), Vector2i(5, 3), Vector2i(1, 8), Vector2i(4, 6), Vector2i(5, 10)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)], "drops": [{"cell": Vector2i(7, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(3, 3), Vector2i(4, 3)], "drops": [{"cell": Vector2i(3, 3), "dir": L}, {"cell": Vector2i(4, 3), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8), Vector2i(2, 8), Vector2i(4, 9), Vector2i(3, 9)], "drops": [{"cell": Vector2i(2, 8), "dir": L}]},
			{"type": "apartment", "cells": [Vector2i(2, 6), Vector2i(3, 6)], "drops": [{"cell": Vector2i(3, 6), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(3, 10), Vector2i(4, 10)], "drops": [{"cell": Vector2i(4, 10), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [200, 300, 370, 410],
		"solution": [[[5, 10], [6, 10], [7, 10], [7, 9], [7, 8], [7, 7], [7, 6], [7, 5], [7, 4], [7, 3], [6, 3], [5, 3], [5, 2], [6, 2], [7, 2], [8, 2], [8, 1], [8, 0]], [[5, 10], [5, 9], [6, 9], [6, 8], [6, 7], [6, 6], [5, 6], [4, 6], [4, 7], [3, 7], [2, 7], [1, 7], [1, 8], [0, 8], [0, 7], [0, 6], [1, 6], [1, 5], [1, 4], [1, 3], [2, 3]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL7", "world": "CROSSLINK", "name": "Crosswinds",
		"cols": 9, "rows": 11, "blocked": [Vector2i(7, 4), Vector2i(7, 6)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 5), Vector2i(4, 6), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 3), Vector2i(7, 5), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(4, 0), Vector2i(3, 9), Vector2i(6, 9), Vector2i(6, 7), Vector2i(4, 4), Vector2i(2, 7), Vector2i(4, 2), Vector2i(8, 2)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "drops": [{"cell": Vector2i(3, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(4, 9), Vector2i(5, 9)], "drops": [{"cell": Vector2i(4, 9), "dir": L}, {"cell": Vector2i(5, 9), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(4, 7), Vector2i(5, 7), Vector2i(4, 8), Vector2i(5, 8)], "drops": [{"cell": Vector2i(5, 7), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(2, 4), Vector2i(3, 4)], "drops": [{"cell": Vector2i(3, 4), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(0, 7), Vector2i(1, 7)], "drops": [{"cell": Vector2i(1, 7), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2)], "drops": [{"cell": Vector2i(5, 2), "dir": L}, {"cell": Vector2i(7, 2), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [230, 340, 420, 470],
		"solution": [[[2, 7], [3, 7], [3, 6], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [4, 0]], [[6, 9], [6, 8], [6, 7], [6, 6], [6, 5], [6, 4], [5, 4], [4, 4]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL8", "world": "CROSSLINK", "name": "Rush Hour",
		"cols": 9, "rows": 11, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 7), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 10), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 10), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 10), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(5, 5), Vector2i(8, 5), Vector2i(6, 9), Vector2i(2, 5), Vector2i(2, 0)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(6, 5), Vector2i(7, 5)], "drops": [{"cell": Vector2i(6, 5), "dir": L}, {"cell": Vector2i(7, 5), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(2, 9), Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9), Vector2i(3, 10), Vector2i(4, 10)], "drops": [{"cell": Vector2i(5, 9), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(0, 5), Vector2i(1, 5), Vector2i(0, 6), Vector2i(1, 6)], "drops": [{"cell": Vector2i(1, 5), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(0, 0), Vector2i(1, 0)], "drops": [{"cell": Vector2i(1, 0), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [250, 360, 450, 500],
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [2, 7], [2, 8], [3, 8], [4, 8], [5, 8], [6, 8], [6, 9]], [[2, 0], [3, 0], [3, 1], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0], [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5]], [[5, 5], [5, 4], [5, 3], [4, 3], [4, 4], [4, 5], [3, 5], [2, 5]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL9", "world": "CROSSLINK", "name": "Gridlock",
		"cols": 9, "rows": 11, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 5), Vector2i(2, 7), Vector2i(2, 9), Vector2i(2, 10), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 5), Vector2i(3, 7), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 5), Vector2i(4, 7), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 9), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(8, 0), Vector2i(2, 3), Vector2i(5, 3), Vector2i(1, 8), Vector2i(8, 4), Vector2i(4, 6), Vector2i(5, 10)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)], "drops": [{"cell": Vector2i(7, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(3, 3), Vector2i(4, 3)], "drops": [{"cell": Vector2i(3, 3), "dir": L}, {"cell": Vector2i(4, 3), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8), Vector2i(2, 8), Vector2i(4, 9), Vector2i(3, 9)], "drops": [{"cell": Vector2i(2, 8), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(6, 4), Vector2i(7, 4), Vector2i(6, 5), Vector2i(7, 5)], "drops": [{"cell": Vector2i(7, 4), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(2, 6), Vector2i(3, 6)], "drops": [{"cell": Vector2i(3, 6), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(3, 10), Vector2i(4, 10)], "drops": [{"cell": Vector2i(4, 10), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [210, 310, 390, 430],
		"solution": [[[2, 3], [1, 3], [1, 4], [1, 5], [2, 5], [3, 5], [4, 5], [4, 6]], [[8, 0], [8, 1], [8, 2], [8, 3], [7, 3], [6, 3], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2], [1, 2], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [1, 8]], [[5, 10], [6, 10], [6, 9], [6, 8], [6, 7], [6, 6], [5, 6], [4, 6], [4, 7], [3, 7], [2, 7], [1, 7], [1, 8]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
	},
	{
		"id": "XL10", "world": "CROSSLINK", "name": "The Tower",
		"cols": 9, "rows": 11, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 8), Vector2i(1, 9), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 5), Vector2i(2, 8), Vector2i(2, 9), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 5), Vector2i(3, 8), Vector2i(3, 9), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 8), Vector2i(4, 10), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 10), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 10)], "max": 3},
			{"cells": [Vector2i(8, 0), Vector2i(1, 6), Vector2i(4, 6), Vector2i(8, 9), Vector2i(1, 3), Vector2i(3, 10), Vector2i(3, 0), Vector2i(7, 5)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)], "drops": [{"cell": Vector2i(7, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(2, 6), Vector2i(3, 6)], "drops": [{"cell": Vector2i(2, 6), "dir": L}, {"cell": Vector2i(3, 6), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(4, 9), Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(5, 10), Vector2i(6, 10)], "drops": [{"cell": Vector2i(7, 9), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(3, 3), Vector2i(2, 3), Vector2i(3, 4), Vector2i(2, 4)], "drops": [{"cell": Vector2i(2, 3), "dir": L}]},
			{"type": "apartment", "cells": [Vector2i(1, 10), Vector2i(2, 10)], "drops": [{"cell": Vector2i(2, 10), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(1, 0), Vector2i(2, 0)], "drops": [{"cell": Vector2i(2, 0), "dir": R}]},
			{"type": "apartment", "cells": [Vector2i(5, 5), Vector2i(6, 5)], "drops": [{"cell": Vector2i(6, 5), "dir": R}]},
		],
		"cards": [
			{"name": "LOCAL", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [210, 300, 380, 420],
		"solution": [[[7, 5], [7, 6], [6, 6], [5, 6], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [4, 0], [3, 0]], [[8, 9], [8, 8], [8, 7], [8, 6], [8, 5], [7, 5], [7, 4], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0]], [[1, 3], [1, 4], [1, 5], [1, 6], [0, 6], [0, 7], [0, 8], [0, 9], [1, 9], [2, 9], [3, 9], [3, 10]]],
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
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
	var lines: Array = [str(level.get("intro", "")), ""]
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
