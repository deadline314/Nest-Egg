class_name ShieldSurface
extends GuardPresenter
## Mechanical forearm plates and directional feedback. Gameplay owns the angle, timing and damage.

const RADIUS := 28.0
const RAISE_TIME := 0.08
const LOWER_TIME := 0.12
const BREAK_TIME := 0.22
const SEGMENTS := 12
const ARC_MIN := 0.0
const ARC_MAX := 360.0
const CASE := Color("21242a")
const STEEL := Color("4c5260")
const INSIDE := Color("343a43")
const EDGE := Color("9c896c")
const LAMP := Color("ebbc70")
const PAINT := Color("a87739")
const LOW_ENERGY := Color("d27156")
const HOT_EDGE := Color("be624c")
const CUSHION := Color("714a3f")
const COATING := Color("a589a9")
const SIDES: Array[float] = [-1.0, 1.0]
const HEAT_FINS: Array[float] = [-2.0, 0.0, 2.0]
const BREAK_POINTS: Array[int] = [3, 6, 9]
const AIM_LIMITS: Array[int] = [0, SEGMENTS]
static var _plate_outline := PackedVector2Array([Vector2(-2, -5), Vector2(3, -6), Vector2(7, -4), Vector2(8, 2), Vector2(5, 5), Vector2(-1, 5)])
static var _plate_skin := PackedVector2Array([Vector2(-0.7, -4), Vector2(3, -4.7), Vector2(6, -3.4), Vector2(6.7, 1.6), Vector2(4.5, 3.8), Vector2(0, 3.8)])
static var _bevel := PackedVector2Array([Vector2(3, -4.7), Vector2(6, -3.4), Vector2(6.7, 1.6), Vector2(4.5, 3.8), Vector2(4.6, -1.5)])

var _active := false
var _broken := false
var _arc_degrees := -1.0
var _rim := PackedVector2Array()
const PART_REACTION := &"reaction_chip"
const PART_EXTENSION := &"extension_plate"
const PART_CUSHION := &"cushion_pad"
const PART_HEAT_SINK := &"heat_sink"
const PART_LIGHT_FRAME := &"light_frame"
const PART_DEFLECT := &"deflect_coat"


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
	var half_arc := deg_to_rad(_arc_degrees * 0.5)
	for i in SEGMENTS + 1:
		var unit := Vector2.RIGHT.rotated(lerpf(-half_arc, half_arc, float(i) / SEGMENTS))
		_rim[i] = unit * RADIUS


## Contact feedback shares the shield's body-centred geometry, without changing
## collision range. Incoming is the source direction used by the gameplay guard.
static func contact(center: Vector2, incoming: Vector2, aim: Vector2) -> Vector2:
	var along := incoming.normalized() if incoming.is_finite() and incoming.length_squared() > 0.0001 else aim.normalized()
	if not along.is_finite() or along.length_squared() <= 0.0001:
		along = Vector2.RIGHT
	return center + along * RADIUS


