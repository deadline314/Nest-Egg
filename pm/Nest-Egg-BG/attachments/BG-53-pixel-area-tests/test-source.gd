extends Node
## Known answers use explicit pixel bounds/counts, independent of ContrastProbe's denominator.
## --out=<absolute directory> [--native] draws the exact floating fixtures and measured text.

var _out := ""
var _native := false
var _checks: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _pattern: Image
var _hdr: Image


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--native":
			_native = true
	if not _out.is_absolute_path():
		push_error("[ContrastGeometry] --out requires an absolute directory")
		get_tree().quit(2)
		return
	if _native and DisplayServer.get_name() == "headless":
		push_error("[ContrastGeometry] Native image mode requires a real rendering window")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	# Bounds below are hand-enumerated half-open image intervals on a 64x64 raster.
	# They deliberately never derive an expected count from world_rect.size or the tested mapper.
	_uniform("identity", 1.0, Vector2.ONE, Vector2.ZERO, Rect2(4, 4, 10, 10), Rect2i(4, 4, 10, 10), 100)
	_uniform("zoom2", 1.0, Vector2(2, 2), Vector2.ZERO, Rect2(4, 4, 10, 10), Rect2i(8, 8, 20, 20), 400)
	_uniform("density2", 2.0, Vector2.ONE, Vector2.ZERO, Rect2(4, 4, 10, 10), Rect2i(8, 8, 20, 20), 400)
	_uniform("zoom2+density2", 2.0, Vector2(2, 2), Vector2.ZERO, Rect2(4, 4, 10, 10), Rect2i(16, 16, 40, 40), 1600)
	_uniform("zoom-half", 1.0, Vector2(0.5, 0.5), Vector2.ZERO, Rect2(4, 4, 10, 10), Rect2i(2, 2, 5, 5), 25)
	_uniform("density-half", 0.5, Vector2.ONE, Vector2.ZERO, Rect2(4, 4, 10, 10), Rect2i(2, 2, 5, 5), 25)
	_uniform("translation", 1.0, Vector2.ONE, Vector2(5, 7), Rect2(4, 4, 10, 10), Rect2i(9, 11, 10, 10), 100)
	_uniform("fractional-translation", 1.0, Vector2.ONE, Vector2(0.25, 0.75), Rect2(4, 4, 10, 10), Rect2i(4, 4, 11, 11), 121)
	_uniform("clipped", 1.0, Vector2.ONE, Vector2.ZERO, Rect2(-4, -4, 10, 10), Rect2i(0, 0, 6, 6), 36)
	_uniform("clipped-zoom+density", 2.0, Vector2(2, 2), Vector2.ZERO, Rect2(-4, -4, 10, 10), Rect2i(0, 0, 24, 24), 576)
	_uniform("off-screen", 1.0, Vector2.ONE, Vector2.ZERO, Rect2(80, 80, 10, 10), Rect2i(), 0)
	_uniform("no-visible-outer-ring", 1.0, Vector2.ONE, Vector2.ZERO, Rect2(0, 0, 64, 64), Rect2i(0, 0, 64, 64), 4096, true)
	_test_hdr()
	_test_known_pattern()
	var failures := _checks.filter(func(row: Dictionary) -> bool: return not row.passed).size()
	var report := {"checks": _checks, "failures": failures, "rows": _rows,
		"contrast_probe_sha256": FileAccess.get_sha256("res://tools/contrast_probe.gd"),
		"test_sha256": FileAccess.get_sha256("res://tools/test_contrast_probe_geometry.gd"),
		"native": _native, "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "hdr_2d": get_viewport().use_hdr_2d,
		"scope": "fixed 64x64 floating-point test images; not a game route or scene readability acceptance"}
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CONTRAST_GEOMETRY checks=", _checks.size(), " failures=", failures)
	if _native:
		_show_native(failures)
		for frame in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var captured := preload("res://tools/viewport_capture.gd").image(get_viewport())
		var error := captured.save_png(_out.path_join("known-answer-native.png"))
		print("CONTRAST_GEOMETRY_NATIVE saved=", error_string(error))
		if error != OK:
			failures += 1
	get_tree().quit(0 if failures == 0 else 1)


func _probe(image: Image, density: float, zoom: Vector2, offset: Vector2) -> ContrastProbe:
	var probe := ContrastProbe.new()
	probe._image = image
	probe._scale = density
	probe._to_screen = Transform2D(Vector2(zoom.x, 0), Vector2(0, zoom.y), offset)
	return probe


func _float_image(value: float) -> Image:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBAF)
	image.fill(Color(value, value, value, 1.0))
	return image


