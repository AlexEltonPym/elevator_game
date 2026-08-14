extends Node2D
## PIXELSPACES level-layout look-test — tetris rooms as islands, a shaft network weaving
## around them, and a REVISED elevator model:
##   • DOCKS = the PixelSpaces elevator sprite used as LANDING DOORS (full tile), one on
##     each room's shaft edge. Closed by default.
##   • CARS = our own programmer-art boxes that ride the shaft behind the doors.
##   • When a car reaches a dock, the landing door AND the car doors open in sync (IRL).
## NOT the game.  godot --path . scenes/pixel_demo.tscn   (+ -- --shot <png>)
## (parse-check first:  godot --headless --path . scenes/pixel_demo.tscn --quit-after 30 )

const PS := "res://assets/pixel/pixelspaces/"
const NPC := PS + "Pre-made NPCs/"

const S := 3
const CELL := 24
const GC := 9
const GR := 12
const UI_H := 150

const WALK := [1, 3]
const SHAFT := 0
const ROOM := 1
const SOLID := 2
const WINDOW := 3

# Car columns stay clear shaft (the lifts ride them). Rooms live in the gaps.
const CAR_COLS := [2, 5, 7]

# Irregular rooms (islands) + their DOCK [car_col, row] (a landing on an adjacent shaft col).
const ROOMS := [
	{"kind": "penthouse", "cells": [[0, 0], [1, 0], [0, 1]], "dock": [2, 0]},           # L
	{"kind": "office", "cells": [[3, 0], [4, 0], [3, 1]], "dock": [5, 0]},              # L
	{"kind": "apartment", "cells": [[0, 5], [1, 5], [0, 6], [1, 6]], "dock": [2, 5]},   # square
	{"kind": "cafe", "cells": [[6, 3], [6, 4], [6, 5]], "dock": [7, 4]},                # I
	{"kind": "atrium", "cells": [[4, 6], [3, 7], [4, 7], [4, 8]], "dock": [5, 7]},      # plus (centre)
	{"kind": "studio", "cells": [[8, 8], [8, 9], [8, 10]], "dock": [7, 9]},             # I
	{"kind": "lobby", "cells": [[0, 10], [1, 10], [0, 11], [1, 11]], "dock": [2, 10]},  # square
]
const BLOCKS := [[3, 3], [4, 4], [6, 7], [3, 9], [6, 1]]
const WINS := [[3, 2], [4, 2], [6, 2], [0, 8], [8, 2], [3, 5]]

const FURN := {
	"penthouse": [["Furniture/Living Room/Couch_large_red.png", 3]],
	"office": [["Furniture/Bedroom/Cabinet_1.png", 3]],
	"apartment": [["Furniture/Bedroom/Bed_red.png", 3]],
	"cafe": [["Furniture/Kitchen/Refrigerator_large_white.png", 3]],
	"atrium": [["Objects/Living Room/Flora_aloe.png", 8]],
	"studio": [["Furniture/Living Room/Couch_small_2_blue.png", 3]],
	"lobby": [["Furniture/Door_opened.png", 3]],
}

var bx := 0.0
var by := 0.0
var tgrid: Array = []
var rgrid: Array = []
var walkers: Array = []
var cars: Array = []
var landings: Array = []      # {spr, col, row}
var door_open: Texture2D
var door_shut: Texture2D

var _shot_path := ""
var _shot_t := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ua := OS.get_cmdline_user_args()
	var i := ua.find("--shot")
	if i != -1 and i + 1 < ua.size():
		_shot_path = ua[i + 1]
	door_open = load(PS + "Furniture/Elevator_opened.png")
	door_shut = load(PS + "Furniture/Elevator_closed.png")
	bx = (720.0 - GC * CELL * S) * 0.5
	by = (1280.0 - UI_H - GR * CELL * S) * 0.5
	_paint()
	_build()


func _cx(c: float) -> float: return bx + c * CELL * S
func _cy(r: float) -> float: return by + r * CELL * S
func _cs() -> float: return CELL * S


