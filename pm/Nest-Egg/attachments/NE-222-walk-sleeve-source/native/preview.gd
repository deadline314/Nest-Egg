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
	label(view,Vector2(30,20),"NE-222 | One native sleeve source | Original standing illustration preserved",26)
	label(view,Vector2(30,65),"SOURCE ONLY: shoulder/cuff binding, anatomy, normal/glow and walking unaccepted",21)
	label(view,Vector2(30,105),"Black / gray / white at 1:1. One 181x311 material crop; original 384x512 canvas.",21)
	var image := Image.load_from_file(root.path_join("art_src/characters/rin_walk_sleeve_22322/sleeve-canvas.png"))
	assert(image != null and image.get_size() == Vector2i(384,512))
	var colors := [Color.BLACK,Color(0.5,0.5,0.5),Color.WHITE]
	for column in 3:
		var panel := ColorRect.new()
		panel.color = colors[column]
		panel.size = Vector2(440,555)
		panel.position = Vector2(30+470*column,140)
		view.add_child(panel)
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.centered = false
		sprite.position = Vector2(60+470*column,160)
		view.add_child(sprite)
	label(view,Vector2(30,712),"34,835 source RGB pixels; reviewed cuff opacity repaired. No runtime asset replacement.",21)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var captured := Capture.image(view)
	assert(captured.get_size() == view.size and captured.save_png(output) == OK)
	print("SLEEVE_SOURCE_CAPTURE size=1440x760 renderer=",RenderingServer.get_current_rendering_method()," hdr=",view.use_hdr_2d)
	get_tree().quit()

func label(view: SubViewport, at: Vector2, text: String, size: int) -> void:
	var node := Label.new()
	node.position = at
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	view.add_child(node)
