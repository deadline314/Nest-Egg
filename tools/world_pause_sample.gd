extends RefCounted
## 探針的觀察者可 ALWAYS；遊戲世界必須自行保持 PAUSABLE，並核對真正狀態未前進。

static func snapshot(level: Level) -> Dictionary:
	return {
		"level_id": level.get_instance_id(),
		"process_mode": level.process_mode,
		"level_can_process": level.can_process(),
		"player_can_process": level.player.can_process(),
		"camera_can_process": level.camera.can_process(),
		"player_id": level.player.get_instance_id(),
		"player_position": level.player.global_position,
		"camera_id": level.camera.get_instance_id(),
		"camera_position": level.camera.global_position,
		"camera_center": level.camera.get_screen_center_position(),
		"canvas_transform": level.get_viewport().get_canvas_transform(),
		"run_time": GameState.run_time,
		"fog_time": level._fog._time if is_instance_valid(level._fog) else 0.0,
	}


static func source_receipt(out: String, paths: Array[String]) -> Dictionary:
	var hashes := {}
	for path in paths:
		hashes[path] = FileAccess.get_sha256(path)
		var name := path.trim_prefix("res://").replace("/", "_") + ".txt"
		var file := FileAccess.open(out.path_join(name), FileAccess.WRITE)
		if file == null:
			push_error("[WorldPauseSample] 無法保存來源：" + out.path_join(name))
			continue
		file.store_buffer(FileAccess.get_file_as_bytes(path))
	return hashes