## The mount stays on the forearm as the leaves fold out around it.
func paint_emitter(canvas: CanvasItem, wrist: Vector2, _center: Vector2, guard_ratio: float) -> Vector2:
	if extension <= 0.0 or break_left > 0.0 or not wrist.is_finite():
		return wrist
	var deployment := smoothstep(0.0, 1.0, extension)
	var side := direction.orthogonal()
	var span := (8.7 if parts.has(PART_EXTENSION) else 6.3) * deployment
	var thickness := 0.71 if parts.has(PART_LIGHT_FRAME) else 0.87
	var base_angle := direction.angle()
	canvas.draw_set_transform(wrist, base_angle, Vector2.ONE)
	canvas.draw_rect(Rect2(-4.5, -2.8, 6.9, 5.6), CASE)
	canvas.draw_rect(Rect2(-3.5, -1.8, 4.0, 3.6), STEEL)
	canvas.draw_line(Vector2(-4.5, 0.8), Vector2(-1.4, 0.8), INSIDE, 1.0)
	for side_sign in SIDES:
		var hinge := wrist + direction * deployment * 2.0 + side * (span * side_sign)
		canvas.draw_set_transform(Vector2.ZERO)
		canvas.draw_line(wrist, hinge + direction * 1.5, CASE, 2.2)
		canvas.draw_line(wrist, hinge + direction * 1.5, EDGE.darkened(0.4), 0.65)
		canvas.draw_set_transform(hinge, base_angle + side_sign * 0.32 * (1.0 - deployment), Vector2(thickness, lerpf(0.34, 0.97, deployment)))
		_paint_plate(canvas, STEEL.darkened(0.10 if side_sign < 0.0 else 0.23))
		canvas.draw_circle(Vector2(0.3, 0.8), 0.65, EDGE.darkened(0.25))
	var plate_scale := lerpf(0.55, 1.0, deployment)
	canvas.draw_set_transform(wrist + direction * (3.0 * deployment), base_angle, Vector2(thickness, 1.0) * plate_scale)
	_paint_plate(canvas, STEEL)
	canvas.draw_line(Vector2(1.6, -2.6), Vector2(3.1, -3.0), PAINT, 1.25)
	canvas.draw_line(Vector2(1.9, -0.6), Vector2(3.4, -1.0), PAINT, 1.25)
	canvas.draw_rect(Rect2(5.1, 0.2, 1.2, 2.7), LAMP if guard_ratio > 0.33 else LOW_ENERGY)
	if parts.has(PART_CUSHION):
		canvas.draw_line(Vector2(-2.7, -3.3), Vector2(-2.7, 4.3), CUSHION, 1.9)
	if parts.has(PART_HEAT_SINK):
		for i in HEAT_FINS:
			canvas.draw_line(Vector2(7, i), Vector2(8.8, i), EDGE, 0.8)
	if parts.has(PART_DEFLECT):
		canvas.draw_line(Vector2(4.0, -3.6), Vector2(6.0, -2.1), COATING, 0.8)
	canvas.draw_set_transform(Vector2.ZERO)
	return wrist


func _paint_plate(canvas: CanvasItem, color: Color) -> void:
	canvas.draw_colored_polygon(_plate_outline, CASE)
	canvas.draw_colored_polygon(_plate_skin, color)
	canvas.draw_colored_polygon(_bevel, INSIDE)
	canvas.draw_line(Vector2(0, -4), Vector2(3, -4.7), EDGE, 0.7)
	canvas.draw_rect(Rect2(0.1, 1.9, 1.1, 1.1), CASE)
	canvas.draw_line(Vector2(4.7, 0.7), Vector2(5.8, 1.0), Color(EDGE, 0.66), 0.55)


func paint(canvas: CanvasItem, center: Vector2, guard_ratio: float, parry_window: bool,
		window_left: float, block_flash: float, parry_flash: float, flash_scale: float, motion_scale: float) -> void:
	if _rim.is_empty() or not has_visible_effects(parry_flash):
		return
	var warm := LAMP.lerp(HOT_EDGE, 1.0 - clampf(guard_ratio, 0.0, 1.0))
	canvas.draw_set_transform(center, direction.angle())
	if break_left > 0.0:
		var t := break_left / BREAK_TIME
		for i in BREAK_POINTS:
			var offset := _rim[i].normalized() * (1.0 - t) * 5.0 * motion_scale
			canvas.draw_line(_rim[i] * 0.77 + offset, _rim[i] * 0.87 + offset, Color(warm, t), 1.0)
	elif extension > 0.0:
		# Two short ticks preserve the existing defence angle without sweeping a bright arc.
		var tick_alpha := 0.54 * extension
		if parry_window:
			tick_alpha = 0.72 + window_left * 0.18 * flash_scale
		for index in AIM_LIMITS:
			var point := _rim[index]
			canvas.draw_line(point * 0.86, point * 0.94, Color(warm, tick_alpha), 0.9)
		if parry_window and parts.has(PART_REACTION):
			canvas.draw_circle(_rim[SEGMENTS >> 1] * 0.9, 1.2, Color(warm, tick_alpha))
	canvas.draw_set_transform(Vector2.ZERO)
	if parry_flash > 0.0 or block_flash > 0.0:
		var perfect := parry_flash > 0.0
		var t := minf(parry_flash / 0.25 if perfect else block_flash / 0.1, 1.0)
		var point := center + impact_direction * RADIUS
		var side := impact_direction.orthogonal()
		var color := Color(LightKit.glow(LAMP if perfect else EDGE, 1.0 + 0.5 * flash_scale), t)
		canvas.draw_line(point - side * 2.0, point + side * 2.0, color, 1.0)
		if perfect:
			canvas.draw_line(point, point + impact_direction * 4.0, color, 0.9)
