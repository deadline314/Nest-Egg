extends Node
## 受控第一章 HUD 與合成輸入驗證，使用私有玩家資料目錄。
const Capture := preload("res://tools/viewport_capture.gd")
var _out := ""
var _width := 1280
var _height := 720
var _checks := 0
var _failures := 0
var _rows: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var profile := OS.get_environment("NE228_HUD_PROFILE").replace("\\", "/").simplify_path().to_lower().trim_suffix("/")
	var actual := OS.get_user_data_dir().replace("\\", "/").simplify_path().to_lower()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--width="): _width = int(arg.trim_prefix("--width="))
		elif arg.begins_with("--height="): _height = int(arg.trim_prefix("--height="))
	if profile.is_empty() or not actual.begins_with(profile + "/") or not _out.is_absolute_path():
		printerr("NE228 HUD capture requires isolated APPDATA and absolute output directory")
		get_tree().quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		printerr("NE228 HUD capture cannot create output directory: ", _out)
		get_tree().quit(2)
		return
	get_window().size = Vector2i(_width, _height)
	DisplayMode.ensure_scaling(get_window())
	_run.call_deferred()


func _run() -> void:
	Settings.use_storage("user://hud-guidance.cfg")
	Settings.set_ui_text_scale(1.0)
	Settings.set_reduce_ui_motion(false)
	GameState.story_autosave = false
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	add_child(LightKit.create_environment())
	var data := (load("res://data/levels/ch1_street.tres") as LevelData).duplicate(true) as LevelData
	data.intro_scene = &""
	for i in data.story_triggers.size():
		data.story_triggers[i] = ""
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _frames(30)
	var floor_y := level._layout.floor_below(int(level.player.position.x / level._layout.tile_size), int(level.player.position.y / level._layout.tile_size))
	_check(is_finite(floor_y), "actual street spawn has support")
	if is_finite(floor_y):
		level.player.position.y = floor_y - 0.01
		level.player.velocity = Vector2.ZERO
		await get_tree().physics_frame
		level.player.apply_floor_snap()
	_check(level.player.is_on_floor(), "player feet contact actual support")
	level.player.set_physics_process(false)
	level.camera.snap_to_target()
	level.camera.force_update_scroll()
	var hud := level.hud
	var cue_owner := Node.new()
	level.add_child(cue_owner)
	# Synthetic UI cue only: no mounted training object or gameplay-success claim.
	hud.show_context_hint(cue_owner, "跨過矮牆。 {jump}", 15.0)
	var initial_key := InputEventKey.new()
	initial_key.physical_keycode = KEY_A
	initial_key.pressed = true
	InputBindings.observe_device(initial_key)
	await _capture("keyboard", hud)
	Settings.set_ui_text_scale(1.2)
	await _capture("large-text", hud)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	InputBindings.observe_device(button)
	_check((hud._hint_caps[0].get_child(0) as Label).text == InputBindings.joy_label(&"jump") and not hud._controls.text.contains("{jump}"), "controller keycap follows recent input")
	await _capture("gamepad-synthetic", hud)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	InputBindings.observe_device(key)
	InputBindings.set_code(&"jump", 0, KEY_V)
	_check((hud._hint_caps[0].get_child(0) as Label).text == "V", "rebound keyboard keycap refreshes")
	_check(Hud.controls_hint().contains(InputBindings.format("{reload}")) and Hud.controls_hint().contains(InputBindings.format("{inventory}")), "pause reference retains full controls")
	var remaining := hud._controls_read_time
	var lock := GameplayLock.acquire(self)
	await _frames(8)
	_check(not hud._controls_card.visible, "cinematic lock immediately hides guidance")
	_check(is_equal_approx(hud._controls_read_time, remaining), "cinematic lock preserves reading time")
	GameplayLock.release(lock)
	await _frames(2)
	_check(hud._controls_card.visible, "guidance returns after lock release")
	Settings.set_reduce_ui_motion(true)
	hud._dismiss_controls()
	await _frames(4)
	_check(not hud._controls_card.visible and hud._controls_card.modulate.a == 0.0, "reduced motion dismisses panel and stays hidden")
	Settings.set_reduce_ui_motion(false)
	hud._controls_card.modulate.a = 1.0
	hud._controls_card.show()
	hud._dismiss_controls()
	await get_tree().create_timer(1.2, true, false, true).timeout
	_check(hud._controls_card.modulate.a < 0.01, "normal fade removes the entire panel")
	print("NE228_HUD_RENDERER ", RenderingServer.get_current_rendering_method(), " | ", RenderingServer.get_video_adapter_name())
	var file := FileAccess.open(_out.path_join("NE-228-hud-%d.json" % _width), FileAccess.WRITE)
	_check(file != null, "layout report opens")
	if file != null:
		var report := {"checks": _checks, "failures": _failures, "resolution": [_width, _height], "controlled_scene": "ch1_street; intro and triggers disabled only in capture copy; isolated synthetic HUD cue is not a training outcome", "physical_controller": false, "layouts": _rows}
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	level.queue_free()
	await _frames(3)
	print("NE228_HUD_RESULT ", _checks, " checks, ", _failures, " failures")
	get_tree().quit(0 if _failures == 0 else 1)


func _capture(tag: String, hud: Hud) -> void:
	await _frames(6)
	var card := hud._controls_card.get_global_rect()
	var label := hud._controls.get_global_rect()
	var screen := get_viewport().get_visible_rect()
	var weapon := hud.weapon_bar.get_global_rect()
	_check(screen.encloses(card), tag + " panel fits viewport")
	_check(card.encloses(label), tag + " text fits panel")
	_check(hud._controls.size.y >= hud._controls.get_minimum_size().y, tag + " text lines are not clipped")
	_check(not card.intersects(weapon), tag + " panel avoids weapon slots")
	_rows.append({"tag": tag, "panel": [card.position.x, card.position.y, card.size.x, card.size.y], "text_lines": hud._controls.get_line_count(), "text": hud._controls.text})
	await RenderingServer.frame_post_draw
	var path := _out.path_join("NE-228-hud-%d-%s.png" % [_width, tag])
	_check(Capture.image(get_viewport()).save_png(path) == OK, tag + " real Forward+ image saved")


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("[NE228 HUD] " + message)
