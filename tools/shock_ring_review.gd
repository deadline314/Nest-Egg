extends Node
## NE-95: legacy placeholder (left) versus production ring (right), same shader and centered geometry.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://verification/shock-ring-review.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var directory := out.get_base_dir()
	var directory_error := OK if directory.is_empty() else DirAccess.make_dir_recursive_absolute(directory)
	if directory_error == OK and not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		directory_error = ERR_CANT_CREATE
	if directory_error != OK:
		push_error("[shock_ring_review] Cannot create %s: %s" % [directory, error_string(directory_error)])
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("[shock_ring_review] A rendering viewport is required.")
		get_tree().quit(1)
		return
	for index in 2:
		var sprite: Sprite2D = Sprite2D.new() if index == 0 else ShockRing.new()
		if index == 0:
			var placeholder := PlaceholderTexture2D.new()
			placeholder.size = Vector2(2, 2)
			sprite.texture = placeholder
		var material := ShaderMaterial.new()
		material.shader = load("res://art/shaders/shock_ring.gdshader")
		material.set_shader_parameter("progress", 0.3)
		material.set_shader_parameter("strength", 0.0)
		material.set_shader_parameter("tint", Color.CYAN)
		sprite.scale = Vector2(80, 80)
		sprite.position = Vector2(160 + index * 320, 180)
		add_child(sprite)  # ShockRing._ready supplies the shared production carrier.
		sprite.visible = true
		sprite.material = material
		print("RING type=%s center=%s rect=%s" % [sprite.texture.get_class(), sprite.position, sprite.get_rect()])
	for i in 10:
		await get_tree().process_frame
	var error := preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out)
	if error != OK:
		push_error("[shock_ring_review] Cannot save %s: %s" % [out, error_string(error)])
	else:
		print("[shock_ring_review] " + ProjectSettings.globalize_path(out))
	get_tree().quit(0 if error == OK else 1)
