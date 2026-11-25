extends "res://tools/ch4_sweep_probe.gd"
## Verify that a saved rehearsal connects to the safe platform and its return shortcut.

const RELAY := "res://data/levels/ch4_factory_relay.tres"
const SAFETY := "res://data/levels/ch4_factory_safety.tres"
const BRIEFED := &"ch4_cleaning_briefing_read"
const SHORTCUT := &"ch4_safety_shortcut_open"


func _write() -> void:
	await super._write()
	if _failures > 0 or not is_instance_valid(_level):
		return
	var high := _level._portals[&"loading_service"] as Portal
	_check(not high.try_use(), "the staff door cannot be opened from the loading bay")
	if not await _portal(&"loading_relay", RELAY) or not await _wait_for_route_input():
		return
	await _walk_to_safety()
	if _failures > 0 or not await _portal(&"relay_safe", SAFETY) or not await _wait_for_route_input():
		return
	await _dial_checkpoint()
	await _talk(&"ch4_safety_instruction")
	_check(GameState.has_flag(BRIEFED), "the service announcement is recorded")
	await _talk(&"ch4_safety_catch")
	_check(GameState.has_flag(SHORTCUT), "the inside latch opens the upper staff door")
	if not await _portal(&"safety_service", LOADING):
		return
	await _portal(&"loading_service", SAFETY)


func _walk_to_safety() -> void:
	var exit := _level._portals[&"relay_safe"] as Portal
	var player := _level.player
	# Isolate floor connectivity from combat difficulty.
	player.health.grant_invulnerability(20.0)
	Input.action_press(&"move_right")
	var deadline := Time.get_ticks_msec() + 30000
	while player.global_position.x < exit.global_position.x - 22.0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	_check(player.global_position.x >= exit.global_position.x - 22.0 and player.is_on_floor(),
			"normal movement crosses the permanent lower floor without defeating a patrol")


func _dial_checkpoint() -> void:
	var phones := _level.find_children("*", "Checkpoint", true, false)
	var checkpoint := phones[0] as Checkpoint if phones.size() == 1 else null
	_check(checkpoint != null, "the safe platform contains a checkpoint")
	if checkpoint == null:
		return
	_level.player.teleport_to(checkpoint.global_position + Vector2(-22.0, 0.0))
	var deadline := Time.get_ticks_msec() + 4000
	while not checkpoint.can_dial() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(checkpoint.can_dial() and checkpoint.start_call(_level.player), "the safe-platform phone dials with the usual interaction rules")
	# A completed-Chapter-3 fixture may be making its first backup.
	# Acknowledge the normal first-checkpoint recording before moving on.
	await _drive([], func() -> bool:
		return not checkpoint.is_calling() and not _level.player.is_on_phone() and not Story._layer.is_radio_frozen())
	_check(checkpoint.activated and GameState.checkpoint_applies(SAFETY), "the usual checkpoint stores a safe entry")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.9, true, false, true).timeout
		_capture("safe-platform")


func _continue() -> void:
	var data := await _route_main.continue_game()
	_level = _route_main.level()
	_check(data.get("level") == SAFETY and _level != null, "cold load returns to the safe platform")
	if _level == null:
		return
	_check(GameState.has_flag(BRIEFED) and GameState.has_flag(SHORTCUT), "the announcement and staff latch persist")
	_check((_level._portals[&"safety_service"] as Portal).is_open(), "the cold route retains its shortcut")
	await _talk(&"ch4_safety_instruction")


func _capture(name: String) -> void:
	if name != "safe-platform":
		return
	var img := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(img.save_jpg(_out_dir.path_join(name + ".jpg"), 0.89) == OK, "captured the platform checkpoint and boundary")
