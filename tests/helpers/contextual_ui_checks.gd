class_name ContextualUiChecks
extends RefCounted
## 真 Level/Hud 與正式 Story/DialogueLayer；不是教學成功或人工手把證據。

static func run(suite: TestSuite) -> void:
	await _hints(suite)
	await _dialogue(suite)
	await _radio_identity_after_authored_reading(suite)


static func _hints(suite: TestSuite) -> void:
	var level: Level = await suite.start_level(PropsSuite.level_data())
	var hud := level.hud
	var owner := Node.new()
	level.add_child(owner)
	var flags := GameState.world_flags.duplicate(true)
	var token := hud.show_context_hint(owner, "跨過矮牆。 {jump}", 8.0)
	suite.check(token > 0 and hud._hint_caps.size() == 1 and hud._controls.text == "跨過矮牆。", "cue displays one action and readable instruction, without the six-action table")
	var cap := hud._hint_caps[0].get_child(0) as Label
	suite.check(cap.text == InputBindings.primary_label(&"jump"), "keycap names the currently rebound input")
	var previous_device := InputBindings.using_gamepad
	var previous_device_id := InputBindings.active_device
	InputBindings._set_device(true, -1)
	cap = hud._hint_caps[0].get_child(0) as Label
	suite.check(cap.text == InputBindings.joy_label(&"jump") and Hud.controls_hint().contains(InputBindings.joy_label(&"reload")), "device switch refreshes cue and retains complete pause controls")
	InputBindings._set_device(previous_device, previous_device_id)
	var event := InputEventAction.new()
	event.action = &"jump"
	event.pressed = true
	Input.parse_input_event(event)
	await suite.frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	suite.check(hud._hint_owner != null and not hud._hint_expired and GameState.world_flags == flags, "a button press never records tutorial success or writes Story flags")
	var lock := GameplayLock.acquire(owner)
	var reading := hud._controls_read_time
	hud._process(1.0)
	suite.check(not hud._controls_card.visible and is_equal_approx(reading, hud._controls_read_time), "lock suppresses whole cue and preserves reading time")
	GameplayLock.release(lock)
	var second := hud.show_context_hint(owner, "射擊並換彈。 {shoot} {reload}", 8.0)
	hud.clear_context_hint(token)
	suite.check(second > token and not hud._hint_expired, "an old completion token cannot clear a replacement cue")
	suite.check(hud.show_context_hint(owner, "三動作 {jump} {shoot} {dash}") == 0 and hud.show_context_hint(owner, "未知 {not_real}") == 0 and hud.show_context_hint(owner, "跳躍 {jump}", NAN) == 0, "invalid, excessive, or nonfinite cue data is refused")
	suite.check(hud.show_context_hint(owner, "移動 {move_left}/{move_right}") == 0 and hud.show_context_hint(owner, "按 {jump} 跨過矮牆。") == 0 and hud.show_context_hint(owner, "{jump}") == 0, "embedded or instructionless tokens cannot render orphan punctuation or fragments")
	var foreign := Node.new()
	suite.runner.add_child(foreign)
	suite.check(hud.show_context_hint(foreign, "跳躍 {jump}") == 0, "foreign-level owner cannot install a cue")
	foreign.queue_free()
	hud._dismiss_controls()
	hud.show_context_hint(owner, "跨過矮牆。 {jump}", 8.0)
	await suite.frames(24)
	suite.check(hud._controls_card.modulate.a == 1.0, "replacement cue cancels prior dismissal tween rather than disappearing later")
	var other_root := Node.new()
	suite.runner.add_child(other_root)
	owner.reparent(other_root)
	hud._process(0.0)
	suite.check(hud._hint_owner == null and hud._hint_expired, "moving a live owner outside its Level invalidates the lease without waiting for deletion")
	owner.reparent(level)
	hud.show_context_hint(owner, "跨過矮牆。 {jump}", 8.0)
	other_root.queue_free()
	owner.queue_free()
	await suite.frames(2)
	suite.check(hud._hint_owner == null and hud._hint_expired and not hud._controls_card.visible, "real owner removal invalidates cue before reuse")
	await suite.end_level(level)


