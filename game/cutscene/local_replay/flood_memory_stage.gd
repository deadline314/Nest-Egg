extends Node2D
## Flood recollection set inside the replay-only World2D.

const Run = preload("res://game/cutscene/local_replay/flood_memory_run.gd")
const STREET := "res://art/environment/scenes/flood_street.webp"
const SHOP := "res://art/environment/stages/old_k_shop.webp"
const PASSENGER := "res://art/environment/stages/flood_memory_child.png"
const CHAIR := "res://data/environment/scene_props/basement/basement__anchor_chair.tres"
const DESK := "res://data/environment/scene_props/basement/basement__notebook_desk.tres"
const READER := "res://data/environment/scene_props/basement/basement__chip_reader.tres"
const CAMERA_LIMIT := 1120
const PASSENGER_MATTE := preload("res://game/cutscene/local_replay/flood_memory_matte.gdshader")
const RAIN := preload("res://game/cutscene/local_replay/flood_memory_rain.gdshader")
const RAIL_HEIGHT := 43.0

var _camera: Camera2D
var _actor: CutsceneActor
var _passenger: Sprite2D
var _water: Polygon2D
var _flooded := false
var _upper := false
var _started_loading_us := 0


func build(point: Vector2) -> bool:
	_started_loading_us = Time.get_ticks_usec()
	var street := _texture(STREET)
	var shop := _texture(SHOP)
	var passenger := _texture(PASSENGER)
	if street == null or shop == null or passenger == null:
		return false
	_mount(street, Vector2(0, -48), 1120.0, -6)
	_mount(shop, Vector2(865, 106), 460.0, -5)
	_steel_line(PackedVector2Array([Vector2(865, 106), Vector2(865, 302)]), 8.0, Color("322921"), -4)
	for path: int in Run.PATHS:
		if path == Run.Segment.PAWNSHOP:
			_platform([Vector2(724, 302), Vector2(865, 302)], false)
		else:
			_platform(Run.PATHS[path], path == Run.Segment.DRY_STAIRS)
	_platform([Vector2(0, 302), Run.PATHS[Run.Segment.ARRIVAL][0]], false)
	_platform([Vector2(674, 302), Vector2(724, 302)], false)

	_water = Polygon2D.new()
	_water.polygon = PackedVector2Array([
		Vector2(349, 307), Vector2(656, 307), Vector2(624, 335), Vector2(357, 335),
	])
	_water.color = Color(0.14, 0.27, 0.34, 0.65)
	_water.z_index = 2
	_water.visible = false
	add_child(_water)

	for x: float in [249.0, 722.0, 893.0]:
		var lamp := LightKit.create_point_light(Color("e5bc89"), 126.0, 0.8, false)
		lamp.position = Vector2(x, 228.0)
		add_child(lamp)
	if not Settings.get_reduce_ui_motion():
		var rain := ColorRect.new()
		rain.position = Vector2(0, -48)
		rain.size = Vector2(865, 386)
		rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rain.z_index = 1
		var rain_material := ShaderMaterial.new()
		rain_material.shader = RAIN
		rain.material = rain_material
		add_child(rain)
	_mount_prop(CHAIR, Vector2(994, 302), 51.0)
	_mount_prop(DESK, Vector2(1047, 302), 42.0)
	_mount_prop(READER, Vector2(1039, 273), 15.5)

	var held := await RigLibrary.prepare_skin_textures("old_k", _checkpoint)
	if not is_inside_tree() or is_queued_for_deletion():
		held.clear()
		return false
	_actor = CutsceneActor.new()
	_actor.position = point
	_actor.ground_y = point.y
	add_child(_actor)
	var ready := _actor.setup(&"old_k", "old_k", "", 1.0, "")
	held.clear()
	if not ready:
		return false
	var crop := AtlasTexture.new()
	crop.atlas = passenger
	var source := passenger.get_size()
	crop.region = Rect2(source * Vector2(0.132, 0.050), source * Vector2(0.706, 0.865))
	_passenger = _mount(crop, Vector2(-23.0, -59.0), 25.0, -1, _actor)
	_passenger.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var matte := ShaderMaterial.new()
	matte.shader = PASSENGER_MATTE
	_passenger.material = matte
	_set_grip(1, false)

	_camera = Camera2D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.zoom = Vector2.ONE * 1.4
	_camera.limit_left = 0
	_camera.limit_right = CAMERA_LIMIT
	_camera.position = point - Vector2(0.0, 34.0)
	_camera.position_smoothing_enabled = not Settings.get_reduce_ui_motion()
	_camera.position_smoothing_speed = 7.5
	add_child(_camera)
	_camera.make_current()
	_camera.reset_smoothing()
	return true


func present(position: Vector2, direction: int, upper: bool, moving: bool, flooded: bool) -> void:
	if not is_instance_valid(_actor):
		return
	if direction != _actor.facing or upper != _upper:
		_upper = upper
		_actor.face(direction)
		_passenger.flip_h = direction < 0
		_passenger.position.x = -23.0 if direction > 0 else -2.0
		_set_grip(direction, upper)
	if _flooded != flooded:
		_flooded = flooded
		_water.visible = flooded
	_actor.position = position
	_actor.ground_y = position.y
	var pose := &"walk" if moving else &"idle"
	if _actor.pose != pose:
		_actor.set_pose(pose)
	_camera.position = position - Vector2(0.0, 23.0 if upper else 34.0)


