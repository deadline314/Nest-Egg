class_name ShieldSurface
extends GuardPresenter
## Telescoping forearm plate and cues for the live guard angle.

const RADIUS := 28.0
const RAISE_TIME := 0.08
const LOWER_TIME := 0.12
const BREAK_TIME := 0.22
const IMPACT_TIME := 0.16
const SEGMENTS := 12
const ARC_MIN := 0.0
const ARC_MAX := 360.0
const CASE := Color("21242a")
const STEEL := Color("59616c")
const EDGE := Color("9c896c")
const LAMP := Color("ebbc70")
const HOT_EDGE := Color("be624c")
const CUSHION := Color("936547")
const SIGNAL := Color("91d3df")
const BREAK_POINTS: Array[int] = [3, 6, 9]
const AIM_LIMITS: Array[int] = [0, SEGMENTS]
const PART_REACTION := &"reaction_chip"
const PART_EXTENSION := &"extension_plate"
const PART_CUSHION := &"cushion_pad"
const PART_HEAT_SINK := &"heat_sink"
const PART_LIGHT_FRAME := &"light_frame"
const PART_DEFLECT := &"deflect_coat"

# The negative x margins are the tongues hidden by the neighbouring parts.
const CUFF := Rect2(-8.2, -2.4, 10.0, 4.8)
const CARRIAGE := Rect2(-1.7, -1.4, 7.2, 2.8)
const ROOT := Rect2(-11.0, -2.4, 25.0, 4.8)
const SLIDER := Rect2(-4.0, -1.75, 18.0, 3.5)
const NOSE := Rect2(-3.2, -1.45, 13.0, 2.9)

var _active := false
var _broken := false
var _arc_degrees := -1.0
var _rim := PackedVector2Array()
var _impact_left := 0.0

# All guards share the same immutable textures. Resolve once at level setup
# so the first press never starts an import or opens the resource on disk.
static var _cuff: Texture2D
static var _carriage: Texture2D
static var _root: Texture2D
static var _slider: Texture2D
static var _nose: Texture2D
static var _loaded := false


func _init() -> void:
	if _loaded:
		return
	_loaded = true
	_cuff = _load_part("res://art/equipment/forearm_deflector/cuff.png")
	_carriage = _load_part("res://art/equipment/forearm_deflector/carriage.png")
	_root = _load_part("res://art/equipment/forearm_deflector/root.png")
	_slider = _load_part("res://art/equipment/forearm_deflector/slider.png")
	_nose = _load_part("res://art/equipment/forearm_deflector/nose.png")


static func _load_part(path: String) -> Texture2D:
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
	if texture == null:
		push_warning("[ShieldSurface] Missing deflector artwork: %s" % path)
	return texture


func update(delta: float, active: bool, broken: bool, aim: Vector2, arc_degrees: float) -> void:
	if aim.is_finite() and aim.length_squared() > 0.0001 and (active or (extension <= 0.0 and break_left <= 0.0)):
		direction = aim.normalized()
	if broken and not _broken and _active:
		break_left = BREAK_TIME
	break_left = maxf(0.0, break_left - maxf(0.0, delta))
	_impact_left = maxf(0.0, _impact_left - maxf(0.0, delta))
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


func notify_impact(incoming: Vector2, at := Vector2.INF) -> void:
	super.notify_impact(incoming, at)
	_impact_left = IMPACT_TIME


## Full guard uses the existing directional defence. These distances describe
## the two nested slides and can be read by the pose checks without drawing.
func slide_offsets() -> Vector2:
	var extended := parts.has(PART_EXTENSION)
	var slider_travel := 14.0 if extended else 7.5
	var nose_travel := 10.0 if extended and parts.has(PART_DEFLECT) else 0.0
	return Vector2(slider_travel * smoothstep(0.26, 0.88, extension),
			nose_travel * smoothstep(0.58, 1.0, extension))


func _forearm_angle(forearm: Vector2) -> float:
	return forearm.angle() if forearm.is_finite() and forearm.length_squared() > 0.01 else direction.angle()


func _plate_transform(wrist: Vector2, forearm: Vector2, facing: int, motion_scale: float) -> Transform2D:
	var fold := smoothstep(0.0, 0.68, extension)
	var thickness := 0.82 if parts.has(PART_LIGHT_FRAME) else 1.0
	var side := -1.0 if facing < 0 else 1.0
	var pitch := clampf(atan2(direction.y, absf(direction.x)), -1.2, 1.2)
	var kick := _impact_left / IMPACT_TIME * motion_scale * (0.07 if parts.has(PART_CUSHION) else 0.13)
	var release := break_left / BREAK_TIME * motion_scale * 0.28
	var open_angle := -PI * 0.5 + side * (0.24 + pitch * 0.68 - kick + release)
	var angle := lerp_angle(_forearm_angle(forearm) + PI, open_angle, fold)
	return Transform2D(angle, Vector2(lerpf(0.66, 1.0, fold), side * thickness), 0.0, wrist)


