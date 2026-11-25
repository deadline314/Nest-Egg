extends "res://tools/ch4_relay_probe.gd"

const WORK := "res://data/levels/ch4_factory_work.tres"
const ERASED := &"ch4_work_cover_erased"
const CROSSED := &"ch4_factory_work_crossed"
const WorkSweep := preload("res://game/hazards/factory_sweep_lane.gd")


func _write() -> void:
	if "--from-safety" in OS.get_cmdline_user_args():
		var record := await _route_main.continue_game()
		_level = _route_main.level()
		_check(record.get("level") == SAFETY and _level != null, "the safety checkpoint fixture restores")
	else:
		await super._write()
	if _failures > 0 or not await _portal(&"safety_work", WORK) or not await _wait_for_route_input():
		return
	var sectors := _level.find_children("*", "Area2D", true, false).filter(
		func(node: Node) -> bool: return node.get_script() == WorkSweep)
	_check(sectors.size() == 2, "two independently placed lanes appear in the work area")
	if sectors.size() != 2:
		return
	var lower := sectors[0] as Area2D
	var upper := sectors[1] as Area2D
	if lower.position.y < upper.position.y:
		var other := upper
		upper = lower
		lower = other
	var cover := _work_cover()
	_check(cover != null and not cover.is_broken, "only the marked lower cover starts intact")
	if cover == null:
		return
	var actor := _level.player
	var health := actor.health.current
	var sector: Rect2 = lower.get("_sector")
	actor.teleport_to(lower.global_position + Vector2(sector.position.x - 24.0, 0.0))
	_level.camera.snap_to_target()
	_check(await _wait_state(lower, WorkSweep.State.WARNING), "entering the lower approach gives a warning")
	_check(actor.health.current == health and not cover.is_broken, "the warning cannot damage or clear the cover")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.35, true, false, true).timeout
		_capture("work-warning")
	actor.teleport_to(lower.global_position + Vector2(-40.0, 0.0))
	_check(await _wait_state(lower, WorkSweep.State.LIVE), "the warning changes into the live sector")
	var deadline := Time.get_ticks_msec() + 1200
	while health == actor.health.current and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(actor.health.current < health and cover.is_broken and GameState.has_flag(ERASED),
			"the live lower sector deals damage and clears only its designated cover")
	_check(_floor_present(cover), "the permanent lower floor remains available")
	# Finish the hit response before relocating the test fixture.
	await get_tree().create_timer(0.65, false, true, false).timeout
	await get_tree().process_frame
	var high_sector: Rect2 = upper.get("_sector")
	actor.teleport_to(upper.global_position + Vector2(high_sector.position.x - 24.0, 0.0))
	_check(await _wait_state(upper, WorkSweep.State.WARNING), "the far sweep warns on the upper catwalk")
	await get_tree().process_frame
	actor.velocity = Vector2.ZERO
	actor.teleport_to(Vector2(upper.global_position.x, lower.global_position.y))
	actor.force_update_transform()
	await get_tree().physics_frame
	var under_health := actor.health.current
	await get_tree().create_timer(1.8, false, true, false).timeout
	_check(actor.health.current == under_health and absf(actor.global_position.x - upper.global_position.x) < 8.0, "the route on the lower floor stays safe under the upper sweep")
	_check(await _talk(&"ch4_work_observation") and GameState.has_flag(CROSSED), "checking the far terminal completes the route")
	var store := _main.get("_run_store") as RunSaveStore
	var flags: Variant = (store.read().get("story", {}) as Dictionary).get("flags")
	_check(flags is Dictionary and flags.get(String(ERASED), false) and flags.get(String(CROSSED), false),
			"both route changes are present in the main save")


func _continue() -> void:
	var record := await _route_main.continue_game()
	_level = _route_main.level()
	_check(record.get("level") == WORK and _level != null, "the cold save resumes the work lane")
	if _level == null:
		return
	var cover := _work_cover()
	_check(cover != null and cover.is_broken and GameState.has_flag(CROSSED),
			"the cold reader keeps the cover removed and the route complete")


func _wait_state(sector: Node, target: int) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while sector.get("_state") != target and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	return sector.get("_state") == target


func _work_cover() -> Breakable:
	for node: Node in get_tree().get_nodes_in_group(WorldState.GROUP):
		var cover := node as Breakable
		if cover != null and cover.data.id == &"ch4_work_test_cover" and _level.is_ancestor_of(cover):
			return cover
	return null


func _capture(name: String) -> void:
	if name != "work-warning":
		return
	var img := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(img.save_jpg(_out_dir.path_join(name + ".jpg"), 0.89) == OK, "captured the work-lane warning")
