extends "res://tools/scenarios/scenario_base.gd"

var _main: Node
var _origin := Vector2(93 * 16, FLOOR_Y)
var checks := 0
var failures := 0
var _marks: Array[Line2D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("REACH_CHECK %s %s" % [value, description])

func _press(gamepad: bool) -> void:
	var event: InputEvent
	if gamepad:
		var button := InputEventJoypadButton.new()
		button.device = 999
		button.button_index = JOY_BUTTON_X
		button.pressed = true
		event = button
	else:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		key.keycode = KEY_E
		key.pressed = true
		event = key
	Input.parse_input_event(event)
	await get_tree().process_frame
	for i in 2: await get_tree().physics_frame
	event = event.duplicate()
	if gamepad: (event as InputEventJoypadButton).pressed = false
	else: (event as InputEventKey).pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
	for i in 2: await get_tree().physics_frame

func _snap(name: String) -> void:
	await settle(3)
	await RenderingServer.frame_post_draw
	capture(name)

class ContactTrace extends Throwable:
	var contact := Vector2.INF
	func _bounce(collision: KinematicCollision2D) -> void:
		if contact == Vector2.INF: contact = collision.get_position()
		super._bounce(collision)
		# Diagnostic capture stops only after the real first collision and response.
		set_physics_process(false)

func _shoot() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	for i in 2: await get_tree().physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _mark(point: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([point + Vector2(-4, -4), point + Vector2(4, 4), point + Vector2(0, 0), point + Vector2(-4, 4), point + Vector2(4, -4)])
	line.default_color = color
	line.width = 1
	line.z_index = 100
	level.add_child(line)
	_marks.append(line)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Story.auto_skip = true
	GameState.story_autosave = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "TRAJECTORY | actual Main / arranged overhead edge\nWhite = forecast, pink = real first contact (diagnostic freeze) | synthetic input"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 12)
	layer.add_child(label)
	await open_arena("", 10.0)
	await clear_enemies()
	for node in get_tree().get_nodes_in_group(Throwable.GROUP): node.queue_free()
	for i in 4: await get_tree().physics_frame
	for direction: float in [1.0, -1.0]:
		place_player(93)
		AimInput.set_virtual_gamepad(player, true)
		Input.action_press(&"aim_right" if direction > 0 else &"aim_left")
		var item := ContactTrace.new()
		item.configure(load("res://data/throwables/pipe.tres"))
		item.position = _origin + Vector2(8, 0)
		level._entities.add_child(item)
		for i in 6: await get_tree().physics_frame
		await _press(false)
		for i in 20: await get_tree().physics_frame
		_check(player.carry.is_holding() and player.carry.held == item, "public pickup completed %s" % direction)
		var obstacle := StaticBody2D.new()
		obstacle.collision_layer = Layers.WORLD
		obstacle.collision_mask = 0
		obstacle.position = player.carry.hold_point() + Vector2(direction * 60, 14)
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(4, 10)
		collision.shape = rectangle
		obstacle.add_child(collision)
		var visual := Polygon2D.new()
		visual.polygon = PackedVector2Array([Vector2(-2,-5), Vector2(2,-5), Vector2(2,5), Vector2(-2,5)])
		visual.color = Color("a0bcc8")
		obstacle.add_child(visual)
		level.add_child(obstacle)
		for i in 4: await get_tree().physics_frame
		for round_index in 3:
			var began := Time.get_ticks_usec()
			for repetition in 50: player.carry._update_preview()
			print("PREVIEW_COST direction=%s round=%d usec_per_update=%.3f" % [direction, round_index, float(Time.get_ticks_usec() - began) / 50])
		var predicted := player.carry._preview_land
		_check(predicted != Vector2.INF, "forecast found terrain %s" % direction)
		if predicted != Vector2.INF: _mark(predicted, Color.WHITE)
		await _snap("forecast-%s" % int(direction))
		await _shoot()
		for i in 150:
			if item.contact != Vector2.INF: break
			await get_tree().physics_frame
		_check(item.contact != Vector2.INF, "actual thrown pipe contacts terrain %s" % direction)
		_check(absf(item.contact.x - obstacle.position.x) <= 3 and absf(item.contact.y - obstacle.position.y) <= 7, "actual first collision is the arranged edge %s" % direction)
		_check(predicted != Vector2.INF and predicted.distance_to(item.contact) <= 2, "forecast matches actual first contact %s predicted=%s actual=%s" % [direction, predicted, item.contact])
		if item.contact != Vector2.INF: _mark(item.contact, Color.MAGENTA)
		await _snap("contact-%s" % int(direction))
		for mark in _marks: mark.queue_free()
		_marks.clear()
		InputBindings.clear_held_inputs()
		item.queue_free()
		obstacle.queue_free()
		for i in 4: await get_tree().physics_frame
	print("PREVIEW_RESULT checks=%d failures=%d" % [checks, failures])
	_main.call("_quit", 1 if failures else 0)


func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await get_tree().process_frame
	return false

func open_arena(_lighting_path: String, _player_tile := 12.0, _base_data: LevelData = null) -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	await _until(func() -> bool: return _main.get("_screen") is MainMenu and not bool(_main.call("_route_pending")))
	await settle(30)
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _until(func() -> bool: return _main.get("_screen") is Level and not bool(_main.call("_route_pending")))
	await settle(30)
	await _skip_active()
	await settle(12)
	_main.call("_on_area_requested", "res://data/levels/ch1_street.tres")
	_check(await _until(func() -> bool: return _main.get("_screen") is Level and (_main.get("_screen") as Level).data.resource_path == "res://data/levels/ch1_street.tres" and not bool(_main.call("_route_pending"))), "actual Main owns formal street route")
	level = _main.get("_screen") as Level
	player = level.player
	player.health.setup(999, 0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	for zone in level.find_children("*", "EncounterZone", true, false): zone.queue_free()
	for actor in get_tree().get_nodes_in_group(NpcActor.GROUP): actor.queue_free()
	player.health.grant_invulnerability(600)
	await _skip_active()
	await settle(20)
	Story.reset_active_presentation(&"probe")
	_origin.y = level._layout.floor_below(93, 10)
	place_player(93)
	await wait(1)

func place_player(_x_tile: float) -> void:
	player.global_position = _origin
	player.velocity = Vector2.ZERO
	snap_camera()


func _skip_active() -> void:
	for i in 60:
		if not Story.is_cinematic_active(): return
		Story.skip_cinematic()
		await settle(4)
