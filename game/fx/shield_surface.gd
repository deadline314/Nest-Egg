class_name ShieldSurface
extends RefCounted
## Directional field presentation. Gameplay owns the angle, timing and damage.
## Geometry is rebuilt only when the block angle changes; no particles or nodes.

const RADIUS := 28.0
const RAISE_TIME := 0.08
const LOWER_TIME := 0.12
const BREAK_TIME := 0.22
const SEGMENTS := 12
const INK := Color(0.035, 0.075, 0.105, 0.95)
const ARC_MIN := 0.0
const ARC_MAX := 360.0

var extension := 0.0
var break_left := 0.0
var direction := Vector2.RIGHT
var impact_direction := Vector2.RIGHT
var _active := false
var _broken := false
var _arc_degrees := -1.0
var _rim := PackedVector2Array()
var _film := PackedVector2Array()


func update(delta: float, active: bool, broken: bool, aim: Vector2, arc_degrees: float) -> void:
	if aim.is_finite() and aim.length_squared() > 0.0001 and (active or (extension <= 0.0 and break_left <= 0.0)):
		direction = aim.normalized()
	if broken and not _broken and _active:
		break_left = BREAK_TIME
	break_left = maxf(0.0, break_left - maxf(0.0, delta))
	extension = move_toward(extension, 1.0 if active else 0.0, maxf(0.0, delta) / (RAISE_TIME if active else LOWER_TIME))
	_active = active
	_broken = broken
	var bounded := clampf(arc_degrees, ARC_MIN, ARC_MAX) if is_finite(arc_degrees) else 120.0
	if not is_equal_approx(_arc_degrees, bounded):
		_arc_degrees = bounded
		_build_geometry()


func _build_geometry() -> void:
	_rim.resize(SEGMENTS + 1)
	_film.resize((SEGMENTS + 1) * 2)
	var half_arc := deg_to_rad(_arc_degrees * 0.5)
	for i in SEGMENTS + 1:
		var unit := Vector2.RIGHT.rotated(lerpf(-half_arc, half_arc, float(i) / SEGMENTS))
		_rim[i] = unit * RADIUS
		_film[i] = unit * RADIUS
		_film[(SEGMENTS + 1) * 2 - 1 - i] = unit * (RADIUS - 5.0)


## Contact feedback shares the shield's body-centred geometry, without changing
## collision range. Incoming is the source direction used by the gameplay guard.
static func contact(center: Vector2, incoming: Vector2, aim: Vector2) -> Vector2:
	var along := incoming.normalized() if incoming.is_finite() and incoming.length_squared() > 0.0001 else aim.normalized()
	if not along.is_finite() or along.length_squared() <= 0.0001:
		along = Vector2.RIGHT
	return center + along * RADIUS


func notify_impact(incoming: Vector2) -> void:
	impact_direction = incoming.normalized() if incoming.is_finite() and incoming.length_squared() > 0.0001 else direction


func paint(canvas: CanvasItem, center: Vector2, guard_ratio: float, parry_window: bool,
		window_left: float, block_flash: float, parry_flash: float, flash_scale: float, motion_scale: float) -> void:
	if _rim.is_empty() or (extension <= 0.0 and break_left <= 0.0 and parry_flash <= 0.0):
		return
	var remaining := clampf(guard_ratio, 0.0, 1.0)
	var strength := clampf(flash_scale, 0.0, 1.0)
	var motion := clampf(motion_scale, 0.0, 1.0)
	var alpha := maxf(extension, minf(parry_flash / 0.25, 1.0))
	var recoil := minf(block_flash / 0.1, 1.0) * 1.5 * motion
	var expansion := lerpf(0.88, 1.0, extension) - recoil / RADIUS
	canvas.draw_set_transform(center, direction.angle(), Vector2.ONE * expansion)
	var tint := Palette.CYAN.lerp(Palette.DANGER, 1.0 - remaining)
	# Narrow transparent film keeps both character and incoming threats visible.
	if break_left <= 0.0:
		if _arc_degrees > 0.01 and _arc_degrees < 359.99:
			canvas.draw_colored_polygon(_film, Color(tint, 0.1 * alpha))
		canvas.draw_polyline(_rim, Color(INK, alpha), 3.4, false)
		var powered := maxi(1, ceili(remaining * SEGMENTS))
		for i in SEGMENTS:
			var lit := i < powered
			var edge := LightKit.glow(tint, 1.2 + 0.25 * strength) if lit else tint.darkened(0.55)
			canvas.draw_line(_rim[i], _rim[i + 1], Color(edge, alpha * (1.0 if lit else 0.45)), 1.4 if lit else 0.8)
		# Both end caps survive low effects and colour blindness.
		for side in 2:
			var index := side * SEGMENTS
			var cap := _rim[index]
			canvas.draw_line(cap * 0.86, cap, Color(Palette.WHITE, alpha * 0.85), 1.5)
		if parry_window:
			var timer_radius := 1.0 + (1.0 + 4.0 * clampf(window_left, 0.0, 1.0) * motion) / RADIUS
			canvas.draw_set_transform(center, direction.angle(), Vector2.ONE * timer_radius)
			canvas.draw_polyline(_rim, Color(Palette.WHITE, alpha * 0.75), 1.0, false)
	else:
		var t := break_left / BREAK_TIME
		# Three small forward fragments; never a full-screen flash or back bubble.
		for i in range(0, SEGMENTS, 4):
			var offset := _rim[i + 2].normalized() * (1.0 - t) * 7.0 * motion
			canvas.draw_line(_rim[i] + offset, _rim[i + 3] + offset, Color(Palette.DANGER, t), 1.3)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if parry_flash > 0.0 or block_flash > 0.0:
		var perfect := parry_flash > 0.0
		var t := minf(parry_flash / 0.25 if perfect else block_flash / 0.1, 1.0)
		var at := center + impact_direction * RADIUS
		var perpendicular := impact_direction.orthogonal()
		var half_size := 3.0 if perfect else 1.7
		canvas.draw_line(at - perpendicular * half_size, at + perpendicular * half_size,
			Color(LightKit.glow(Palette.WHITE, 1.6), t * lerpf(0.65, 1.0, strength)), 1.5)
