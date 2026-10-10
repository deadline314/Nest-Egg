extends Node
## Controlled original-art NPC fixture; authored coat angles are not gameplay data.

const DATA_PATH := "res://art/rigs/npc_animations.json"
const CAPTURE := preload("res://tools/viewport_capture.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := ""
	var legacy := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
		elif argument == "--legacy": legacy = true
	assert(output.is_absolute_path())
	assert(DirAccess.make_dir_recursive_absolute(output) == OK or DirAccess.dir_exists_absolute(output))
	var data := RigLibrary.load_json(DATA_PATH).duplicate(true)
	(data["poses"]["stand"]["bones"] as Dictionary)["coat_1"] = 0.35
	(data["poses"]["sit"]["bones"] as Dictionary)["coat_1"] = -0.35
	RigLibrary._json_cache[DATA_PATH] = data
	var captures: Array[Dictionary] = []
	var checks := 0
	for facing in [1, -1]:
		for pose in ["stand", "sit"]:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(1200, 1400)
			viewport.transparent_bg = true
			viewport.use_hdr_2d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			viewport.add_child(LightKit.create_environment())
			var light := LightKit.create_point_light(Color.WHITE, 1200.0, 0.8, false, false)
			light.position = Vector2(600, 400)
			viewport.add_child(light)
			var holder := Node2D.new()
			holder.scale = Vector2.ONE * 20.0
			viewport.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			assert(rig.setup("rin", "npc"))
			var animator := rig.animator as NpcAnimator
			assert(animator != null and rig.has_bone(&"coat_1"))
			var input := RigInput.new()
			input.facing = facing
			input.two_handed = false
			input.npc_pose = StringName(pose)
			for frame in 120:
				rig.animate(1.0 / 60.0, input)
				assert(animator._use_npc)
				var expected: float = animator._spring_angle[&"coat_1"]
				if not legacy: expected += animator._angles[&"coat_1"] + animator._overlay.get(&"coat_1", 0.0)
				assert(is_equal_approx(rig.bone(&"coat_1").rotation, expected))
				checks += 2
			var bounds := rig.visual_bounds()
			assert(bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.is_finite())
			holder.position += Vector2(viewport.size) * 0.5 - bounds.get_center()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var file := "%s_%s_f%d.png" % ["legacy" if legacy else "composed", pose, facing]
			var image := CAPTURE.image(viewport)
			assert(image.get_size() == viewport.size and image.save_png(output.path_join(file)) == OK)
			checks += 2
			captures.append({"file": file, "pose": pose, "facing": facing,
				"authored": animator._angles[&"coat_1"], "overlay": animator._overlay.get(&"coat_1", 0.0),
				"spring": animator._spring_angle[&"coat_1"], "actual": rig.bone(&"coat_1").rotation})
			viewport.queue_free()
			await get_tree().process_frame
	var report := {"checks": checks, "frames_simulated": 480, "snapshots": 4,
		"renderer": RenderingServer.get_current_rendering_method(), "legacy": legacy,
		"captures": captures, "art_acceptance": false,
		"scope": "Controlled NPC pose data demonstrates composition only; no gameplay pose or artwork changed."}
	var file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	get_tree().quit()
