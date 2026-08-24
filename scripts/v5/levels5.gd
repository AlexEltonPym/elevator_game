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

## Which star-tier plan the autosolve should pre-draw (1..4 from the level's `sols`); 4 = the
## perfect plan. Set by the select screen's secret 1-4 hover shortcut. Cleared after use.
static var autosolve_tier := 4

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

## GHOST-HAND DEMO seen-state: a level's tutorial demo plays ONCE ever (persisted here), so it
## doesn't replay every time you re-enter to plan. Parallels the stars cache.
const DEMOS_PATH := "user://v5_demos.json"
static var _demos_cache = null

static func _load_demos() -> void:
	if _demos_cache != null:
		return
	_demos_cache = {}
	if FileAccess.file_exists(DEMOS_PATH):
		var f := FileAccess.open(DEMOS_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				_demos_cache = d


static func demo_seen(id: String) -> bool:
	_load_demos()
	return bool(_demos_cache.get(id, false))


static func mark_demo_seen(id: String) -> void:
	_load_demos()
	if bool(_demos_cache.get(id, false)):
		return
	_demos_cache[id] = true
	var f := FileAccess.open(DEMOS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_demos_cache))
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
		"cols": 5, "rows": 5, "blocked": [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3)],
		"overlaps": [
			{"cells": [Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(4, 0)], "max": 3},
			{"cells": [Vector2i(2, 0), Vector2i(2, 4)], "max": 6},
		],
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
		"quota": 10, "max_lost": 8, "shift": 60.0,
		"stars": [170, 250, 310, 350],
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]],
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]],  # lobby straight up to the shared office dock
		"sols": [[[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]]],
		"spawn": {"interval_start": 3.0, "interval_end": 2.6, "ramp": 50.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.0},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-2", "world": "TUTORIAL", "name": "Handoff",
		"cols": 8, "rows": 5, "blocked": [Vector2i(0, 2), Vector2i(1, 1), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 4), Vector2i(6, 2), Vector2i(7, 2), Vector2i(7, 3)],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 3), Vector2i(1, 2), Vector2i(1, 3), Vector2i(2, 1), Vector2i(2, 3), Vector2i(5, 1), Vector2i(5, 3), Vector2i(6, 1), Vector2i(6, 3), Vector2i(7, 1)], "max": 3},
			{"cells": [Vector2i(2, 0), Vector2i(2, 4), Vector2i(2, 2), Vector2i(5, 2), Vector2i(5, 0), Vector2i(5, 4)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(0, 0), Vector2i(1, 0)],
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
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 16, "max_lost": 12, "shift": 60.0,
		"stars": [160, 240, 300, 330],
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[5, 0], [5, 1], [5, 2], [5, 3], [5, 4]]],
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]],  # atrium handoff: LIFT 1 (blue) up the left, LIFT 2 (green) down the right
		"sols": [[[[2, 2], [2, 1], [2, 0]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]], [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4]], [[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]]], [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4]], [[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]]], [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4]], [[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]]]],
		"spawn": {"interval_start": 2.6, "interval_end": 2.2, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-3", "world": "TUTORIAL", "name": "Squeeze",
		"cols": 6, "rows": 9, "blocked": [Vector2i(0, 1), Vector2i(0, 3), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 7), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 7), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)],
		"overlaps": [
			{"cells": [Vector2i(2, 1), Vector2i(2, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 7)], "max": 3},
			{"cells": [Vector2i(2, 0), Vector2i(2, 2), Vector2i(2, 4), Vector2i(3, 6), Vector2i(3, 8)], "max": 6},
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
			{"type": "office", "cells": [Vector2i(4, 8), Vector2i(5, 8)],
					"drops": [{"cell": Vector2i(4, 8), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": COL_B},
		],
		"quota": 20, "max_lost": 8, "shift": 60.0,
		"stars": [170, 240, 300, 340],
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]],
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]],  # LIFT 1 up the left half; LIFT 2 bridges the atrium up the right half
		"sols": [[[[3, 6], [3, 5], [3, 4], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0]], [[3, 6], [3, 7], [3, 8]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]]],
		"spawn": {"interval_start": 2.6, "interval_end": 2.2, "ramp": 50.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.9},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-4", "world": "TUTORIAL", "name": "Freight",
		"cols": 7, "rows": 7, "blocked": [Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 2), Vector2i(1, 4), Vector2i(1, 6), Vector2i(5, 3)],
		"overlaps": [
			{"cells": [Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 6), Vector2i(1, 3), Vector2i(1, 5), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(3, 1), Vector2i(3, 3), Vector2i(3, 5), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 5), Vector2i(5, 1), Vector2i(5, 5), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6)], "max": 3},
			{"cells": [Vector2i(2, 0), Vector2i(3, 6), Vector2i(3, 0), Vector2i(3, 2), Vector2i(3, 4)], "max": 6},
		],
		"rooms": [
			{"type": "delivery", "cells": [
					Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
					"drops": [
						{"cell": Vector2i(1, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(4, 6), Vector2i(5, 6)],
					"drops": [
						{"cell": Vector2i(4, 6), "dir": L}]},
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0)],
					"drops": [
						{"cell": Vector2i(4, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(4, 2), Vector2i(5, 2)],
					"drops": [
						{"cell": Vector2i(4, 2), "dir": L}]},
			{"type": "office", "cells": [Vector2i(4, 4), Vector2i(5, 4)],
					"drops": [
						{"cell": Vector2i(4, 4), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_D},
		],
		"quota": 15, "max_lost": 8, "shift": 60.0,
		"stars": [160, 230, 290, 320],
		"solution": [[[3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[3, 4], [3, 5], [3, 6], [2, 6], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0]]],
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [3, 6]], [[3, 6], [3, 5], [3, 4], [3, 3], [3, 2], [3, 1], [3, 0]]],  # cargo runs bay up to the cafe; local threads the next column down to lobby
		"sols": [[[[3, 2], [3, 3], [3, 4]], [[3, 6], [3, 5], [3, 4], [2, 4], [2, 3], [2, 2], [3, 2], [3, 1], [3, 0]]], [[[3, 0], [3, 1], [3, 2], [3, 3], [3, 4]], [[3, 0], [2, 0], [2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [3, 6]]], [[[3, 6], [3, 5], [3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[2, 0], [2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [3, 6]]], [[[3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[3, 4], [3, 5], [3, 6], [2, 6], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0]]]],
		"patience": {"delivery": 62.0},
		"spawn": {"interval_start": 3.4, "interval_end": 3.0, "ramp": 55.0,
				"burst_min": 1, "burst_max": 2, "gap": 1.1},
		"mix": {"visitor": 1.0},
		"reactivate": 0.0,
	},
	{
		"id": "T-5", "world": "TUTORIAL", "name": "Express Line",
		"cols": 7, "rows": 11, "blocked": [Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 7), Vector2i(3, 2), Vector2i(4, 10), Vector2i(5, 4), Vector2i(5, 10), Vector2i(6, 0), Vector2i(6, 4)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 6), Vector2i(1, 8), Vector2i(1, 9), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(3, 1), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(3, 9), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 7), Vector2i(4, 9), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 7), Vector2i(5, 9), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 5), Vector2i(6, 7), Vector2i(6, 9), Vector2i(6, 10)], "max": 3},
			{"cells": [Vector2i(1, 0), Vector2i(4, 0), Vector2i(1, 10), Vector2i(4, 3), Vector2i(4, 6), Vector2i(4, 8)], "max": 6},
		],
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
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "EXPRESS", "type": "express", "color": COL_C, "cap": 2},
		],
		"quota": 16, "max_lost": 10, "shift": 60.0,
		"stars": [240, 340, 440, 470],   # cap-2 express + penthouse demand 1.0: the CLEAN split (express=penthouse shuttle, local=offices) is the STRICT optimum (~492); a double-up/weave scores less (~457 -> 3★). 4★ has ~22 headroom (optimal 610): CLEAN split (express=penthouse shuttle, local=offices) is now the optimum; 4★ has ~25 headroom so a clean route earns it, a double-up route lands 3★: 4★ has ~15 headroom so a clean near-optimal route earns it, not a fiddly exact optimum
		"solution": [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8]], [[1, 10], [1, 9], [1, 8], [0, 8], [0, 7], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0], [1, 0]]],
		"sols": [[[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8]], [[1, 10], [1, 9], [1, 8], [0, 8], [0, 7], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0], [1, 0]]]],
		"patience": {"visitor": 62.0},
		"demand": {"penthouse": 1.0},   # express tutorial: lots of executives -> serving them fast pays
		"spawn": {"interval_start": 2.4, "interval_end": 2.0, "ramp": 60.0,
				"burst_min": 1, "burst_max": 2, "gap": 0.8},
		"mix": {"visitor": 1.0},
	},
	{
		"id": "T-6", "world": "TUTORIAL", "name": "Loading & Lift",
		"cols": 9, "rows": 9, "blocked": [Vector2i(0, 7), Vector2i(1, 4), Vector2i(5, 0), Vector2i(5, 5), Vector2i(5, 8), Vector2i(6, 0), Vector2i(6, 1), Vector2i(7, 0), Vector2i(7, 3), Vector2i(7, 8), Vector2i(8, 0), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 8)],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 6), Vector2i(0, 8), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 6), Vector2i(1, 8), Vector2i(2, 2), Vector2i(2, 6), Vector2i(3, 2), Vector2i(3, 5), Vector2i(3, 6), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 8), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 6), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 7), Vector2i(6, 8), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 5), Vector2i(8, 1), Vector2i(8, 4), Vector2i(8, 5)], "max": 3},
			{"cells": [Vector2i(0, 0), Vector2i(5, 3), Vector2i(2, 3), Vector2i(5, 7), Vector2i(6, 6), Vector2i(0, 5)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0), Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(4, 3), Vector2i(3, 3)], "drops": [{"cell": Vector2i(4, 3), "dir": R}, {"cell": Vector2i(3, 3), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(2, 8), Vector2i(3, 8)], "drops": [{"cell": Vector2i(4, 7), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(8, 6), Vector2i(7, 6), Vector2i(8, 7), Vector2i(7, 7)], "drops": [{"cell": Vector2i(7, 6), "dir": L}]},
			{"type": "office", "cells": [Vector2i(2, 5), Vector2i(1, 5)], "drops": [{"cell": Vector2i(1, 5), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0, "cap": 2},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [400, 580, 720, 800],
		"solution": [[[6, 6], [6, 7], [5, 7], [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6], [0, 5]], [[6, 6], [6, 5], [6, 4], [6, 3], [5, 3]], [[0, 5], [0, 4], [0, 3], [1, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]],
		"sols": [[[[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5]], [[5, 7], [6, 7], [6, 6], [6, 5], [6, 4], [6, 3], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2], [2, 3]], [[5, 7], [5, 6], [6, 6]]], [[[2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]], [[5, 3], [6, 3], [6, 4], [6, 5], [6, 6]], [[2, 3], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]]], [[[6, 6], [6, 7], [5, 7], [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6], [0, 5]], [[6, 6], [6, 5], [6, 4], [6, 3], [5, 3]], [[0, 5], [0, 4], [0, 3], [1, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]], [[[6, 6], [6, 7], [5, 7], [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6], [0, 5]], [[6, 6], [6, 5], [6, 4], [6, 3], [5, 3]], [[0, 5], [0, 4], [0, 3], [1, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]]],
		"spawn": {"interval_start": 2.80, "interval_end": 2.30, "ramp": 45.00, "burst_min": 1, "burst_max": 2, "gap": 1.00},
		"mix": {"visitor": 1.00},
		"patience": {"delivery": 60.00, "visitor": 55.00},
	},
	# ===================== CROSSLINK =====================
	{
		"id": "XL1", "world": "CROSSLINK", "name": "Crosslink",
		"cols": 9, "rows": 7, "ground_row": 0, "blocked": [Vector2i(0, 5), Vector2i(5, 6), Vector2i(6, 0), Vector2i(6, 6), Vector2i(8, 1), Vector2i(8, 3), Vector2i(8, 5), Vector2i(8, 6)],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(1, 2), Vector2i(1, 4), Vector2i(2, 2), Vector2i(2, 4), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 6), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 3), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 5), Vector2i(8, 6)], "max": 3},
			{"cells": [Vector2i(0, 0), Vector2i(1, 5), Vector2i(4, 5), Vector2i(4, 4), Vector2i(7, 2), Vector2i(2, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0), Vector2i(3, 1), Vector2i(2, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(2, 5), Vector2i(3, 5)], "drops": [{"cell": Vector2i(2, 5), "dir": L}, {"cell": Vector2i(3, 5), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(8, 4), Vector2i(7, 4), Vector2i(6, 4), Vector2i(5, 4), Vector2i(7, 5), Vector2i(6, 5)], "drops": [{"cell": Vector2i(5, 4), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(5, 2), Vector2i(6, 2), Vector2i(5, 3), Vector2i(6, 3)], "drops": [{"cell": Vector2i(6, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 3), Vector2i(1, 3)], "drops": [{"cell": Vector2i(1, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [480, 690, 860, 960],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[1, 5], [1, 4], [2, 4], [2, 3]], [[7, 2], [7, 1], [6, 1], [5, 1], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5]], [[4, 5], [4, 4], [3, 4], [3, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]],
		"sols": [[[[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 3], [2, 4], [1, 4], [1, 5]], [[4, 5], [4, 4]], [[2, 3], [3, 3], [3, 4], [4, 4]]], [[[1, 5], [1, 4], [2, 4], [2, 3]], [[7, 2], [7, 1], [6, 1], [5, 1], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5]], [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 3], [3, 3], [3, 4], [4, 4], [4, 5]]], [[[1, 5], [1, 4], [2, 4], [2, 3]], [[7, 2], [7, 1], [6, 1], [5, 1], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5]], [[4, 5], [4, 4], [3, 4], [3, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]], [[[1, 5], [1, 4], [2, 4], [2, 3]], [[7, 2], [7, 1], [6, 1], [5, 1], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5]], [[4, 5], [4, 4], [3, 4], [3, 3], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]]],
	},
	{
		"id": "XL2", "world": "CROSSLINK", "name": "Foyer",
		"cols": 9, "rows": 8, "ground_row": 0, "blocked": [Vector2i(0, 5), Vector2i(1, 4), Vector2i(2, 4), Vector2i(2, 7), Vector2i(3, 4), Vector2i(4, 4), Vector2i(4, 5), Vector2i(6, 7), Vector2i(8, 5), Vector2i(8, 6)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 1), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(2, 1), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 7), Vector2i(3, 1), Vector2i(3, 4), Vector2i(3, 5), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 7), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 7), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(3, 2), Vector2i(0, 2), Vector2i(6, 6), Vector2i(6, 3), Vector2i(1, 0)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 3), Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3), Vector2i(2, 2), Vector2i(1, 2)], "drops": [{"cell": Vector2i(2, 2), "dir": R}, {"cell": Vector2i(1, 2), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(3, 7), Vector2i(4, 7)], "drops": [{"cell": Vector2i(5, 6), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(8, 3), Vector2i(7, 3), Vector2i(8, 4), Vector2i(7, 4)], "drops": [{"cell": Vector2i(7, 3), "dir": L}]},
			{"type": "office", "cells": [Vector2i(3, 0), Vector2i(2, 0)], "drops": [{"cell": Vector2i(2, 0), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [480, 700, 870, 970],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]],
		"sols": [[[[1, 0], [1, 1], [2, 1], [3, 1], [3, 2], [4, 2], [4, 3], [5, 3], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [6, 2], [7, 2], [7, 1], [7, 0]], [[0, 2], [0, 1], [0, 0], [1, 0]]], [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]], [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]], [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]]],
	},
	{
		"id": "XL3", "world": "CROSSLINK", "name": "High Rise",
		"cols": 9, "rows": 9, "ground_row": 0, "blocked": [Vector2i(0, 1), Vector2i(0, 3), Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 5), Vector2i(2, 0), Vector2i(3, 0), Vector2i(6, 7), Vector2i(7, 3), Vector2i(7, 4)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 0), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 8), Vector2i(2, 0), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 8), Vector2i(3, 0), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 7), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(4, 0), Vector2i(6, 5), Vector2i(3, 5), Vector2i(1, 7), Vector2i(3, 1), Vector2i(7, 8)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(7, 0), Vector2i(6, 0), Vector2i(5, 0), Vector2i(7, 1), Vector2i(6, 1), Vector2i(5, 1)], "drops": [{"cell": Vector2i(5, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(6, 6), Vector2i(5, 6), Vector2i(4, 6), Vector2i(3, 6), Vector2i(5, 5), Vector2i(4, 5)], "drops": [{"cell": Vector2i(5, 5), "dir": R}, {"cell": Vector2i(4, 5), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(5, 7), Vector2i(4, 7), Vector2i(3, 7), Vector2i(2, 7), Vector2i(4, 8), Vector2i(3, 8)], "drops": [{"cell": Vector2i(2, 7), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)], "drops": [{"cell": Vector2i(2, 1), "dir": R}]},
			{"type": "office", "cells": [Vector2i(5, 8), Vector2i(6, 8)], "drops": [{"cell": Vector2i(6, 8), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [420, 610, 770, 850],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]], [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5]], [[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [5, 4], [6, 4], [6, 5], [7, 5], [7, 6], [7, 7], [7, 8]]],
		"sols": [[[[7, 8], [7, 7], [7, 6], [7, 5], [6, 5]], [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [2, 5], [2, 6], [1, 6], [1, 7]], [[4, 0], [4, 1], [4, 2], [5, 2], [6, 2], [7, 2], [8, 2], [8, 3], [8, 4], [8, 5], [8, 6], [8, 7], [8, 8], [7, 8]]], [[[7, 8], [8, 8], [8, 7], [8, 6], [8, 5], [7, 5], [6, 5]], [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [2, 5], [2, 6], [1, 6], [1, 7]], [[6, 5], [6, 4], [6, 3], [6, 2], [5, 2], [4, 2], [4, 1], [4, 0]]], [[[7, 8], [8, 8], [8, 7], [8, 6], [8, 5], [7, 5], [6, 5]], [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [2, 5], [2, 6], [1, 6], [1, 7]], [[6, 5], [6, 4], [6, 3], [6, 2], [5, 2], [4, 2], [4, 1], [4, 0]]], [[[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]], [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5]], [[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [5, 4], [6, 4], [6, 5], [7, 5], [7, 6], [7, 7], [7, 8]]]],
	},
	{
		"id": "XL4", "world": "CROSSLINK", "name": "Atrium",
		"cols": 9, "rows": 8, "ground_row": 0, "blocked": [Vector2i(2, 7), Vector2i(5, 4), Vector2i(5, 7)],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 6), Vector2i(1, 7), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 7), Vector2i(3, 2), Vector2i(4, 2), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 2), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 7), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 5), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6)], "max": 3},
			{"cells": [Vector2i(6, 0), Vector2i(0, 4), Vector2i(3, 4), Vector2i(6, 6), Vector2i(0, 0), Vector2i(6, 7), Vector2i(3, 3), Vector2i(7, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)], "drops": [{"cell": Vector2i(5, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(1, 4), Vector2i(2, 4)], "drops": [{"cell": Vector2i(1, 4), "dir": L}, {"cell": Vector2i(2, 4), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(3, 7), Vector2i(4, 7)], "drops": [{"cell": Vector2i(5, 6), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(2, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(8, 7), Vector2i(7, 7)], "drops": [{"cell": Vector2i(7, 7), "dir": L}]},
			{"type": "atrium", "cells": [Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)], "drops": [{"cell": Vector2i(4, 3), "dir": L}, {"cell": Vector2i(6, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [490, 710, 890, 990],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [3, 3], [3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6], [6, 6], [6, 7]]],
		"sols": [[[[6, 0], [6, 1], [6, 2], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6], [6, 6]], [[3, 3], [3, 4]], [[0, 4], [0, 3], [1, 3], [2, 3], [3, 3], [3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6]]], [[[6, 7], [6, 6], [7, 6], [7, 5], [7, 4], [7, 3], [7, 2], [7, 1], [7, 0], [6, 0]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 7], [6, 6], [6, 5], [5, 5], [4, 5], [4, 4], [3, 4], [3, 3], [3, 2], [4, 2], [5, 2], [6, 2], [6, 1], [6, 0]]], [[[6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [3, 3], [3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6], [6, 6], [6, 7]]], [[[6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [3, 3], [3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6], [6, 6], [6, 7]]]],
	},
	{
		"id": "XL5", "world": "CROSSLINK", "name": "Skyline",
		"cols": 9, "rows": 9, "ground_row": 0, "blocked": [Vector2i(2, 2), Vector2i(2, 4), Vector2i(3, 0), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 5), Vector2i(5, 8), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 4), Vector2i(8, 5)],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 2), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 7), Vector2i(5, 8), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 8), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 8), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(4, 7), Vector2i(1, 7), Vector2i(4, 6), Vector2i(0, 0), Vector2i(7, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(4, 8), Vector2i(3, 8), Vector2i(2, 8), Vector2i(1, 8), Vector2i(3, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(3, 7), "dir": R}, {"cell": Vector2i(2, 7), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(8, 6), Vector2i(7, 6), Vector2i(6, 6), Vector2i(5, 6), Vector2i(7, 7), Vector2i(6, 7)], "drops": [{"cell": Vector2i(5, 6), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(2, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(5, 3), Vector2i(6, 3)], "drops": [{"cell": Vector2i(6, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"patience": {"executive": 78.0},
		"stars": [430, 630, 790, 870],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [4, 7]]],
		"sols": [[[[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [4, 7]], [[7, 0], [8, 0], [8, 1], [8, 2], [8, 3], [7, 3]], [[1, 7], [1, 6], [2, 6], [3, 6], [4, 6], [4, 7]]], [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [4, 7]]], [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [4, 7]]], [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [4, 7]]]],
	},
	{
		"id": "XL6", "world": "CROSSLINK", "name": "Courtyard",
		"cols": 9, "rows": 9, "ground_row": 0, "blocked": [Vector2i(0, 8), Vector2i(2, 4), Vector2i(2, 8), Vector2i(5, 5), Vector2i(5, 7), Vector2i(7, 5), Vector2i(7, 8), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 5), Vector2i(8, 7)],
		"overlaps": [
			{"cells": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 8), Vector2i(1, 2), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 8), Vector2i(2, 2), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 8), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 8), Vector2i(4, 2), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, 2), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 7), Vector2i(5, 8), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 8), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 8), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(3, 6), Vector2i(0, 6), Vector2i(4, 6), Vector2i(0, 0), Vector2i(3, 3), Vector2i(4, 3), Vector2i(8, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(3, 7), Vector2i(2, 7), Vector2i(1, 7), Vector2i(0, 7), Vector2i(2, 6), Vector2i(1, 6)], "drops": [{"cell": Vector2i(2, 6), "dir": R}, {"cell": Vector2i(1, 6), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(8, 6), Vector2i(7, 6), Vector2i(6, 6), Vector2i(5, 6), Vector2i(7, 7), Vector2i(6, 7)], "drops": [{"cell": Vector2i(5, 6), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(2, 0), Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(1, 3), Vector2i(2, 3)], "drops": [{"cell": Vector2i(2, 3), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3)], "drops": [{"cell": Vector2i(5, 3), "dir": L}, {"cell": Vector2i(7, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [460, 670, 830, 930],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[3, 3], [3, 4], [3, 5], [3, 6]], [[0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0]], [[7, 0], [7, 1], [7, 2], [6, 2], [5, 2], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [3, 6]]],
		"sols": [[[[7, 0], [7, 1], [7, 2], [8, 2], [8, 3], [8, 4], [7, 4], [6, 4], [5, 4], [4, 4], [4, 3], [3, 3], [3, 4], [3, 5], [2, 5], [1, 5], [0, 5], [0, 6]], [[4, 3], [3, 3]], [[3, 6], [4, 6]]], [[[8, 3], [8, 2], [7, 2], [7, 1], [7, 0]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [1, 5], [2, 5], [3, 5], [3, 6]], [[3, 6], [4, 6], [4, 5], [4, 4], [4, 3], [3, 3]]], [[[3, 3], [3, 4], [3, 5], [3, 6], [4, 6]], [[0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0]], [[7, 0], [7, 1], [7, 2], [8, 2], [8, 3], [8, 4], [7, 4], [6, 4], [5, 4], [4, 4], [4, 5], [4, 6], [3, 6]]], [[[3, 3], [3, 4], [3, 5], [3, 6]], [[0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0]], [[7, 0], [7, 1], [7, 2], [6, 2], [5, 2], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [3, 6]]]],
	},
	{
		"id": "XL7", "world": "CROSSLINK", "name": "Sidestep",
		"cols": 9, "rows": 8, "ground_row": 0, "blocked": [Vector2i(0, 0), Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 0), Vector2i(4, 7), Vector2i(7, 7), Vector2i(8, 0)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 7), Vector2i(1, 0), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 7), Vector2i(2, 0), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 7), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 7), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 7), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 7), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 4), Vector2i(8, 7)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(5, 5), Vector2i(8, 5), Vector2i(0, 6), Vector2i(2, 2), Vector2i(2, 1), Vector2i(6, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(6, 5), Vector2i(7, 5)], "drops": [{"cell": Vector2i(6, 5), "dir": L}, {"cell": Vector2i(7, 5), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(4, 6), Vector2i(3, 6), Vector2i(2, 6), Vector2i(1, 6), Vector2i(3, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(1, 6), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3), Vector2i(1, 3)], "drops": [{"cell": Vector2i(1, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 1), Vector2i(1, 1)], "drops": [{"cell": Vector2i(1, 1), "dir": R}]},
			{"type": "office", "cells": [Vector2i(8, 3), Vector2i(7, 3)], "drops": [{"cell": Vector2i(7, 3), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [360, 510, 640, 720],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[0, 6], [0, 5], [1, 5], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1]], [[5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2]], [[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [7, 4], [8, 4], [8, 5]]],
		"sols": [[[[2, 2], [2, 1], [3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [4, 5], [5, 5]], [[6, 3], [6, 4], [5, 4], [5, 5]], [[0, 6], [0, 5], [1, 5], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1]]], [[[2, 1], [2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]], [[5, 5], [5, 4], [5, 3], [4, 3], [3, 3], [2, 3], [2, 2]], [[5, 5], [4, 5], [3, 5], [2, 5], [1, 5], [0, 5], [0, 6]]], [[[0, 6], [0, 5], [1, 5], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1]], [[5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2]], [[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [7, 4], [8, 4], [8, 5]]], [[[0, 6], [0, 5], [1, 5], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1]], [[5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2]], [[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [7, 4], [8, 4], [8, 5]]]],
	},
	{
		"id": "XL8", "world": "CROSSLINK", "name": "Rush Hour",
		"cols": 9, "rows": 9, "ground_row": 0, "blocked": [Vector2i(2, 0), Vector2i(4, 8), Vector2i(6, 5), Vector2i(6, 7), Vector2i(6, 8), Vector2i(7, 5), Vector2i(7, 7), Vector2i(7, 8), Vector2i(8, 6), Vector2i(8, 7)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 4), Vector2i(1, 6), Vector2i(1, 8), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 4), Vector2i(2, 6), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 8), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 8), Vector2i(6, 2), Vector2i(6, 5), Vector2i(6, 7), Vector2i(6, 8), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 5), Vector2i(7, 7), Vector2i(7, 8), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(7, 0), Vector2i(5, 3), Vector2i(8, 3), Vector2i(5, 7), Vector2i(0, 2), Vector2i(0, 5), Vector2i(5, 6)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(6, 3), Vector2i(7, 3)], "drops": [{"cell": Vector2i(6, 3), "dir": L}, {"cell": Vector2i(7, 3), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(2, 8), Vector2i(3, 8)], "drops": [{"cell": Vector2i(4, 7), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(2, 2), Vector2i(1, 2), Vector2i(2, 3), Vector2i(1, 3)], "drops": [{"cell": Vector2i(1, 2), "dir": L}]},
			{"type": "office", "cells": [Vector2i(2, 5), Vector2i(1, 5)], "drops": [{"cell": Vector2i(1, 5), "dir": L}]},
			{"type": "office", "cells": [Vector2i(7, 6), Vector2i(6, 6)], "drops": [{"cell": Vector2i(6, 6), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"patience": {"executive": 78.0},
		"stars": [430, 620, 780, 870],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[8, 3], [8, 2], [8, 1], [8, 0], [7, 0]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]]],
		"sols": [[[[0, 2], [0, 1], [1, 1], [2, 1], [3, 1], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]], [[0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]], [[5, 6], [5, 7]]], [[[8, 3], [8, 2], [8, 1], [8, 0], [7, 0]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]]], [[[8, 3], [8, 2], [8, 1], [8, 0], [7, 0]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]]], [[[8, 3], [8, 2], [8, 1], [8, 0], [7, 0]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]]]],
	},
	{
		"id": "XL9", "world": "CROSSLINK", "name": "Gridlock",
		"cols": 9, "rows": 9, "ground_row": 0, "blocked": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 8), Vector2i(7, 4), Vector2i(8, 0)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 8), Vector2i(2, 1), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 8), Vector2i(3, 1), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 2), Vector2i(5, 4), Vector2i(5, 6), Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 6), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(4, 0), Vector2i(4, 7), Vector2i(7, 7), Vector2i(4, 6), Vector2i(4, 2), Vector2i(5, 5), Vector2i(3, 0), Vector2i(5, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(7, 0), Vector2i(6, 0), Vector2i(5, 0), Vector2i(7, 1), Vector2i(6, 1), Vector2i(5, 1)], "drops": [{"cell": Vector2i(5, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(5, 7), Vector2i(6, 7)], "drops": [{"cell": Vector2i(5, 7), "dir": L}, {"cell": Vector2i(6, 7), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(1, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(3, 6), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)], "drops": [{"cell": Vector2i(3, 2), "dir": R}]},
			{"type": "office", "cells": [Vector2i(7, 5), Vector2i(6, 5)], "drops": [{"cell": Vector2i(6, 5), "dir": L}]},
			{"type": "office", "cells": [Vector2i(1, 0), Vector2i(2, 0)], "drops": [{"cell": Vector2i(2, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(7, 3), Vector2i(6, 3)], "drops": [{"cell": Vector2i(6, 3), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [410, 590, 740, 830],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[4, 0], [3, 0]], [[4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]],
		"sols": [[[[5, 3], [5, 4], [5, 5], [5, 6], [6, 6], [7, 6], [7, 7]], [[3, 0], [3, 1], [4, 1], [4, 2], [5, 2], [6, 2], [7, 2], [8, 2], [8, 3], [8, 4], [8, 5], [8, 6], [8, 7], [7, 7]], [[3, 0], [4, 0]]], [[[3, 0], [4, 0]], [[4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]], [[[4, 0], [3, 0]], [[4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]], [[[4, 0], [3, 0]], [[4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]]],
	},
	{
		"id": "XL10", "world": "CROSSLINK", "name": "Last Orders",
		"cols": 9, "rows": 9, "ground_row": 0, "blocked": [Vector2i(0, 3), Vector2i(0, 5), Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 4), Vector2i(3, 7), Vector2i(3, 8), Vector2i(8, 2), Vector2i(8, 8)],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 8), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 8), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 7), Vector2i(3, 8), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 5), Vector2i(6, 6), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)], "max": 3},
			{"cells": [Vector2i(6, 0), Vector2i(7, 7), Vector2i(4, 7), Vector2i(4, 6), Vector2i(7, 3), Vector2i(2, 2)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)], "drops": [{"cell": Vector2i(5, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(7, 8), Vector2i(6, 8), Vector2i(5, 8), Vector2i(4, 8), Vector2i(6, 7), Vector2i(5, 7)], "drops": [{"cell": Vector2i(6, 7), "dir": R}, {"cell": Vector2i(5, 7), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(1, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(3, 6), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(5, 3), Vector2i(6, 3), Vector2i(5, 4), Vector2i(6, 4)], "drops": [{"cell": Vector2i(6, 3), "dir": R}]},
			{"type": "office", "cells": [Vector2i(0, 2), Vector2i(1, 2)], "drops": [{"cell": Vector2i(1, 2), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT", "type": "standard", "color": COL_A},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
		],
		"quota": 20, "max_lost": 4, "shift": 60.0,
		"stars": [480, 700, 880, 970],
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[4, 7], [4, 6]], [[7, 3], [7, 4], [7, 5], [7, 6], [7, 7]], [[2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [6, 1], [6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [8, 3], [8, 4], [8, 5], [8, 6], [8, 7], [7, 7]]],
		"sols": [[[[4, 7], [4, 6], [5, 6], [6, 6], [7, 6], [7, 7]], [[2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [6, 1], [6, 0]], [[7, 7], [8, 7], [8, 6], [8, 5], [7, 5], [6, 5], [5, 5], [4, 5], [4, 4], [4, 3], [3, 3], [2, 3], [2, 2]]], [[[4, 6], [4, 7]], [[7, 3], [7, 4], [7, 5], [7, 6], [6, 6], [5, 6], [4, 6], [4, 7]], [[2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [6, 1], [6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [8, 3], [8, 4], [8, 5], [8, 6], [8, 7], [7, 7]]], [[[4, 7], [4, 6]], [[7, 3], [7, 4], [7, 5], [7, 6], [7, 7]], [[2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [6, 1], [6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [8, 3], [8, 4], [8, 5], [8, 6], [8, 7], [7, 7]]], [[[4, 7], [4, 6]], [[7, 3], [7, 4], [7, 5], [7, 6], [7, 7]], [[2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [6, 1], [6, 0], [7, 0], [7, 1], [7, 2], [7, 3], [8, 3], [8, 4], [8, 5], [8, 6], [8, 7], [7, 7]]]],
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
