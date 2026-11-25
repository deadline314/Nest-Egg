extends "res://tools/ch4_ward_probe.gd"
## Plays past the ward using actual portals, shift-board choices and a cold save.
## Use a separate scratch save directory from the ward probe.

const LOUNGE := "res://data/levels/ch4_revival_lounge.tres"
const APPROACH := "res://data/levels/ch4_factory_approach.tres"
const LOADING := "res://data/levels/ch4_factory_loading.tres"
const MATCHED := &"ch4_factory_batch_matched"
const RAIL := &"ch4_loader_rail_released"
const FLOOR := &"ch4_fixed_ground_marked"


func _write() -> void:
	await super._write()
	if _failures != 0 or not is_instance_valid(_level):
		return
	if not await _portal(&"ward_entry", RECEPTION) or not await _portal(&"reception_lounge", LOUNGE):
		return
	_check(not (_level._portals[&"lounge_factory"] as Portal).try_use(), "the factory route asks for a real shift lead")
	await _talk(&"ch4_ali")
	if not await _portal(&"lounge_factory", APPROACH):
		return
	_check(not (_level._portals[&"approach_loading"] as Portal).try_use(), "the loading door requires the shift list comparison")
	await _talk(&"ch4_shift_board", ["nineteen", "leave"])
	_check(not GameState.has_flag(MATCHED) and StoryItems.holds(SLIP), "checking the wrong batch leaves the form available and the door locked")
	await _talk(&"ch4_shift_board", ["seventeen"])
	if not await _portal(&"approach_loading", LOADING):
		return
	await _talk(&"ch4_workbench")
	_check(GameState.has_flag(FLOOR), "checking the work boundary completes the approach")
	_check(not (_level._portals[&"loading_rail"] as Portal).try_use(), "the high route initially has its maintenance catch")
	await _talk(&"ch4_rail_release")
	_check(GameState.has_flag(RAIL), "the loading bay releases the separate upper route")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(2.0, true, false, true).timeout
		_capture("factory-loading")
	if not await _portal(&"loading_rail", APPROACH):
		return
	if await _portal(&"approach_rail", LOADING) and await _wait_for_route_input():
		await get_tree().physics_frame
		await get_tree().physics_frame
		var entrance := _level._portals[&"loading_rail"] as Portal
		_check(_level.player.is_on_floor() and entrance.contains_point(_level.player.global_position), "the high entry settles beside the upper catwalk door")


func _portal(id: StringName, destination: String) -> bool:
	if not await _wait_for_route_input():
		return false
	return await super._portal(id, destination)


func _wait_for_route_input() -> bool:
	# The screen can exist while the covered route still owns input.
	var deadline := Time.get_ticks_msec() + ProbeMainRoute.LIMIT_MSEC
	while Transition.is_active() or bool(_main.call("_route_pending")):
		if Time.get_ticks_msec() >= deadline:
			_check(false, "the previous transition releases input")
			return false
		await _settle(1)
	return true


func _continue() -> void:
	var data := await _route_main.continue_game()
	_level = _route_main.level()
	_check(data.get("level") == LOADING and _level != null, "a cold reader resumes in the loading bay")
	if _level == null:
		return
	_check(GameState.has_flag(MATCHED) and GameState.has_flag(RAIL) and GameState.has_flag(FLOOR), "the batch, open route and survey come back")
	_check(StoryItems.holds(SLIP), "the check does not consume the ward's collection slip")
	_check((_level._portals[&"loading_rail"] as Portal).is_open(), "the high route is still open")
	await _talk(&"ch4_workbench")


func _capture(name: String) -> void:
	if name == "factory-loading":
		super._capture(name)
