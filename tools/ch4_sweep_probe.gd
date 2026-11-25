extends "res://tools/ch4_factory_probe.gd"

const COVER := &"ch4_sweep_sample"
const CLEARED := &"ch4_demo_cover_cleared"
const DEMO := &"ch4_t_demo_sweep"


func _write() -> void:
	await super._write()
	if _failures or not is_instance_valid(_level):
		return
	var cover := _cover()
	_check(cover != null, "the loading bay spawns its designated cover")
	if cover == null:
		return
	await get_tree().physics_frame
	_check(_sample_hit(cover) == cover and _floor_present(cover), "marked cover has a body beside the permanent floor")
	await _cancel_preview(cover)
	await _talk(&"ch4_sweep_console")
	await get_tree().physics_frame
	_check(GameState.has_flag(CLEARED) and cover.is_broken, "the completed demonstration clears its own cover")
	_check(_sample_hit(cover) != cover and _floor_present(cover), "the cover collision disappears and the floor stays")
	var store := _main.get("_run_store") as RunSaveStore
	var raw := store.read()
	_check((raw.get("story", {}) as Dictionary).get("flags", {}).get(String(CLEARED)) == true, "the clearance was published to the main slot")



func _continue() -> void:
	await super._continue()
	var cover := _cover()
	_check(cover != null and GameState.has_flag(CLEARED), "the cold reader restores clearance")
	if cover == null:
		return
	await get_tree().physics_frame
	_check(cover.is_broken and _sample_hit(cover) != cover and _floor_present(cover), "cold reload restores the outline without putting collision back")


func _cancel_preview(cover: Breakable) -> void:
	var console := _object(&"ch4_sweep_console")
	if console == null:
		_check(false, "the loading bay has a sweep console")
		return
	_level.player.global_position = cover.global_position + Vector2(-28, 0)
	await _settle(12)
	_level.camera.snap_to_target()
	await _settle(12)
	var warning := cover.get_node_or_null(^"SweepWarning") as Node2D
	var motion_before := Settings.get_reduce_ui_motion()
	Settings.set_reduce_ui_motion(true)
	_check(Story.play(DEMO, false), "the warning can be started from the safe floor")
	await get_tree().create_timer(0.45, true, false, true).timeout
	_check(warning != null and warning.get("_progress") == 0.5 and not warning.is_processing() and not cover.hurtbox.enabled, "reduced motion keeps a readable stationary warning")
	_check(not GameState.has_flag(CLEARED) and not cover.is_broken, "the warning never clears the cover before completion")
	_capture("sweep-warning")
	Story.reset_active_presentation(&"leave")
	await _settle(8)
	Settings.set_reduce_ui_motion(motion_before)
	_check(warning != null and warning.get("_progress") < 0.0 and not GameState.has_flag(CLEARED) and not cover.is_broken, "cancelling removes the warning without clearing the cover")


func _cover() -> Breakable:
	for item: Node in get_tree().get_nodes_in_group(WorldState.GROUP):
		var cover := item as Breakable
		if cover != null and cover.data.id == COVER and _level.is_ancestor_of(cover):
			return cover
	return null


func _sample_hit(cover: Breakable) -> Object:
	var start := cover.world_center() - Vector2(26, 0)
	var query := PhysicsRayQueryParameters2D.create(start, cover.world_center(), Layers.WORLD)
	return cover.get_world_2d().direct_space_state.intersect_ray(query).get("collider")


func _floor_present(cover: Breakable) -> bool:
	var foot := cover.global_position
	var ray := PhysicsRayQueryParameters2D.create(foot - Vector2(0, 4), foot + Vector2(0, 12), Layers.WORLD, [cover.get_rid()])
	return not cover.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _capture(name: String) -> void:
	if name == "sweep-warning":
		if DisplayServer.get_name() == "headless":
			return
		var img := preload("res://tools/viewport_capture.gd").image(get_viewport())
		_check(img.save_jpg(_out_dir.path_join(name + ".jpg"), 0.89) == OK, "captured the warning over the test cover and permanent ground")
