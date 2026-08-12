extends SceneTree
## Entry point for the scenario fingerprint tool (tools/fingerprint.gd):
##
##   & "C:\Program Files\Godot_v4.2.2-stable_mono_win64\Godot_v4.2.2-stable_mono_win64_console.exe" `
##       --headless --path . --script tools/run_fingerprint.gd
##
## One scenario per engine frame, exactly like tests/run_balance.gd.

var fp = preload("res://tools/fingerprint.gd").new()


func _process(_delta: float) -> bool:
	return fp.step(self)
