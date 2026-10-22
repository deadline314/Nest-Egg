extends Node
## NE-223：導覽狀態（釘選、探索、目標列）的跨程序驗收。每個模式都是獨立的程序，從真正的 Main 進入，存檔放在 --save-dir。
## 用法：godot --headless --path . res://tools/quest_resume_probe.tscn -- --mode=write|continue|corrupt --save-dir=<絕對路徑>
##   write：新遊戲 → 釘選一項支線 → 走到當舖 → 死一次再重來 → 換到第二章當舖；每一步都核對釘選與已探索的格子沒有掉，
##          最後像玩家一樣退出（會存檔），並把核對用的數字寫到 --save-dir/expect.json。
##   continue：另一個程序按「繼續遊戲」，釘選、兩章的探索格數與目標列都和退出前一致。
##   corrupt：先把存檔裡的導覽資料改壞（找不到的任務、不存在的區域、超出地圖的格子），重新簽章後再按「繼續遊戲」：
##          遊戲不崩潰，警告寫出具體欄位，有效的探索保留，釘選退回追蹤主線。
## 結束時印出 QUEST_RESUME 開頭的摘要；有任何一項不符就以非零狀態結束。只讀故事資料，不改任務或旗標定義。

const LIMIT_MSEC := 120000
const PIN := "sq8_ch1_labels"
## 讓支線公開的旗標（故事資料裡的 visible_flags），只寫本輪記憶體。
const PIN_VISIBLE_FLAG := &"ch1_labels_started"
const PROLOGUE := "res://data/levels/ch1_prologue.tres"
const PAWNSHOP := "res://data/levels/ch1_pawnshop.tres"
const CH2_PAWNSHOP := "res://data/levels/ch2_pawnshop.tres"
const BOGUS_AREA := "res://data/levels/no_such_area.tres"

