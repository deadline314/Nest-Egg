extends Node
## ST-22 隔離圖證：正式 stall_home 路由；同場景OBJECT／可選電影入口明確標示 synthetic。
const Capture := preload("res://tools/viewport_capture.gd")
const OBJECT_SCENE := &"ch1_t_ali_3"
const ENTRY_SCENE := &"st22_synthetic_choice"
var output := ""
var wide := false
var checks := 0
var failures := 0
var main: Node
var evidence: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg == "--wide":
			wide = true
	var isolated := OS.get_environment("ST22_PROFILE").replace("\\", "/").to_lower().trim_suffix("/")
	var actual := OS.get_user_data_dir().replace("\\", "/").to_lower()
	if isolated.is_empty() or not actual.begins_with(isolated + "/") or not output.is_absolute_path():
		push_error("ST22 requires an isolated APPDATA profile and absolute --out directory.")
		get_tree().quit(2)
		return
	var err := DirAccess.make_dir_recursive_absolute(output)
	if err != OK:
		push_error("ST22 cannot create output directory %s: %s" % [output, error_string(err)])
		get_tree().quit(2)
		return
	Settings.set_ui_text_scale(1.2)
	Settings.set_reduce_ui_motion(false)
	Settings.set_skip_cutscenes(false)
	GameState.story_autosave = false
	Story.auto_skip = true
	Engine.max_fps = 60
	DisplayMode.ensure_scaling(get_tree().root)
	get_tree().root.size = Vector2i(2100, 900) if wide else Vector2i(1600, 900)
	# 單一工具變因：正式KEEP模式之外，用EXPAND使實際viewport成為840×360。
	# 報告明標，不宣稱本票修改了正式視窗策略。
	if wide:
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_run.call_deferred()


