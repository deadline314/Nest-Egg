extends Node
## 序章跨程序續玩與長按略過探針（ST-16）：每一種情境都在獨立的程序裡從真正的 Main 進入，存檔放在 --save-dir。
## 用法：godot --path . res://tools/prologue_resume_probe.tscn -- --mode=<模式> --save-dir=<絕對路徑> [--out=<截圖資料夾>]
##   continue-mid：上一個程序（prologue_play_probe --stop-after=ch1_prologue_jump_done）練到一半退出；
##                 這裡按「繼續遊戲」，要回到序章、保留已做完的練習、不重播開場、沒有死亡。
##   continue-done：上一個程序玩完序章進到當舖；這裡繼續要直接回當舖，序章的演出一段都不重播。
##   skip：新遊戲進序章後，用手把打開暫停選單、長按「略過序章」，要直接回當舖並拿到第一章的目標；
##         只記略過與出口，不把沒做過的練習標成完成；接著正常退出（會存檔）。
##   continue-skip：接在 skip 之後的另一個程序；繼續要回當舖，不重播序章、練習旗標仍是空的。

const PROLOGUE := "res://data/levels/ch1_prologue.tres"
const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const PRACTICE_FLAGS: Array[StringName] = [&"ch1_prologue_bench_done", &"ch1_prologue_jump_done", &"ch1_prologue_shot_done",
		&"ch1_prologue_melee_done", &"ch1_prologue_guard_done", &"ch1_prologue_dash_done"]
const LIMIT_MSEC := 120000

var _mode := ""
var _save_dir := ""
var _out := ""
var _main: Node
var _failures := 0
var _played: Array[StringName] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _mode not in ["continue-mid", "continue-done", "skip", "continue-skip"] or not _save_dir.is_absolute_path():
		push_error("[PrologueResumeProbe] 需要 --mode=continue-mid|continue-done|skip|continue-skip 與絕對路徑 --save-dir")
		get_tree().quit(2)
		return
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(4)
	var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
	print("saved %s (%s)" % [name, error_string(image.save_png(_out.path_join(name + ".png")))])


func _level() -> Level:
	var screen: Variant = _main.get("_screen")
	return screen as Level if screen is Level else null