func read_terminal() -> void:
	_passenger.reparent(self)
	_passenger.z_index = 0
	_actor.set_hand_target({"hand": "front", "release": true})
	_actor.set_hand_target({"hand": "back", "release": true})
	_actor.face(1)
	var seat := Vector2(986, 247)
	var reading_point := Vector2(1027, 302)
	if Settings.get_reduce_ui_motion():
		_passenger.position = seat
		_actor.position = reading_point
	else:
		var seat_motion := create_tween()
		seat_motion.tween_property(_passenger, "position", seat, 0.53).set_trans(Tween.TRANS_SINE)
		await seat_motion.finished
		_actor.set_pose(&"walk")
		var step := create_tween()
		step.tween_property(_actor, "position", reading_point, 0.2)
		await step.finished
		_actor.set_pose(&"idle")
	_actor.set_hand_target({"hand": "back", "to": [1034.2, 270.8], "time": 0.3})
	Sfx.play(&"switch", -23.0)


func _set_grip(direction: int, upper: bool) -> void:
	_actor.set_hand_target({"hand": "back", "space": "actor", "to": [-9.0 * direction, -35.0], "time": 0.18})
	var front := [10.0 * direction, -RAIL_HEIGHT] if upper else [-11.0 * direction, -33.0]
	_actor.set_hand_target({"hand": "front", "space": "actor", "to": front, "time": 0.18})


func _platform(points: Array, rail: bool) -> void:
	var surface := PackedVector2Array(points)
	var face := PackedVector2Array(points)
	var seam := PackedVector2Array()
	for point: Vector2 in surface:
		seam.append(point + Vector2(0.0, 10.0))
	_steel_line(surface, 2.4, Color("607887") if rail else Color("394b56"), -2)
	_steel_line(seam, 1.2, Color("17232c"), -2)
	for index in range(points.size() - 1, -1, -1):
		face.append(points[index] + Vector2(0, 14.0))
	var shade := Polygon2D.new()
	shade.polygon = face
	shade.color = Color("272f35")
	shade.z_index = -3
	add_child(shade)
	if not rail:
		return
	var top := PackedVector2Array()
	var brace := PackedVector2Array()
	for point: Vector2 in points:
		top.append(point - Vector2(0.0, RAIL_HEIGHT))
		brace.append(point - Vector2(0.0, 21.0))
	for index in range(1, points.size()):
		var start: Vector2 = points[index - 1]
		var end: Vector2 = points[index]
		var posts := maxi(1, ceili(start.distance_to(end) / 33.0))
		for post in posts:
			var foot := start.lerp(end, float(post) / posts)
			var base := PackedVector2Array([foot + Vector2(-3, 2), foot + Vector2(3, 2)])
			_steel_line(PackedVector2Array([foot, foot - Vector2(0, RAIL_HEIGHT)]), 2.8, Color("465c66"), -2)
			_steel_line(base, 2.0, Color("293a45"), -1)
	_steel_line(brace, 2.2, Color("3c4c57"), -2)
	_steel_line(top, 3.4, Color("45555c"), -1)
	var crown := PackedVector2Array()
	for point: Vector2 in top:
		crown.append(point - Vector2(0.0, 0.95))
	_steel_line(crown, 1.1, Color("8e9285"), -1)
	for beam: Vector2 in [Vector2(546, 240), Vector2(650, 240)]:
		_steel_line(PackedVector2Array([beam, Vector2(beam.x, 318)]), 6.0, Color("364853"), -4)
	_steel_line(PackedVector2Array([Vector2(546, 318), Vector2(650, 248)]), 4.0, Color("33424e"), -4)
	_steel_line(PackedVector2Array([Vector2(546, 248), Vector2(650, 318)]), 4.0, Color("33424e"), -4)


func _steel_line(points: PackedVector2Array, width: float, color: Color, depth: int) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.z_index = depth
	add_child(line)


func _mount_prop(path: String, foot: Vector2, width: float) -> void:
	var data := load(path) as PropData if ResourceLoader.exists(path) else null
	if data == null:
		return
	var image := _texture(data.texture)
	if image == null:
		return
	var height := width * float(image.get_height()) / image.get_width()
	_mount(image, foot - Vector2(width * 0.5, height), width, -1)


func _mount(texture: Texture2D, point: Vector2, width: float, depth: int, parent: Node2D = null) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = point
	sprite.centered = false
	sprite.scale = Vector2.ONE * width / texture.get_width()
	sprite.z_index = depth
	(self if parent == null else parent).add_child(sprite)
	return sprite


func _checkpoint() -> void:
	if is_inside_tree() and Time.get_ticks_usec() - _started_loading_us >= 4000:
		await get_tree().process_frame
		_started_loading_us = Time.get_ticks_usec()


func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
