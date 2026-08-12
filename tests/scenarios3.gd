extends RefCounted
## Harness scenario list, ADAPTED from the shared game data in
## scripts/v3/scenarios3.gd (route sets + canonical per-level seeds). The
## game's watch mode reads the same table, so the harness and the game can
## never drift apart. This file only maps {level, strategy} onto the harness
## keys that tests/balance.gd asserts on:
##   L1_naive / L1_intended / ... ("intended" = the shared data's "thesis")
##   X1_smoke (X-1's only strategy: the old smoke-test route set)

const Scen = preload("res://scripts/v3/scenarios3.gd")


static func scenarios() -> Array:
	var out: Array = []
	for id in ["L1", "L2", "L3", "L4"]:
		var sets: Dictionary = Scen.route_sets(id)
		out.append({"key": "%s_naive" % id, "level": id, "seed": Scen.SEEDS[id],
				"desc": sets.naive.desc, "routes": sets.naive.routes})
		out.append({"key": "%s_intended" % id, "level": id, "seed": Scen.SEEDS[id],
				"desc": sets.thesis.desc, "routes": sets.thesis.routes})
	var x: Dictionary = Scen.route_sets("X-1")
	out.append({"key": "X1_smoke", "level": "X-1", "seed": Scen.SEEDS["X-1"],
			"desc": x.thesis.desc, "routes": x.thesis.routes})
	return out