func _uniform(name: String, density: float, zoom: Vector2, offset: Vector2, box: Rect2, expected_rect: Rect2i, expected_pixels: int, empty_ring := false) -> void:
	var probe := _probe(_float_image(0.25), density, zoom, offset)
	var actual_rect := probe._screen_rect(box)
	var pixels := probe._pixel_count(box)
	var mean := probe.mean_luma(box)
	var parts := probe.contrast_parts(box, 2.0)
	var contrast := probe.contrast(box, 2.0)
	var prefix := name + ": "
	_check(actual_rect == expected_rect if expected_pixels > 0 else not actual_rect.has_area(), prefix + "actual pixel bounds", str(actual_rect), str(expected_rect))
	_close(pixels, float(expected_pixels), prefix + "pixel count")
	_close(mean, 0.25 if expected_pixels > 0 else 0.0, prefix + "uniform mean")
	_close(contrast, 0.0, prefix + "uniform contrast")
	_close(float(parts.get("outer", NAN)), 0.0 if expected_pixels == 0 or empty_ring else 0.25, prefix + "uniform outer mean")
	_check(contrast < ContrastProbe.MIN_PLAYER_CONTRAST and contrast < ContrastProbe.MIN_ENEMY_CONTRAST, prefix + "cannot falsely pass readability", contrast, 0.0)
	_rows.append({"name": name, "pixels": pixels, "expected_pixels": expected_pixels, "mean": mean, "contrast": contrast})


func _test_hdr() -> void:
	_hdr = _float_image(2.0)
	var probe := _probe(_hdr, 2.0, Vector2(2, 2), Vector2.ZERO)
	var box := Rect2(4, 4, 10, 10)
	_close(_hdr.get_pixel(20, 20).r, 2.0, "HDR fixture retains 2.0")
	_close(probe.mean_luma(box), 2.0, "HDR transformed mean is 2.0")
	_close(probe.contrast(box, 2.0), 0.0, "HDR uniform contrast")
	_rows.append({"name": "HDR2.0", "pixels": probe._pixel_count(box), "expected_pixels": 1600, "mean": probe.mean_luma(box), "contrast": probe.contrast(box, 2.0)})


func _test_known_pattern() -> void:
	_pattern = _float_image(0.1)
	# Explicit 40x40 interior pixels [16,56)x[16,56). The ring is [8,64)^2 minus those 1600 pixels.
	for y in range(16, 56):
		for x in range(16, 56):
			_pattern.set_pixel(x, y, Color(0.4, 0.4, 0.4, 1))
	var probe := _probe(_pattern, 2.0, Vector2(2, 2), Vector2.ZERO)
	var box := Rect2(4, 4, 10, 10)
	var parts := probe.contrast_parts(box, 2.0)
	_close(probe._pixel_count(box), 1600, "pattern inner hand-count is 1600")
	_close(probe._pixel_count(box.grow(2.0)), 3136, "pattern outer hand-count is 3136")
	_close(probe.mean_luma(box), 0.4, "pattern interior mean")
	_close(float(parts.get("inner", NAN)), 0.4, "pattern bright percentile")
	_close(float(parts.get("body", NAN)), 0.4, "pattern body percentile")
	_close(float(parts.get("outer", NAN)), 0.1, "pattern ring mean")
	_close(float(parts.get("bright", NAN)), 2.5, "pattern bright hand-answer (0.4-0.1)/(0.1+0.02)")
	_close(float(parts.get("dark", NAN)), -2.5, "pattern dark hand-answer")
	_close(probe.contrast(box, 2.0), 2.5, "pattern chosen contrast")
	_rows.append({"name": "0.4 / 0.1 pattern", "pixels": probe._pixel_count(box), "expected_pixels": 1600, "mean": probe.mean_luma(box), "contrast": probe.contrast(box, 2.0), "parts": parts})


func _close(actual: float, expected: float, message: String) -> void:
	_check(is_finite(actual) and absf(actual - expected) < 0.0001, message, actual, expected)


func _check(passed: bool, message: String, actual: Variant, expected: Variant) -> void:
	_checks.append({"passed": passed, "message": message, "actual": actual, "expected": expected})
	print("CHECK ", passed, " ", message, " actual=", actual, " expected=", expected)


func _show_native(failures: int) -> void:
	get_window().size = Vector2i(1280, 720)
	DisplayMode.ensure_scaling(get_window())
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.size = Vector2(640, 360)
	background.color = Color("111827")
	layer.add_child(background)
	_label(layer, Vector2(16, 10), 14, "Known-answer pixel-area fixtures / %d checks / %d failures" % [_checks.size(), failures])
	_label(layer, Vector2(16, 33), 10, "%s / %s / HDR=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), get_viewport().use_hdr_2d])
	var lines := "Fixture                   pixels/expected     mean   contrast\n"
	for row in _rows:
		lines += "%-25s %6.0f/%-6d   %5.3f   %6.3f\n" % [row.name, row.pixels, row.expected_pixels, row.mean, row.contrast]
	_label(layer, Vector2(16, 62), 10, lines)
	_label(layer, Vector2(16, 294), 11, "Uniform=0.25; empty sample/ring must not pass.\nPattern bright=(0.4-0.1)/(0.1+0.02)=2.5. HDR mean=2.0.\nSynthetic floating images; not a game route.")
	_texture(layer, _pattern, Vector2(496, 68))
	_label(layer, Vector2(496, 49), 10, "0.4 inside / 0.1 ring")
	_texture(layer, _hdr, Vector2(496, 220))
	_label(layer, Vector2(496, 201), 10, "HDR source = 2.0")


func _label(parent: Node, at: Vector2, size: int, value: String) -> void:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.text = value
	parent.add_child(label)


func _texture(parent: Node, source: Image, at: Vector2) -> void:
	var texture := TextureRect.new()
	texture.position = at
	texture.size = Vector2(128, 128)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.texture = ImageTexture.create_from_image(source)
	parent.add_child(texture)
