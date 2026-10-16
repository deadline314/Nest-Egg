extends Node
## NE-279：隔離存檔的冷啟動回顧與 Forward+ UI 擷取。
## --out=<絕對路徑> --mode=seed/replay/verify/capture --size=1280x720 --text-scale=1.2
## seed 是明示的已看過故事 fixture，不代表正式新遊戲路線驗收。

const FIRST := "res://data/levels/ch1_pawnshop.tres"
const OPENING := &"ch1_p01_door"
var _out := ""
var _mode := "capture"
var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--size="):
			var dims := argument.trim_prefix("--size=").split("x")
			get_window().size = Vector2i(int(dims[0]), int(dims[1]))
			DisplayMode.ensure_scaling(get_window())
		elif argument.begins_with("--text-scale="):
			Settings.use_storage("user://codex-probe-settings.cfg")
			Settings.set_ui_text_scale(float(argument.trim_prefix("--text-scale=")))
	if not _out.is_absolute_path():
		push_error("[CodexReplayProbe] --out 必須是絕對隔離目錄")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	GameState.story_autosave = false
	var store := RunSaveStore.new(_out.path_join("slot.json"))
	store.validator = RunSnapshot.prepare
	if _mode == "seed":
		GameState.start_new_run(GameState.difficulties[1])
		Story._completed[OPENING] = true
		Progression.credits = 137
		var fixture := RunSnapshot.capture(FIRST, {"position": [100, 160], "health": 4, "world": {}, "loadout": {}})
		_check(store.write(fixture, true), "明示的完整存檔 fixture 寫入隔離目錄")
	elif _mode in ["replay", "verify"]:
		var loaded := store.read()
		_check(not loaded.is_empty(), "獨立程序從磁碟讀回完整存檔")
		if loaded.is_empty():
			get_tree().quit(1)
			return
		RunSnapshot.apply(loaded)
		_check(Story.can_replay(OPENING) and Progression.credits == 137, "冷啟動保留本輪回顧解鎖與信用點")
		if _mode == "replay":
			var before := GameState.story_progress_snapshot()
			var economy := Progression.snapshot()
			var bytes := FileAccess.get_file_as_string(store.path)
			var backup_bytes := FileAccess.get_file_as_string(store.path + ".bak") if FileAccess.file_exists(store.path + ".bak") else ""
			var codex := CodexScreen.new()
			add_child(codex)
			await _frames(4)
			codex.select_tab(1)
			await _frames(3)
			await _action(&"ui_accept")
			_check(Story.is_replaying(), "圖鑑確認事件啟動真正回看")
			await _action(&"ui_cancel")
			for i in 600:
				if not Story.is_replaying():
					break
				await _frames(1)
			_check(not Story.is_replaying() and codex.visible, "略過事件返回同一份圖鑑")
			_check(GameState.story_progress_snapshot() == before and Progression.snapshot() == economy, "回看前後所有故事與成長資料完全相同")
			var after_backup := FileAccess.get_file_as_string(store.path + ".bak") if FileAccess.file_exists(store.path + ".bak") else ""
			_check(FileAccess.get_file_as_string(store.path) == bytes and after_backup == backup_bytes, "回看不寫入或旋轉完整存檔與既有備份")
			codex.queue_free()
			await _frames(3)
	elif _mode == "capture":
		await _capture_pages()
	else:
		_check(false, "不支援的 probe 模式")
	await _frames(3)
	get_tree().quit(1 if _failed else 0)


func _capture_pages() -> void:
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	for language in ["zh", "ja", "en"]:
		Story.set_language(language)
		Story.reset_progress()
		var codex := CodexScreen.new()
		add_child(codex)
		await _frames(5)
		codex.select_tab(1)
		await _capture("empty-" + language)
		codex.queue_free()
		await _frames(3)
		for id: StringName in [OPENING, &"ch1_c09_wake", &"ch1_c14_home"]:
			Story._completed[id] = true
		codex = CodexScreen.new()
		add_child(codex)
		await _frames(5)
		codex.select_tab(1)
		await _frames(3)
		for index in codex._replay_page.buttons.size():
			codex._replay_page.buttons[index].grab_focus()
			await _frames(3)
			_check_layout(codex)
			if index == 1:
				await _capture("memories-" + language)
		codex.select_tab(0)
		await _capture("defeats-" + language)
		codex.queue_free()
		await _frames(3)
	# 暫停頁完整顯示；fixture 無關卡，不代表關卡路線驗收。
	var pause := PauseMenu.new()
	add_child(pause)
	pause.open()
	await _capture("pause-entry")
	pause._open_codex()
	await _frames(5)
	pause._codex.select_tab(1)
	await _capture("pause-memories")
	pause._codex._start_replay(OPENING)
	await _frames(8)
	await _capture("pause-replay")
	await _action(&"ui_cancel")
	for i in 600:
		if not Story.is_replaying():
			break
		await _frames(1)
	_check(not Story.is_replaying() and get_tree().paused and pause._codex.visible, "暫停回看結束後維持暫停並還原圖鑑")
	await _capture("pause-return")
	pause.close()
	pause.queue_free()
	await _frames(3)


func _check_layout(root: Control) -> void:
	var codex := root as CodexScreen
	if codex != null:
		var scroll: VScrollBar = codex._replay_page._detail_scroll.get_v_scroll_bar()
		_check(scroll.max_value <= scroll.page + 1.0, "目前三段回顧的名稱與一句說明完整顯示，不必捲動")
	var viewport := root.get_global_rect()
	for control: Control in root.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or not (control is Button or control is Label):
			continue
		var bounds := control.get_global_rect()
		_check(viewport.grow(1).encloses(bounds), "可見文字／按鈕在畫布內：%s" % (control as Variant).text)


func _capture(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	_check(image.save_png(_out.path_join(name + ".png")) == OK, "保存 " + name)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event, true)
	await _frames(2)
	event = event.duplicate() as InputEventAction
	event.pressed = false
	get_viewport().push_input(event, true)
	await _frames(2)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
	print(("PASS: " if condition else "FAIL: ") + message)
