extends Node

func _ready() -> void:
	var source := Image.load_from_file("res://art_src/creatures/watchdog/design_21801/design_rgba.png")
	assert(source != null and source.get_size() == Vector2i(1536, 1024))
	var out := "res://pm/Nest-Egg/images/NE-218-watchdog-source"
	assert(DirAccess.make_dir_recursive_absolute(out) == OK)
	for face in [1, -1]:
		for entry in [["black", Color.BLACK], ["gray", Color(0.5, 0.5, 0.5)], ["white", Color.WHITE]]:
			var viewport := SubViewport.new()
			viewport.size = source.get_size()
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			var background := ColorRect.new()
			background.size = Vector2(viewport.size)
			background.color = entry[1]
			viewport.add_child(background)
			var sprite := Sprite2D.new()
			sprite.texture = ImageTexture.create_from_image(source)
			sprite.centered = false
			sprite.flip_h = face < 0
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			viewport.add_child(sprite)
			for frame in 2:
				await RenderingServer.frame_post_draw
			var rendered := preload("res://tools/viewport_capture.gd").image(viewport)
			assert(rendered.get_size() == source.get_size())
			assert(rendered.save_png(out.path_join("%s_face%d.png" % [entry[0], face])) == OK)
			viewport.queue_free()
			await get_tree().process_frame
	print("NE218_SOURCE_NATIVE renderer=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name(), " canvas=1536x1024 faces=2 backgrounds=3; source preview only")
	get_tree().quit()
