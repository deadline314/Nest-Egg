extends Node2D

func _ready() -> void:
	var tag := "before"
	var tag_seen := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			if tag_seen:
				push_error("[slasher-leg-capture] pass --tag only once (before or after)")
				get_tree().quit(1)
				return
			tag_seen = true
			tag = arg.trim_prefix("--tag=")
			if tag not in ["before", "after"]:
				push_error("[slasher-leg-capture] unknown --tag '%s'; expected before or after" % tag)
				get_tree().quit(1)
				return
	var out := "res://pm/Nest-Egg/images/NE-90-slasher-leg/" + tag + "/"
	DirAccess.make_dir_recursive_absolute(out)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 1400)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(LightKit.create_environment())
	var key := LightKit.create_point_light(Color.WHITE, 1100, 0.8, false, false)
	key.position = Vector2(500, 500)
	viewport.add_child(key)
	var records: Array = []
	for facing in [1, -1]:
		for state in ["idle", "walk", "run", "aim", "crouch", "jump", "hurt", "fall", "lunge"]:
			var holder := Node2D.new()
			holder.position = Vector2(768, 1300)
			holder.scale = Vector2.ONE * 23.78
			viewport.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			assert(rig.setup("slasher"))
			var input := RigInput.new()
			input.facing = facing
			input.aim_dir = Vector2(facing, 0)
			input.two_handed = false
			input.run_speed = 150
			input.relaxed = state in ["idle", "walk", "run"]
			input.velocity.x = facing * (60.0 if state == "walk" else 150.0 if state == "run" else 0.0)
			input.crouching = state == "crouch"
			input.on_floor = state != "jump"
			input.velocity.y = -80 if state == "jump" else 0
			for frame in 120:
				input.hurt = state == "hurt" and frame == 0
				input.dead = state == "fall"
				input.action = &"slasher.slash" if state == "lunge" else &""
				input.action_t = frame / 119.0
				rig.animate(1.0 / 60.0, input)
				var positions: Dictionary = {}
				for side in ["front", "back"]:
					var wrist := rig.bone(StringName("hand_" + side))
					assert(wrist.global_position.is_finite())
					positions[side] = [wrist.global_position.x, wrist.global_position.y]
				records.append({"face":facing,"state":state,"frame":frame,"wrist_pixels":positions})
				if frame in [0, 30, 60, 119]:
					for delay in 2:
						await RenderingServer.frame_post_draw
					assert(preload("res://tools/viewport_capture.gd").image(viewport).save_png(out + "%s_face%d_frame%d.png" % [state, facing, frame]) == OK)
			holder.queue_free()
			await get_tree().process_frame
	FileAccess.open(out + "trace.json", FileAccess.WRITE).store_string(JSON.stringify(records))
	print("SLASHER_NATIVE ", tag, " frames=", records.size(), " renderer=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name())
	viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit()
