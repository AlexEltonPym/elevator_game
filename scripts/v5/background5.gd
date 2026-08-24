extends Node2D
## The world behind the building (realism pass). Draws, in raw screen space BEHIND the
## grid: a day->night sky, a parallax skyline, drifting clouds, a sun that arcs over and
## sets into stars, the grass ground line, and the side-on dirt underground with a few
## buried bones. It lines everything up on Grid5.GROUND_Y (the street line the building
## sits on) and drives the day/night phase off the shift clock (main5.elapsed / shift_len):
## the level opens at sunrise and the stars come out as last orders approach.
##
## Pure primitive drawing — no art assets — so it renders on a clean clone. Nothing here
## touches the sim (view/render only): the fingerprint is unaffected.

var game = null # main5.gd (for the shift clock); null-safe (static sunrise when absent).

const VP := Vector2(720.0, 1280.0)   # design viewport (project.godot); stretch keeps aspect
const TOP_HUD := 98.0                # opaque top bar covers 0..98
const BOTTOM_HUD := 1010.0           # card panel covers 1010..1280

# Sky gradient keyframes across the shift: (phase, top colour, horizon colour). Sunrise at
# 0, golden hour ~0.7, sunset ~0.85, night at 1. Interpolated per-frame in _sky_at.
const SKY := [
	[0.00, Color(0.34, 0.40, 0.60), Color(0.98, 0.74, 0.52)], # sunrise: peach horizon
	[0.16, Color(0.40, 0.60, 0.86), Color(0.78, 0.87, 0.96)], # morning
	[0.45, Color(0.33, 0.61, 0.93), Color(0.71, 0.87, 0.99)], # midday blue
	[0.70, Color(0.44, 0.53, 0.82), Color(0.99, 0.80, 0.53)], # golden hour
	[0.85, Color(0.28, 0.27, 0.54), Color(0.97, 0.55, 0.42)], # sunset orange
	[1.00, Color(0.05, 0.06, 0.14), Color(0.11, 0.13, 0.28)], # night
]

var _stars: Array = []    # {x,y,r} fixed field, twinkles by index
var _clouds: Array = []   # {x,y,s,spd}
var _specks: Array = []   # dirt grain {x,y,r,d}
var _bones: Array = []    # {x, kind} buried finds, placed along the dirt band


func _ready() -> void:
	if Levels5.headless:
		set_process(false)
		visible = false
		return
	z_index = -100  # behind the grid / cars / passengers
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260823
	for i in 90:
		_stars.append({"x": rng.randf() * VP.x, "y": 108.0 + rng.randf() * 620.0,
				"r": rng.randf_range(0.7, 1.9), "ph": rng.randf() * TAU})
	for i in 5:
		_clouds.append({"x": rng.randf() * VP.x, "y": 150.0 + rng.randf() * 300.0,
				"s": rng.randf_range(0.8, 1.6), "spd": rng.randf_range(5.0, 12.0)})
	for i in 260:
		_specks.append({"x": rng.randf() * VP.x, "y": rng.randf(),
				"r": rng.randf_range(1.0, 2.6), "d": rng.randf_range(0.10, 0.30)})
	# A couple of small buried finds, spread wide (the dirt band is thin now).
	var kinds := ["skull", "bone"]
	for i in kinds.size():
		_bones.append({"x": 200.0 + i * 330.0 + rng.randf_range(-40.0, 40.0), "kind": kinds[i]})


func _process(_dt: float) -> void:
	queue_redraw()


## Day phase 0 (sunrise / planning) .. 1 (night). The full arc spans the shift exactly: the day
## ENDS at nightfall on the bell. (There's no last-orders drain any more, so the old DAY_PAD that
## left the bell at dusk and let the drain finish it would now freeze the sky mid-afternoon.)
func _phase() -> float:
	if game == null:
		return 0.0
	var sl: float = game.shift_len
	if sl <= 0.0:
		return 0.0
	return clampf(game.elapsed / sl, 0.0, 1.0)


