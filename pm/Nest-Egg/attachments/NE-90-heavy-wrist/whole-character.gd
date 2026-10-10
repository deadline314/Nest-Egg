extends Node2D

func _ready() -> void:
	var id := "heavy_gunner"
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--char="): id = arg.trim_prefix("--char=")
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	assert(id == "heavy_gunner" and not out.is_empty())
	DirAccess.make_dir_recursive_absolute(out)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 1400)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(LightKit.create_environment())
	var light := LightKit.create_point_light(Color.WHITE, 1100, 0.8, false, false)
	light.position = Vector2(500, 500)
	viewport.add_child(light)
	for facing in [1, -1]:
		for state in ["idle", "run", "aim_up", "crouch", "jump", "block", "stagger", "dead"]:
			var holder := Node2D.new()
			holder.position = Vector2(768, 1250)
			holder.scale = Vector2.ONE * 14.0
			viewport.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			assert(rig.setup(id))
			rig.set_weapon("minigun")
			var input := RigInput.new()
			input.facing = facing
			input.aim_dir = Vector2(facing, -1 if state == "aim_up" else 0).normalized()
			input.two_handed = true
			input.velocity = Vector2(facing * 150, -200 if state == "jump" else 0) if state in ["run", "jump"] else Vector2.ZERO
			input.crouching = state == "crouch"
			input.on_floor = state != "jump"
			input.blocking = state == "block"
			input.staggered = state == "stagger"
			input.dead = state == "dead"
			for frame in 120:
				rig.animate(1.0 / 60.0, input)
				if frame in [0, 30, 60, 119]:
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					assert(preload("res://tools/viewport_capture.gd").image(viewport).save_png(out.path_join("%s_face%d_frame%d.png" % [state, facing, frame])) == OK)
			holder.queue_free()
			await get_tree().process_frame
	print("WHOLE_CHARACTER ", id, " frames=1920 snapshots=64", " renderer=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name())
	get_tree().quit()
