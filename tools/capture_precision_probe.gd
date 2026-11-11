extends Node
## BG-54: both encodings share one immutable native HDR readback.
## The observer runs while paused; the actual Level explicitly remains PAUSABLE.

var _out := ""
var _width := 1280
var _height := 720
var _checks := 0
var _failures: Array[String] = []
var _files := {}
var _captures: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").replace("\\", "/")
		elif arg.begins_with("--width="):
			_width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="):
			_height = int(arg.trim_prefix("--height="))
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[BG54] --out requires an absolute directory")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var sources := preload("res://tools/world_pause_sample.gd").source_receipt(_out, ["res://tools/capture_precision_probe.gd", "res://tools/world_pause_sample.gd", "res://tools/viewport_capture.gd", "res://ui/kit/scene_backdrop.gd"])
	Settings.use_storage("user://BG-54-capture-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[0])
	add_child(LightKit.create_environment())
	var level := Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	level.configure(load("res://data/levels/ch1_pawnshop.tres") as LevelData)
	add_child(level)
	await get_tree().create_timer(2.0, true, false, true).timeout
	get_tree().paused = true
	var before := preload("res://tools/world_pause_sample.gd").snapshot(level)
	await _pair("world")
	level._pause_menu.open()
	await _pair("pause")
	level._pause_menu._open_navigation("quests")
	await _pair("quests")
	var after := preload("res://tools/world_pause_sample.gd").snapshot(level)
	_check(before == after and not level.can_process() and not level.player.can_process(), "the same player, camera, canvas transform, fog and clock remain frozen")
	_check(get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() == "forward_plus", "the actual native viewport uses Forward+ and HDR 2D")
	var report := {"checks": _checks, "failures": _failures, "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info()["string"], "resolution": [_width, _height], "sources": sources, "world_before": before, "world_after": after, "captures": _captures, "files": _files, "classification": "actual formal pawnshop Level with native UI; legacy/new PNGs encoded from each single raw readback; synthetic setup, no physical controller or campaign completion"}
	var file := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BG54_CAPTURE ", JSON.stringify(report))
	get_tree().paused = false
	level.queue_free()
	for i in 6:
		await get_tree().process_frame
	Sfx.stop_all()
	Music.stop(0.0)
	Ambience.stop_all(0.0)
	await get_tree().create_timer(0.3, true, false, true).timeout
	print("checks: %d, failures: %d" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _pair(page: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var raw := get_viewport().get_texture().get_image()
	var bytes := raw.get_data()
	var legacy := raw.duplicate() as Image
	legacy.convert(Image.FORMAT_RGBA8)
	legacy.linear_to_srgb()
	var encoded := preload("res://tools/viewport_capture.gd").encode(raw, true)
	var prefix := "BG-54-%s-%d" % [page, _width]
	var raw_name := prefix + "-linear.bin"
	var old_name := prefix + "-before.png"
	var new_name := prefix + "-after.png"
	_write(raw_name, bytes)
	_write(old_name, legacy.save_png_to_buffer())
	_write(new_name, encoded.save_png_to_buffer())
	var max_error := 0.0
	var alpha_error := 0.0
	for y in range(0, raw.get_height(), 17):
		for x in range(0, raw.get_width(), 17):
			var linear := raw.get_pixel(x, y)
			var actual := encoded.get_pixel(x, y)
			for pair in [[linear.r, actual.r], [linear.g, actual.g], [linear.b, actual.b]]:
				var expected: float = pair[0] * 12.92 if pair[0] <= 0.0031308 else 1.055 * pow(pair[0], 1.0 / 2.4) - 0.055
				max_error = maxf(max_error, absf(pair[1] - clampf(expected, 0, 1)))
			alpha_error = maxf(alpha_error, absf(actual.a - linear.a))
	_check(raw.get_data() == bytes, page + " encodes both PNGs without mutating the raw HDR bytes")
	_check(encoded.get_size() == raw.get_size(), page + " preserves native dimensions")
	_check(raw.get_size() == Vector2i(_width, _height), page + " raw pixels match the requested native resolution")
	_check(max_error <= 1.0 / 255.0 + 0.00001 and alpha_error <= 1.0 / 255.0 + 0.00001, page + " matches the independent float transfer formula within one byte step")
	_captures.append({"page": page, "size": [raw.get_width(), raw.get_height()], "format": raw.get_format(), "linear_raw": raw_name, "legacy_png": old_name, "encoded_png": new_name, "max_srgb_error_sampled": max_error, "max_alpha_error_sampled": alpha_error})


func _write(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(_out.path_join(name), FileAccess.WRITE)
	file.store_buffer(bytes)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	_files[name] = {"bytes": bytes.size(), "sha256": hash.finish().hex_encode()}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("FAIL: " + message)