func _wait_level(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		var level := _level()
		if level != null and level.data.resource_path == path and level.player != null:
			return true
		await _frames(1)
	return false


func _joy(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _prologue_scenes_played() -> Array[StringName]:
	return _played.filter(func(id: StringName) -> bool: return String(id).begins_with("ch1_p0"))


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
	print("PROLOGUE_RESUME_PROBE mode=%s failures=%d" % [_mode, _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)


func _continue() -> void:
	var data: Dictionary = (_main.get("_run_store") as RunSaveStore).read()
	_check(not data.is_empty(), "the previous process left a readable save")
	# 主選單的「繼續遊戲」按鈕走的就是這個入口。
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline and bool(_main.call("_route_pending")):
		await _frames(10)
	_main.call("_on_continue_requested")
	var expected := PROLOGUE if _mode == "continue-mid" else PAWNSHOP
	_check(await _wait_level(expected), "continue lands in %s" % expected.get_file())
	await _frames(120)
	await _shot("ST-16-resume-%s" % _mode)
	_check(_prologue_scenes_played().is_empty(), "continue never replays a prologue scene (played %s)" % [_played])
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"), "no death or first registration was spent")
	match _mode:
		"continue-mid":
			_check(GameState.has_flag(&"ch1_prologue_bench_done") and GameState.has_flag(&"ch1_prologue_jump_done"), "the practice done before quitting is still done")
			_check(not GameState.has_flag(&"ch1_prologue_shot_done") and not GameState.has_flag(&"ch1_prologue_exit"), "practice not yet done stays open")
			var range_station := _station(&"ch1_training_range")
			_check(range_station != null and range_station.is_active(), "the next practice station is waiting for the player")
			_check(not GameplayLock.is_locked() and not Story.is_cinematic_active(), "control is back with the player")
		"continue-done":
			_check(GameState.has_flag(&"ch1_prologue_exit") and not GameState.has_flag(&"ch1_prologue_skipped"), "the completed prologue is remembered as completed")
			_check(PRACTICE_FLAGS.all(func(flag: StringName) -> bool: return GameState.has_flag(flag)), "every practice stays done")
			_check(_has_first_goal(), "the first chapter goal is on the quest list")
		"continue-skip":
			_check(GameState.has_flag(&"ch1_prologue_skipped") and GameState.has_flag(&"ch1_prologue_exit"), "the skip is remembered")
			_check(PRACTICE_FLAGS.all(func(flag: StringName) -> bool: return not GameState.has_flag(flag)), "skipping never marks a practice as done")
			_check(_has_first_goal(), "the first chapter goal is on the quest list")


func _skip() -> void:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var started := false
	while Time.get_ticks_msec() < deadline and _level() == null:
		if not started and not bool(_main.call("_route_pending")):
			_main.call("_on_start_requested", GameState.difficulties[1])
			started = _main.get("_active_run")
		await _frames(30)
	_check(await _wait_level(PROLOGUE), "a new game from Main enters the prologue")
	# 開場演出讀完（略過鍵），等到操作交回玩家。
	for i in 2400:
		if not Story.is_cinematic_active() and not GameplayLock.is_locked() and i > 60:
			break
		if Story.is_cinematic_active():
			Story.skip_cinematic()
		await _frames(6)
	# 拿起手把按 Start（暫停）：提示與選單改用手把，暫停選單打開。
	_joy(JOY_BUTTON_START, true)
	await _frames(2)
	_joy(JOY_BUTTON_START, false)
	await _frames(40)
	var menu: PauseMenu = _level()._pause_menu if _level() != null else null
	_check(menu != null and menu._root.visible and is_instance_valid(menu._skip_button), "the pause menu offers the prologue skip")
	if menu == null or not is_instance_valid(menu._skip_button):
		return
	menu._skip_button.grab_focus()
	await _frames(4)
	# 長按確認鍵（手把 A）一秒多：不經過確認視窗，直接略過。
	_joy(JOY_BUTTON_A, true)
	for i in 30:
		await _frames(1)
	await _shot("ST-16-skip-hold-pad")
	for i in 60:
		await _frames(1)
	var confirm_opened := is_instance_valid(menu) and is_instance_valid(menu._skip_confirm)
	_joy(JOY_BUTTON_A, false)
	_check(not confirm_opened, "a long press skips without the confirmation dialog")
	_check(await _wait_level(PAWNSHOP), "the long-press skip lands in the pawnshop")
	await _frames(150)
	await _shot("ST-16-skip-arrival")
	_check(GameState.has_flag(&"ch1_prologue_skipped") and GameState.has_flag(&"ch1_prologue_exit"), "the skip records only the skip and the exit")
	_check(PRACTICE_FLAGS.all(func(flag: StringName) -> bool: return not GameState.has_flag(flag)), "skipping never marks a practice as done")
	_check(GameState.deaths == 0 and not GameState.has_flag(&"ch1_first_death_done"), "skipping spends no death")
	_check(_has_first_goal(), "the first chapter goal is on the quest list right after the skip")


func _station(id: StringName) -> TrainingStation:
	var level := _level()
	if level == null:
		return null
	for node in level.find_children("*", "TrainingStation", true, false):
		if (node as TrainingStation).data.id == id:
			return node
	return null


## 第一章的第一個主線目標（上屋頂找鷺）在任務清單的第一位：讀的是地圖與任務頁用的同一份任務資料與目前的旗標。
func _has_first_goal() -> bool:
	var catalog := QuestCatalog.new()
	catalog.load_story_sources()
	var main_quests := catalog.list_for("ch1_kasa", "main", false, GameState.world_flags)
	print("MAIN_QUESTS %s" % [main_quests.map(func(q: Dictionary) -> String: return str(q.get("id", "")))])
	return not main_quests.is_empty() and main_quests[0]["id"] == "ch1_meet_egret"
