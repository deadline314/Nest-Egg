extends "res://tests/smoke_test.gd"

func _run() -> void:
	var mode := "right"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-mode="):
			mode = arg.trim_prefix("--probe-mode=")
	AimInput.using_gamepad = mode != "mouse"
	AimInput.restore_direction(Vector2.LEFT if mode == "left" else Vector2.RIGHT)
	print("NE249_INPUT mode=", mode, " using_gamepad=", AimInput.using_gamepad, " last_direction=", AimInput._last_stick_dir)
	await super._run()

func _check(condition: bool, message: String) -> void:
	if message == "the player can physically leave while both members remain alive":
		for player in get_tree().get_nodes_in_group(&"player"):
			print("NE249_EXIT actual_x=",player.global_position.x," facing=",player.facing," velocity_x=",player.velocity.x," aim_dir=",player.aim_dir," passed=",condition)
	super._check(condition,message)
