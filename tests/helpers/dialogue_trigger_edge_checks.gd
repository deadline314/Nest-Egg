extends RefCounted
## Real dialogue owners, public analog events; not physical-controller acceptance.
static func run(s: TestSuite) -> void:
	check_localized_presentation(s)
	var layer := DialogueLayer.new()
	s.runner.add_child(layer)
	await _process_frames(s,1)
	var lines: Array[Dictionary] = [
		{"name": "Rin", "color": Color.WHITE, "portrait": "", "text": "First line stays until a second press."},
		{"name": "Rin", "color": Color.WHITE, "portrait": "", "text": "Second line."},
	]
	_axis(0.0)
	_keyboard_device()
	layer.start_cinematic(&"test_trigger_dialogue", lines)
	_axis(0.9)
	s.check(layer._text.visible_ratio == 1.0 and layer._cinematic_index == 0, "first trigger press reveals the current dialogue line")
	s.check(InputBindings.using_gamepad and layer._skip.text.contains(InputBindings.joy_label(&"ui_cancel")), "cinematic dialogue observes its consumed controller event and refreshes the visible prompt")
	_mouse_device()
	s.check(not InputBindings.using_gamepad and layer._skip.text.contains(InputBindings.code_label(KEY_ESCAPE)) and layer._cinematic_index == 0, "moving the mouse restores keyboard hints without advancing dialogue")
	for value: float in [InputMap.action_get_deadzone(&"shoot"), 0.92, 0.8, 1.0, 0.85]:
		_axis(value)
	s.check(layer.is_cinematic_active() and layer._cinematic_index == 0, "held trigger variation cannot advance or finish cinematic dialogue")
	_axis(0.0)
	_axis(0.95)
	s.check(layer._cinematic_index == 1, "releasing then pressing advances dialogue exactly once")
	layer.cancel_cinematic()
	_axis(0.0)
	layer.queue_free()
	await _process_frames(s,1)

	var player := CutscenePlayer.new()
	s.runner.add_child(player)
	_keyboard_device()
	player.play(&"test_trigger_cutscene", {"overlay": true, "steps": [
		{"do": "say", "speaker": "rin", "text": "First animated line waits for another press."},
		{"do": "say", "speaker": "rin", "text": "Second animated line."},
	]})
	await _process_frames(s,2)
	_axis(0.9)
	s.check(player._dialogue.is_complete() and player.steps_run == 0, "first trigger press reveals the animated line")
	s.check(InputBindings.using_gamepad and player._skip_hint.text.contains(InputBindings.joy_label(&"ui_cancel")), "animated dialogue observes its consumed controller event and refreshes the visible prompt")
	_mouse_device()
	s.check(not InputBindings.using_gamepad and player._skip_hint.text.contains(InputBindings.code_label(KEY_ESCAPE)) and player.steps_run == 0, "moving the mouse restores keyboard hints without advancing the animated line")
	for value: float in [InputMap.action_get_deadzone(&"shoot"), 0.92, 0.8, 1.0, 0.85]:
		_axis(value)
		await _process_frames(s,1)
	s.check(is_instance_valid(player) and player.is_running() and player.steps_run == 0 and not player._advance_requested, "held trigger variation cannot request the next animated line")
	_axis(0.0)
	_axis(0.95)
	await _process_frames(s,2)
	s.check(is_instance_valid(player) and player.is_running() and player.steps_run == 1, "a new trigger press advances to the second animated line")
	_axis(0.0)
	if is_instance_valid(player):
		player.cancel()
	await _process_frames(s,2)
	InputBindings.clear_held_inputs()


static func check_localized_presentation(s: TestSuite) -> void:
	var original_language := Story.language
	var dialogue := CutsceneDialogue.new()
	s.runner.add_child(dialogue)
	for row: Array in [["zh", "跳過"], ["ja", "スキップ"], ["en", "Skip"]]:
		Story.language = row[0]
		dialogue.show_line({"name": "Speaker"}, "Skydome keeps its name together.", "noise")
		s.check(UiKit.cinematic_skip_hint(Story.language).ends_with(row[1]), "cutscene skip hint follows %s" % Story.language)
		for label: Label in [dialogue._text, dialogue._ghost_a, dialogue._ghost_b]:
			s.check(label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and label.language == Story.language
				and label.visible_characters_behavior == TextServer.VC_CHARS_AFTER_SHAPING,
				"each subtitle layer wraps with the selected language")
	Story.language = original_language
	dialogue.free()

static func _axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

static func _process_frames(s: TestSuite, count: int) -> void:
	for i in count:
		await s.runner.get_tree().process_frame

static func _keyboard_device() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F10
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

static func _mouse_device() -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(8, 0)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
