extends Node
## Real primary Main route; semantic UI events, not human play or Story authority.
const MainScene := preload("res://scenes/main.tscn")
const Capture := preload("res://tools/viewport_capture.gd")
const INTRO := &"ch1_c01_open"
const ROUNDS := 3
const MAX_EVENTS := 128
const RECLAIM_TEXTURE_SLACK_BYTES := 1048576
const RECLAIM_OBJECTS_PER_ROUND := 8
const OLD_PREFETCH_SHA := "899a16248df56a7da81ed857bb96840c2463b94bb9f2e698fe53212f78643528"
const NEW_PREFETCH_SHA := "31adc870a9594b247c01aed458a83901188e34e2f00a3944c352332f72bef013"
var _main: Node
var _out := ""
var _slot := ""
var _phase := ""
var _checks := 0
var _failures := 0
var _events: Array[Dictionary] = []
var _images: Array[Dictionary] = []
var _starts := 0
var _finishes := 0
var _accept_lines := 0
var _last_line := ""
var _opening_shot := false
var _retired: Array[WeakRef] = []
var _saved: Dictionary = {}
var _cold_record: Dictionary = {}
var _finished := false
var _tool_sha := ""
var _policy := "main-thread-rd-472"
var _prefetch_sha := ""
var _talks: Array[String] = []
var _talk_lines := 0
var _interact_presses := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tool_sha = FileAccess.get_sha256(get_script().resource_path)
	_prefetch_sha = FileAccess.get_sha256("res://core/asset_prefetch.gd")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--slot="):
			_slot = argument.trim_prefix("--slot=").replace("\\", "/")
		elif argument.begins_with("--phase="):
			_phase = argument.trim_prefix("--phase=")
		elif argument.begins_with("--policy="):
			_policy = argument.trim_prefix("--policy=")
	if not _out.is_absolute_path() or not _slot.is_absolute_path() or not _slot.ends_with(".json") \
			or _slot == ProjectSettings.globalize_path(RunSaveStore.DEFAULT_PATH) \
			or _phase not in ["record", "cold"] or DisplayServer.get_name() == "headless" \
			or _policy not in ["threaded-native", "main-thread-rd-472"] \
			or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("[BG31Main] requires native Forward+, absolute isolated --out/--slot=.json and record|cold")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[BG31Main] cannot create isolated output directory")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _check(value: bool, label: String) -> bool:
	_checks += 1
	if not value:
		_failures += 1
	print("BG31_MAIN_CHECK:", "PASS" if value else "FAIL", ":", label)
	return value


