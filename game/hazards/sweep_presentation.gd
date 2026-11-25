extends RefCounted
## Pairs built-in lighting on the physical emitter with floor markings sized
## to the actual sweep sector. Neither presentation controls gameplay timing.

const EMITTER_PATH := "res://art/environment/emitters/factory_sweep.png"
const EMITTER_WIDTH := 25.0
const SCAN_STEPS := 16
const GUIDE := Color(0.82, 0.90, 0.94, 0.78)
const WARN := Color(1.0, 0.69, 0.29, 0.88)
const LIVE := Color(0.55, 0.86, 0.95, 0.88)
const RAIL_SHADOW := Color(0.05, 0.08, 0.12, 0.78)

static var _emitter_texture: Texture2D
static var _emitter_checked := false


static func mount_emitter(parent: Node2D, sector: Rect2) -> void:
	var texture := _load_emitter_texture()
	if texture == null:
		return
	var emitter := Sprite2D.new()
	emitter.name = "SweepEmitter"
	emitter.texture = texture
	var scale_factor := minf(EMITTER_WIDTH, sector.size.x) / texture.get_width()
	emitter.scale = Vector2.ONE * scale_factor
	emitter.position = Vector2(sector.get_center().x, sector.position.y - texture.get_height() * scale_factor * 0.35)
	# The hull receives normal scene lighting. Marks and lens status are
	# composited in front by the emissive lane owner.
	emitter.z_index = -1
	parent.add_child(emitter)


static func _load_emitter_texture() -> Texture2D:
	if _emitter_checked:
		return _emitter_texture
	_emitter_checked = true
	# A checkout has the tiny source PNG even before the editor builds its
	# import cache. Packaged builds use the imported texture from the PCK.
	if FileAccess.file_exists(EMITTER_PATH):
		var bytes := FileAccess.get_file_as_bytes(EMITTER_PATH)
		if not bytes.is_empty():
			var image := Image.new()
			if image.load_png_from_buffer(bytes) == OK:
				_emitter_texture = ImageTexture.create_from_image(image)
	elif ResourceLoader.exists(EMITTER_PATH, "Texture2D"):
		_emitter_texture = load(EMITTER_PATH) as Texture2D
	if _emitter_texture == null:
		push_warning("[FactorySweep] Emitter texture unavailable: %s. Keeping the sweep guides." % EMITTER_PATH)
	return _emitter_texture


static func scan_step(progress: float, reduce_motion: bool) -> int:
	return roundi(SCAN_STEPS * 0.5) if reduce_motion else clampi(roundi(progress * SCAN_STEPS), 0, SCAN_STEPS)


static func draw_warning(canvas: CanvasItem, sector: Rect2, step: int, training: bool) -> void:
	_draw_guides(canvas, sector, GUIDE)
	_draw_floor_track(canvas, sector, WARN, false)
	var progress := float(step) / SCAN_STEPS
	if training:
		var y := lerpf(sector.position.y, sector.end.y - 1.0, progress)
		canvas.draw_rect(Rect2(sector.position.x, y, sector.size.x, 1.0), WARN)
		return
	_draw_lens(canvas, sector, WARN)
	var x := lerpf(sector.position.x + 1.0, sector.end.x - 1.0, progress)
	# Keep the moving line narrow and translucent. The guides continue to
	# mark the whole future hitbox while the floor lights show scan motion.
	canvas.draw_rect(Rect2(x - 0.5, sector.position.y, 1.0, sector.size.y), Color(WARN, 0.24))
	var width := minf(sector.size.x, 7.0)
	var left := clampf(x - width * 0.5, sector.position.x, sector.end.x - width)
	canvas.draw_rect(Rect2(left, sector.end.y - 2.0, width, 2.0), WARN)


static func draw_live(canvas: CanvasItem, sector: Rect2, reduce_flashes: bool) -> void:
	var light := Color(LIVE, 0.60) if reduce_flashes else LIVE
	_draw_guides(canvas, sector, light)
	_draw_floor_track(canvas, sector, light, true)
	_draw_lens(canvas, sector, light)
	var spill := minf(sector.size.y, 4.0)
	canvas.draw_rect(Rect2(sector.position.x, sector.end.y - spill, sector.size.x, spill), Color(light, light.a * 0.20))
	# Long, faint glints on the two sides establish height without washing
	# out the wall paint or resembling a modal laid over the scenery.
	var height := minf(sector.size.y, 3.0)
	canvas.draw_rect(Rect2(sector.position, Vector2(sector.size.x, height)), Color(light, light.a * 0.12))


static func lens_position(sector: Rect2) -> Vector2:
	return Vector2(sector.get_center().x - minf(EMITTER_WIDTH, sector.size.x) * 0.07, sector.position.y)


static func _draw_guides(canvas: CanvasItem, sector: Rect2, color: Color) -> void:
	var a := sector.position
	var b := sector.end
	var cap_width := minf(sector.size.x * 0.24, 11.0)
	var side := minf(sector.size.y * 0.34, 11.0)
	for x in [a.x, b.x]:
		canvas.draw_line(Vector2(x, a.y), Vector2(x, b.y), Color(color, color.a * 0.34), 0.75)
		canvas.draw_line(Vector2(x, a.y), Vector2(x, a.y + side), color, 1.0)
		canvas.draw_line(Vector2(x, b.y - side), Vector2(x, b.y), color, 1.0)
	canvas.draw_line(a, a + Vector2(cap_width, 0.0), color, 1.0)
	canvas.draw_line(Vector2(b.x - cap_width, a.y), Vector2(b.x, a.y), color, 1.0)


static func _draw_floor_track(canvas: CanvasItem, sector: Rect2, color: Color, active: bool) -> void:
	var y := sector.end.y - 1.0
	canvas.draw_rect(Rect2(sector.position.x, y - 1.0, sector.size.x, 2.0), RAIL_SHADOW)
	if active:
		canvas.draw_rect(Rect2(sector.position.x, y, sector.size.x, 1.0), color)
	# A row of small metallic lamp slots runs along the actual floor of
	# the sector. Long sectors cap the number of marks at 12.
	var slots := clampi(roundi(sector.size.x / 20.0), 2, 12)
	var cell := sector.size.x / slots
	var width := minf(cell * 0.46, 6.0)
	for i in range(slots):
		var start := sector.position.x + cell * (i + 0.5) - width * 0.5
		canvas.draw_rect(Rect2(start, y - 1.0, width, 1.0), Color(color, color.a * 0.85))


static func _draw_lens(canvas: CanvasItem, sector: Rect2, tint: Color) -> void:
	if _emitter_texture == null:
		return
	var center := lens_position(sector)
	var half_width := minf(sector.size.x * 0.25, 5.0)
	canvas.draw_rect(Rect2(center.x - half_width, center.y - 0.6, half_width * 2.0, 0.8), tint)