static func _dialogue(suite: TestSuite) -> void:
	var layer := DialogueLayer.new()
	suite.runner.add_child(layer)
	await suite.frames(2)
	var old_scale := Settings.get_ui_text_scale()
	var old_motion := Settings.get_reduce_ui_motion()
	Settings.set_ui_text_scale(1.2)
	Settings.set_reduce_ui_motion(true)
	var lines: Array[Dictionary] = Story.resolved_lines(&"ch1_t_oldk_1")
	# Pick the longest currently loaded authored dialogue line, not an easy mirrored fixture.
	for id: String in Story._scenes:
		if Story.scene_mode(StringName(id)) != Story.MODE_DIALOGUE:
			continue
		for line in Story.resolved_lines(StringName(id)):
			if not lines.is_empty() and str(line.text).length() > str(lines[0].text).length():
				lines = [line]
	suite.check(not lines.is_empty(), "authored old K dialogue is loaded; no fabricated fallback text")
	if lines.is_empty():
		layer.queue_free()
		Settings.set_ui_text_scale(old_scale)
		Settings.set_reduce_ui_motion(old_motion)
		return
	var completed: Array[StringName] = []
	layer.cinematic_finished.connect(func(id: StringName) -> void: completed.append(id))
	layer.start_cinematic(&"ui_fixture", lines)
	await suite.frames(3)
	for size in [Vector2(640, 360), Vector2(840, 360)]:
		var safe := CinematicFraming.rect_for(size)
		layer._layout_cinematic(safe)
		await suite.frames(2)
		suite.check(safe.encloses(layer._dialogue_panel.get_rect()) and safe.encloses(layer._text.get_rect()), "dialogue and full body stay in true 21:9 safe rect: %s" % size)
		suite.check(layer._text.get_combined_minimum_size().y <= layer._text.size.y + 0.01 and not layer._text.get_rect().intersects(layer._continue.get_rect()), "120%% body fits without clipping or sharing continue prompt space: %s" % size)
	var full := layer._text.text
	var original_lines := lines.duplicate(true)
	layer.advance()
	suite.check(layer._text.visible_ratio == 1.0 and layer._text.text == full and completed.is_empty(), "first advance reveals the entire original line without finishing")
	layer.cancel_cinematic()
	suite.check(completed.is_empty() and not layer.is_cinematic_active(), "cancel releases presentation without sending completion")
	suite.check(lines == original_lines, "cancel never clears the caller's authored line array")
	var context_before := Story._presentation_context.duplicate(true)
	Story._presentation_context = {"framing_source":"object", "source_id":"fixture-reader"}
	layer.start_cinematic(&"ui_object_fixture", lines)
	suite.check(layer._name.text.begins_with("閱讀") and not layer._portrait.visible, "real presentation context switches reading identity and removes empty portrait slot")
	layer.cancel_cinematic()
	Story._presentation_context = context_before
	var radio: Array[Dictionary] = [{"name": "通訊員", "color": Palette.CYAN, "portrait": "", "text": "前方道路已確認，請留意屋頂的出口。"}]
	layer.enqueue_radio(&"ui_radio_fixture", radio)
	suite.check(layer._radio_root.modulate.a == 1.0 and layer._radio_slide == null, "reduce motion reveals radio immediately without input delay")
	layer._layout_cinematic(CinematicFraming.rect_for(Vector2(640,360)))
	suite.check(layer._radio_root.position.y >= 82 and layer._radio_name.text.contains("通訊"), "radio is identified and leaves the existing y52 quest objective row unobscured")
	layer.cancel_radio()
	Settings.set_ui_text_scale(old_scale)
	Settings.set_reduce_ui_motion(old_motion)
	layer.queue_free()
	await suite.frames(2)


