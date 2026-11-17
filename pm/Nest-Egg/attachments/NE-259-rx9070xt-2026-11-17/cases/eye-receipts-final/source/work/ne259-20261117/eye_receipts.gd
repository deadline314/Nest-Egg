extends "res://tools/enemy_glow_probe.gd"
# 明示運行中復原舊掛點，並非歷史 checkout；其餘產品來源保持最終候選。
class LegacyGlow extends EnemyGlow:
	func _place() -> void:
		var data := _enemy.data
		if not _searched:
			_searched = true
			_anchor = _find_anchor(data.light_part)
		var offset := Vector2(data.light_offset.x * float(_enemy.facing), data.light_offset.y)
		if _anchor != null and is_instance_valid(_anchor):
			global_position = _anchor.global_position + offset
		else:
			position = offset

func _receipt(glow: EnemyGlow, sprite: Sprite2D, name: String) -> Dictionary:
	var source_pixel := sprite.to_local(glow.global_position) - sprite.offset
	var screen := get_viewport().get_final_transform() * glow.get_global_transform_with_canvas() * Vector2.ZERO
	var path := _out.path_join(name + ".png")
	Capture.image(get_viewport()).save_png(path)
	return {"name": name, "source_pixel": [source_pixel.x, source_pixel.y], "screen": [screen.x, screen.y],
		"z": glow.z_index, "png_sha256": FileAccess.get_sha256(path),
		"head_transform": str(sprite.global_transform), "marker_transform": str(glow.global_transform)}

func _run() -> void:
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	Story._layer.visible = false
	var level := await _open(load("res://data/levels/ch1_warehouse.tres") as LevelData)
	var feet := _floor_spot(level)
	level.player.global_position = feet - Vector2(0, 2)
	var enemy := _spawn(level, "watchdog", feet + Vector2(70, 0))
	_subjects.append(enemy)
	await _settle(40)
	(get_viewport().get_camera_2d() as LevelCamera).snap_to_target()
	await _settle(150)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.find_child("EnemyGlow", false, false).free()
	enemy.data.light_offset = Vector2(6, -4)
	enemy.data.light_mark = Vector2(2.5, 1.5)
	var glow := LegacyGlow.new()
	glow._enemy = enemy
	enemy.add_child(glow)
	var head := enemy.creature.joint_of("head")
	var sprite := head.get_child(0) as Sprite2D
	await _settle(4)
	var rows := [_receipt(glow, sprite, "receipt-original-restored")]
	glow.z_index = 3
	await _settle(4)
	rows.append(_receipt(glow, sprite, "receipt-z-only"))
	glow.global_position = head.to_global(Vector2(9.72, -4.6))
	await _settle(4)
	rows.append(_receipt(glow, sprite, "receipt-eye-position"))
	var record := {"kind": "final candidate with old placement/data restored only in this instance; fixed enemy pose",
		"user_data_dir": OS.get_user_data_dir(), "head_z": head.z_index, "stages": rows}
	var file := FileAccess.open(_out.path_join("receipts.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("NE259_EYE_RECEIPTS:", JSON.stringify(record))
	_subjects.clear()
	level.queue_free()
	await _settle(4)
	await AudioRelease.settle(get_tree())
	get_tree().quit()
