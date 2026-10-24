extends "res://tools/scenarios/scenario_base.gd"

var checks := 0
var failures := 0

func _ready() -> void:
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
	for i in 2: await get_tree().physics_frame
	if gamepad: (event as InputEventJoypadButton).pressed = false
	else: (event as InputEventKey).pressed = false
	Input.parse_input_event(event)
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
	label.text = "PICKUP REACH PHYSICS FIXTURE | synthetic E / pad X | no Main route or hardware claim"
	label.position = Vector2(12, 12)
	layer.add_child(label)
	for direction in [1.0, -1.0]:
		await open_arena("res://data/lighting/neutral.tres", 10.0, EnemySuiteBase.map_data())
		await clear_enemies()
		var item := Throwable.new()
		item.configure(load("res://data/throwables/crate_small.tres"))
		item.position = Vector2(160 + direction * 20, FLOOR_Y)
		level._entities.add_child(item)
		var wall := StaticBody2D.new()
		wall.collision_layer = Layers.WORLD
		wall.collision_mask = 0
		wall.position = Vector2(160 + direction * 10, FLOOR_Y - 24)
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
		item.position = Vector2(160 + direction * 20, FLOOR_Y)
		item.velocity = Vector2.ZERO
		wall.queue_free()
		for i in 6: await get_tree().physics_frame
		_check(player.carry.nearest_pickable() == item, "unblocked target restored %s" % direction)
		await _press(direction < 0)
		_check(player.carry.is_holding() and player.carry.held == item, "unblocked bound interaction succeeds %s" % direction)
		await _snap("open-%s" % int(direction))
		InputBindings.clear_held_inputs()
		await finish()
	print("REACH_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)
