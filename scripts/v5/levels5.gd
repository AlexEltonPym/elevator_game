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
const WORLDS := ["TUTORIAL", "CROSSLINK", "SKYSCRAPER"]

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
		"stars": [69, 101, 134, 163],   # opt~181, 4-star at ~90% (headroom)
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
		"stars": [51, 75, 99, 121],   # opt~134, 4-star at ~90% (headroom)
		"solution": [[[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]],
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]],  # atrium handoff: LIFT 1 (blue) up the left, LIFT 2 (green) down the right
		"sols": [[[[2, 2], [2, 1], [2, 0]], [[5, 0], [5, 1], [5, 2]]], [[[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]], [[[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]], [[[2, 4], [2, 3], [2, 2], [2, 1], [2, 0]], [[5, 4], [5, 3], [5, 2], [5, 1], [5, 0]]]],
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
		"stars": [40, 58, 76, 93],   # atrium play ~104 live, 4-star at ~90% (headroom); snake alt scores higher (softness)
		"solution": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]],  # atrium transfer: LIFT 1 drops at the atrium (2,4), LIFT 2 bridges up the right
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]],  # LIFT 1 up the left half; LIFT 2 bridges the atrium up the right half
		"sols": [[[[3, 8], [3, 7], [3, 6], [3, 5], [3, 4], [2, 4]], [[2, 2], [2, 1], [2, 0]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]], [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]], [[2, 4], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]]],
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
		# FIXED ROSTER (cargo tutorial): 8 freight runs (bay A -> cafe B, back to the bay) + 2
		# office commuters (lobby C -> offices D/E). Front-loads cargo so the freight lift is the
		# star; the two passengers keep the local lift relevant.
		"manifest": [
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "visitor", "from": "C", "to": "D"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "visitor", "from": "C", "to": "E"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
			{"type": "delivery", "from": "A", "to": "B", "return": "A"},
		],
		"stars": [90, 135, 180, 220],   # manifest roster (10 pax): hand solution ~244 live, 4-star at ~90%
		"solution": [[[3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[3, 6], [3, 5], [3, 4], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0]]],
		"demo": [[[2, 0], [2, 1], [2, 2], [2, 3], [2, 4], [2, 5], [2, 6], [3, 6]], [[3, 6], [3, 5], [3, 4], [3, 3], [3, 2], [3, 1], [3, 0]]],  # cargo runs bay up to the cafe; local threads the next column down to lobby
		"sols": [[[[2, 0], [3, 0]], [[3, 4], [3, 3], [3, 2], [3, 1], [3, 0], [2, 0]]], [[[3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[3, 6], [3, 5], [3, 4], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0]]], [[[3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[3, 6], [3, 5], [3, 4], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0]]], [[[3, 4], [3, 3], [3, 2], [3, 1], [3, 0]], [[3, 6], [3, 5], [3, 4], [2, 4], [2, 3], [2, 2], [2, 1], [2, 0], [3, 0]]]],
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
		"stars": [71, 105, 138, 168],   # opt~187, 4-star at ~90% (headroom)
		"solution": [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8]], [[4, 8], [3, 8], [3, 7], [3, 6], [3, 5], [3, 4], [3, 3], [2, 3], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [1, 10], [1, 9], [2, 9], [3, 9], [4, 9]]],
		"sols": [[[[4, 8], [4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [3, 1], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [1, 8], [2, 8], [3, 8]], [[4, 3], [3, 3], [3, 4], [3, 5], [3, 6], [4, 6]]], [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8]], [[1, 10], [1, 9], [2, 9], [2, 8], [2, 7], [2, 6], [2, 5], [2, 4], [2, 3], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10]]], [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8]], [[4, 8], [3, 8], [3, 7], [3, 6], [3, 5], [3, 4], [3, 3], [2, 3], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [1, 10], [1, 9], [2, 9], [3, 9], [4, 9]]], [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8]], [[4, 8], [3, 8], [3, 7], [3, 6], [3, 5], [3, 4], [3, 3], [2, 3], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [1, 10], [1, 9], [2, 9], [3, 9], [4, 9]]]],
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
		"stars": [135, 199, 263, 320],   # opt~356, 4-star at ~90% (headroom)
		"solution": [[[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3]], [[5, 3], [6, 3], [6, 4], [6, 5], [6, 6]], [[2, 3], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [6, 7], [5, 7]]],
		"sols": [[[[0, 5], [0, 4], [0, 3], [1, 3], [2, 3], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3]], [[6, 6], [6, 7], [5, 7]], [[6, 6], [6, 5], [6, 4], [6, 3], [5, 3]]], [[[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3]], [[5, 3], [6, 3], [6, 4], [6, 5], [6, 6]], [[2, 3], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [6, 7], [5, 7]]], [[[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3]], [[5, 3], [6, 3], [6, 4], [6, 5], [6, 6]], [[2, 3], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [6, 7], [5, 7]]], [[[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3]], [[5, 3], [6, 3], [6, 4], [6, 5], [6, 6]], [[2, 3], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [6, 7], [5, 7]]]],
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
		"stars": [156, 230, 304, 370],   # opt~411, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[1, 5], [1, 4], [2, 4], [2, 3]], [[4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [5, 1], [6, 1], [7, 1], [7, 2]], [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 3], [3, 3], [3, 4], [4, 4], [4, 5]]],
		"sols": [[[[4, 5], [4, 4]], [[1, 5], [1, 4], [2, 4], [2, 3], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]], [[7, 2], [7, 1], [6, 1], [5, 1], [4, 1], [4, 2], [4, 3], [4, 4], [4, 5]]], [[[1, 5], [1, 4], [2, 4], [2, 3]], [[4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [5, 1], [6, 1], [7, 1], [7, 2]], [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 3], [3, 3], [3, 4], [4, 4], [4, 5]]], [[[1, 5], [1, 4], [2, 4], [2, 3]], [[4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [5, 1], [6, 1], [7, 1], [7, 2]], [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 3], [3, 3], [3, 4], [4, 4], [4, 5]]], [[[1, 5], [1, 4], [2, 4], [2, 3]], [[4, 5], [4, 4], [4, 3], [4, 2], [4, 1], [5, 1], [6, 1], [7, 1], [7, 2]], [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2], [2, 3], [3, 3], [3, 4], [4, 4], [4, 5]]]],
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
		"stars": [130, 192, 253, 308],   # opt~342, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]],
		"sols": [[[[6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [6, 2], [5, 2], [4, 2], [3, 2]], [[0, 2], [0, 1], [1, 1], [1, 0]]], [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]], [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]], [[[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]], [[6, 3], [5, 3], [5, 2], [4, 2], [3, 2]], [[1, 0], [1, 1], [2, 1], [3, 1], [3, 2]]]],
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
		"stars": [111, 164, 216, 263],   # opt~292, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[7, 8], [7, 7], [7, 6], [7, 5], [6, 5], [6, 4], [6, 3], [6, 2], [5, 2], [4, 2], [4, 1], [4, 0]], [[3, 5], [3, 4], [3, 3], [3, 2], [3, 1]], [[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]]],
		"sols": [[[[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]], [[4, 0], [4, 1], [4, 2], [4, 3], [4, 4], [5, 4], [6, 4], [6, 5]], [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5]]], [[[7, 8], [7, 7], [7, 6], [7, 5], [6, 5], [6, 4], [6, 3], [6, 2], [5, 2], [4, 2], [4, 1], [4, 0]], [[3, 5], [3, 4], [3, 3], [3, 2], [3, 1]], [[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]]], [[[7, 8], [7, 7], [7, 6], [7, 5], [6, 5], [6, 4], [6, 3], [6, 2], [5, 2], [4, 2], [4, 1], [4, 0]], [[3, 5], [3, 4], [3, 3], [3, 2], [3, 1]], [[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]]], [[[7, 8], [7, 7], [7, 6], [7, 5], [6, 5], [6, 4], [6, 3], [6, 2], [5, 2], [4, 2], [4, 1], [4, 0]], [[3, 5], [3, 4], [3, 3], [3, 2], [3, 1]], [[3, 5], [2, 5], [2, 6], [1, 6], [1, 7]]]],
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
		"stars": [158, 233, 308, 374],   # opt~416, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [7, 0], [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 6], [7, 6], [6, 6], [6, 7]]],
		"sols": [[[[7, 3], [7, 4], [7, 5], [7, 6], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [1, 3], [2, 3], [3, 3]], [[3, 3], [3, 4]]], [[[6, 7], [6, 6], [6, 5], [5, 5], [4, 5], [4, 4], [3, 4], [3, 3]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [6, 1], [6, 2], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6], [6, 6], [6, 7]]], [[[3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [7, 0], [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 6], [7, 6], [6, 6], [6, 7]]], [[[3, 4], [4, 4], [4, 5], [5, 5], [6, 5], [6, 6], [6, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], [[6, 0], [7, 0], [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 6], [7, 6], [6, 6], [6, 7]]]],
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
		"stars": [127, 188, 248, 302],   # opt~335, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [3, 6], [2, 6], [2, 5], [1, 5], [1, 6], [1, 7]]],
		"sols": [[[[4, 7], [4, 6]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [4, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [8, 3], [8, 2], [8, 1], [8, 0]]], [[[4, 6], [3, 6], [2, 6], [1, 6], [1, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[4, 6], [4, 5], [5, 5], [6, 5], [7, 5], [7, 4], [7, 3], [7, 2], [7, 1], [7, 0]]], [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [5, 4], [4, 4], [4, 5], [4, 6], [3, 6], [2, 6], [1, 6], [1, 7]]], [[[4, 6], [4, 7]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [1, 7]], [[7, 0], [7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [6, 5], [5, 5], [4, 5], [4, 6], [3, 6], [2, 6], [2, 5], [1, 5], [1, 6], [1, 7]]]],
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
		"stars": [127, 188, 248, 302],   # opt~335, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[3, 3], [3, 4], [3, 5], [3, 6], [4, 6], [4, 5], [4, 4], [4, 3]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [1, 4], [1, 5], [0, 5], [0, 6]], [[4, 3], [3, 3], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]]],
		"sols": [[[[3, 3], [4, 3]], [[8, 3], [8, 4], [7, 4], [6, 4], [5, 4], [4, 4], [4, 5], [4, 6]], [[0, 6], [0, 5], [1, 5], [2, 5], [3, 5], [3, 6], [4, 6]]], [[[3, 6], [4, 6], [4, 5], [4, 4], [5, 4], [6, 4], [7, 4], [8, 4], [8, 3]], [[3, 3], [3, 4], [3, 5], [3, 6], [4, 6]], [[7, 0], [7, 1], [7, 2], [6, 2], [5, 2], [4, 2], [4, 3], [3, 3], [3, 2], [2, 2], [1, 2], [0, 2], [0, 1], [0, 0]]], [[[3, 6], [4, 6], [4, 5], [4, 4], [4, 3]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [1, 5], [2, 5], [3, 5], [3, 6], [4, 6]], [[7, 0], [7, 1], [7, 2], [6, 2], [5, 2], [4, 2], [4, 3], [3, 3]]], [[[3, 3], [3, 4], [3, 5], [3, 6], [4, 6], [4, 5], [4, 4], [4, 3]], [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [1, 4], [1, 5], [0, 5], [0, 6]], [[4, 3], [3, 3], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]]]],
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
		"stars": [95, 139, 184, 224],   # opt~249, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[5, 5], [4, 5], [3, 5], [2, 5], [1, 5], [0, 5], [0, 6]], [[2, 2], [2, 3], [2, 4], [3, 4], [4, 4], [5, 4], [5, 5]], [[7, 0], [7, 1], [8, 1], [8, 2], [7, 2], [6, 2], [5, 2], [4, 2], [3, 2], [3, 3], [4, 3], [5, 3], [6, 3], [6, 4], [7, 4], [8, 4], [8, 5]]],
		"sols": [[[[2, 1], [2, 2], [2, 3], [3, 3], [4, 3], [5, 3], [6, 3]], [[8, 5], [8, 4], [7, 4], [6, 4], [6, 3]], [[2, 1], [2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]]], [[[5, 5], [4, 5], [3, 5], [2, 5], [1, 5], [0, 5], [0, 6]], [[2, 2], [2, 3], [2, 4], [3, 4], [4, 4], [5, 4], [5, 5]], [[8, 5], [8, 4], [7, 4], [6, 4], [6, 3], [6, 2], [7, 2], [7, 1], [7, 0]]], [[[5, 5], [4, 5], [3, 5], [2, 5], [1, 5], [0, 5], [0, 6]], [[5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2]], [[7, 0], [7, 1], [7, 2], [6, 2], [6, 3], [6, 4], [7, 4], [8, 4], [8, 5]]], [[[5, 5], [4, 5], [3, 5], [2, 5], [1, 5], [0, 5], [0, 6]], [[2, 2], [2, 3], [2, 4], [3, 4], [4, 4], [5, 4], [5, 5]], [[7, 0], [7, 1], [8, 1], [8, 2], [7, 2], [6, 2], [5, 2], [4, 2], [3, 2], [3, 3], [4, 3], [5, 3], [6, 3], [6, 4], [7, 4], [8, 4], [8, 5]]]],
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
		"stars": [115, 169, 223, 272],   # opt~302, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[7, 0], [7, 1], [7, 2], [8, 2], [8, 3]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [4, 5], [5, 5], [5, 6], [5, 7]]],
		"sols": [[[[0, 2], [0, 1], [1, 1], [2, 1], [3, 1], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2], [7, 1], [7, 0]], [[0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]], [[5, 6], [5, 7]]], [[[0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]], [[8, 3], [8, 2], [8, 1], [8, 0], [7, 0]], [[7, 0], [7, 1], [7, 2], [6, 2], [5, 2], [5, 3], [4, 3], [4, 4], [4, 5], [5, 5], [5, 6], [5, 7]]], [[[7, 0], [7, 1], [7, 2], [8, 2], [8, 3]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [5, 7]]], [[[7, 0], [7, 1], [7, 2], [8, 2], [8, 3]], [[5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [2, 1], [1, 1], [0, 1], [0, 2]], [[5, 3], [4, 3], [4, 4], [3, 4], [2, 4], [1, 4], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [4, 5], [5, 5], [5, 6], [5, 7]]]],
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
		"stars": [142, 210, 278, 338],   # opt~375, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[3, 0], [4, 0]], [[4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]],
		"sols": [[[[4, 2], [4, 1], [4, 0], [3, 0]], [[3, 0], [3, 1], [2, 1], [1, 1], [1, 2], [1, 3], [1, 4], [2, 4], [3, 4], [4, 4], [4, 3], [4, 2], [5, 2], [5, 3]], [[4, 6], [5, 6], [5, 5], [5, 4], [5, 3]]], [[[4, 0], [3, 0]], [[4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]], [[4, 0], [4, 1], [4, 2], [5, 2], [5, 3], [5, 4], [5, 5], [5, 6], [4, 6], [4, 7]]], [[[3, 0], [4, 0]], [[4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]], [[[3, 0], [4, 0]], [[4, 7], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2]], [[4, 7], [4, 6], [5, 6], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [4, 1], [4, 0]]]],
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
		"stars": [152, 224, 296, 360],   # opt~400, 4-star at ~90% (headroom)
		"spawn": {"interval_start": 2.20, "interval_end": 1.70, "ramp": 40.00, "burst_min": 1, "burst_max": 2, "gap": 0.90, "cover": true},
		"mix": {"visitor": 0.60, "shopper": 0.25, "patient": 0.15},
		"solution": [[[4, 6], [4, 7]], [[7, 7], [7, 6], [7, 5], [7, 4], [7, 3]], [[7, 7], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [7, 3], [7, 2], [7, 1], [7, 0], [6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [2, 2], [2, 3], [3, 3], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]]],
		"sols": [[[[7, 7], [7, 6], [6, 6], [5, 6], [4, 6], [4, 7]], [[7, 7], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [7, 3]], [[7, 3], [7, 2], [7, 1], [7, 0], [6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [4, 3], [4, 4], [4, 5], [5, 5], [6, 5], [7, 5], [7, 4]]], [[[4, 6], [4, 7]], [[7, 7], [7, 6], [7, 5], [7, 4], [7, 3]], [[7, 7], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [7, 3], [7, 2], [7, 1], [7, 0], [6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [2, 2], [2, 3], [3, 3], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]]], [[[4, 6], [4, 7]], [[7, 7], [7, 6], [7, 5], [7, 4], [7, 3]], [[7, 7], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [7, 3], [7, 2], [7, 1], [7, 0], [6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [2, 2], [2, 3], [3, 3], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]]], [[[4, 6], [4, 7]], [[7, 7], [7, 6], [7, 5], [7, 4], [7, 3]], [[7, 7], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [7, 3], [7, 2], [7, 1], [7, 0], [6, 0], [6, 1], [6, 2], [5, 2], [4, 2], [3, 2], [2, 2], [2, 3], [3, 3], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7]]]],
	},
	{
		"id": "XL11", "world": "SKYSCRAPER", "name": "The Gauntlet", "thesis": "", "intro": "",
		"cols": 9, "rows": 12, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(0, 11), Vector2i(1, 2), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 9), Vector2i(1, 10), Vector2i(1, 11), Vector2i(2, 2), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 9), Vector2i(2, 10), Vector2i(2, 11), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 9), Vector2i(3, 11), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 9), Vector2i(4, 11), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 9), Vector2i(6, 0), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(7, 0), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 11), Vector2i(8, 0), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 11)], "max": 3},
			{"cells": [Vector2i(4, 0), Vector2i(4, 4), Vector2i(7, 4), Vector2i(3, 10), Vector2i(2, 3), Vector2i(1, 7), Vector2i(1, 8), Vector2i(5, 8), Vector2i(8, 1)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "drops": [{"cell": Vector2i(3, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(5, 4), Vector2i(6, 4)], "drops": [{"cell": Vector2i(5, 4), "dir": L}, {"cell": Vector2i(6, 4), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(7, 10), Vector2i(6, 10), Vector2i(5, 10), Vector2i(4, 10), Vector2i(6, 11), Vector2i(5, 11)], "drops": [{"cell": Vector2i(4, 10), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4), Vector2i(1, 4)], "drops": [{"cell": Vector2i(1, 3), "dir": R}]},
			{"type": "office", "cells": [Vector2i(3, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(2, 7), "dir": L}]},
			{"type": "atrium", "cells": [Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8)], "drops": [{"cell": Vector2i(2, 8), "dir": L}, {"cell": Vector2i(4, 8), "dir": R}]},
			{"type": "office", "cells": [Vector2i(6, 1), Vector2i(7, 1)], "drops": [{"cell": Vector2i(7, 1), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": Color(0.46, 0.84, 0.52)},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"stars": [222, 326, 431, 525],   # opt~583 (90s), 4-star ~90% headroom; deep sweep (adept~417 -> optimal~583)
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.10, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.10, "from": "A", "to": "E"},
			{"w": 0.06, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "G"},
			{"w": 0.06, "from": "G", "to": "A"},
			{"w": 0.14, "from": "D", "to": "B", "type": "delivery", "return": "A"},
		],
		"solution": [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4]], [[1, 7], [1, 8], [1, 9], [1, 10], [2, 10], [3, 10]], [[1, 7], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11], [1, 11], [2, 11], [3, 11], [3, 10], [3, 9], [4, 9], [5, 9], [6, 9], [7, 9], [8, 9], [8, 8], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0], [7, 0], [6, 0], [5, 0], [4, 0]], [[2, 3], [2, 4], [3, 4], [4, 4]]],
		"sols": [[[[3, 10], [3, 9], [2, 9], [1, 9], [1, 8], [1, 7]], [[2, 3], [2, 4], [2, 5], [2, 6], [1, 6], [1, 7], [1, 8]], [[7, 4], [7, 3], [7, 2], [6, 2], [5, 2], [5, 1], [5, 0], [4, 0]], [[5, 8], [6, 8], [7, 8], [8, 8], [8, 7], [8, 6], [8, 5], [8, 4], [7, 4]]], [[[4, 4], [3, 4], [3, 5], [3, 6], [2, 6], [1, 6], [1, 7], [1, 8]], [[3, 10], [3, 9], [2, 9], [1, 9], [1, 8], [1, 7]], [[5, 8], [6, 8], [7, 8], [8, 8], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0], [7, 0], [6, 0], [5, 0], [4, 0]], [[2, 3], [3, 3], [4, 3], [4, 4]]], [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4]], [[1, 7], [1, 8], [1, 9], [1, 10], [2, 10], [3, 10], [3, 9], [4, 9], [5, 9], [5, 8]], [[3, 10], [3, 11], [2, 11], [1, 11], [0, 11], [0, 10], [0, 9], [0, 8], [0, 7], [1, 7], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6], [6, 6], [7, 6], [8, 6], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0], [7, 0], [6, 0], [5, 0], [4, 0]], [[2, 3], [2, 4], [3, 4], [4, 4]]], [[[4, 0], [4, 1], [4, 2], [4, 3], [4, 4]], [[1, 7], [1, 8], [1, 9], [1, 10], [2, 10], [3, 10]], [[1, 7], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11], [1, 11], [2, 11], [3, 11], [3, 10], [3, 9], [4, 9], [5, 9], [6, 9], [7, 9], [8, 9], [8, 8], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0], [7, 0], [6, 0], [5, 0], [4, 0]], [[2, 3], [2, 4], [3, 4], [4, 4]]]],
	},
	{
		"id": "XL12", "world": "SKYSCRAPER", "name": "Loading Bay", "thesis": "", "intro": "",
		"cols": 10, "rows": 11, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 10), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 10), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 10), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 10), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 10), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 9), Vector2i(9, 10)], "max": 3},
			{"cells": [Vector2i(1, 0), Vector2i(3, 8), Vector2i(6, 8), Vector2i(9, 0), Vector2i(5, 2), Vector2i(4, 4), Vector2i(3, 7), Vector2i(5, 5)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(4, 0), Vector2i(3, 0), Vector2i(2, 0), Vector2i(4, 1), Vector2i(3, 1), Vector2i(2, 1)], "drops": [{"cell": Vector2i(2, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9), Vector2i(6, 9), Vector2i(4, 8), Vector2i(5, 8)], "drops": [{"cell": Vector2i(4, 8), "dir": L}, {"cell": Vector2i(5, 8), "dir": R}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(7, 0), Vector2i(8, 0), Vector2i(7, 1), Vector2i(8, 1)], "drops": [{"cell": Vector2i(8, 0), "dir": R}]},
			{"type": "office", "cells": [Vector2i(7, 2), Vector2i(6, 2)], "drops": [{"cell": Vector2i(6, 2), "dir": L}]},
			{"type": "office", "cells": [Vector2i(2, 4), Vector2i(3, 4)], "drops": [{"cell": Vector2i(3, 4), "dir": R}]},
			{"type": "office", "cells": [Vector2i(1, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(2, 7), "dir": R}]},
			{"type": "office", "cells": [Vector2i(7, 5), Vector2i(6, 5)], "drops": [{"cell": Vector2i(6, 5), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": Color(0.46, 0.84, 0.52)},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.10, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.10, "from": "A", "to": "D"},
			{"w": 0.06, "from": "D", "to": "A"},
			{"w": 0.10, "from": "A", "to": "E"},
			{"w": 0.06, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "F"},
			{"w": 0.06, "from": "F", "to": "A"},
			{"w": 0.10, "from": "A", "to": "G"},
			{"w": 0.06, "from": "G", "to": "A"},
			{"w": 0.14, "from": "C", "to": "B", "type": "delivery", "return": "A"},
		],
		"solution": [[[1, 0], [1, 1], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3], [5, 4], [4, 4], [4, 5], [5, 5]], [[3, 7], [3, 8], [2, 8], [1, 8], [0, 8], [0, 7], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0], [1, 0]], [[9, 0], [9, 1], [9, 2], [9, 3], [9, 4], [9, 5], [9, 6], [9, 7], [9, 8], [8, 8], [7, 8], [6, 8]]],
		"stars": [260, 280, 300, 330],   # floor-anchored, 4* at ~90% of live ceil 377
		"sols": [[[[4, 4], [4, 5], [4, 6], [4, 7], [3, 7]], [[1, 0], [1, 1], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2]], [[4, 4], [4, 3], [3, 3], [2, 3], [1, 3], [1, 4], [1, 5], [1, 6], [2, 6], [3, 6], [3, 7], [3, 8], [2, 8], [2, 9], [2, 10], [3, 10], [4, 10], [5, 10], [6, 10], [7, 10], [7, 9], [7, 8], [7, 7], [7, 6], [6, 6], [5, 6], [5, 5], [5, 4], [6, 4], [7, 4], [8, 4], [9, 4], [9, 3], [9, 2], [9, 1], [9, 0]]], [[[4, 4], [5, 4], [6, 4], [7, 4], [8, 4], [8, 3], [7, 3], [6, 3], [5, 3], [5, 2], [4, 2], [3, 2], [2, 2], [1, 2], [1, 1], [1, 0]], [[3, 8], [3, 7], [3, 6], [3, 5], [2, 5], [1, 5], [1, 4], [1, 3], [0, 3], [0, 2], [0, 1], [0, 0], [1, 0]], [[9, 0], [9, 1], [9, 2], [9, 3], [9, 4], [9, 5], [9, 6], [9, 7], [8, 7], [7, 7], [6, 7], [5, 7], [4, 7], [3, 7], [3, 8]]], [[[5, 2], [5, 3], [5, 4], [5, 5], [4, 5], [4, 4], [4, 3], [4, 2], [3, 2], [2, 2], [1, 2], [1, 1], [1, 0]], [[3, 7], [3, 8], [2, 8], [1, 8], [0, 8], [0, 7], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0], [1, 0]], [[9, 0], [9, 1], [9, 2], [9, 3], [9, 4], [9, 5], [9, 6], [9, 7], [9, 8], [8, 8], [7, 8], [6, 8]]], [[[1, 0], [1, 1], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [5, 3], [5, 4], [4, 4], [4, 5], [5, 5]], [[3, 7], [3, 8], [2, 8], [1, 8], [0, 8], [0, 7], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [0, 1], [0, 0], [1, 0]], [[9, 0], [9, 1], [9, 2], [9, 3], [9, 4], [9, 5], [9, 6], [9, 7], [9, 8], [8, 8], [7, 8], [6, 8]]]],
	},
	{
		"id": "XL13", "world": "SKYSCRAPER", "name": "Crossover", "thesis": "", "intro": "",
		"cols": 10, "rows": 12, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 10), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 6), Vector2i(1, 10), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 6), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 11), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 11), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 9), Vector2i(7, 11), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 9), Vector2i(8, 11), Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 9), Vector2i(9, 10), Vector2i(9, 11)], "max": 3},
			{"cells": [Vector2i(5, 0), Vector2i(4, 7), Vector2i(1, 7), Vector2i(0, 9), Vector2i(3, 4), Vector2i(8, 10), Vector2i(1, 0), Vector2i(0, 11), Vector2i(7, 8)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(8, 0), Vector2i(7, 0), Vector2i(6, 0), Vector2i(8, 1), Vector2i(7, 1), Vector2i(6, 1)], "drops": [{"cell": Vector2i(6, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(4, 8), Vector2i(3, 8), Vector2i(2, 8), Vector2i(1, 8), Vector2i(3, 7), Vector2i(2, 7)], "drops": [{"cell": Vector2i(3, 7), "dir": R}, {"cell": Vector2i(2, 7), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(4, 9), Vector2i(3, 9), Vector2i(2, 9), Vector2i(1, 9), Vector2i(3, 10), Vector2i(2, 10)], "drops": [{"cell": Vector2i(1, 9), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(1, 4), Vector2i(2, 4), Vector2i(1, 5), Vector2i(2, 5)], "drops": [{"cell": Vector2i(2, 4), "dir": R}]},
			{"type": "penthouse", "cells": [Vector2i(4, 10), Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10), Vector2i(5, 11), Vector2i(6, 11)], "drops": [{"cell": Vector2i(7, 10), "dir": R}]},
			{"type": "office", "cells": [Vector2i(3, 0), Vector2i(2, 0)], "drops": [{"cell": Vector2i(2, 0), "dir": L}]},
			{"type": "office", "cells": [Vector2i(2, 11), Vector2i(1, 11)], "drops": [{"cell": Vector2i(1, 11), "dir": L}]},
			{"type": "office", "cells": [Vector2i(9, 8), Vector2i(8, 8)], "drops": [{"cell": Vector2i(8, 8), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": Color(0.46, 0.84, 0.52)},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.10, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.16, "from": "A", "to": "E"},
			{"w": 0.10, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "F"},
			{"w": 0.06, "from": "F", "to": "A"},
			{"w": 0.10, "from": "A", "to": "G"},
			{"w": 0.06, "from": "G", "to": "A"},
			{"w": 0.10, "from": "A", "to": "H"},
			{"w": 0.06, "from": "H", "to": "A"},
			{"w": 0.14, "from": "D", "to": "B", "type": "delivery", "return": "A"},
		],
		"solution": [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4], [5, 5], [6, 5], [7, 5], [7, 6], [6, 6], [6, 7], [6, 8], [7, 8], [7, 9], [6, 9], [5, 9], [5, 8], [5, 7], [4, 7]], [[1, 7], [1, 6], [2, 6], [3, 6], [3, 5], [3, 4]], [[5, 0], [4, 0], [4, 1], [4, 2], [3, 2], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11]], [[3, 4], [4, 4], [4, 5], [4, 6], [4, 7]]],
		"stars": [230, 270, 310, 360],   # floor-anchored, 4* at ~90% of live ceil 408
		"sols": [[[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4], [5, 5], [6, 5], [7, 5], [7, 6], [6, 6], [6, 7], [6, 8], [7, 8], [7, 9], [6, 9], [5, 9], [5, 8], [5, 7], [4, 7]], [[1, 7], [1, 6], [2, 6], [3, 6], [3, 5], [3, 4]], [[5, 0], [4, 0], [4, 1], [4, 2], [3, 2], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11]], [[3, 4], [4, 4], [4, 5], [4, 6], [4, 7]]], [[[1, 0], [1, 1], [2, 1], [3, 1], [4, 1], [5, 1], [5, 0]], [[1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11]], [[1, 7], [1, 6], [2, 6], [3, 6], [3, 5], [3, 4]], [[3, 4], [4, 4], [4, 5], [4, 6], [4, 7], [5, 7], [5, 8], [5, 9], [6, 9], [7, 9], [8, 9], [8, 10]]], [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4], [5, 5], [5, 6], [5, 7], [4, 7]], [[1, 7], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11]], [[1, 0], [1, 1], [2, 1], [3, 1], [4, 1], [4, 0], [5, 0]], [[3, 4], [3, 5], [3, 6], [4, 6], [4, 7]]], [[[5, 0], [5, 1], [5, 2], [5, 3], [5, 4], [5, 5], [6, 5], [7, 5], [7, 6], [6, 6], [6, 7], [6, 8], [7, 8], [7, 9], [6, 9], [5, 9], [5, 8], [5, 7], [4, 7]], [[1, 7], [1, 6], [2, 6], [3, 6], [3, 5], [3, 4]], [[5, 0], [4, 0], [4, 1], [4, 2], [3, 2], [2, 2], [2, 1], [1, 1], [1, 0], [0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11]], [[3, 4], [4, 4], [4, 5], [4, 6], [4, 7]]]],
	},
	{
		"id": "XL14", "world": "SKYSCRAPER", "name": "Ascent", "thesis": "", "intro": "",
		"cols": 10, "rows": 12, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 9), Vector2i(0, 11), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 9), Vector2i(1, 11), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 9), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 9), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 9), Vector2i(4, 11), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 5), Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 11), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 5), Vector2i(6, 8), Vector2i(6, 9), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 5), Vector2i(7, 8), Vector2i(7, 9), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 5), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 11), Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 9), Vector2i(9, 11)], "max": 3},
			{"cells": [Vector2i(3, 0), Vector2i(8, 6), Vector2i(5, 6), Vector2i(0, 10), Vector2i(0, 4), Vector2i(9, 10), Vector2i(3, 3), Vector2i(9, 3), Vector2i(9, 4), Vector2i(5, 4), Vector2i(0, 8), Vector2i(4, 8)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(6, 0), Vector2i(5, 0), Vector2i(4, 0), Vector2i(6, 1), Vector2i(5, 1), Vector2i(4, 1)], "drops": [{"cell": Vector2i(4, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(8, 7), Vector2i(7, 7), Vector2i(6, 7), Vector2i(5, 7), Vector2i(7, 6), Vector2i(6, 6)], "drops": [{"cell": Vector2i(7, 6), "dir": R}, {"cell": Vector2i(6, 6), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(4, 10), Vector2i(3, 10), Vector2i(2, 10), Vector2i(1, 10), Vector2i(3, 11), Vector2i(2, 11)], "drops": [{"cell": Vector2i(1, 10), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(2, 4), Vector2i(1, 4), Vector2i(2, 5), Vector2i(1, 5)], "drops": [{"cell": Vector2i(1, 4), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10), Vector2i(6, 11), Vector2i(7, 11)], "drops": [{"cell": Vector2i(8, 10), "dir": R}]},
			{"type": "office", "cells": [Vector2i(1, 3), Vector2i(2, 3)], "drops": [{"cell": Vector2i(2, 3), "dir": R}]},
			{"type": "office", "cells": [Vector2i(7, 3), Vector2i(8, 3)], "drops": [{"cell": Vector2i(8, 3), "dir": R}]},
			{"type": "atrium", "cells": [Vector2i(8, 4), Vector2i(7, 4), Vector2i(6, 4)], "drops": [{"cell": Vector2i(8, 4), "dir": R}, {"cell": Vector2i(6, 4), "dir": L}]},
			{"type": "atrium", "cells": [Vector2i(1, 8), Vector2i(2, 8), Vector2i(3, 8)], "drops": [{"cell": Vector2i(1, 8), "dir": L}, {"cell": Vector2i(3, 8), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": Color(0.46, 0.84, 0.52)},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.10, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.16, "from": "A", "to": "E"},
			{"w": 0.10, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "F"},
			{"w": 0.06, "from": "F", "to": "A"},
			{"w": 0.10, "from": "A", "to": "G"},
			{"w": 0.06, "from": "G", "to": "A"},
			{"w": 0.14, "from": "D", "to": "B", "type": "delivery", "return": "A"},
		],
		"solution": [[[8, 6], [9, 6], [9, 7], [9, 8], [9, 9], [9, 10]], [[3, 3], [4, 3], [5, 3], [6, 3], [6, 2], [7, 2], [8, 2], [9, 2], [9, 3], [9, 4]], [[3, 0], [3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [4, 5], [5, 5], [6, 5], [7, 5], [8, 5], [8, 6]], [[0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6]]],
		"stars": [170, 210, 250, 300],   # floor-anchored, 4* at ~90% of live ceil 340
		"sols": [[[[3, 3], [3, 4], [3, 5], [3, 6], [3, 7], [4, 7], [4, 8], [4, 9], [5, 9], [6, 9], [7, 9], [8, 9], [9, 9], [9, 10]], [[9, 3], [9, 4]], [[4, 8], [5, 8], [6, 8], [7, 8], [8, 8], [9, 8], [9, 7], [9, 6], [8, 6], [8, 5], [7, 5], [6, 5], [5, 5], [5, 4], [5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [3, 0]], [[0, 10], [0, 9], [0, 8], [0, 7], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [1, 2], [2, 2], [2, 1], [2, 0], [3, 0]]], [[[5, 6], [4, 6], [4, 7], [3, 7], [2, 7], [1, 7], [0, 7], [0, 8]], [[3, 0], [3, 1], [3, 2], [3, 3], [4, 3], [5, 3], [6, 3], [6, 2], [7, 2], [8, 2], [9, 2], [9, 3]], [[3, 0], [2, 0], [2, 1], [2, 2], [1, 2], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [3, 5], [4, 5], [5, 5], [6, 5], [7, 5], [8, 5], [8, 6]], [[9, 10], [9, 9], [9, 8], [9, 7], [9, 6], [8, 6]]], [[[5, 6], [4, 6], [4, 7], [4, 8], [4, 9], [3, 9], [2, 9], [1, 9], [0, 9], [0, 10]], [[3, 0], [3, 1], [3, 2], [3, 3], [4, 3], [5, 3], [6, 3], [6, 2], [7, 2], [8, 2], [9, 2], [9, 3], [9, 4]], [[8, 6], [8, 5], [7, 5], [6, 5], [5, 5], [4, 5], [3, 5], [3, 6], [2, 6], [1, 6], [0, 6], [0, 5], [0, 4], [0, 3], [0, 2], [1, 2], [2, 2], [2, 1], [2, 0], [3, 0]], [[8, 6], [9, 6], [9, 7], [9, 8], [9, 9], [9, 10]]], [[[8, 6], [9, 6], [9, 7], [9, 8], [9, 9], [9, 10]], [[3, 3], [4, 3], [5, 3], [6, 3], [6, 2], [7, 2], [8, 2], [9, 2], [9, 3], [9, 4]], [[3, 0], [3, 1], [3, 2], [3, 3], [3, 4], [3, 5], [4, 5], [5, 5], [6, 5], [7, 5], [8, 5], [8, 6]], [[0, 4], [0, 5], [0, 6], [1, 6], [2, 6], [3, 6], [4, 6], [5, 6]]]],
	},
	{
		"id": "XL15", "world": "SKYSCRAPER", "name": "The Spire", "thesis": "", "intro": "",
		"cols": 10, "rows": 13, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(0, 11), Vector2i(0, 12), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(1, 12), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 4), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(2, 12), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 6), Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(4, 2), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 8), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 8), Vector2i(5, 12), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 6), Vector2i(6, 8), Vector2i(6, 11), Vector2i(6, 12), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 6), Vector2i(7, 8), Vector2i(7, 12), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 12), Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 9), Vector2i(9, 10), Vector2i(9, 12)], "max": 3},
			{"cells": [Vector2i(3, 0), Vector2i(7, 9), Vector2i(4, 9), Vector2i(1, 11), Vector2i(5, 4), Vector2i(9, 11), Vector2i(1, 5), Vector2i(7, 7), Vector2i(3, 7), Vector2i(4, 3)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(6, 0), Vector2i(5, 0), Vector2i(4, 0), Vector2i(6, 1), Vector2i(5, 1), Vector2i(4, 1)], "drops": [{"cell": Vector2i(4, 0), "dir": L}]},
			{"type": "cafe", "cells": [Vector2i(7, 10), Vector2i(6, 10), Vector2i(5, 10), Vector2i(4, 10), Vector2i(6, 9), Vector2i(5, 9)], "drops": [{"cell": Vector2i(6, 9), "dir": R}, {"cell": Vector2i(5, 9), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(5, 11), Vector2i(4, 11), Vector2i(3, 11), Vector2i(2, 11), Vector2i(4, 12), Vector2i(3, 12)], "drops": [{"cell": Vector2i(2, 11), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(7, 4), Vector2i(6, 4), Vector2i(7, 5), Vector2i(6, 5)], "drops": [{"cell": Vector2i(6, 4), "dir": L}]},
			{"type": "office", "cells": [Vector2i(7, 11), Vector2i(8, 11)], "drops": [{"cell": Vector2i(8, 11), "dir": R}]},
			{"type": "office", "cells": [Vector2i(3, 5), Vector2i(2, 5)], "drops": [{"cell": Vector2i(2, 5), "dir": L}]},
			{"type": "atrium", "cells": [Vector2i(6, 7), Vector2i(5, 7), Vector2i(4, 7)], "drops": [{"cell": Vector2i(6, 7), "dir": R}, {"cell": Vector2i(4, 7), "dir": L}]},
			{"type": "office", "cells": [Vector2i(2, 3), Vector2i(3, 3)], "drops": [{"cell": Vector2i(3, 3), "dir": R}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": Color(0.46, 0.84, 0.52)},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.10, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.10, "from": "A", "to": "E"},
			{"w": 0.06, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "F"},
			{"w": 0.06, "from": "F", "to": "A"},
			{"w": 0.10, "from": "A", "to": "H"},
			{"w": 0.06, "from": "H", "to": "A"},
			{"w": 0.14, "from": "D", "to": "B", "type": "delivery", "return": "A"},
		],
		"solution": [[[9, 11], [9, 10], [9, 9], [8, 9], [7, 9]], [[1, 5], [1, 4], [2, 4], [3, 4], [4, 4], [4, 3], [4, 2], [3, 2], [3, 1], [3, 0]], [[3, 0], [2, 0], [2, 1], [2, 2], [1, 2], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11], [1, 11], [1, 10], [2, 10], [3, 10], [3, 9], [4, 9]], [[5, 4], [5, 5], [5, 6], [6, 6], [7, 6], [7, 7], [7, 8], [7, 9]]],
		"stars": [140, 210, 290, 370],   # floor-anchored, 4* at ~90% of live ceil 417
		"sols": [[[[5, 4], [4, 4], [3, 4], [2, 4], [1, 4], [1, 5]], [[3, 7], [3, 8], [4, 8], [5, 8], [6, 8], [7, 8], [7, 7], [7, 6], [6, 6], [5, 6], [4, 6], [3, 6], [2, 6], [2, 7], [2, 8], [2, 9], [2, 10], [1, 10], [1, 11]], [[1, 11], [0, 11], [0, 10], [0, 9], [1, 9], [1, 8], [1, 7], [1, 6], [1, 5]], [[7, 9], [8, 9], [8, 8], [8, 7], [8, 6], [8, 5], [8, 4], [8, 3], [7, 3], [6, 3], [5, 3], [5, 4]]], [[[5, 4], [5, 5], [5, 6], [6, 6], [7, 6], [7, 7], [7, 8], [7, 9], [8, 9], [8, 10], [9, 10], [9, 11]], [[4, 9], [3, 9], [3, 10], [2, 10], [1, 10], [1, 11]], [[5, 4], [5, 3], [5, 2], [4, 2], [3, 2], [3, 1], [3, 0], [2, 0], [2, 1], [2, 2], [1, 2], [1, 3], [1, 4], [1, 5]], [[3, 7], [3, 6], [2, 6], [1, 6], [1, 5]]], [[[7, 7], [7, 8], [6, 8], [5, 8], [4, 8], [4, 9]], [[4, 9], [3, 9], [3, 8], [3, 7], [3, 6], [4, 6], [4, 5], [4, 4], [4, 3], [4, 2], [3, 2], [3, 1], [3, 0]], [[3, 0], [2, 0], [2, 1], [2, 2], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [1, 7], [1, 8], [1, 9], [1, 10], [1, 11]], [[7, 9], [8, 9], [8, 8], [8, 7], [8, 6], [7, 6], [6, 6], [5, 6], [5, 5], [5, 4]]], [[[9, 11], [9, 10], [9, 9], [8, 9], [7, 9]], [[1, 5], [1, 4], [2, 4], [3, 4], [4, 4], [4, 3], [4, 2], [3, 2], [3, 1], [3, 0]], [[3, 0], [2, 0], [2, 1], [2, 2], [1, 2], [1, 3], [0, 3], [0, 4], [0, 5], [0, 6], [0, 7], [0, 8], [0, 9], [0, 10], [0, 11], [1, 11], [1, 10], [2, 10], [3, 10], [3, 9], [4, 9]], [[5, 4], [5, 5], [5, 6], [6, 6], [7, 6], [7, 7], [7, 8], [7, 9]]]],
	},
	{
		"id": "XL16", "world": "SKYSCRAPER", "name": "Skyline", "thesis": "", "intro": "",
		"cols": 10, "rows": 12, "blocked": [],
		"overlaps": [
			{"cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 11), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 11), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 5), Vector2i(4, 7), Vector2i(4, 11), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 7), Vector2i(5, 11), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 7), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 9), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 9), Vector2i(8, 11), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 9), Vector2i(9, 11)], "max": 3},
			{"cells": [Vector2i(9, 0), Vector2i(6, 8), Vector2i(3, 8), Vector2i(0, 10), Vector2i(3, 3), Vector2i(9, 10), Vector2i(6, 6), Vector2i(7, 8)], "max": 6},
		],
		"rooms": [
			{"type": "lobby", "cells": [Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1)], "drops": [{"cell": Vector2i(8, 0), "dir": R}]},
			{"type": "cafe", "cells": [Vector2i(6, 9), Vector2i(5, 9), Vector2i(4, 9), Vector2i(3, 9), Vector2i(5, 8), Vector2i(4, 8)], "drops": [{"cell": Vector2i(5, 8), "dir": R}, {"cell": Vector2i(4, 8), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(4, 10), Vector2i(3, 10), Vector2i(2, 10), Vector2i(1, 10), Vector2i(3, 11), Vector2i(2, 11)], "drops": [{"cell": Vector2i(1, 10), "dir": L}]},
			{"type": "delivery", "label": "storage", "cells": [Vector2i(5, 3), Vector2i(4, 3), Vector2i(5, 4), Vector2i(4, 4)], "drops": [{"cell": Vector2i(4, 3), "dir": L}]},
			{"type": "penthouse", "cells": [Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10), Vector2i(6, 11), Vector2i(7, 11)], "drops": [{"cell": Vector2i(8, 10), "dir": R}]},
			{"type": "office", "cells": [Vector2i(4, 6), Vector2i(5, 6)], "drops": [{"cell": Vector2i(5, 6), "dir": R}]},
			{"type": "office", "cells": [Vector2i(9, 8), Vector2i(8, 8)], "drops": [{"cell": Vector2i(8, 8), "dir": L}]},
		],
		"cards": [
			{"name": "LIFT 1", "type": "standard", "color": COL_A},
			{"name": "LIFT 2", "type": "standard", "color": Color(0.46, 0.84, 0.52)},
			{"name": "EXPRESS", "type": "express", "color": COL_D, "speed": 1500.0, "accel": 1200.0},
			{"name": "CARGO", "type": "cargo", "color": COL_C, "speed": 100.0, "accel": 80.0},
		],
		"quota": 20, "max_lost": 4, "shift": 90.0,
		"spawn": {"interval_start": 2.2, "interval_end": 1.7, "ramp": 40.0, "burst_min": 1, "burst_max": 2, "gap": 0.9, "cover": true},
		"mix": {"visitor": 0.6, "shopper": 0.25, "patient": 0.15},
		"trips": [
			{"w": 0.10, "from": "A", "to": "B"},
			{"w": 0.06, "from": "B", "to": "A"},
			{"w": 0.16, "from": "A", "to": "C"},
			{"w": 0.10, "from": "C", "to": "A"},
			{"w": 0.16, "from": "A", "to": "E"},
			{"w": 0.10, "from": "E", "to": "A"},
			{"w": 0.10, "from": "A", "to": "F"},
			{"w": 0.06, "from": "F", "to": "A"},
			{"w": 0.10, "from": "A", "to": "G"},
			{"w": 0.06, "from": "G", "to": "A"},
			{"w": 0.14, "from": "D", "to": "B", "type": "delivery", "return": "A"},
		],
		"solution": [[[6, 8], [7, 8], [7, 9], [8, 9], [9, 9], [9, 10]], [[6, 8], [7, 8]], [[9, 0], [9, 1], [9, 2], [8, 2], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6], [6, 7], [6, 8]], [[3, 3], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]],
		"stars": [150, 220, 300, 380],   # floor-anchored, 4* at ~90% of live ceil 424
		"sols": [[[[3, 8], [3, 7], [4, 7], [5, 7], [6, 7], [6, 6]], [[9, 10], [9, 9], [8, 9], [7, 9], [7, 8], [7, 7], [8, 7], [9, 7], [9, 6], [9, 5], [9, 4], [9, 3], [9, 2], [9, 1], [9, 0]], [[3, 8], [2, 8], [2, 9], [1, 9], [0, 9], [0, 10]], [[6, 8], [7, 8]]], [[[6, 6], [6, 7], [6, 8]], [[3, 8], [3, 7], [3, 6], [3, 5], [3, 4], [3, 3], [2, 3], [2, 4], [2, 5], [2, 6], [2, 7], [2, 8]], [[9, 10], [9, 9], [8, 9], [7, 9], [7, 8], [7, 7], [7, 6], [6, 6], [6, 5], [7, 5], [8, 5], [9, 5], [9, 4], [9, 3], [9, 2], [9, 1], [9, 0]], [[6, 8], [7, 8]]], [[[6, 8], [7, 8], [7, 9], [8, 9], [9, 9], [9, 10]], [[9, 0], [9, 1], [9, 2], [9, 3], [9, 4], [9, 5], [8, 5], [7, 5], [6, 5], [6, 6], [6, 7], [6, 8]], [[6, 8], [7, 8]], [[3, 3], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]], [[[6, 8], [7, 8], [7, 9], [8, 9], [9, 9], [9, 10]], [[6, 8], [7, 8]], [[9, 0], [9, 1], [9, 2], [8, 2], [7, 2], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6], [6, 7], [6, 8]], [[3, 3], [3, 4], [3, 5], [3, 6], [3, 7], [3, 8]]]],
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
