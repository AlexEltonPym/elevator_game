extends Node2D
## A little tip coin that a served passenger sends flying up to the TIPS counter — so it
## reads that tips come FROM passengers. Purely visual (spawned by hud5.fly_coin, self-frees).

var r := 11.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, r + 1.6, Color(0.55, 0.42, 0.10, 0.95))     # dark rim
	draw_circle(Vector2.ZERO, r, Color(0.99, 0.83, 0.32))                 # gold face
	draw_circle(Vector2.ZERO, r - 3.0, Color(0.99, 0.83, 0.32).lightened(0.12))
	draw_circle(Vector2(-r * 0.32, -r * 0.32), r * 0.28, Color(1, 1, 0.9, 0.9))  # shine
	draw_string(ThemeDB.fallback_font, Vector2(-4.0, 5.0), "$",
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, 15, Color(0.5, 0.38, 0.08))