## 真 level_02 height_marks 閱讀後播作者 radio；radio 是 UI-only，未授 Story 結果。
static func _radio_identity_after_authored_reading(suite: TestSuite) -> void:
	var previous_skip := Story.auto_skip
	var previous_setting := Settings.get_skip_cutscenes()
	Story.auto_skip = false
	Settings.set_skip_cutscenes(false)
	var data := (load("res://data/levels/level_02.tres") as LevelData).duplicate(true) as LevelData
	data.intro_scene = &""
	# Private capture fixture: jumping to the actual OBJECT must not enqueue unrelated & movies.
	for i in data.story_triggers.size():
		data.story_triggers[i] = ""
	var level: Level = await suite.start_level(data)
	var entry_position := level.player.global_position
	var object: NpcActor
	for node in suite.runner.get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and level.is_ancestor_of(node) and node.data.id == &"height_marks":
			object = node
	suite.check(object != null, "actual height_marks OBJECT exists in authored level_02")
	if object == null:
		await suite.end_level(level)
		Story.auto_skip = previous_skip
		Settings.set_skip_cutscenes(previous_setting)
		return
	level.player.global_position = object.global_position + Vector2(24, 0)
	object._talk()
	await suite.frames(3)
	var layer := Story._layer
	suite.check(layer.is_cinematic_active() and layer._name.text.contains(object.data.display_name), "true NpcActor reading request displays original object's identity")
	level.hud._process(0.0)
	suite.check(not level.hud._framing_edge_root.visible and Story.framing.scope_count() == 0, "actual object reading hides the conflicting timer header without adding cinematic bars")
	var cinematic_portrait := layer._portrait
	var reading_title := layer._reading_title
	var reading_style := layer._name_plate.get_theme_stylebox(&"panel")
	Story.reset_active_presentation(&"leave")
	await suite.frames(3)
	# Cancel releases reading; a nearby, genuinely available movie entrance may
	# still preview its bars. Leave that entrance before expecting gameplay HUD.
	level.player.global_position = entry_position
	level.player.velocity = Vector2.ZERO
	await suite.runner.get_tree().create_timer(CinematicFraming.CHECK_INTERVAL + CinematicFraming.EASE_SECONDS + 0.1).timeout
	level.hud._process(0.0)
	suite.check(not Story.is_cinematic_active() and not GameplayLock.is_locked() and Story.framing.selected_target() == null and level.hud._framing_edge_root.visible, "leaving actual object reading and cinematic preview range restores the gameplay header")
	var lines: Array[Dictionary] = Story.resolved_lines(&"radio_market_mei")
	suite.check(not lines.is_empty(), "authored radio_market_mei is loaded without fabricated fallback")
	if not lines.is_empty():
		var first := lines[0]
		var finished: Array[StringName] = []
		var observer := func(id: StringName) -> void: finished.append(id)
		layer.radio_finished.connect(observer)
		layer.enqueue_radio(&"radio_market_mei", lines)
		suite.check(layer._radio_name.text.begins_with("通訊") and layer._radio_name.text.contains(str(first.name)) and not layer._radio_name.text.contains(reading_title), "radio identifies its own authored speaker, never the preceding object")
		suite.check(layer._portrait == cinematic_portrait and layer._name_plate.get_theme_stylebox(&"panel") == reading_style, "radio cannot replace cinematic portrait or reading nameplate")
		var texture := RigLibrary.optional_texture(str(first.portrait)) if not str(first.portrait).is_empty() else null
		suite.check(layer._radio_portrait.texture == texture and layer._radio_portrait.visible == (texture != null), "radio updates its own portrait visibility from its own actual texture")
		suite.check(layer._radio_queue.size() == lines.size() and finished.is_empty(), "enqueue preserves all authored lines and does not finish early")
		var hold := layer._radio_hold
		suite.check(is_equal_approx(hold, 1.6 + str(first.text).length() * 0.055) and is_equal_approx(layer._radio_wait, float(first.get("delay", 0.0))), "unchanged authored hold and silence timing")
		layer._process(0.01)
		suite.check(is_equal_approx(layer._radio_hold, hold), "typewriter phase does not consume the reading hold")
		layer._radio_text.visible_ratio = 1.0
		layer._process(0.2)
		suite.check(is_equal_approx(layer._radio_hold, hold - 0.2) and finished.is_empty(), "full line uses hold countdown without premature completion")
		layer.cancel_radio()
		# Explicit timing fixture uses a private copy of actual text, never modifies authored registry.
		var delayed := first.duplicate(true)
		delayed["delay"] = 0.25
		var fixture: Array[Dictionary] = [delayed]
		layer.enqueue_radio(&"ui_radio_delay_fixture", fixture)
		var delay_hold := layer._radio_hold
		layer._process(0.1)
		suite.check(not layer._radio_root.visible and is_equal_approx(layer._radio_wait, 0.15) and is_equal_approx(layer._radio_hold, delay_hold), "private timing fixture respects silence before reveal and preserves hold")
		layer.cancel_radio()
		layer.radio_finished.disconnect(observer)
	await suite.end_level(level)
	Story.auto_skip = previous_skip
	Settings.set_skip_cutscenes(previous_setting)