var _mode := ""
var _save_dir := ""
var _main: Node
var _failures := 0
## 每個模式走到最後才設定；中途因腳本錯誤中斷的協程不能算通過。
var _completed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
	if _mode not in ["write", "continue", "corrupt"] or not _save_dir.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_save_dir) != OK:
		push_error("[QuestResumeProbe] 需要 --mode=write|continue|corrupt 與可寫入的絕對路徑 --save-dir")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	if _mode == "corrupt" and not _corrupt_save():
		print("QUEST_RESUME mode=corrupt failures=1")
		get_tree().quit(1)
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# The observer runs while paused; its game must retain the normal root policy.
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	_main.set("_run_store", RunSaveStore.new(_save_dir.path_join("slot.json")))
	add_child(_main)
	await _settle(30)
	match _mode:
		"write":
			await _write()
		"continue":
			await _continue()
		"corrupt":
			await _continue_corrupt()
	_check(_completed, "the %s mode ran to the end" % _mode)
	print("QUEST_RESUME mode=%s failures=%d" % [_mode, _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)


func _write() -> void:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var started := false
	while Time.get_ticks_msec() < deadline and _level() == null:
		if not started and not bool(_main.call("_route_pending")):
			_main.call("_on_start_requested", GameState.difficulties[1])
			started = true
		await _settle(30)
	_check(_level() != null and _level().data.resource_path == PROLOGUE, "a new game from Main enters the prologue")
	await _skip_cinematics()
	var nav := QuestMapState.for_run()
	_check(nav.pinned_id.is_empty() and _objective() != "", "a new game tracks the main quest with a non-empty objective (%s)" % _objective())
	GameState.set_flag(PIN_VISIBLE_FLAG)
	nav.pin(PIN, _guidance().catalog)
	await _settle(20)
	_check(nav.pinned_id == PIN and _guidance().state == nav, "pinning a visible side quest is stored in the run's navigation")
	var pinned_goal := _objective()
	_check(not pinned_goal.is_empty(), "the objective row follows the pinned side quest (%s)" % pinned_goal)
	var prologue_cells := _explored(PROLOGUE)
	_check(prologue_cells > 0, "standing in the prologue reveals cells (%d)" % prologue_cells)
	await _enter(PAWNSHOP)
	var pawn_cells := _explored(PAWNSHOP)
	_check(pawn_cells > 0 and nav.pinned_id == PIN, "entering the pawnshop reveals cells (%d) and keeps the pin" % pawn_cells)
	# 在當舖死一次（序章的倒地是練習，不算死亡）。
	var dead := _level()
	var dead_id := dead.get_instance_id()
	var lethal := DamageInfo.create(9999, Combat.Team.ENEMY, &"probe")
	lethal.ignore_invulnerability = true
	dead.player.health.take_damage(lethal)
	# 第一次死亡是劇情的診間過場（不經死亡畫面，播完直接重生）；之後才是死亡畫面的「立即再挑戰」。兩條都接受。
	var death_deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var retried := false
	while Time.get_ticks_msec() < death_deadline and _level() != null and _level().get_instance_id() == dead_id:
		var screen := _death_screen()
		if screen != null and not retried:
			await _settle(30)
			screen.retry_requested.emit()
			retried = true
		elif Story.is_cinematic_active():
			Story.skip_cinematic()
		await _settle(4)
	_check(GameState.deaths == 1, "the death is counted once (%d)" % GameState.deaths)
	_check(await _wait_level("", dead_id), "dying and retrying reloads an area")
	await _skip_cinematics()
	nav = QuestMapState.for_run()
	_check(nav.pinned_id == PIN, "the pin survives death and retry (%s)" % nav.pinned_id)
	_check(_explored(PROLOGUE) >= prologue_cells and _explored(PAWNSHOP) >= pawn_cells, "explored cells survive death and retry (prologue %d → %d, pawnshop %d → %d)" % [prologue_cells, _explored(PROLOGUE), pawn_cells, _explored(PAWNSHOP)])
	# 章節切換：同一輪進第二章，第一章的探索與釘選仍在。
	await _enter(CH2_PAWNSHOP)
	nav = QuestMapState.for_run()
	_check(_explored(PROLOGUE) >= prologue_cells and _explored(PAWNSHOP) >= pawn_cells, "chapter 1 exploration survives the chapter switch")
	_check(nav.pinned_id == PIN, "the pin is kept across the chapter switch")
	_check(_objective() != "", "chapter 2 shows a non-empty objective after the switch (%s)" % _objective())
	await _settle(30)
	var expect := {"pinned_id": nav.pinned_id, "level": CH2_PAWNSHOP, "explored": {PROLOGUE: _explored(PROLOGUE), PAWNSHOP: _explored(PAWNSHOP), CH2_PAWNSHOP: _explored(CH2_PAWNSHOP)}, "objective": _objective()}
	var file := FileAccess.open(_save_dir.path_join("expect.json"), FileAccess.WRITE)
	_check(file != null, "expect.json is writable")
	if file != null:
		file.store_string(JSON.stringify(expect, "\t"))
		file.close()
	print("QUEST_RESUME_WRITE %s" % JSON.stringify(expect))
	_completed = true


func _continue() -> void:
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_dir.path_join("expect.json")))
	_check(expect is Dictionary, "the write process left expect.json")
	if not expect is Dictionary:
		return
	await _press_continue(str(expect["level"]))
	var nav := QuestMapState.for_run()
	_check(nav.issues.is_empty(), "the saved navigation restores without warnings (%s)" % [nav.issues])
	_check(nav.pinned_id == str(expect["pinned_id"]), "the pin comes back after a real restart (%s)" % nav.pinned_id)
	for path: String in expect["explored"]:
		_check(_explored(path) >= int(expect["explored"][path]), "explored cells of %s come back (%d of %d)" % [path.get_file(), _explored(path), int(expect["explored"][path])])
	_check(_objective() == str(expect["objective"]), "the objective row matches the one before quitting (%s)" % _objective())
	_completed = true


