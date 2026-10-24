extends "res://tools/scenarios/scenario_base.gd"

var _main: Node
var _origin := Vector2(93 * 16, FLOOR_Y)
var checks := 0
var failures := 0

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

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Story.auto_skip = true
	GameState.story_autosave = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "SAFE DROP | actual Main street / arranged wall and crate\nSynthetic E / pad X | not hardware or natural chapter verification"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 12)
	layer.add_child(label)
	await open_arena("", 10.0)
	await clear_enemies()
	for direction: float in [1.0, -1.0]:
		place_player(93)
		AimInput.set_virtual_gamepad(player, true)
		Input.action_press(&"aim_right" if direction > 0 else &"aim_left")
		var item := Throwable.new()
		item.configure(load("res://data/throwables/crate_small.tres"))
		item.position = _origin + Vector2(8, 0)
		level._entities.add_child(item)
		for i in 6: await get_tree().physics_frame
		await _press(direction < 0)
		for i in 20: await get_tree().physics_frame
		_check(player.carry.is_holding() and player.carry.held == item, "public pickup completed %s" % direction)
		var wall := StaticBody2D.new()
		wall.collision_layer = Layers.WORLD
		wall.collision_mask = 0
		wall.position = _origin + Vector2(direction * 14, -48)
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(3, 96)
		collision.shape = rectangle
		wall.add_child(collision)
		var visual := Polygon2D.new()
		visual.polygon = PackedVector2Array([Vector2(-1.5,-48), Vector2(1.5,-48), Vector2(1.5,48), Vector2(-1.5,48)])
		visual.color = Color("4c6778")
		wall.add_child(visual)
		level.add_child(wall)
		for i in 4: await get_tree().physics_frame
		await _snap("holding-%s" % int(direction))
		var near_edge := direction * wall.global_position.x - 1.5
		await _press(direction < 0)
		_check(not player.carry.is_holding() and item.state == Throwable.State.REST, "public drop releases %s" % direction)
		_check(direction * item.global_position.x + item.data.size.x * .5 < near_edge, "public drop stays before wall %s x=%s" % [direction, item.global_position.x])
		await _snap("released-%s" % int(direction))
		for i in 50: await get_tree().physics_frame
		_check(item.is_on_floor() and direction * item.global_position.x + item.data.size.x * .5 < near_edge, "prop settles on original side %s x=%s" % [direction, item.global_position.x])
		await _snap("settled-%s" % int(direction))
		InputBindings.clear_held_inputs()
		item.queue_free()
		wall.queue_free()
		for i in 4: await get_tree().physics_frame
	print("DROP_RESULT checks=%d failures=%d" % [checks, failures])
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
