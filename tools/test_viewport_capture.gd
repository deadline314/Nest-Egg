extends Node
## Run with gpu_lock.py -- godot --path . res://tools/test_viewport_capture.tscn.
## Checks known sRGB colors, LDR byte preservation, alpha and native dimensions.
func _ready() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
			if out.is_empty() or not out.is_absolute_path():
				push_error("[viewport_capture_check] --out requires an absolute directory")
				get_tree().quit(1)
				return
	if not out.is_empty() and DirAccess.make_dir_recursive_absolute(out) != OK:
		push_error("[viewport_capture_check] cannot create " + out)
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("[viewport_capture_check] requires a rendered viewport")
		get_tree().quit(1)
		return
	get_tree().create_timer(10).timeout.connect(get_tree().quit.bind(1))
	for hdr in [false, true]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64,64)
		viewport.transparent_bg = true
		viewport.use_hdr_2d = hdr
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var rect := ColorRect.new()
		rect.size = Vector2(32,32)
		rect.color = Color("737b86")
		viewport.add_child(rect)
		var translucent := ColorRect.new()
		translucent.position = Vector2(40,0)
		translucent.size = Vector2(16,16)
		translucent.color = Color(1,1,1,.37)
		viewport.add_child(translucent)
		for i in 3: await RenderingServer.frame_post_draw
		var raw := viewport.get_texture().get_image()
		var encoded := preload("res://tools/viewport_capture.gd").image(viewport)
		var pixel := encoded.get_pixel(10,10)
		print("CAPTURE_CHECK HDR=",hdr," raw_format=",raw.get_format()," raw=",raw.get_pixel(10,10)," encoded=",pixel)
		assert(absf(pixel.r - rect.color.r) < .012 and absf(pixel.g - rect.color.g) < .012 and absf(pixel.b - rect.color.b) < .012)
		assert(encoded.get_size() == Vector2i(64,64))
		assert(encoded.get_pixel(50,50).a == 0)
		assert(absf(encoded.get_pixel(45,5).a - .37) < .006)
		if not hdr: assert(raw.get_data() == encoded.get_data())
		if not out.is_empty():
			assert(raw.save_png(out.path_join("hdr_%s_raw.png" % hdr)) == OK)
			assert(encoded.save_png(out.path_join("hdr_%s_encoded.png" % hdr)) == OK)
		viewport.queue_free()
		await get_tree().process_frame
	get_tree().quit()
