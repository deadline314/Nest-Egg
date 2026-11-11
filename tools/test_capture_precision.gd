extends Node
## CPU-only transfer-function test against the real capture encoder.
## Before encode() exists, adapt only viewport acquisition to an Image input; retain the original encoding body.

const Capture := preload("res://tools/viewport_capture.gd")
var _checks := 0
var _failures: Array[String] = []
var _out := ""
var _manifest := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=").replace("\\", "/")
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[CapturePrecision] --out requires an absolute directory")
		get_tree().quit(2)
		return
	_run()


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://tools/viewport_capture.gd")
	var encoder: Object
	var mode := "public encode"
	if source.contains("static func encode("):
		encoder = Capture.new()
	else:
		mode = "legacy body; viewport acquisition replaced with Image input"
		var adapter := GDScript.new()
		adapter.source_code = source.replace("static func image(viewport: Viewport) -> Image:", "static func encode(source: Image, hdr: bool) -> Image:").replace("var result := viewport.get_texture().get_image()", "var result := source.duplicate() as Image").replace("if viewport.use_hdr_2d:", "if hdr:")
		if adapter.reload() != OK:
			push_error("[CapturePrecision] legacy acquisition adapter did not compile")
			get_tree().quit(2)
			return
		encoder = adapter.new()
	_check(encoder != null, "the actual capture encoding entry is available")
	_write_bytes("capture-source.gd", FileAccess.get_file_as_bytes("res://tools/viewport_capture.gd"))
	_write_bytes("test-source.gd", FileAccess.get_file_as_bytes("res://tools/test_capture_precision.gd"))
	var rows := []
	for format in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF]:
		var raw := Image.create(256, 64, false, format)
		for y in raw.get_height():
			for x in raw.get_width():
				var value := float(x) / 255.0 * 0.03
				raw.set_pixel(x, y, Color(value, value * 0.75, value * 0.5, 0.37))
		var before := raw.get_data()
		var encoded: Image = encoder.call("encode", raw, true)
		var actual_levels := {}
		var reference_levels := {}
		var max_error := 0.0
		var reference := Image.create(256, 64, false, Image.FORMAT_RGBA8)
		for x in raw.get_width():
			var linear := raw.get_pixel(x, 0)
			var expected := Color(_srgb(linear.r), _srgb(linear.g), _srgb(linear.b), linear.a)
			for y in reference.get_height():
				reference.set_pixel(x, y, expected)
			var actual := encoded.get_pixel(x, 0)
			max_error = maxf(max_error, maxf(absf(actual.r - expected.r), maxf(absf(actual.g - expected.g), absf(actual.b - expected.b))))
			actual_levels[roundi(actual.r * 255)] = true
			reference_levels[roundi(expected.r * 255)] = true
		_check(max_error <= 1.0 / 255.0 + 0.00001, "float format %d dark values stay within one sRGB byte step (error %.6f)" % [format, max_error])
		_check(actual_levels.size() >= reference_levels.size() - 1, "float format %d preserves dark ramp levels (%d vs %d)" % [format, actual_levels.size(), reference_levels.size()])
		_check(encoded.get_size() == raw.get_size(), "float format %d preserves dimensions" % format)
		_check(absf(encoded.get_pixel(20, 20).a - 0.37) < 0.004, "float format %d preserves alpha without gamma conversion" % format)
		_check(raw.get_data() == before, "float format %d leaves raw HDR data unchanged" % format)
		_write_bytes("ramp-%d-linear.bin" % format, before)
		_write_bytes("ramp-%d-encoded.bin" % format, encoded.get_data())
		_write_bytes("ramp-%d-encoded.png" % format, encoded.save_png_to_buffer())
		_write_bytes("ramp-%d-reference.png" % format, reference.save_png_to_buffer())
		rows.append({"format": format, "size": [256, 64], "max_srgb_error": max_error, "encoded_levels": actual_levels.size(), "reference_levels": reference_levels.size()})
	var ldr := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	ldr.fill(Color(0.12, 0.34, 0.56, 0.37))
	var ldr_bytes := ldr.get_data()
	var unchanged: Image = encoder.call("encode", ldr, false)
	_check(unchanged.get_data() == ldr_bytes, "LDR bytes remain identical")
	var result := {"mode": mode, "checks": _checks, "failures": _failures, "samples": rows, "files": _manifest}
	var file := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("CAPTURE_PRECISION ", JSON.stringify(result))
	print("checks: %d, failures: %d" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


## IEC 61966-2-1 transfer function, evaluated before any 8-bit quantization.
func _srgb(value: float) -> float:
	return value * 12.92 if value <= 0.0031308 else 1.055 * pow(value, 1.0 / 2.4) - 0.055


func _write_bytes(name: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(_out.path_join(name), FileAccess.WRITE)
	file.store_buffer(bytes)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	_manifest[name] = {"bytes": bytes.size(), "sha256": hash.finish().hex_encode()}


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("FAIL: " + message)