func _paint() -> void:
	tgrid.resize(GR)
	rgrid.resize(GR)
	for r in GR:
		tgrid[r] = []
		rgrid[r] = []
		for c in GC:
			tgrid[r].append(SHAFT)
			rgrid[r].append(-1)
	for id in ROOMS.size():
		for cell in ROOMS[id].cells:
			tgrid[cell[1]][cell[0]] = ROOM
			rgrid[cell[1]][cell[0]] = id
	for b in BLOCKS:
		if tgrid[b[1]][b[0]] == SHAFT:
			tgrid[b[1]][b[0]] = SOLID
	for w in WINS:
		if tgrid[w[1]][w[0]] == SHAFT:
			tgrid[w[1]][w[0]] = WINDOW


func _build() -> void:
	_bg()
	var frame := ColorRect.new()
	frame.color = Color(0.18, 0.16, 0.20)
	frame.position = Vector2(_cx(0) - 2 * S, _cy(0) - 2 * S)
	frame.size = Vector2(GC * _cs() + 4 * S, GR * _cs() + 4 * S)
	add_child(frame)
	for r in GR:
		for c in GC:
			_cell(c, r)
	for id in ROOMS.size():
		_furnish(id)
	_add_cars()          # cars first (behind the landing doors)
	_add_landings()      # doors on top
	_ui()


# ------------------------------------------------------------------ background

func _bg() -> void:
	var gy := _cy(GR)
	var sky := ColorRect.new()
	sky.color = Color(0.44, 0.63, 0.80)
	sky.size = Vector2(720, gy)
	add_child(sky)
	_at(PS + "Backgrounds/Mountain_large_1.png", Vector2(-40, gy - 87 * 3), 3)
	_at(PS + "Backgrounds/Cloud_1.png", Vector2(40, 50), 3)
	_at(PS + "Backgrounds/Cloud_small_3.png", Vector2(610, 100), 4)
	var grass := ColorRect.new()
	grass.color = Color(0.45, 0.62, 0.34)
	grass.position = Vector2(0, gy)
	grass.size = Vector2(720, 1280 - gy)
	add_child(grass)
	_at(PS + "Backgrounds/House_small_beige.png", Vector2(2, gy - 40 * 2), 2)
	_at(PS + "Backgrounds/House_largel_red.png", Vector2(636, gy - 56 * 2), 2)


# ------------------------------------------------------------------ cells

func _cell(c: int, r: int) -> void:
	var pos := Vector2(_cx(c), _cy(r))
	var cs := _cs()
	match tgrid[r][c]:
		ROOM:
			_rect(pos, Vector2(cs, cs), Color(0.86, 0.82, 0.76))
			_rect(pos + Vector2(0, cs - 2 * S), Vector2(cs, 2 * S), Color(0.45, 0.40, 0.36))
			_room_borders(c, r, pos, cs)
		SHAFT:
			_rect(pos, Vector2(cs, cs), Color(0.13, 0.14, 0.18))
			_rect(pos + Vector2(2 * S, 2 * S), Vector2(cs - 4 * S, cs - 4 * S), Color(0.17, 0.18, 0.23))
		SOLID:
			_rect(pos, Vector2(cs, cs), Color(0.31, 0.29, 0.27))
			for k in 3:
				_rect(pos + Vector2(0, (k * 2 + 1) * 4 * S), Vector2(cs, 3 * S), Color(0.85, 0.6, 0.2, 0.55))
		WINDOW:
			_rect(pos, Vector2(cs, cs), Color(0.20, 0.22, 0.27))
			_rect(pos + Vector2(2 * S, 2 * S), Vector2(cs - 4 * S, cs - 4 * S), Color(0.62, 0.80, 0.88, 0.92))
			_rect(pos + Vector2(cs / 2 - S, 2 * S), Vector2(2 * S, cs - 4 * S), Color(0.75, 0.85, 0.9))
			_rect(pos + Vector2(2 * S, cs / 2 - S), Vector2(cs - 4 * S, 2 * S), Color(0.75, 0.85, 0.9))


func _room_borders(c: int, r: int, pos: Vector2, cs: float) -> void:
	var id: int = rgrid[r][c]
	var b := Color(0.33, 0.24, 0.20)
	var t := 2 * S
	if not _same(c, r - 1, id): _rect(pos, Vector2(cs, t), b)
	if not _same(c, r + 1, id): _rect(pos + Vector2(0, cs - t), Vector2(cs, t), b)
	if not _same(c - 1, r, id): _rect(pos, Vector2(t, cs), b)
	if not _same(c + 1, r, id): _rect(pos + Vector2(cs - t, 0), Vector2(t, cs), b)


