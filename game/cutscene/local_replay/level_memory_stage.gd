extends Node2D
## Draws the authored part of a chapter map in a private World2D. Only scenery
## is installed: the live Level, encounter, NPC and snapshot paths stay absent.

const ACTOR_HALF_WIDTH := 9.0
const CAMERA_ZOOM := 1.7
const MAX_STAGE_LIGHTS := 5
const MAP_BUILD_SLICE_USEC := 4000

var _camera: Camera2D
var _actor: CutsceneActor
var _route := Vector2.ZERO
var _surface := 0.0
var _scenery_rects: Dictionary[StringName, Rect2] = {}
var _marker: Polygon2D
var _slice_started := 0


## The two beats must lie on the same authored platform or floor span.
func build(data: LevelData, from_id: StringName, to_id: StringName, start_before := 0.0) -> Dictionary:
	_slice_started = Time.get_ticks_usec()
	var layout := LevelBuilder.parse(data)
	if not layout.is_valid():
		return {}
	var from := Vector2.INF
	var to := Vector2.INF
	for spawn: Dictionary in layout.spawns:
		var resource: Resource = spawn["resource"]
		if resource is PortalData or resource is NpcData:
			if resource.id == from_id:
				from = spawn["position"]
			if resource.id == to_id:
				to = spawn["position"]
	var start := layout.player_start if start_before <= 0.0 else from - Vector2(start_before, 0)
	if not _configure_route(layout, start, from, to):
		return {}
	var ambient := CanvasModulate.new()
	ambient.color = Color("b3b9c6")
	add_child(ambient)
	var wall := BackWall.new()
	add_child(wall)
	wall.setup(layout, hash(data.id), data.environment)
	await _checkpoint()
	await _spawn_scenery(data, layout, wall.geometry)
	await _checkpoint()
	var terrain := Terrain.new()
	terrain.z_index = WorldLayers.TERRAIN
	terrain.wall_geometry = wall.geometry
	add_child(terrain)
	terrain.build(layout, data.environment, data.load_regions())
	terrain.remove_from_group(&"terrain")
	await _checkpoint()
	for index in mini(layout.lamps.size(), MAX_STAGE_LIGHTS):
		var fixture := LightKit.create_point_light(Color("ddd3b5"), 136.0, 1.05, false)
		fixture.position = layout.lamps[index] + Vector2(0, 83)
		add_child(fixture)
	var held := await RigLibrary.prepare_skin_textures("egret", _checkpoint)
	var actor_ready := _create_actor(start)
	held.clear()
	if not actor_ready:
		return {}
	_camera = Camera2D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.zoom = Vector2.ONE * CAMERA_ZOOM
	_camera.limit_left = 0
	_camera.limit_right = int(layout.pixel_size().x)
	_camera.position_smoothing_enabled = not Settings.get_reduce_ui_motion()
	_camera.position_smoothing_speed = 8.0
	_camera.position = start - Vector2(0, 49)
	add_child(_camera)
	_camera.make_current()
	_camera.reset_smoothing()
	return {"from": from, "to": to}


func advance_movement(axis: float, delta: float) -> void:
	var old_x := _actor.position.x
	_actor.position.x = clampf(old_x + axis * 114.0 * delta, _route.x, _route.y)
	var moving := not is_equal_approx(old_x, _actor.position.x)
	var pose := &"walk" if moving else &"idle"
	if _actor.pose != pose:
		_actor.set_pose(pose)
	if moving:
		_actor.face(1 if axis > 0 else -1)
	_camera.position.x = _actor.position.x


func is_near(point: Vector2) -> bool:
	return absf(point.x - _actor.position.x) <= 25.0


func gesture(name: StringName, target: Vector2) -> void:
	_actor.face(1 if target.x >= _actor.position.x else -1)
	_actor.play_gesture(name)


func set_speaking(active: bool) -> void:
	_actor.set_talking(active)


