extends "res://tools/prologue_resume_probe.gd"
## ST-16: real Main skip -> actual pause-menu archive -> readonly replay -> cold continue.
## Inherits --mode=skip|continue-skip --save-dir --out. Never seeds watched flags.

const OPENING := &"ch1_p01_door"


func _run() -> void:
	Story.scene_started.connect(func(id: StringName, _mode_name: StringName) -> void: _played.append(id))
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("_run_store", RunSaveStore.new(_save_dir.path_join("slot.json")))
	add_child(_main)
	await _frames(30)
	if _mode == "skip":
		await _skip()
	else:
		await _continue()
	await _archive_replay()
	print("PROLOGUE_REPLAY_PROBE mode=%s failures=%d" % [_mode, _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)


func _archive_replay() -> void:
	_check(Story.can_replay(OPENING), "the actual opening presentation unlocked its archive without fixture grants")
	var level := _level()
	if level == null:
		return
	var ready_deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < ready_deadline and (Story.is_cinematic_active() or GameplayLock.is_locked() or _main.call("_route_pending")):
		Story.skip_cinematic()
		await _ui_frames(1)
	_check(not GameplayLock.is_locked() and not _main.call("_route_pending"), "the actual transition has returned control before opening the menu")
	_main.call("_save_run")
	await _ui_frames(3)
	_joy(JOY_BUTTON_START, true)
	await _ui_frames(2)
	_joy(JOY_BUTTON_START, false)
	await _ui_frames(4)
	var menu := level._pause_menu
	_check(menu._root.visible and get_tree().paused, "gamepad Start opens the actual pawnshop pause menu")
	for action: StringName in [&"move_left", &"jump", &"shoot", &"block", &"dash", &"melee"]:
		_check(menu._controls_label.is_visible_in_tree() and menu._controls_label.text.contains(InputBindings.primary_label(action)), "skipped prologue retains the actual bound control hint: " + String(action))
	_check(menu._controls_label.text.contains("近戰"), "basic control help identifies melee as well as its contextual finisher")
	await _shot("ST-16-skipped-control-help-" + _mode)
	menu._quest_button.pressed.emit()
	await _ui_frames(4)
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var current := QuestMapState.for_run().target(catalog, "ch1_kasa", GameState.world_flags)
	var goal := str(QuestCatalog.current_step(current, GameState.world_flags).get("title", ""))
	var visible_goal := false
	for label: Label in menu._navigation.find_children("*", "Label", true, false):
		visible_goal = visible_goal or (label.is_visible_in_tree() and label.text.contains(goal) and not goal.is_empty())
	_check(visible_goal, "the real quest page displays the next formal objective after skipping")
	await _shot("ST-16-skipped-next-objective-" + _mode)
	for i in 3:
		if not is_instance_valid(menu._navigation):
			break
		await _action(&"ui_cancel")
	await _ui_frames(4)
	# Use the same button signal as the real pause menu; no separate Codex instance.
	var buttons := menu._root.find_children("*", "Button", true, false)
	var archive_button: Button
	for button: Button in buttons:
		if button.text == "圖鑑":
			archive_button = button
	_check(archive_button != null, "the actual pause menu offers archives")
	if archive_button == null:
		return
	archive_button.pressed.emit()
	await _ui_frames(4)
	var codex: CodexScreen = menu._codex
	codex._tabs[1].grab_focus()
	await _action(&"ui_accept")
	_check(codex._current_tab == 1 and codex._replay_page.entries.any(func(entry: Dictionary) -> bool: return entry["id"] == OPENING), "confirm switches to memories containing the earned prologue opening")
	await _shot("ST-16-earned-prologue-archive-" + _mode)
	var store: RunSaveStore = _main.get("_run_store")
	var primary := FileAccess.get_file_as_bytes(store.path)
	var backup := FileAccess.get_file_as_bytes(store.path + ".bak") if FileAccess.file_exists(store.path + ".bak") else PackedByteArray()
	var before := var_to_bytes([GameState.story_progress_snapshot(), Progression.snapshot(), QuestMapState.for_run().snapshot()])
	var selected := codex._replay_page.selected
	var focus := get_viewport().gui_get_focus_owner()
	await _action(&"ui_accept")
	_check(Story.is_replaying() and not codex.visible, "actual archive confirm starts the isolated prologue replay")
	# The opening begins with an establishing shot. Wait for the actual actors,
	# rather than using a fixed frame count that photographs an empty first frame.
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var actors_visible := false
	while Time.get_ticks_msec() < deadline and Story.is_replaying():
		var actors: Dictionary = Story._replay.get("_actors")
		if actors.has(&"rin") and actors.has(&"k"):
			actors_visible = true
			break
		await _ui_frames(1)
	_check(actors_visible, "the actual replay renders Rin and Old K before capture")
	await _ui_frames(6)
	await _shot("ST-16-earned-prologue-replay-" + _mode)
	await _action(&"ui_cancel")
	_check(not Story.is_replaying() and codex.visible and codex._replay_page.selected == selected, "return ends replay and restores the original archive selection")
	_check(get_viewport().gui_get_focus_owner() == focus and get_tree().paused and not GameplayLock.is_locked(), "return restores focus and retains the user's pause")
	_check(before == var_to_bytes([GameState.story_progress_snapshot(), Progression.snapshot(), QuestMapState.for_run().snapshot()]), "replay leaves all story, economy, items and exploration unchanged")
	_check(FileAccess.get_file_as_bytes(store.path) == primary and (FileAccess.get_file_as_bytes(store.path + ".bak") if FileAccess.file_exists(store.path + ".bak") else PackedByteArray()) == backup, "replay preserves exact primary and backup bytes")
	codex._close()
	await _ui_frames(4)
	menu.close()
	_check(not get_tree().paused and not GameplayLock.is_locked(), "closing the actual pause menu returns normal gameplay")


func _action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event, true)
	await _ui_frames(2)
	event = event.duplicate() as InputEventAction
	event.pressed = false
	get_viewport().push_input(event, true)
	await _ui_frames(2)


func _ui_frames(count: int) -> void:
	# GUI focus, tweens and viewport input advance on idle frames, not physics ticks.
	for i in count:
		await get_tree().process_frame
