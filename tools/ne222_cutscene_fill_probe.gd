extends Node2D

var _out := "user://ne222-cutscene-fill"
var _legacy_level_fill := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			_out = arg.trim_prefix("--out-dir=")
		elif arg == "--legacy-level-fill":
			_legacy_level_fill = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var original_fill := LightKit.character_fill
	var original_cap := LightKit.character_light_cap
	var records: Array[Dictionary] = []
	var shader_fill: Array[float] = []
	for fill: float in [1.0, 4.0]:
		LightKit.character_fill = fill
		LightKit.character_light_cap = LightKit.character_light_cap_for(0.05, fill)
		var scene: Dictionary = Story._scenes["ch1_c09_wake"].duplicate(true)
		# Keep the actual stage, actor and camera; stop before the temporary flash/dialogue.
		scene["steps"] = scene["steps"].slice(0, 2)
		# Diagnostic framing only: the shipped camera clips the ponytail at the letterbox.
		scene["steps"][0]["pos"][1] = 205.0
		scene["steps"].append({"do": "wait", "time": 60.0})
		var player := CutscenePlayer.new()
		add_child(player)
		player.play(&"ne222_fill_probe", scene)
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		var rig: CharacterRig = player._actors[&"rin"].rig
		if _legacy_level_fill:
			rig.use_level_lighting = true
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var material_fill := rig._fill
		shader_fill.append(material_fill)
		var image := get_viewport().get_texture().get_image()
		var png := preload("res://tools/viewport_capture.gd").image(get_viewport())
		assert(png.save_png(_out.path_join("clinic_fill_%d.png" % int(fill))) == OK)
		records.append({"level_fill": fill, "actor_fill": material_fill, "actor_cap": rig._light_material.get_shader_parameter("light_cap"), "hdr_format": image.get_format(), "image_size": [image.get_width(), image.get_height()]})
		player.skip()
		while is_instance_valid(player) and player.is_running():
			await get_tree().process_frame
		player.queue_free()
		await get_tree().process_frame
	LightKit.character_fill = original_fill
	LightKit.character_light_cap = original_cap
	var passed := is_equal_approx(shader_fill[0], 1.0) and is_equal_approx(shader_fill[1], 1.0)
	var report := {"result": "PASS" if passed else "FAIL", "legacy_level_fill": _legacy_level_fill, "capture_camera_y": 205.0, "records": records, "scope": "actual clinic stage with diagnostic framing; not hip/anatomy or shipped camera acceptance"}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	get_tree().quit(0 if passed else 1)
