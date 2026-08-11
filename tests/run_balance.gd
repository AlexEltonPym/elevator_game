extends SceneTree
## Entry point for the v3 balance harness. ONE command, run from the project
## root (see README "Balance harness"):
##
##   & "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe" `
##       --headless --path . --script tests/run_balance.gd
##
## All logic lives in tests/balance.gd; this wrapper runs one scenario per
## engine frame so queued node deletions flush between scenarios.

var harness = preload("res://tests/balance.gd").new()


func _process(_delta: float) -> bool:
	return harness.step(self)
