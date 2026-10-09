extends Node
## All authored cutscene stages, one at a time, using native HDR Forward+ readback.
const ViewportCapture := preload("res://tools/viewport_capture.gd")

func _ready() -> void:
	var out := "res://pm/Nest-Egg/images"
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(out)
	add_child(LightKit.create_environment())
	for id in StageLibrary.ids():
		if not only.is_empty() and String(id) != only:
			continue
		var stage := StageLibrary.build(id)
		var def := StageLibrary.definition(id)
		var ambient := CanvasModulate.new()
		ambient.color = Color(str(def.get("ambient", "#ffffff")))
		add_child(ambient)
		stage.scale = Vector2.ONE * stage.default_camera_zoom
		stage.position = Vector2(320, 180) - stage.default_camera_pos * stage.default_camera_zoom
		stage.apply_parallax(stage.default_camera_pos)
		add_child(stage)
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/BG-19-stage-%s.png" % [out, id]
		ViewportCapture.image(get_viewport()).save_png(path)
		print("[stage_capture] " + path)
		stage.queue_free()
		ambient.queue_free()
		for i in 3:
			await get_tree().process_frame
	get_tree().quit()
