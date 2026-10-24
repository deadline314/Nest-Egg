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
	label.text = "PICKUP REACH | Main street route with arranged wall / crate\nSynthetic E / pad X | no natural chapter or hardware claim"
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 12)
	layer.add_child(label)
	await open_arena("res://data/lighting/neutral.tres", 10.0, EnemySuiteBase.map_data())
	await clear_enemies()
	for direction in [1.0, -1.0]:
		place_player(10.0)
		var item := Throwable.new()
		item.configure(load("res://data/throwables/crate_small.tres"))
		item.position = _origin + Vector2(direction * 20, 0)
		level._entities.add_child(item)
		var wall := StaticBody2D.new()
		wall.collision_layer = Layers.WORLD
		wall.collision_mask = 0
		wall.position = _origin + Vector2(direction * 10, -24)
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(3, 48)
		collision.shape = shape
		wall.add_child(collision)
		var visual := Polygon2D.new()
		visual.polygon = PackedVector2Array([Vector2(-1.5,-24),Vector2(1.5,-24),Vector2(1.5,24),Vector2(-1.5,24)])
		visual.color = Color("4c6778")
		wall.add_child(visual)
		level.add_child(wall)
		for i in 6: await get_tree().physics_frame
		_check(item.can_pick_up(), "fixture settled %s" % direction)
		_check(player.carry.nearest_pickable() == null, "blocked target rejected %s" % direction)
		_check(not item._prompt._player_near(), "blocked invitation absent %s" % direction)
		await wait(.3)
		await _snap("blocked-%s" % int(direction))
		await _press(direction < 0)
		_check(not player.carry.is_holding(), "real bound interaction cannot reach through wall %s" % direction)
		await _snap("pressed-%s" % int(direction))
		if player.carry.is_holding(): player.carry.put_down()
		item.position = _origin + Vector2(direction * 20, 0)
		item.velocity = Vector2.ZERO
		wall.queue_free()
		for i in 6: await get_tree().physics_frame
		_check(player.carry.nearest_pickable() == item, "unblocked target restored %s" % direction)
		await _press(direction < 0)
		_check(player.carry.is_holding() and player.carry.held == item, "unblocked bound interaction succeeds %s" % direction)
		await _snap("open-%s" % int(direction))
		InputBindings.clear_held_inputs()
		if player.carry.is_holding(): player.carry.put_down()
		item.queue_free()
		for i in 6: await get_tree().physics_frame
	await wait(.5)
	await settle(10)
	print("REACH_RESULT checks=%d failures=%d" % [checks, failures])
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
	_main.call("_on_start_requested", GameState.difficulties[1])
	await _until(func() -> bool: return _main.get("_screen") is Level and not bool(_main.call("_route_pending")))
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
