extends Node2D

const CHARACTER_LIGHT := preload("res://art/shaders/character_light.gdshader")
const ENERGIES := [0.0, 0.15, 0.75]
const RECEIVERS := [
	{"id": "directional_sprite", "kind": "directional", "shape": "sprite", "center": Vector2(55.0, 65.0), "mask": 1},
	{"id": "directional_polygon", "kind": "directional", "shape": "polygon", "center": Vector2(175.0, 65.0), "mask": 2},
	{"id": "point_sprite", "kind": "point", "shape": "sprite", "center": Vector2(315.0, 65.0), "mask": 4},
	{"id": "point_polygon", "kind": "point", "shape": "polygon", "center": Vector2(455.0, 65.0), "mask": 8},
]

var _out_dir := "user://ne222-light-energy-probe"
var _items: Dictionary = {}
var _lights: Dictionary = {}
var _records: Array[Dictionary] = []
var _failures: Array[String] = []
var _gray_reference := Vector3.ZERO
var _gray_reference_set := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			_out_dir = arg.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_build_probe()
	await _run_captures()
	_write_report()
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _build_probe() -> void:
	var canvas_modulate := CanvasModulate.new()
	canvas_modulate.color = Color(0.2, 0.2, 0.2, 1.0)
	add_child(canvas_modulate)

	var diffuse := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	diffuse.fill(Color.WHITE)
	var diffuse_texture := ImageTexture.create_from_image(diffuse)
	var normal := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	normal.fill(Color(0.5, 0.5, 1.0, 1.0))
	var normal_texture := ImageTexture.create_from_image(normal)
	var canvas_texture := CanvasTexture.new()
	canvas_texture.diffuse_texture = diffuse_texture
	canvas_texture.normal_texture = normal_texture

	for spec: Dictionary in RECEIVERS:
		var node: CanvasItem
		if spec.shape == "sprite":
			var sprite := Sprite2D.new()
			sprite.texture = canvas_texture
			sprite.position = spec.center
			node = sprite
		else:
			var polygon := Polygon2D.new()
			polygon.position = spec.center
			polygon.polygon = PackedVector2Array([Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32)])
			polygon.uv = PackedVector2Array([Vector2(0, 0), Vector2(64, 0), Vector2(64, 64), Vector2(0, 64)])
			polygon.texture = canvas_texture
			node = polygon
		node.name = spec.id
		node.light_mask = int(spec.mask)
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = CHARACTER_LIGHT
		material.set_shader_parameter("fill", 1.0)
		material.set_shader_parameter("light_cap", 0.5)
		node.material = material
		add_child(node)
		_items[spec.id] = node
		_lights[spec.id] = _make_light(spec)

	var reference := Sprite2D.new()
	reference.name = "unshaded_gray_reference"
	reference.texture = diffuse_texture
	reference.position = Vector2(575.0, 65.0)
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	reference.material = unshaded
	reference.modulate = Color(0.5, 0.5, 0.5, 1.0)
	add_child(reference)
	_items["unshaded_gray_reference"] = reference


func _make_light(spec: Dictionary) -> Light2D:
	var light: Light2D
	if spec.kind == "directional":
		var directional := DirectionalLight2D.new()
		directional.height = 140.0
		light = directional
	else:
		var point := PointLight2D.new()
		point.texture = _radial_light_texture()
		point.texture_scale = 7.0
		point.height = 140.0
		light = point
	light.name = "%s_light" % spec.id
	light.position = spec.center
	light.color = Color.WHITE
	light.energy = 0.0
	light.enabled = true
	light.range_item_cull_mask = int(spec.mask)
	add_child(light)
	return light


func _radial_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture


func _run_captures() -> void:
	for receiver: Dictionary in RECEIVERS:
		for other: Light2D in _lights.values():
			other.enabled = false
		var light: Light2D = _lights[receiver.id]
		light.enabled = true
		for energy: float in ENERGIES:
			light.energy = energy
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			if image.get_format() not in [Image.FORMAT_RGBH, Image.FORMAT_RGBAH, Image.FORMAT_RGBF, Image.FORMAT_RGBAF]:
				_failures.append("Expected an HDR RGBA viewport image; got format %s" % image.get_format())
			var pixel := _sample_at(receiver.id, image)
			var gray := _sample_at("unshaded_gray_reference", image)
			var gray_vector := Vector3(gray.r, gray.g, gray.b)
			if not _gray_reference_set:
				_gray_reference = gray_vector
				_gray_reference_set = true
			elif gray_vector.distance_to(_gray_reference) > 0.01:
				_failures.append("Unshaded gray reference changed during captures: %s vs %s" % [gray_vector, _gray_reference])
			var key := "%s@%.2f" % [receiver.id, energy]
			_items[key] = pixel
			var record := {"sample": key, "energy": energy, "linear_rgb": [pixel.r, pixel.g, pixel.b], "linear_luminance": _luminance(pixel), "image_format": image.get_format()}
			_records.append(record)
			var png_path := ProjectSettings.globalize_path("%s/%s_%02d.png" % [_out_dir, receiver.id, int(round(energy * 100.0))])
			var png_error := _save_srgb_png(image, png_path)
			if png_error != OK:
				_failures.append("Could not save %s: error %s" % [png_path, png_error])

		var zero_lum := _luminance(_items["%s@0.00" % receiver.id])
		var low_lum := _luminance(_items["%s@0.15" % receiver.id])
		var high_lum := _luminance(_items["%s@0.75" % receiver.id])
		if low_lum - zero_lum <= 0.005:
			_failures.append("%s: energy 0.15 did not contribute above zero (delta %.6f)" % [receiver.id, low_lum - zero_lum])
		if high_lum - low_lum <= 0.01:
			_failures.append("%s: energy 0.75 did not contribute above 0.15 (delta %.6f)" % [receiver.id, high_lum - low_lum])
		if high_lum <= low_lum:
			_failures.append("%s: energy response is not monotonic" % receiver.id)

	if maxf(_gray_reference.x, maxf(_gray_reference.y, _gray_reference.z)) < 0.01:
		_failures.append("Unshaded gray reference is missing/black; harness could be sampling an empty viewport")


func _sample_at(node_id: String, image: Image) -> Color:
	var item := _items[node_id] as CanvasItem
	var transform := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var center: Vector2 = transform * (item as Node2D).global_position
	var point := Vector2i(roundi(center.x), roundi(center.y))
	if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
		_failures.append("Sample %s is outside captured image at %s (%s)" % [node_id, point, image.get_size()])
		return Color.BLACK
	var sample := image.get_pixel(point.x, point.y)
	if not is_finite(sample.r) or not is_finite(sample.g) or not is_finite(sample.b):
		_failures.append("Sample %s contains non-finite HDR values" % node_id)
	return sample


func _save_srgb_png(source: Image, path: String) -> Error:
	var output := source.duplicate()
	output.convert(Image.FORMAT_RGBA8)
	output.linear_to_srgb()
	return output.save_png(path)


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _write_report() -> void:
	var report := {
		"renderer_expected": "Forward+ HDR 2D",
		"shader_resource": "res://art/shaders/character_light.gdshader",
		"source_shader_sha256": FileAccess.get_sha256("res://art/shaders/character_light.gdshader"),
		"canvas_modulate_linear": [0.2, 0.2, 0.2],
		"uniforms": {"fill": 1.0, "light_cap": 0.5},
		"energies": ENERGIES,
		"receivers": _records,
		"unshaded_gray_reference_linear": [_gray_reference.x, _gray_reference.y, _gray_reference.z],
		"failures": _failures,
		"result": "PASS" if _failures.is_empty() else "FAIL",
		"note": "CPU harness validation is not anatomy, art, or final-screen acceptance."
	}
	var file := FileAccess.open(ProjectSettings.globalize_path("%s/report.json" % _out_dir), FileAccess.WRITE)
	if file == null:
		push_error("Could not write report JSON")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(JSON.stringify({"result": report.result, "failures": _failures, "report": ProjectSettings.globalize_path("%s/report.json" % _out_dir)}))
	for failure: String in _failures:
		push_error(failure)