## Interpolated (top, horizon) sky colours at phase p.
func _sky_at(p: float) -> Array:
	for i in range(1, SKY.size()):
		if p <= float(SKY[i][0]):
			var a: Array = SKY[i - 1]
			var b: Array = SKY[i]
			var t: float = (p - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return [(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t)]
	return [SKY.back()[1], SKY.back()[2]]


func _draw() -> void:
	var gy: float = Grid5.GROUND_Y
	var p := _phase()
	var night := smoothstep(0.72, 0.98, p)     # 0 day .. 1 fully dark
	var sky := _sky_at(p)
	var top: Color = sky[0]
	var horizon: Color = sky[1]
	# --- SKY: vertical gradient from top colour down to the horizon at the ground line.
	var bands := 40
	for i in bands:
		var f := float(i) / float(bands)
		var y := f * gy
		draw_rect(Rect2(0.0, y, VP.x, gy / float(bands) + 1.0), top.lerp(horizon, f * f))
	# --- STARS: fade in as night falls, gentle twinkle.
	if night > 0.02:
		var tw := Time.get_ticks_msec() / 600.0
		for s in _stars:
			if s.y > gy - 30.0:
				continue
			var a: float = night * (0.55 + 0.45 * sin(tw + s.ph))
			draw_circle(Vector2(s.x, s.y), s.r, Color(1.0, 1.0, 0.96, a))
	# --- SUN / MOON arc. The sun rides an arc left->right and dips at the horizon into a
	# warm glow; a pale moon takes over once it has set.
	_draw_celestial(gy, p, night)
	# --- CLOUDS: drift slowly, thin out at night.
	var cloud_a := (1.0 - night) * 0.9
	if cloud_a > 0.02:
		var t := Time.get_ticks_msec() / 1000.0
		for c in _clouds:
			var x: float = fposmod(c.x + t * c.spd, VP.x + 260.0) - 130.0
			_draw_cloud(Vector2(x, c.y), c.s, cloud_a)
	# --- SKYLINE: distant buildings along the horizon, behind the main building. Windows
	# warm up as it gets dark. Drawn last of the sky layers so it sits on the ground line.
	_draw_skyline(gy, night)
	# --- GRASS ground line + side-on DIRT underground with buried bones.
	_draw_ground(gy, night)


## A WIDE, shallow arc for the sun/moon: they rise off the left edge low in the open sky
## beside the building, sweep up to an apex over the roof, and set off the right edge — so
## most of their travel is in clear side-sky, not hidden behind the tower. `t` is the arc
## parameter 0..1; returns the screen position on that parabola.
func _arc_pos(gy: float, t: float) -> Vector2:
	var sky_h := gy - TOP_HUD
	var edge_y := gy - sky_h * 0.42   # height at the screen edges (level with the building sides)
	var peak_y := gy - sky_h * 0.99   # apex, just under the top HUD
	var u := 2.0 * t - 1.0            # -1 at left edge .. 0 at apex .. +1 at right edge
	return Vector2(lerpf(-45.0, VP.x + 45.0, t), peak_y + (edge_y - peak_y) * u * u)


func _draw_celestial(gy: float, p: float, night: float) -> void:
	# Sun: rides the arc across 0..0.92 of the day, then a moon rises on the left for the night.
	var span := 0.92
	if p < span:
		var st := clampf(p / span, 0.0, 1.0)
		var pos := _arc_pos(gy, st)
		var low := (2.0 * st - 1.0) * (2.0 * st - 1.0)   # 1 at the horizon edges, 0 at the apex
		var col := Color(1.0, 0.96, 0.80).lerp(Color(1.0, 0.62, 0.36), low)
		draw_circle(pos, 62.0, Color(col, 0.10))   # glow
		draw_circle(pos, 43.0, Color(col, 0.20))
		draw_circle(pos, 27.0, col)
	if night > 0.04:
		# Moon rises on the left and climbs toward the apex as the night deepens.
		var mt := clampf((p - 0.80) / 0.20, 0.0, 1.0)
		var pos := _arc_pos(gy, lerpf(0.06, 0.40, mt))
		var mc := Color(0.92, 0.93, 0.85, night)
		draw_circle(pos, 30.0, Color(mc, night * 0.12))
		draw_circle(pos, 22.0, mc)
		draw_circle(pos + Vector2(8.0, -5.0), 20.0,
				Color(_sky_at(p)[0], night * 0.9))   # crescent bite in the sky colour


func _draw_cloud(c: Vector2, s: float, a: float) -> void:
	var col := Color(1.0, 1.0, 1.0, a)
	for o in [Vector2(-34, 6), Vector2(-12, -6), Vector2(12, -3), Vector2(34, 7), Vector2(0, 8)]:
		draw_circle(c + o * s, 20.0 * s, col)
	draw_rect(Rect2(c.x - 40.0 * s, c.y + 4.0 * s, 80.0 * s, 12.0 * s), col)


## Distant skyline silhouette. Deterministic block heights so it never jitters. Lit windows
## grow warm as night falls, so the city reads as alive after dark.
func _draw_skyline(gy: float, night: float) -> void:
	var base := gy
	var heights := [120.0, 200.0, 90.0, 260.0, 150.0, 300.0, 110.0, 230.0, 170.0, 130.0]
	var col := Color(0.20, 0.22, 0.30).lerp(Color(0.05, 0.05, 0.11), night)
	var x := -20.0
	var k := 0
	while x < VP.x:
		var w: float = 56.0 + float((k * 37) % 40)
		var h: float = heights[k % heights.size()]
		draw_rect(Rect2(x, base - h, w, h), col)
		if night > 0.05:
			var wc := Color(1.0, 0.83, 0.45, night * 0.85)
			var rows := int(h / 26.0)
			for r in rows:
				for cx in 2:
					if ((k * 7 + r * 3 + cx * 5) % 4) == 0:
						draw_rect(Rect2(x + 12.0 + cx * 24.0, base - h + 14.0 + r * 26.0,
								9.0, 12.0), wc)
		x += w + 10.0
		k += 1


func _draw_ground(gy: float, night: float) -> void:
	var dirt_top := Color(0.36, 0.26, 0.17).lerp(Color(0.16, 0.11, 0.08), night)
	var dirt_bot := Color(0.24, 0.16, 0.10).lerp(Color(0.09, 0.06, 0.05), night)
	# Dirt body from the ground line to the bottom of the play window (card panel covers below).
	var bands := 24
	for i in bands:
		var f := float(i) / float(bands)
		var y := gy + f * (VP.y - gy)
		draw_rect(Rect2(0.0, y, VP.x, (VP.y - gy) / float(bands) + 1.0),
				dirt_top.lerp(dirt_bot, f))
	# Grain speckles (fixed field mapped into the dirt band).
	for s in _specks:
		var y: float = gy + 10.0 + s.y * (BOTTOM_HUD - gy - 10.0)
		draw_circle(Vector2(s.x, y), s.r, Color(0.0, 0.0, 0.0, s.d * (1.0 - night * 0.5)))
	# Buried finds sit LOW in the (thin) dirt band, small, so they don't crowd the grass.
	var by := gy + (BOTTOM_HUD - gy) * 0.74
	for b in _bones:
		_draw_find(Vector2(b.x, by), str(b.kind), night, 0.62)
	# Grass cap on the ground line.
	var grass := Color(0.42, 0.66, 0.32).lerp(Color(0.16, 0.30, 0.16), night)
	draw_rect(Rect2(0.0, gy, VP.x, 20.0), grass)
	draw_rect(Rect2(0.0, gy - 3.0, VP.x, 5.0), grass.lightened(0.18))
	var bx := 0.0
	while bx < VP.x:
		draw_rect(Rect2(bx, gy - 6.0, 2.0, 7.0), grass.lightened(0.10))
		bx += 13.0


## A little buried find (skull / bone), drawn bone-white against the dirt at `scl` scale.
func _draw_find(c: Vector2, kind: String, night: float, scl := 1.0) -> void:
	var bone := Color(0.86, 0.83, 0.74).lerp(Color(0.55, 0.53, 0.48), night)
	draw_set_transform(c, 0.0, Vector2(scl, scl))
	match kind:
		"skull":
			draw_circle(Vector2.ZERO, 12.0, bone)
			draw_rect(Rect2(-7.0, 8.0, 14.0, 8.0), bone)   # jaw
			draw_circle(Vector2(-4.5, -1.0), 3.0, Color(0.12, 0.09, 0.07))
			draw_circle(Vector2(4.5, -1.0), 3.0, Color(0.12, 0.09, 0.07))
			draw_rect(Rect2(-1.5, 3.0, 3.0, 4.0), Color(0.12, 0.09, 0.07))
		_: # a single long bone
			draw_line(Vector2(-16.0, -8.0), Vector2(16.0, 8.0), bone, 6.0)
			for e in [Vector2(-16.0, -8.0), Vector2(16.0, 8.0)]:
				draw_circle(Vector2(e.x, e.y - 3.0), 4.5, bone)
				draw_circle(Vector2(e.x, e.y + 3.0), 4.5, bone)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