func _stage(label: String, extra: Dictionary = {}) -> void:
	if _events.size() >= MAX_EVENTS:
		_check(false, "bounded stage log capacity exceeded")
		return
	var event := {"stage": label, "pid": OS.get_process_id(), "ticks_ms": Time.get_ticks_msec(),
		"process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(),
		"engine_static_bytes": OS.get_static_memory_usage(),
		"engine_node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"engine_object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"engine_orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"render_texture_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"render_video_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"prefetch": AssetPrefetch.stats()}
	event.merge(extra)
	_events.append(event)
	print("BG31_MAIN_STAGE:", JSON.stringify(event))


func _wait(predicate: Callable, label: String, milliseconds := 45000) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline and _failures == 0:
		if predicate.call():
			return _check(true, label)
		await get_tree().process_frame
	return _check(false, label + " (timeout or earlier failed check)")


func _route_idle() -> bool:
	return is_instance_valid(_main) and not _main._route_pending() and not Transition.is_active()


func _menu_ready() -> bool:
	return _route_idle() and _main._screen is MainMenu and _main._screen.is_inside_tree()


func _world_ready() -> bool:
	if not _route_idle() or not _main._screen is Level or Story.is_cinematic_active() or GameplayLock.is_locked():
		return false
	var level := _main._screen as Level
	return level.is_initialized() and level.data.resource_path == _main.FIRST_LEVEL \
		and is_instance_valid(level.player) and not level.player.is_dead() and level.player.is_on_floor() \
		and not get_tree().paused


func _opaque(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		return false
	var node: Node = control
	while node != null:
		if node is CanvasItem:
			var item := node as CanvasItem
			if item.modulate.a < 0.999 or item.self_modulate.a < 0.999:
				return false
		node = node.get_parent()
	return true


func _button_ready(button: Button) -> bool:
	if not _opaque(button) or button.disabled or button.size.x <= 0 or button.size.y <= 0:
		return false
	var transform := button.get_global_transform_with_canvas()
	var viewport := get_viewport().get_visible_rect()
	for corner: Vector2 in [Vector2.ZERO, Vector2(button.size.x, 0), button.size, Vector2(0, button.size.y)]:
		if not viewport.has_point(transform * corner):
			return false
	return true


func _action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _press(button: Button, label: String) -> bool:
	if not await _wait(func() -> bool: return _button_ready(button), "loaded visible Button: " + label):
		return false
	button.grab_focus()
	if not _check(get_viewport().gui_get_focus_owner() == button, "actual focus: " + label):
		return false
	_stage("button-input", {"button": label, "instance": button.get_instance_id()})
	_action(&"ui_accept", true)
	await get_tree().process_frame
	_action(&"ui_accept", false)
	await get_tree().process_frame
	return _failures == 0


func _on_started(id: StringName, mode: StringName) -> void:
	if id == INTRO:
		_starts += 1
	_stage("story-started", {"scene": String(id), "mode": String(mode)})


func _on_finished(id: StringName) -> void:
	if id == INTRO:
		_finishes += 1
	_stage("story-finished", {"scene": String(id)})


func _opening() -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and _failures == 0:
		if _world_ready() and _finishes == 1:
			break
		if Story.is_cinematic_active() and Story._current_cinematic != INTRO:
			_check(false, "unexpected cinematic is not guessed or bypassed")
			break
		var player := Story._player as CutscenePlayer
		if is_instance_valid(player) and player.scene_id == INTRO and player._running:
			if player.skipping or player.user_skipped or player.speed != 1.0:
				_check(false, "actual opening must retain normal speed without skip")
				break
			if player.choice_active():
				_check(false, "baseline opening unexpectedly has a choice; no invented selection")
				break
			var dialogue := player._dialogue as CutsceneDialogue
			if _opaque(dialogue) and dialogue.is_complete() and not dialogue._text.text.is_empty() \
					and (not dialogue._frame.visible or _opaque(dialogue._frame)) \
					and player._fade.color.a <= 0.001 and not Transition.is_active():
				var line := player._current_where + "|" + dialogue._text.text
				if line != _last_line:
					if not _opening_shot:
						await _shot("cinematic")
						_opening_shot = _failures == 0
					if _failures != 0:
						break
					_last_line = line
					_accept_lines += 1
					_stage("authored-line-accept", {"where": player._current_where,
						"text": dialogue._text.text, "scene": String(player.scene_id)})
					_action(&"ui_accept", true)
					await get_tree().process_frame
					_action(&"ui_accept", false)
		await get_tree().process_frame
	return _check(_world_ready() and _starts == 1 and _finishes == 1 and _accept_lines == 3
		and _opening_shot and Story._completed.has(INTRO),
		"natural pawnshop opening: three actual complete lines, one start/completion, playable world")


func _find_person(root: Node) -> NpcActor:
	for child: Node in root.get_children():
		var person := child as NpcActor
		if person != null and person.data != null and person.data.kind == NpcData.Kind.PERSON:
			return person
		person = _find_person(child)
		if person != null:
			return person
	return null


## 用移動鍵走到人物面前、按互動鍵，逐句讀完他目前要說的那一段；不直接呼叫對話或授予旗標。
func _npc_talk(label: String) -> bool:
	if not _check(_world_ready(), "live playable Level before NPC talk: " + label):
		return false
	var level := _main._screen as Level
	var person := _find_person(level)
	if not _check(person != null and person.current_talk_index() >= 0, "loaded person with an available talk: " + label):
		return false
	var scene: StringName = person.data.talks[person.current_talk_index()].scene
	var expected_lines := Story.resolved_lines(scene).size()
	var count_before := person.talk_count
	if not _check(Story.scene_mode(scene) == Story.MODE_DIALOGUE and expected_lines > 0
		and not Story.was_seen(scene) and not _talks.has(String(scene)),
		"current talk is an unread dialogue, never a replay of a finished one: " + label):
		return false
	var direction := &"move_right" if person.global_position.x > level.player.global_position.x else &"move_left"
	_stage("npc-walk-input", {"label": label, "scene": String(scene), "direction": String(direction),
		"player_x": level.player.global_position.x, "person_x": person.global_position.x, "talk_count": count_before})
	_action(direction, true)
	var reached := await _wait(func() -> bool: return person.interaction_available() and Story.framing.is_interaction_target(person),
		"actual walk input reaches the person's interaction range: " + label, 20000)
	_action(direction, false)
	if not reached:
		return false
	var presses := 0
	while presses < 5 and not Story.is_cinematic_active() and _failures == 0:
		presses += 1
		await get_tree().physics_frame
		_action(&"interact", true)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_action(&"interact", false)
		for _frame in 12:
			if Story.is_cinematic_active():
				break
			await get_tree().process_frame
	_interact_presses += presses
	if not _check(Story.is_cinematic_active() and Story._current_cinematic == scene,
			"interact input starts the person's current talk: " + label):
		return false
	var layer := Story._layer as DialogueLayer
	var accepted := 0
	var last_line := ""
	var shot := _phase != "record"
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline and _failures == 0 and Story.is_cinematic_active():
		if layer.is_cinematic_active() and _opaque(layer._text) and layer._text.visible_ratio >= 1.0 and not layer._text.text.is_empty():
			var line := "%s|%d" % [layer._cinematic_id, layer._cinematic_index]
			if line != last_line:
				if not shot:
					await _shot("npc")
					shot = _failures == 0
				if _failures != 0:
					break
				last_line = line
				accepted += 1
				_stage("npc-line-accept", {"label": label, "scene": String(layer._cinematic_id),
					"index": layer._cinematic_index, "text": layer._text.text})
				_action(&"ui_accept", true)
				await get_tree().process_frame
				_action(&"ui_accept", false)
		await get_tree().process_frame
	_talk_lines += accepted
	if not await _wait(func() -> bool: return _world_ready() and person.talk_count == count_before + 1,
			"talk settles once into the playable world: " + label):
		return false
	if not _check(accepted >= expected_lines and Story.was_seen(scene) and not get_tree().paused
		and not GameplayLock.is_locked() and level.player.is_physics_processing(),
		"every authored line accepted once, scene recorded, no residual freeze: " + label):
		return false
	_talks.append(String(scene))
	_stage("npc-talk-settled", {"label": label, "scene": String(scene), "lines": accepted,
		"interact_presses": presses, "talk_count": person.talk_count})
	return true


func _find_menu_button(root: Node) -> Button:
	for child: Node in root.get_children():
		if child is Button and child.text == "回主選單":
			return child as Button
		var found := _find_menu_button(child)
		if found != null:
			return found
	return null


func _timed_pause(level: Level, pause: PauseMenu, label: String) -> bool:
	var hud := level.hud as Hud
	if not _check(is_instance_valid(hud) and is_instance_valid(hud._timer_label),
			"actual live HUD timer exists during PauseMenu: " + label):
		return false
	var timer := hud._timer_label as Label
	var runtime_before: float = GameState.run_time
	var hud_before: String = timer.text
	var started := Time.get_ticks_msec()
	var observed_frames := 0
	if not _check(get_tree().paused and _main.process_mode == Node.PROCESS_MODE_PAUSABLE
		and not _main.can_process() and not level.can_process()
		and pause.can_process() and pause._root.can_process()
		and hud_before == UiKit.format_time(runtime_before),
		"real pause blocks Main/Level, preserves matching HUD clock and keeps Pause UI processing: " + label):
		return false
	# Observe real wall time and real process frames; do not sync rendering or drain prefetch.
	while Time.get_ticks_msec() - started < 300:
		await get_tree().process_frame
		observed_frames += 1
		if not get_tree().paused or _main.can_process() or level.can_process() \
				or not pause.can_process() or not pause._root.can_process() \
				or GameState.run_time != runtime_before or timer.text != hud_before:
			_check(false, "timed actual Pause changed world processing or clocks: " + label)
			return false
	_stage("timed-pause-observed", {"label": label, "elapsed_ms": Time.get_ticks_msec() - started,
		"observed_process_frames": observed_frames, "run_time_before": runtime_before,
		"run_time_after": GameState.run_time, "hud_before": hud_before, "hud_after": timer.text,
		"main_can_process": _main.can_process(), "level_can_process": level.can_process(),
		"pause_can_process": pause.can_process()})
	return _check(observed_frames >= 2 and Time.get_ticks_msec() - started >= 300
		and GameState.run_time == runtime_before and timer.text == hud_before
		and timer.text == UiKit.format_time(GameState.run_time),
		"timed 300ms real Pause holds runtime/HUD exactly; original menu Button follows: " + label)


func _back_to_menu(label: String) -> bool:
	if not _check(_world_ready(), "live playable Level before PauseMenu: " + label):
		return false
	var level := _main._screen as Level
	var old_level: WeakRef = weakref(level)
	var old_player: WeakRef = weakref(level.player)
	_retired.append(old_level)
	_retired.append(old_player)
	var pause := level._pause_menu as PauseMenu
	_stage("pause-open-input", {"label": label, "level": level.get_instance_id(),
		"player": level.player.get_instance_id()})
	_action(&"pause", true)
	await get_tree().process_frame
	_action(&"pause", false)
	if not await _wait(func() -> bool: return is_instance_valid(pause) and pause._root.visible and get_tree().paused,
			"actual PauseMenu opens: " + label):
		return false
	if not await _timed_pause(level, pause, label):
		return false
	var button := _find_menu_button(pause)
	if not _check(button != null, "actual PauseMenu menu Button found: " + label):
		return false
	if not await _press(button, "PauseMenu / 回主選單 / " + label):
		return false
	# Drop local actor references before observing the natural route's release.
	level = null
	pause = null
	button = null
	if not await _wait(_menu_ready, "natural Main menu after loaded Pause callback: " + label):
		return false
	if not _check(old_level.get_ref() == null and old_player.get_ref() == null,
			"old Level and Player freed by actual route: " + label):
		return false
	_saved = _main._run_store.read()
	if not _check(not _saved.is_empty() and _main._run_store.issues.is_empty()
		and _saved.get("level") == _main.FIRST_LEVEL and _saved.get("cinematic") == ""
		and _saved["story"]["seen"].has(String(INTRO)), "genuine canonical completed-opening slot: " + label):
		return false
	for talk: String in _talks:
		if not _check(_saved["story"]["seen"].count(talk) == 1, "saved slot records finished talk exactly once: %s / %s" % [talk, label]):
			return false
	_stage("menu-settled", {"label": label, "slot_sha256": FileAccess.get_sha256(_slot)})
	return true


func _continue(label: String) -> bool:
	if not _check(_menu_ready(), "actual menu ready to Continue: " + label):
		return false
	var menu := _main._screen as MainMenu
	if not _check(menu.continue_available and menu._continue_button != null, "loaded Continue available: " + label):
		return false
	var old_menu: WeakRef = weakref(menu)
	_retired.append(old_menu)
	if not await _press(menu._continue_button, "MainMenu / 繼續遊戲 / " + label):
		return false
	menu = null
	if not await _wait(_world_ready, "actual Main Continue restored pawnshop: " + label):
		return false
	var level := _main._screen as Level
	var position: Array = _saved["runtime"]["position"]
	var expected_position := Vector2(float(position[0]), float(position[1]))
	var live := RunSnapshot.capture(_main._level_path, level.run_snapshot())
	var live_prepared := RunSnapshot.prepare(live)
	if not _check(live_prepared.has("data"), "restored live capture still validates: " + label):
		return false
	var data: Dictionary = live_prepared["data"]
	var encode_saved := RunSaveCodec.encode(_saved)
	var encode_live := RunSaveCodec.encode(data)
	var decoded_saved := RunSaveCodec.decode(encode_saved)
	var decoded_live := RunSaveCodec.decode(encode_live)
	if not _check(decoded_saved.has("data") and decoded_live.has("data"), "real restored and saved projections JSON roundtrip: " + label):
		return false
	var saved_json: Dictionary = decoded_saved["data"]
	var live_json: Dictionary = decoded_live["data"]
	if not _check(old_menu.get_ref() == null and level.player.health.current == int(_saved["runtime"]["health"])
		and level.player.global_position.distance_to(expected_position) <= 2.0
		and live_json["story"] == saved_json["story"] and live_json["progression"] == saved_json["progression"],
		"Continue preserves real position/health/story/custody/progression; old menu freed: " + label):
		return false
	_stage("continue-world", {"label": label, "level": level.get_instance_id(),
		"player": level.player.get_instance_id(), "position": [level.player.global_position.x, level.player.global_position.y]})
	return true


func _shot(kind: String) -> void:
	if not _check(_phase == "record" and _images.size() < 4 and kind in ["menu", "cinematic", "world", "npc"],
			"bounded genuine viewport capture: " + kind):
		return
	await RenderingServer.frame_post_draw
	var valid := _menu_ready() if kind == "menu" else _world_ready() if kind == "world" \
		else Story._layer.is_cinematic_active() and _talks.is_empty() if kind == "npc" \
		else is_instance_valid(Story._player) and Story._current_cinematic == INTRO \
			and _opaque(Story._player._dialogue) and Story._player._dialogue.is_complete()
	if not _check(valid and not Transition.is_active(), "capture still matches actual displayed stage: " + kind):
		return
	var path := _out.path_join("BG31-primary-" + kind + ".png")
	if not _check(not FileAccess.file_exists(path), "capture never overwrites earlier evidence: " + kind):
		return
	var image := Capture.image(get_viewport())
	if not _check(image != null and not image.is_empty() and image.save_png(path) == OK, "full viewport PNG: " + kind):
		return
	_images.append({"kind": kind, "path": path, "sha256": FileAccess.get_sha256(path),
		"width": image.get_width(), "height": image.get_height(), "pid": OS.get_process_id(),
		"process_frame": Engine.get_process_frames()})
	_stage("viewport-captured", {"kind": kind, "path": path})


func _run() -> void:
	_stage("probe-entry", {"phase": _phase, "slot": _slot, "engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(),
		"policy": _policy, "prefetch_sha256": _prefetch_sha})
	if not _check(_prefetch_sha == (OLD_PREFETCH_SHA if _policy == "threaded-native" else NEW_PREFETCH_SHA),
			"declared comparison factor matches exact original/repaired prefetch source"):
		await _finish()
		return
	if not _check(not Story.auto_skip and not Settings.get_skip_cutscenes(), "existing genuine no-skip settings; no toggled Story state"):
		await _finish()
		return
	var store := RunSaveStore.new(_slot)
	store.validator = RunSnapshot.prepare
	if _phase == "record":
		if not _check(not store.exists() and not FileAccess.file_exists(_out.path_join("record-summary.json")),
				"fresh isolated record slot/output; no overwrite or reused evidence"):
			await _finish()
			return
	else:
		var record_text := FileAccess.get_file_as_string(_out.path_join("record-summary.json"))
		var record: Variant = JSON.parse_string(record_text)
		if not _check(record is Dictionary and record.get("failures", -1) == 0
			and record.get("phase") == "record" and record.get("pid") != OS.get_process_id()
			and record.get("tool_sha256") == _tool_sha
			and record.get("policy") == _policy and record.get("prefetch_sha256") == _prefetch_sha
			and record.get("slot") == _slot and not FileAccess.file_exists(_out.path_join("cold-summary.json")),
			"cold uses the genuine successful record from a distinct OS process; fresh cold evidence"):
			await _finish()
			return
		_cold_record = record
		for talk: Variant in record.get("npc_talks", []):
			_talks.append(str(talk))
		_saved = store.read()
		if not _check(not _saved.is_empty() and store.issues.is_empty()
			and FileAccess.get_sha256(_slot) == str(record.get("slot_sha256_after_record", "")),
			"cold genuine slot exact record checksum before actual Main initialization"):
			await _finish()
			return
		for talk: String in _talks:
			if not _check(_saved["story"]["seen"].count(talk) == 1, "cold slot holds the record talk exactly once: " + talk):
				await _finish()
				return
	Story.scene_started.connect(_on_started)
	Story.scene_finished.connect(_on_finished)
	_main = MainScene.instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	_main._run_store = store  # Explicit isolated real store before actual Main._ready.
	add_child(_main)
	if not await _wait(_menu_ready, "real Main initial menu route"):
		await _finish()
		return
	_stage("initial-menu")
	if _phase == "record":
		var menu := _main._screen as MainMenu
		if not _check(not menu.continue_available and not menu.overwrite_required, "fresh loaded Start menu"):
			await _finish()
			return
		if not await _wait(func() -> bool: return _button_ready(menu._start_button), "initial menu animation and visible Start"):
			await _finish()
			return
		await _shot("menu")
		if not await _press(menu._start_button, "MainMenu / 開始任務"):
			await _finish()
			return
		if not _check(menu._difficulty_page.visible and menu._selected != null, "actual loaded difficulty page and default selection"):
			await _finish()
			return
		if not await _press(menu._confirm_button, "difficulty / 出發"):
			await _finish()
			return
		menu = null
		if not await _opening():
			await _finish()
			return
		_stage("initial-world")
		await _shot("world")
	else:
		if not await _continue("cold-first"):
			await _finish()
			return
	if not await _npc_talk(_phase):
		await _finish()
		return
	for round_index in ROUNDS:
		var label := "%s-round-%d" % [_phase, round_index + 1]
		if not await _back_to_menu(label) or not await _continue(label):
			await _finish()
			return
	if not await _back_to_menu(_phase + "-terminal"):
		await _finish()
		return
	_check(_starts == (1 if _phase == "record" else 0) and _finishes == _starts,
		"completed opening never replays across genuine Continue routes")
	_check(_talks.size() == (1 if _phase == "record" else 2),
		"one new talk finished per process; none skipped or replayed")
	for reference: WeakRef in _retired:
		_check(reference.get_ref() == null, "naturally retired screen/actor weak reference released")
	_check_reclaim()
	_check(_images.size() == (4 if _phase == "record" else 0), "exact menu/cinematic/world/npc evidence cap; no cold duplicate captures")
	var prefetch := AssetPrefetch.stats()
	if _policy == "main-thread-rd-472":
		_check(prefetch.get("strategy", -1) == 2 and prefetch.get("main_load_total", 0) > 0
			and prefetch.get("threaded_request_calls", -1) == 0 and prefetch["failed_total"] == 0,
			"real repaired prefetch policy exercised without background requests or failed loads")
	else:
		_check(not prefetch.has("strategy") and prefetch["inflight_limit"] == 4
			and prefetch["requested_total"] > 0 and prefetch["collected_total"] > 0 and prefetch["failed_total"] == 0,
			"exact original four-slot native async policy exercised without failed loads")
	await _finish()


## 每次回到選單都要回到同一個水位：節點數相同、沒有孤兒節點，貼圖與物件不隨輪數累積。
## 物件數容許每輪多出本工具自己保存的弱參照。
func _check_reclaim() -> void:
	var settled: Array[Dictionary] = []
	for event: Dictionary in _events:
		if event["stage"] == "menu-settled":
			settled.append(event)
	if not _check(settled.size() == ROUNDS + 1, "one settled menu record per return"):
		return
	var first := settled[0]
	var last := settled[settled.size() - 1]
	var orphans := 0
	var same_nodes := true
	var texture_min := int(first["render_texture_bytes"])
	var texture_max := texture_min
	for event: Dictionary in settled:
		orphans += int(event["engine_orphan_nodes"])
		same_nodes = same_nodes and event["engine_node_count"] == first["engine_node_count"]
		texture_min = mini(texture_min, int(event["render_texture_bytes"]))
		texture_max = maxi(texture_max, int(event["render_texture_bytes"]))
	_check(same_nodes and orphans == 0, "every return to menu settles at the same node count with no orphan nodes")
	_check(texture_max - texture_min <= RECLAIM_TEXTURE_SLACK_BYTES,
		"renderer texture memory does not grow across repeated returns (spread %d bytes)" % (texture_max - texture_min))
	var growth := int(last["engine_object_count"]) - int(settled[1]["engine_object_count"])
	_check(growth <= (ROUNDS - 1) * RECLAIM_OBJECTS_PER_ROUND,
		"object count does not accumulate across repeated returns (growth %d after warm-up round)" % growth)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_stage("pre-real-main-quit", {"failures": _failures})
	var summary := {"scope": "primary real Main rendering lifecycle; semantic UI, not human/full-chapter/NE246/Source authority proof",
		"phase": _phase, "pid": OS.get_process_id(), "slot": _slot, "checks": _checks,
		"tool_sha256": _tool_sha,
		"policy": _policy, "prefetch_sha256": _prefetch_sha,
		"failures": _failures, "rounds_requested": ROUNDS, "opening_starts": _starts,
		"opening_finishes": _finishes, "complete_authored_lines_accepted": _accept_lines,
		"npc_talks": _talks, "npc_lines_accepted": _talk_lines, "interact_presses": _interact_presses,
		"images": _images, "events": _events, "cold_record_pid": _cold_record.get("pid", 0),
		"slot_sha256_after_record": FileAccess.get_sha256(_slot) if FileAccess.file_exists(_slot) else "",
		"raw_error_gate": "Root wrapper must reject all ERROR/SCRIPT/Parse/Compile output through natural EOF, including real Main quit",
		"memory_scope": "stage engine static bytes, object counts and renderer-reported texture/video bytes; process WorkingSet/Private sampled externally by PID"}
	var summary_path := _out.path_join(_phase + "-summary.json")
	var file: FileAccess = null
	if FileAccess.file_exists(summary_path):
		push_error("[BG31Main] refusing to overwrite existing summary: " + summary_path)
		_failures += 1
	else:
		file = FileAccess.open(summary_path, FileAccess.WRITE)
	if file == null and not FileAccess.file_exists(summary_path):
		push_error("[BG31Main] failed writing summary: " + str(FileAccess.get_open_error()))
		_failures += 1
	elif file != null:
		file.store_string(JSON.stringify(summary, "\t"))
		file.close()
	print("BG31_MAIN_RESULT:", _checks, " checks / ", _failures, " failures / PID ", OS.get_process_id())
	if is_instance_valid(_main):
		await _main._quit(0 if _failures == 0 else 1)
	else:
		get_tree().quit(1)
