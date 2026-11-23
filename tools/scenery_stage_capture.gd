extends Node
## All authored cutscene stages, one at a time, using native HDR Forward+ readback.
const ViewportCapture := preload("res://tools/viewport_capture.gd")

func _ready() -> void:
	var out := "user://verification/scenery-stages"
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var ids := StageLibrary.ids()
	if not only.is_empty() and not ids.has(StringName(only)):
		push_error("[stage_capture] Unknown stage: %s" % only)
		get_tree().quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(out)
	if directory_error == OK and not DirAccess.dir_exists_absolute(out):
		directory_error = ERR_CANT_CREATE
	if directory_error != OK:
		push_error("[stage_capture] Cannot create %s: %s" % [out, error_string(directory_error)])
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("[stage_capture] A rendering viewport is required.")
		get_tree().quit(1)
		return
	add_child(LightKit.create_environment())
	for id in ids:
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
		var path := out.path_join("BG-19-stage-%s.png" % id)
		var saved := ViewportCapture.image(get_viewport()).save_png(path)
		if saved != OK:
			push_error("[stage_capture] Cannot save %s: %s" % [path, error_string(saved)])
			get_tree().quit(1)
			return
		print("[stage_capture] " + ProjectSettings.globalize_path(path))
		stage.queue_free()
		ambient.queue_free()
		for i in 3:
			await get_tree().process_frame
	get_tree().quit()
