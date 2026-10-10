extends Node
const Capture = preload("res://viewport_capture.gd")

func _ready() -> void:
	var root := ""
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root = arg.trim_prefix("--root=")
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	assert(root.is_absolute_path() and output.is_absolute_path())
	var view := SubViewport.new()
	view.size = Vector2i(1440,760)
	view.use_hdr_2d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var back := ColorRect.new()
	back.color = Color("202735")
	back.size = Vector2(1440,760)
	view.add_child(back)
	label(view,Vector2(30,20),"NE-222 | Native visible source parts | Original standing art preserved",26)
	label(view,Vector2(30,65),"SOURCE ONLY: not rigged / animation, seams, lighting and gameplay not accepted",21)
	var colors := [Color.BLACK,Color(0.5,0.5,0.5),Color.WHITE]
	for column in 3:
		var panel := ColorRect.new()
		panel.color = colors[column]
		panel.size = Vector2(440,555)
		panel.position = Vector2(30+470*column,140)
		view.add_child(panel)
		for row in 2:
			var name := "metal_hand" if row == 0 else "near_boot"
			var path := root.path_join("art_src/characters/rin_walk_source_ig01/author_parts/%s.png" % name)
			var image := Image.load_from_file(path)
			assert(image != null and not image.is_empty())
			var sprite := Sprite2D.new()
			sprite.texture = ImageTexture.create_from_image(image)
			sprite.centered = false
			sprite.position = Vector2(100+470*column,165+235*row)
			sprite.scale = Vector2.ONE
			view.add_child(sprite)
	label(view,Vector2(30,105),"Black / gray / white, original pixels at 1:1. Hand 95x130; boot 232x247. No resize.",21)
	label(view,Vector2(30,712),"Thumb, cuff, lace knot and outsole retained. Hidden wrist/calf layers remain unverified.",21)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var captured := Capture.image(view)
	assert(captured.get_size() == view.size and captured.save_png(output) == OK)
	print("VISIBLE_PARTS_CAPTURE size=1440x760 renderer=",RenderingServer.get_current_rendering_method()," hdr=",view.use_hdr_2d)
	get_tree().quit()

func label(view: SubViewport, at: Vector2, text: String, size: int) -> void:
	var node := Label.new()
	node.position = at
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	view.add_child(node)
