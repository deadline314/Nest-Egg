extends "res://tests/smoke_test.gd"

var expected_using_gamepad := false
var expected_direction := Vector2.RIGHT
var expected_msec := 0
var verify_restoration_in_check := false

func _run() -> void:
	var mode := "right"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-mode="):
			mode = arg.trim_prefix("--probe-mode=")
	AimInput.using_gamepad = mode != "mouse"
	AimInput.restore_direction(Vector2.LEFT if mode == "left" else Vector2.RIGHT)
	print("NE249_INPUT mode=", mode, " using_gamepad=", AimInput.using_gamepad, " last_direction=", AimInput._last_stick_dir)
	if OS.get_cmdline_user_args().has("--probe-direct"):
		expected_using_gamepad = AimInput.using_gamepad
		expected_direction = AimInput._last_stick_dir
		expected_msec = AimInput._last_stick_msec
		verify_restoration_in_check = true
		var suite := EncounterSuite.new(self)
		await suite._test_free_encounter()
		var restored := AimInput.using_gamepad == expected_using_gamepad and AimInput._last_stick_dir == expected_direction and AimInput._last_stick_msec == expected_msec
		print("NE249_EXTERNAL_RESTORE expected=", [expected_using_gamepad, expected_direction, expected_msec], " actual=", [AimInput.using_gamepad, AimInput._last_stick_dir, AimInput._last_stick_msec], " passed=", restored)
		_check(restored, "external encounter restoration preserves incoming aim statics")
		await _finish()
		return
	await super._run()

func _check(condition: bool, message: String) -> void:
	if verify_restoration_in_check and message == "free encounter restores aim source direction and timestamp":
		var restored := AimInput.using_gamepad == expected_using_gamepad and AimInput._last_stick_dir == expected_direction and AimInput._last_stick_msec == expected_msec
		print("NE249_RESTORE expected=", [expected_using_gamepad, expected_direction, expected_msec], " actual=", [AimInput.using_gamepad, AimInput._last_stick_dir, AimInput._last_stick_msec], " passed=", restored)
		condition = condition and restored
	if message == "real movement crosses the former entry gate and starts combat":
		for player in get_tree().get_nodes_in_group(&"player"):
			print("NE249_ENTRY actual_x=", player.global_position.x, " facing=", player.facing, " velocity_x=", player.velocity.x, " aim_dir=", player.aim_dir, " passed=", condition)
	if message == "the player can physically leave while both members remain alive":
		for player in get_tree().get_nodes_in_group(&"player"):
			print("NE249_EXIT actual_x=",player.global_position.x," facing=",player.facing," velocity_x=",player.velocity.x," aim_dir=",player.aim_dir," passed=",condition)
	super._check(condition,message)
