extends "res://tools/enemy_glow_probe.gd"
func _run() -> void:
	var quality_before := Settings.get_light_quality()
	Settings.set_light_quality(LightQuality.Tier.HIGH)
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
	var camera := get_viewport().get_camera_2d() as LevelCamera
	camera.snap_to_target()
	await _settle(150)
	var glow := enemy.find_child("EnemyGlow", false, false) as EnemyGlow
	var head := enemy.creature.joint_of("head")
	var sprite := head.get_child(0) as Sprite2D
	var texture := sprite.texture.get_image()
	var local := sprite.to_local(glow.global_position) - sprite.offset
	var pixel := Vector2i(local)
	var screen := get_viewport().get_final_transform() * glow.get_global_transform_with_canvas() * Vector2.ZERO
	var view := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var expected := head.to_global(Vector2(9.6, -4.64))
	var report := {"kind": "in-process controlled rendering, product source unchanged", "user_data_dir": OS.get_user_data_dir(),
		"head_local_z": head.z_index, "glow_z": glow.z_index, "current_marker_source_pixel": [local.x, local.y],
		"head_alpha_at_marker": texture.get_pixelv(pixel).a, "current_marker_screen": [screen.x, screen.y],
		"eye_screen_from_authored_image": [ (view * expected).x, (view * expected).y ],
		"old_offset": [enemy.data.light_offset.x, enemy.data.light_offset.y]}
	Capture.image(get_viewport()).save_png(_out.path_join("control-original.png"))
	glow.z_index = head.z_index + 1
	await _settle(4)
	Capture.image(get_viewport()).save_png(_out.path_join("control-z-only.png"))
	glow.set_process(false)
	glow.global_position = expected
	await _settle(4)
	Capture.image(get_viewport()).save_png(_out.path_join("control-eye-position.png"))
	var file := FileAccess.open(_out.path_join("control-index.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("NE259_EYE_CONTROL:", JSON.stringify(report))
	_subjects.clear()
	level.queue_free()
	await _settle(4)
	Settings.set_light_quality(quality_before)
	await AudioRelease.settle(get_tree())
	get_tree().quit()