func _continue_corrupt() -> void:
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_dir.path_join("expect.json")))
	await _press_continue(str(expect["level"]) if expect is Dictionary else "")
	var nav := QuestMapState.for_run()
	var text := "\n".join(nav.issues)
	_check(text.contains("navigation.pinned_id"), "the warning names navigation.pinned_id")
	_check(text.contains("navigation.explored.%s" % BOGUS_AREA), "the warning names the bogus area")
	_check(text.contains("navigation.explored.%s.999999,-3" % PROLOGUE), "the warning names the out-of-map cell")
	_check(nav.pinned_id.is_empty(), "an unknown pin falls back to tracking the main quest")
	_check(not nav.explored.has(BOGUS_AREA) and _explored(PROLOGUE) > 0, "valid exploration is kept and the bogus area is dropped")
	_check(_objective() != "", "the objective row still shows the main quest (%s)" % _objective())
	_completed = true


## 把存檔的導覽欄位改壞，再用同一套編碼重新簽章，讓讀檔走到導覽的還原而不是整份被拒。
func _corrupt_save() -> bool:
	var path := _save_dir.path_join("slot.json")
	var decoded := RunSaveCodec.decode(FileAccess.get_file_as_string(path))
	if not decoded.has("data"):
		push_error("[QuestResumeProbe] %s 讀不出存檔（%s）；先跑 --mode=write。" % [path, decoded.get("error", "")])
		return false
	var data: Dictionary = decoded["data"]
	var nav: Dictionary = data.get("navigation", {})
	nav["pinned_id"] = "no_such_quest"
	var explored: Dictionary = nav.get("explored", {})
	explored[BOGUS_AREA] = {"1,1": true}
	if explored.has(PROLOGUE):
		explored[PROLOGUE]["999999,-3"] = true
	nav["explored"] = explored
	data["navigation"] = nav
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[QuestResumeProbe] 無法寫入 %s" % path)
		return false
	file.store_string(RunSaveCodec.encode(data))
	file.close()
	return true


func _press_continue(level_path: String) -> void:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline and bool(_main.call("_route_pending")):
		await _settle(10)
	_main.call("_on_continue_requested")
	_check(await _wait_level(level_path), "continue lands in the saved area %s" % level_path.get_file())
	await _skip_cinematics()
	await _settle(60)


func _enter(path: String) -> void:
	var current := _level()
	var current_id := current.get_instance_id() if current != null else 0
	GameState.pending_portal = &""
	_main.call("_on_area_requested", path)
	_check(await _wait_level(path, current_id), "Main routes into %s" % path.get_file())
	await _skip_cinematics()
	await _settle(40)


func _skip_cinematics() -> void:
	for i in 60:
		if not Story.is_cinematic_active():
			return
		Story.skip_cinematic()
		await _settle(4)


## other_id：要等到換掉的那一個關卡（用 instance id，舊關卡可能已經釋放）。
func _wait_level(path: String, other_id := 0) -> bool:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		var level := _level()
		if level != null and level.get_instance_id() != other_id and (path.is_empty() or level.data.resource_path == path) and level.player != null and level.is_inside_tree():
			return true
		await _settle(1)
	return false


func _level() -> Level:
	var screen: Variant = _main.get("_screen") if is_instance_valid(_main) else null
	return screen as Level if screen is Level else null


func _guidance() -> QuestGuidance:
	var level := _level()
	return level.hud.quest_guidance if level != null and level.hud != null else null


func _objective() -> String:
	var guidance := _guidance()
	if guidance == null:
		return ""
	var label: Label = guidance.get("_label")
	return label.text if label != null else ""


func _explored(path: String) -> int:
	return (QuestMapState.for_run().explored.get(path, {}) as Dictionary).size()


func _death_screen() -> DeathScreen:
	var level := _level()
	if level == null:
		return null
	for node in level.find_children("*", "DeathScreen", true, false):
		return node as DeathScreen
	return null


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
