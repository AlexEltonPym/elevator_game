extends SceneTree
## Throwaway: for every shipped level, commit its stored `solution` and run it at the SHIPPED
## instance seed (hash(id), shift mode) to the close — print served / lost / tips / stars. This
## is the "can the best plan run clean" check that the user's 0-lost rule is really about.
func _initialize() -> void:
	await process_frame
	for i in Levels5.LEVELS.size():
		var lv: Dictionary = Levels5.LEVELS[i]
		Levels5.injected = null
		Levels5.current = i
		Levels5.headless = true
		var node = load("res://scenes/v5_main.tscn").instantiate()
		node.headless = true
		root.add_child(node)
		await process_frame
		await process_frame
		node.to_plan()
		var sol: Array = lv.get("solution", [])
		for ci in sol.size():
			var cells: Array = []
			for xy in sol[ci]:
				cells.append(Vector2i(int(xy[0]), int(xy[1])))
			node.commit_route(ci, cells, false)
		node.rng.seed = hash(str(lv.id))   # shipped instance seed (headless start_run won't reseed)
		node.start_run()
		node.set_process(false)
		var t := 0.0
		while node.state == node.State.PLAYING and t < 400.0:
			node.advance(0.1); t += 0.1
		var flag := "  <<< LOSSY" if node.lost > 0 else ""
		print("%-4s served=%2d lost=%2d tips=%3d stars=%d%s" % [
				str(lv.id), node.served, node.lost, roundi(node.tips), node.star_count(), flag])
		node.free()
	quit()