func verify(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[ST22 probe] " + text)


func _settled() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not Transition.is_active():
			await get_tree().create_timer(0.2, true, false, true).timeout
			if not Transition.is_active():
				return
	verify(false, "Main transition did not settle")


func _tap_key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().physics_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _interact() -> void:
	await _tap_key(InputBindings.get_code(&"interact", 0))


func _place(level: Level, feet: Vector2) -> void:
	var layout := level.get("_layout") as LevelLayout
	var floor_y := layout.floor_below(int(feet.x / layout.tile_size), int(feet.y / layout.tile_size))
	verify(is_finite(floor_y), "controlled position has a real layout support")
	if not is_finite(floor_y):
		return
	level.player.position = Vector2(feet.x, floor_y - 0.01)
	level.player.velocity = Vector2.ZERO
	for i in 6:
		await get_tree().physics_frame
	level.player.apply_floor_snap()
	verify(level.player.is_on_floor(), "controlled player is grounded before capture")
	level.camera.snap_to_target()
	level.camera.force_update_scroll()


func _shot(stage: String, classification: String) -> void:
	await get_tree().create_timer(0.8, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var file := "ST-22-%s-%s.png" % ["wide" if wide else "16x9", stage]
	var image := Capture.image(get_viewport())
	verify(not image.is_empty() and image.save_png(output.path_join(file)) == OK, "capture written: " + file)
	var safe := Story.framing.safe_rect()
	evidence.append({"file": file, "classification": classification, "viewport": str(get_viewport().get_visible_rect().size),
		"safe_rect": str(safe), "amount": Story.framing.amount, "scopes": Story.framing.scope_count(),
		"context": Story.current_presentation_context(), "request": Story.current_presentation_request(),
		"waiters": Story._waiters.size(), "request_results": Story._request_results.size(), "ui_text_scale": Settings.get_ui_text_scale(),
		"window_aspect": "tool EXPAND" if wide else "formal KEEP"})
	print("ST22_SHOT ", JSON.stringify(evidence.back()))


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await _settled()
	main.call("_on_start_requested", GameState.difficulties[1])
	await _settled()
	GameState.pending_portal = &""
	main.call("_on_area_requested", "res://data/levels/ch1_stall.tres")
	await _settled()
	var level := main.get("_screen") as Level
	verify(level != null and level.data.id == &"ch1_stall", "controlled Main route reaches the formal stall map")
	if level != null:
		await _formal_stall(level)
	Story.reset_active_presentation(&"leave")
	main.queue_free()
	for i in 4:
		await get_tree().process_frame
	var report := FileAccess.open(output.path_join("ST-22-%s-report.json" % ("wide" if wide else "16x9")), FileAccess.WRITE)
	verify(report != null, "report is writable")
	if report != null:
		report.store_string(JSON.stringify({"checks": checks, "failures": failures, "evidence": evidence,
			"scope": "controlled route with synthetic key events; not a human walkthrough"}, "\t"))
		report.close()
	print("ST22_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _formal_stall(level: Level) -> void:
	var portal := level._portals.get(&"stall_home") as Portal
	verify(portal != null, "formal stall_home exists")
	if portal == null:
		return
	Story.auto_skip = false
	await _place(level, portal.position + Vector2(-70, 0))
	verify(not portal.preview_available(), "the original story gate excludes movie preview")
	await _shot("stall-locked", "formal map; controlled placement")
	var ali: NpcActor
	for node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		if level.is_ancestor_of(node) and (node as NpcActor).data.id == &"ch1_ali_stall":
			ali = node as NpcActor
	verify(ali != null, "the formal Ali conversation provider exists")
	if ali == null:
		return
	await _place(level, ali.position + Vector2(-70, 0))
	await _shot("person-approach", "formal PERSON; controlled placement")
	verify(not Story.is_cinematic_active() and not GameState.has_flag(&"knows_ali_address"), "PERSON preview does not grant the door flag")
	await _place(level, ali.position + Vector2(-12, 0))
	await _interact()
	verify(Story.is_cinematic_active() and Story.current_presentation_context().get("framing_source") == "person", "synthetic physical interact starts the formal PERSON conversation")
	await _shot("person-dialogue", "formal PERSON; synthetic key event")
	await _tap_key(KEY_ESCAPE)
	verify(GameState.has_flag(&"knows_ali_address"), "formal conversation completion unlocks the existing door flag")
	await _place(level, portal.position + Vector2(-70, 0))
	await _shot("stall-preview", "formal movie entrance; controlled placement")
	verify(portal.preview_available() and Story.framing.selected_target() == portal and not Story.was_seen(&"ch1_c14_home"), "formal movie preview is eligible without starting the intro")
	await _place(level, portal.position + Vector2(-110, 0))
	await _shot("stall-retreat", "formal movie entrance; controlled retreat")
	verify(is_zero_approx(Story.framing.amount) and not Story.was_seen(&"ch1_c14_home"), "retreat restores framing without marking the home movie seen")
	await _synthetic_sources(level, portal.position + Vector2(-110, 0))
	await _place(level, portal.position + Vector2(-8, 0))
	await _interact()
	await _settled()
	verify(Story._current_cinematic == &"ch1_c14_home", "the actual portal routes to the original home intro")
	await _shot("home-movie", "formal home intro; actual portal route from synthetic key event")
	await _tap_key(KEY_ESCAPE)


func _synthetic_sources(level: Level, feet: Vector2) -> void:
	# 合成OBJECT重用剛才真人物的正式scene，來源資格不能按scene ID猜測。
	var talk := NpcTalk.new()
	talk.scene = OBJECT_SCENE
	var data := NpcData.new()
	data.id = &"st22_synthetic_object"
	data.display_name = "合成閱讀物件"
	data.kind = NpcData.Kind.OBJECT
	data.talks = [talk]
	var object := NpcActor.new()
	object.configure(data, Vector2i(0, 0))
	level.add_child(object)
	object.position = feet
	await _place(level, feet + Vector2(-8, 0))
	await _interact()
	verify(Story.current_presentation_context().get("framing_source") == "object" and Story.framing.scope_count() == 0, "synthetic OBJECT is readable without a formal framing scope")
	await _shot("synthetic-object", "synthetic OBJECT fixture in formal map")
	await _tap_key(KEY_ESCAPE)
	object.queue_free()
	Story._scenes[String(ENTRY_SCENE)] = {"mode": "animated", "steps": [
		{"do": "scene", "id": "old_k_shop", "fade": 0.0},
		{"do": "choice", "text": "這是合成電影入口，請選擇接下來的方向。", "default": "stay", "options": [
			{"id": "stay", "text": "先留在這裡。"}, {"id": "go", "text": "前往下一個房間。"}]}]}
	var entry_data := CinematicEntryData.new()
	entry_data.id = &"st22_synthetic_entry"
	entry_data.scene = ENTRY_SCENE
	var entry := CinematicEntrance.new()
	entry.configure(entry_data)
	level.add_child(entry)
	entry.position = feet
	await _place(level, feet + Vector2(-8, 0))
	await _interact()
	for i in 60:
		if is_instance_valid(Story._player) and Story._player.choice_active():
			break
		await get_tree().process_frame
	verify(is_instance_valid(Story._player) and Story._player.choice_active(), "synthetic movie entrance reaches its actual choice UI")
	await _shot("synthetic-choice", "synthetic explicit movie entry and choice")
	await _tap_key(KEY_ESCAPE)
	entry.queue_free()
	Story._scenes.erase(String(ENTRY_SCENE))
