extends GuardPresenter
## The reinforced forearm takes the hit. Its emitters vent a brief deflecting pulse on contact.

const RAISE_TIME := 0.11
const LOWER_TIME := 0.14
const BREAK_TIME := 0.23
const SIGNAL := Color("9cdae1")
const AMBER := Color("e4ac73")
const CASING := Color("334651")
const CERAMIC := Color("afbec2")
const RECESS := Color("202c36")
const PART_REACTION := &"reaction_chip"
const PART_RANGE := &"extension_plate"
const PART_DAMPER := &"cushion_pad"
const PART_VENT := &"heat_sink"
const PART_FRAME := &"light_frame"
const PART_REFLECT := &"deflect_coat"

var arc_degrees := 120.0
var _active := false
var _broken := false
var _shell := PackedVector2Array()
var _shell_size := Vector2.ZERO


func update(delta: float, active: bool, broken: bool, aim: Vector2, coverage: float) -> void:
	arc_degrees = clampf(coverage, 0.0, 360.0) if is_finite(coverage) else 120.0
	if aim.is_finite() and aim.length_squared() > 0.0001:
		direction = aim.normalized()
	if broken and not _broken and _active:
		break_left = BREAK_TIME
	extension = move_toward(extension, 1.0 if active else 0.0,
			maxf(0.0, delta) / (RAISE_TIME if active else LOWER_TIME))
	break_left = maxf(0.0, break_left - maxf(0.0, delta))
	_active = active
	_broken = broken


func emitter_span() -> float:
	return 7.0 if parts.has(PART_RANGE) else 5.6


## The contact follows the exposed length of the supporting forearm.
func position_on_surface(at: Vector2, wrist: Vector2, forearm: Vector2, _facing: int, _motion_scale: float) -> Vector2:
	if not wrist.is_finite() or not at.is_finite():
		return at
	var along := forearm.normalized() if forearm.is_finite() and forearm.length_squared() > 0.0001 else direction
	var offset := clampf((at - wrist).dot(along), -5.0, 0.5)
	var outward := along.orthogonal()
	if outward.dot(at - wrist) < 0.0:
		outward = -outward
	return wrist + along * offset + outward * 2.5


func paint_emitter(canvas: CanvasItem, wrist: Vector2, _center: Vector2, guard_ratio: float,
		forearm := Vector2.RIGHT, facing := 1, _motion_scale := 1.0) -> Vector2:
	if extension <= 0.0 or not wrist.is_finite():
		return wrist
	var angle := forearm.angle() if forearm.is_finite() and forearm.length_squared() > 0.0001 else direction.angle()
	var side := -1.0 if facing < 0 else 1.0
	var frame_height := 1.65 if parts.has(PART_FRAME) else 2.15
	var color := SIGNAL if guard_ratio > 0.3 else AMBER
	var length := emitter_span()
	var dimensions := Vector2(length, frame_height)
	if _shell_size != dimensions:
		_shell_size = dimensions
		_shell = PackedVector2Array([
			Vector2(-length, -1.0), Vector2(-length + 0.85, -frame_height),
			Vector2(-0.7, -frame_height), Vector2(0.75, -0.95),
			Vector2(0.75, 0.95), Vector2(-0.7, frame_height),
			Vector2(-length + 0.85, frame_height), Vector2(-length, 1.0)])
	canvas.draw_set_transform(wrist, angle, Vector2(1.0, side))
	canvas.draw_colored_polygon(_shell, Color(CASING, extension))
	canvas.draw_line(Vector2(-length + 0.8, frame_height - 0.35), Vector2(-0.7, frame_height - 0.35), Color(RECESS, extension), 0.65)
	canvas.draw_line(Vector2(-length + 1.0, -frame_height + 0.25), Vector2(-0.75, -frame_height + 0.25), Color(CERAMIC, 0.85 * extension), 0.55)
	canvas.draw_line(Vector2(-length + 1.1, -0.35), Vector2(-0.85, -0.35),
			Color(color, extension * (0.92 if parts.has(PART_REFLECT) else 0.58)), 0.65)
	if parts.has(PART_VENT):
		for i in 3:
			var vent := -4.7 + float(i) * 1.22
			canvas.draw_line(Vector2(vent, 1.35), Vector2(vent + 0.43, 0.45), Color(CERAMIC, 0.75 * extension), 0.5)
	if parts.has(PART_DAMPER):
		canvas.draw_line(Vector2(-length, frame_height + 0.2), Vector2(-0.9, frame_height + 0.2), Color(AMBER, 0.70 * extension), 0.8)
	canvas.draw_set_transform(Vector2.ZERO)
	return wrist


func paint(canvas: CanvasItem, center: Vector2, _guard_ratio: float, parry_window: bool,
		window_left: float, block_flash: float, parry_flash: float, flash_scale: float, motion_scale: float) -> void:
	if parry_window and extension > 0.0:
		var angle := deg_to_rad(arc_degrees * 0.5)
		var guide := Color(SIGNAL, lerpf(0.22, 0.46, window_left) * extension * flash_scale)
		var low := direction.rotated(-angle)
		var high := direction.rotated(angle)
		canvas.draw_line(center + low * 25.0, center + low * 27.5, guide, 0.75)
		canvas.draw_line(center + high * 25.0, center + high * 27.5, guide, 0.75)
	var strength := maxf(block_flash / 0.10, parry_flash / 0.25)
	if strength <= 0.0 or not impact_position.is_finite():
		return
	var color := SIGNAL if parry_flash > 0.0 or parts.has(PART_REFLECT) else CERAMIC
	if break_left > 0.0:
		color = AMBER
	var tangent := impact_direction.orthogonal()
	var reach := 8.0 if parts.has(PART_RANGE) else 5.0
	var p := impact_position + impact_direction * (1.0 - strength) * 4.0 * motion_scale
	canvas.draw_line(p - tangent * reach, p + tangent * reach, Color(color, strength * flash_scale), 1.15)
	if parry_flash > 0.0 and parts.has(PART_REACTION):
		var outer := p + impact_direction * 2.5
		canvas.draw_line(outer - tangent * reach * 0.6, outer + tangent * reach * 0.6, Color(SIGNAL, strength * flash_scale), 0.75)