func _same(c: int, r: int, id: int) -> bool:
	return c >= 0 and c < GC and r >= 0 and r < GR and rgrid[r][c] == id


func _rect(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var rc := ColorRect.new()
	rc.color = col
	rc.position = pos
	rc.size = size
	add_child(rc)
	return rc


func _at(path: String, pos: Vector2, scale: int) -> void:
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = pos
	s.scale = Vector2(scale, scale)
	add_child(s)


# ------------------------------------------------------------------ furniture + people

func _furnish(id: int) -> void:
	var cells: Array = ROOMS[id].cells
	var best: Array = cells[0]
	for cell in cells:
		if cell[1] > best[1] or (cell[1] == best[1] and cell[0] < best[0]):
			best = cell
	var c: int = best[0]
	var r: int = best[1]
	var base_uy := (r + 1) * CELL - 2
	for it in FURN.get(ROOMS[id].kind, []):
		_floor_sprite(PS + it[0], c * CELL + it[1], base_uy)
	var lo := c
	var hi := c
	for cell in cells:
		if cell[1] == r:
			lo = mini(lo, cell[0])
			hi = maxi(hi, cell[0])
	_walker(lo * CELL + 2, (hi + 1) * CELL - 18, base_uy)


func _floor_sprite(path: String, ux: float, baseline_uy: float) -> void:
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = Vector2(bx + ux * S, by + baseline_uy * S - tex.get_height() * S)
	s.scale = Vector2(S, S)
	add_child(s)


func _walker(xmin: float, xmax: float, baseline_uy: float) -> void:
	var tex := load(NPC + "Male.png") as Texture2D
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.region_enabled = true
	s.centered = false
	s.scale = Vector2(S, S)
	add_child(s)
	var w := {
		"spr": s, "xmin": xmin, "xmax": maxf(xmin + 1, xmax),
		"x": randf_range(xmin, maxf(xmin + 1, xmax)), "dir": 1 if randf() < 0.5 else -1,
		"speed": randf_range(5.0, 9.0), "y": by + baseline_uy * S - 16 * S,
		"t": 0.0, "i": 0, "fps": 6.0,
	}
	walkers.append(w)
	_place_walker(w)


func _place_walker(w: Dictionary) -> void:
	w.spr.position = Vector2(bx + w.x * S, w.y)
	w.spr.flip_h = w.dir < 0
	w.spr.region_rect = Rect2(WALK[w.i] * 16, 0, 16, 16)


# ------------------------------------------------------------------ landing doors (docks)

func _add_landings() -> void:
	for rm in ROOMS:
		var d: Array = rm.dock
		var s := Sprite2D.new()
		s.texture = door_shut
		s.centered = false
		s.scale = Vector2(S, S)   # full tile
		# centre the 26x23 sprite in the 24-unit cell
		s.position = Vector2(_cx(d[0]) + (_cs() - door_shut.get_width() * S) * 0.5,
				_cy(d[1] + 1) - door_shut.get_height() * S)
		add_child(s)
		landings.append({"spr": s, "col": d[0], "row": d[1]})


# ------------------------------------------------------------------ programmer-art cars

func _add_cars() -> void:
	# one car per column that has docks; it visits each dock in turn
	for col in CAR_COLS:
		var stops: Array = []
		for rm in ROOMS:
			if rm.dock[0] == col:
				stops.append(rm.dock[1])
		stops.sort()
		if stops.is_empty():
			continue
		var car := {
			"col": col, "stops": stops, "si": 0, "floor": float(stops[0]),
			"target": stops[0], "dir": 1, "dwell": 0.0, "open": 0.0,
			"cable": _rect(Vector2.ZERO, Vector2.ZERO, Color(0.30, 0.30, 0.34)),
			"frame": _rect(Vector2.ZERO, Vector2.ZERO, Color(0.22, 0.25, 0.32)),
			"inner": _rect(Vector2.ZERO, Vector2.ZERO, Color(0.86, 0.82, 0.58)),
			"ld": _rect(Vector2.ZERO, Vector2.ZERO, Color(0.44, 0.50, 0.60)),
			"rd": _rect(Vector2.ZERO, Vector2.ZERO, Color(0.44, 0.50, 0.60)),
		}
		cars.append(car)
		_place_car(car)


func _place_car(car: Dictionary) -> void:
	var cs := _cs()
	var pad := 4 * S
	var x := _cx(car.col) + pad
	var w := cs - pad * 2
	var top := _cy(car.floor) + pad
	var h := cs - pad * 2
	# cable up to the roof
	car.cable.position = Vector2(x + w * 0.5 - S, _cy(0))
	car.cable.size = Vector2(2 * S, top - _cy(0))
	car.frame.position = Vector2(x, top)
	car.frame.size = Vector2(w, h)
	car.inner.position = Vector2(x + 2 * S, top + 2 * S)
	car.inner.size = Vector2(w - 4 * S, h - 4 * S)
	# doors slide apart by `open` (0 shut, 1 open)
	var half := (w - 4 * S) * 0.5
	var dw: float = half * (1.0 - car.open)
	car.ld.position = Vector2(x + 2 * S, top + 2 * S)
	car.ld.size = Vector2(dw, h - 4 * S)
	car.rd.position = Vector2(x + 2 * S + (w - 4 * S) - dw, top + 2 * S)
	car.rd.size = Vector2(dw, h - 4 * S)


func _tick_car(car: Dictionary, delta: float) -> void:
	var target := float(car.target)
	if absf(car.floor - target) <= 0.02:
		car.floor = target
		car.dwell += delta
		car.open = minf(1.0, car.open + delta * 4.0)   # doors opening
		if car.dwell > 1.6:
			car.dwell = 0.0
			car.si += car.dir
			if car.si >= car.stops.size():
				car.si = car.stops.size() - 2
				car.dir = -1
			elif car.si < 0:
				car.si = 1
				car.dir = 1
			car.si = clampi(car.si, 0, car.stops.size() - 1)
			car.target = car.stops[car.si]
	else:
		car.open = maxf(0.0, car.open - delta * 6.0)    # doors shut before moving
		if car.open <= 0.01:
			car.floor += clampf(target - car.floor, -2.6 * delta, 2.6 * delta)
	_place_car(car)


func _sync_doors() -> void:
	for lg in landings:
		var open := false
		for car in cars:
			if car.col == lg.col and car.open > 0.5 and absf(car.floor - float(lg.row)) < 0.1:
				open = true
		lg.spr.texture = door_open if open else door_shut


# ------------------------------------------------------------------ ui

func _ui() -> void:
	var band := ColorRect.new()
	band.color = Color(0.10, 0.11, 0.14, 0.94)
	band.position = Vector2(0, 1280 - UI_H)
	band.size = Vector2(720, UI_H)
	add_child(band)
	var top := 1280 - UI_H
	_label("PIXELSPACES — rooms + docks + cars", Vector2(18, top + 10), 20, Color(0.95, 0.98, 0.95))
	_label("tetris rooms (islands) · docks = PixelSpaces DOORS (full tile) · our programmer-art CAR rides behind · both open in sync",
			Vector2(18, top + 40), 13, Color(0.85, 0.9, 0.85))
	_swatch(Color(0.86, 0.82, 0.76), "room", 18, top + 70)
	_swatch(Color(0.13, 0.14, 0.18), "shaft", 130, top + 70)
	_swatch(Color(0.44, 0.50, 0.60), "car (our art)", 250, top + 70)
	_swatch(Color(0.62, 0.80, 0.88), "window", 420, top + 70)


func _swatch(col: Color, text: String, x: float, y: float) -> void:
	_rect(Vector2(x, y), Vector2(22, 22), col)
	_label(text, Vector2(x + 28, y + 2), 13, Color(0.85, 0.9, 0.85))


func _label(text: String, pos: Vector2, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l


# ------------------------------------------------------------------ tick

func _process(delta: float) -> void:
	for w in walkers:
		w.x += w.dir * w.speed * delta
		if w.x >= w.xmax:
			w.x = w.xmax
			w.dir = -1
		elif w.x <= w.xmin:
			w.x = w.xmin
			w.dir = 1
		w.t += delta
		var wp: float = 1.0 / float(w.fps)
		while w.t >= wp:
			w.t -= wp
			w.i = (w.i + 1) % WALK.size()
		_place_walker(w)
	for car in cars:
		_tick_car(car, delta)
	_sync_doors()
	if _shot_path != "":
		_shot_t += delta
		if _shot_t > 1.4:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