func place_fixture(id: StringName, point: Vector2, dimensions: Vector2) -> Sprite2D:
	var mount := Node2D.new()
	mount.position = point
	mount.z_index = WorldLayers.PROPS
	add_child(mount)
	return FixtureArt.attach(mount, id, Vector2(-dimensions.x * 0.5, -dimensions.y), dimensions)


func scenery_rect(id: StringName) -> Rect2:
	return _scenery_rects.get(id, Rect2())


func mark(point: Vector2) -> void:
	if not is_instance_valid(_marker):
		_marker = Polygon2D.new()
		_marker.name = "MemoryWaypoint"
		_marker.polygon = PackedVector2Array([Vector2(-4, -2), Vector2(0, 3), Vector2(4, -2)])
		_marker.color = Color("ffe0a6")
		_marker.z_index = WorldLayers.PROPS + 1
		add_child(_marker)
	_marker.visible = point.is_finite()
	if _marker.visible:
		_marker.position = point - Vector2(0, 68)


func _create_actor(start: Vector2) -> bool:
	_actor = CutsceneActor.new()
	_actor.name = "Egret"
	_actor.position = start
	_actor.ground_y = _surface
	add_child(_actor)
	return _actor.setup(&"egret", "egret", "res://art/portraits/egret.png", 1.0, "")


func _configure_route(layout: LevelLayout, start: Vector2, from: Vector2, to: Vector2) -> bool:
	if not start.is_finite() or not from.is_finite() or not to.is_finite() or not is_equal_approx(start.y, from.y) or not is_equal_approx(from.y, to.y):
		return false
	var left := minf(start.x, minf(from.x, to.x)) - ACTOR_HALF_WIDTH
	var right := maxf(start.x, maxf(from.x, to.x)) + ACTOR_HALF_WIDTH
	var surfaces := layout.solid_rects + layout.platform_rects
	for cells: Rect2i in surfaces:
		var rect := layout.cells_to_pixels(cells)
		if not is_equal_approx(rect.position.y, start.y) or rect.position.x > left or rect.end.x < right:
			continue
		_surface = rect.position.y
		_route = Vector2(maxf(rect.position.x + ACTOR_HALF_WIDTH, left - 16), minf(rect.end.x - ACTOR_HALF_WIDTH, right + 16))
		return true
	return false


func _spawn_scenery(data: LevelData, layout: LevelLayout, walls: BackWallGeometry) -> void:
	var dirs := data.environment.prop_dirs() if data.environment != null else PackedStringArray([PropLibrary.DEFAULT_DIR])
	var entries := data.load_props()
	for entry: Dictionary in entries:
		await _checkpoint()
		var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
		if prop == null:
			continue
		var placement := PropPlacement.resolve(entry, prop, layout)
		if placement.is_empty():
			continue
		var rect: Rect2 = placement["rect"]
		if not ScenerySupport.check_prop(entry, prop, rect, layout, walls, entries, dirs).is_empty():
			continue
		_scenery_rects[prop.id] = rect
		place_scenery(prop, rect, bool(placement["flip"]))


func place_scenery(prop: PropData, rect: Rect2, flip := false) -> void:
	var texture := LitTextures.load_texture(prop.texture, Vector2i(rect.size) * PropData.TEXTURE_SCALE)
	var sprite := Sprite2D.new()
	sprite.name = String(prop.id)
	sprite.texture = texture
	sprite.centered = false
	sprite.flip_h = flip
	sprite.scale = rect.size / Vector2(texture.get_size())
	sprite.position = rect.position
	sprite.z_index = WorldLayers.PROPS
	if prop.layer == PropData.Layer.FRONT:
		sprite.z_index = WorldLayers.STAGE_FRONT
		sprite.modulate.a = prop.front_alpha
	add_child(sprite)


func _checkpoint() -> void:
	if Time.get_ticks_usec() - _slice_started >= MAP_BUILD_SLICE_USEC:
		await get_tree().process_frame
		_slice_started = Time.get_ticks_usec()