func position_on_surface(at: Vector2, wrist: Vector2, forearm: Vector2, facing: int, motion_scale: float) -> Vector2:
	if not at.is_finite() or not wrist.is_finite():
		return at
	if extension <= 0.0:
		return wrist
	var stages := slide_offsets()
	var tip := stages.x + (3.8 + stages.y + NOSE.end.x if stages.y > 0.0 else SLIDER.end.x)
	var pose := _plate_transform(wrist, forearm, facing, motion_scale)
	# Leave a margin to account for the transparent chamfers at both ends.
	var x := clampf((pose.affine_inverse() * at).x, ROOT.position.x + 1.0, tip - 1.0)
	return pose * Vector2(x, 0.0)


## The axle follows the actual wrist while the plate pivots across the shot.
## Each moving rail shares the same local x axis and overlaps its socket.
func paint_emitter(canvas: CanvasItem, wrist: Vector2, _center: Vector2, guard_ratio: float,
		forearm := Vector2.RIGHT, facing := 1, motion_scale := 1.0) -> Vector2:
	if extension <= 0.0 or not wrist.is_finite():
		return wrist
	var fold := smoothstep(0.0, 0.68, extension)
	var stages := slide_offsets()
	var alloy := parts.has(PART_DEFLECT)
	var cushioned := parts.has(PART_CUSHION)
	var side := -1.0 if facing < 0 else 1.0
	var strike := _impact_left / IMPACT_TIME
	var tint := Color(0.83, 0.97, 1.0) if alloy else Color.WHITE
	canvas.draw_set_transform(wrist, _forearm_angle(forearm), Vector2(1.0, side))
	_paint_piece(canvas, _cuff, CUFF)
	if cushioned:
		var compression := 1.0 - strike * motion_scale * 0.65
		canvas.draw_rect(Rect2(-6.8, -2.35, 2.0 * compression, 0.9), CUSHION)
	canvas.draw_set_transform_matrix(_plate_transform(wrist, forearm, facing, motion_scale))
	if stages.y > 0.0:
		var nose_x := stages.x + stages.y + 3.8
		_paint_piece(canvas, _nose, Rect2(NOSE.position + Vector2(nose_x, 0), NOSE.size), tint)
	_paint_piece(canvas, _slider, Rect2(SLIDER.position + Vector2(stages.x, 0), SLIDER.size), tint)
	_paint_piece(canvas, _root, ROOT, tint)
	if parts.has(PART_HEAT_SINK):
		# The vents lift in sequence as the slide locks.
		for fin in 3:
			var x := 4.6 + fin * 2.0
			var lift := smoothstep(0.36 + fin * 0.11, 0.68 + fin * 0.11, extension)
			canvas.draw_line(Vector2(x, 1.35), Vector2(x - lift * motion_scale, 2.1 + lift * 0.9), EDGE, 0.62)
	if alloy:
		var charge := maxf(0.36, strike * Settings.flash_scale())
		var rail_tip := stages.x + (stages.y + 11.0 if stages.y > 0.0 else 10.0)
		var groove := Color(SIGNAL, charge * fold)
		canvas.draw_line(Vector2(4.5, -0.2), Vector2(maxf(4.5, rail_tip), -0.2), groove, 0.68)
		if stages.y > 0.0:
			canvas.draw_line(Vector2(rail_tip - 3.0, -0.74), Vector2(rail_tip, -0.74), groove, 0.67)
	_paint_piece(canvas, _carriage, CARRIAGE)
	var led := LAMP if guard_ratio > 0.33 else HOT_EDGE
	canvas.draw_rect(Rect2(1.3, 0.5, 1.2, 0.62), Color(led, 0.9 * fold))
	canvas.draw_set_transform(Vector2.ZERO)
	return wrist


func _paint_piece(canvas: CanvasItem, texture: Texture2D, rect: Rect2, tint := Color.WHITE) -> void:
	if texture != null:
		canvas.draw_texture_rect(texture, rect, false, tint)
	else:
		canvas.draw_rect(rect, CASE)
		canvas.draw_rect(rect.grow(-0.38), STEEL * tint)


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
			var scan := (1.0 - window_left) * motion_scale
			var marker := _rim[SEGMENTS >> 1] * (0.86 + 0.11 * scan)
			canvas.draw_line(marker - Vector2(0, 1.6), marker + Vector2(0, 1.6), Color(SIGNAL, tick_alpha * flash_scale), 0.9)
	canvas.draw_set_transform(Vector2.ZERO)
	if parry_flash > 0.0 or block_flash > 0.0:
		var perfect := parry_flash > 0.0
		var t := minf(parry_flash / 0.25 if perfect else block_flash / 0.1, 1.0)
		var point := impact_position if impact_position.is_finite() else center + impact_direction * RADIUS
		var side := impact_direction.orthogonal()
		var color := Color(LightKit.glow(LAMP if perfect else EDGE, 1.0 + 0.5 * flash_scale), t)
		canvas.draw_line(point - side * 2.0, point + side * 2.0, color, 1.0)
		if perfect:
			canvas.draw_line(point, point + impact_direction * 4.0, color, 0.9)
		if parts.has(PART_DEFLECT):
			var sweep := 1.0 - t
			var back := point + impact_direction * (1.0 + 5.0 * sweep * motion_scale)
			var pulse := Color(LightKit.glow(SIGNAL, 1.0 + 0.3 * flash_scale), t * flash_scale)
			canvas.draw_line(back, back + impact_direction * 4.5 + side * 2.0, pulse, 0.72)
			canvas.draw_line(back, back + impact_direction * 4.5 - side * 2.0, pulse, 0.72)
