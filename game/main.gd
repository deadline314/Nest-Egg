extends Node
## 遊戲進入點與畫面路由：主選單 → 關卡 → 過關畫面。
## 同一時間只存在一個畫面；切換時舊畫面完整釋放，避免記憶體累積。

## 新遊戲的第一個區域的預設值；實際起點以 data/release/campaign.json 為準（CampaignEdition.first_level）。
## 舊的雨夜關卡在 data/levels/level_01.tres 保留給既有測試與開發用，只有開發版可進入。
const FIRST_LEVEL := CampaignEdition.DEFAULT_FIRST_LEVEL
const RETRY_CAPTION := "NEST 回溯紀錄 #%d"
const RETRY_HOLD := 0.22

var _result_completion: Node
var _story_completion: Node
## Existing native probes still use the original radio owner name.
var _radio_completion: Node:
	get:
		return _story_completion
var _screen: Node
## 目前這一關的資料路徑（重試會重載同一關；通關後依 LevelData.next_level 接續）。
var _level_path := FIRST_LEVEL
var _run_store := RunSaveStore.new()
var _active_run := false
var _save_queued := false
var _continue_data: Dictionary = {}
## 本版本還沒有存檔時，可接續的較舊累積版本存檔路徑（只讀，之後寫進本版本自己的槽）。
var _import_path := ""
var _resume_runtime: Dictionary = {}
var _cinematic := ""
var _cinematic_entry: Dictionary = {}
var _cinematic_context: Dictionary = {}
var _cinematic_request := 0
var _chapter_complete := false
var _navigation: QuestMapState
var _runtime_save_queued := false
var _pending_screen: Node
var _quitting := false
var _destination_pending := false
var _restore_publish_pending := false
var _publishing_restore := false
var _destination_save_prompt: Control
var _destination_retry: Callable
var _destination_save_lock := 0


func _ready() -> void:
	# 發行檢查：`<執行檔> --headless -- --edition-info` 印出這份程式收錄的章節與章末後結束，不開主選單、不碰存檔。
	if OS.get_cmdline_user_args().has("--edition-info"):
		print("EDITION_INFO ", JSON.stringify(CampaignEdition.current().scope_report()))
		get_tree().quit()
		return
	get_tree().auto_accept_quit = false
	_story_completion = preload("res://game/story_flag_completion.gd").new()
	_story_completion.main = self
	add_child(_story_completion)
	_result_completion = preload("res://game/story_result_completion.gd").new()
	_result_completion.main = self
	add_child(_result_completion)
	_run_store.validator = RunSnapshot.prepare
	GameState.run_save_requested.connect(_queue_save)
	Progression.credits_changed.connect(func(_value: int, _delta: int) -> void: _queue_save())
	Progression.upgrades_changed.connect(_queue_save)
	Progression.abilities_changed.connect(_queue_save)
	Progression.pawned_changed.connect(_queue_save)
	EventBus.mechanism_toggled.connect(func(_id: StringName, _active: bool) -> void: _queue_save())
	EventBus.player_health_changed.connect(func(_value: int, _max: int) -> void: _queue_runtime_save())
	EventBus.player_loadout_changed.connect(func(_loadout: Loadout) -> void: _queue_runtime_save())
	EventBus.player_consumables_changed.connect(func(_bag: ConsumableBag) -> void: _queue_save())
	EventBus.enemy_killed.connect(func(_id: StringName, _finisher: bool) -> void: _queue_save())
	Story.scene_started.connect(_on_scene_started)
	Story.scene_finished.connect(_on_scene_finished)
	Story.presentation_cancelled.connect(_on_presentation_cancelled)
	add_child(LightKit.create_environment())
	_show_main_menu()


## 換畫面：用轉場蓋住 → 釋放舊畫面並加入新畫面 → 揭開。
func _switch_to(screen: Node, kind := Transition.Kind.FADE, center := Vector2(0.5, 0.5),
		caption := "", hold := 0.0) -> void:
	_pending_screen = screen
	await Transition.play(kind, _swap_screen.bind(screen), -1.0, center, caption, hold)


func _swap_screen(screen: Node) -> void:
	_pending_screen = null
	_destination_pending = false
	if is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
	GameplayLock.set_base_paused(false)
	Fx.reset_time()
	_screen = screen
	add_child(screen)
	if screen is Level and not screen.is_initialized():
		_restore_publish_pending = false
		return  # Failed initialization emits menu_requested; never publish or save its partial scene.
	# Level._ready 已裝齊玩家、世界及續玩資料，通知才可離開 Main。
	if _restore_publish_pending:
		_restore_publish_pending = false
		_publishing_restore = true
		RunSnapshot.publish_restored()
		_publishing_restore = false
	_queue_save()


func _show_main_menu() -> void:
	if _route_pending():
		return
	_save_run()
	_active_run = false
	Story.reset_active_presentation(&"menu")
	var lineage := _read_continue()
	_continue_data = lineage.get("data", {})
	# 在主選單的時候，背景先把新遊戲第一個區域與開場過場的貼圖載進來。
	var first_path := CampaignEdition.current().first_level
	AssetPrefetch.warm_level(first_path)
	var first := load(first_path) as LevelData if ResourceLoader.exists(first_path) else null
	if first != null:
		AssetPrefetch.request(AssetPrefetch.scene_texture_paths(first.intro_scene))
	var menu := MainMenu.new()
	menu.continue_available = not _continue_data.is_empty()
	menu.overwrite_required = _run_store.exists()
	menu.save_notice = _save_notice(lineage)
	for issue in _run_store.issues:
		push_warning("[RunSave] %s" % issue)
	menu.continue_requested.connect(_on_continue_requested, CONNECT_DEFERRED)
	menu.start_requested.connect(_on_start_requested, CONNECT_DEFERRED)
	menu.quit_requested.connect(_quit, CONNECT_DEFERRED)
	_switch_to(menu, Transition.Kind.SCAN)


## 本版本自己的存檔優先；沒有時才找較舊累積版本的存檔接續（原檔保留）。
func _read_continue() -> Dictionary:
	_import_path = ""
	var data := _run_store.read()
	if not data.is_empty() or _run_store.exists():
		return {"data": data}
	var other := _run_store.find_other_editions(CampaignEdition.current())
	if other.has("data"):
		_import_path = other["path"]
	return other


## 主選單上的一句存檔說明：先講可以做什麼，再講原因；沒有異狀時不顯示。
func _save_notice(lineage: Dictionary) -> String:
	var notices: Array = _continue_data.get("notices", [])
	if _run_store.unknown_version:
		var detail := _run_store.player_issue()
		return detail if detail.contains("版本") else "存檔版本較新，請更新遊戲或明確覆寫。"
	if not _import_path.is_empty():
		return "可接續「%s」的進度，原存檔不會被修改。" % (lineage["edition"] as CampaignEdition).title()
	if lineage.has("newer"):
		return "找到「%s」的存檔，請用該版本繼續；那份存檔不受影響。" % (lineage["newer"] as CampaignEdition).title()
	if not _run_store.issues.is_empty():
		if _continue_data.is_empty():
			return "存檔讀取失敗（%s），原檔已保留；可開始新遊戲。" % _run_store.player_issue()
		return "已從備份恢復進度，可以繼續遊戲。"
	if not notices.is_empty():
		return notices[0]
	if _continue_data.is_empty() and FileAccess.file_exists(GameState.STORY_SAVE_PATH):
		return "舊版只保存故事，無法繼續整輪；可開始新遊戲，原故事檔會保留。"
	return ""


func _on_start_requested(difficulty: DifficultyData) -> void:
	if _route_pending():
		return
	_active_run = false
	GameState.story_autosave = false
	GameState.start_new_run(difficulty)
	_clear_cinematic()
	_resume_runtime = {}
	_chapter_complete = false
	_level_path = CampaignEdition.current().first_level
	_active_run = true
	_bind_navigation()
	# 選單已明確確認覆寫；新輪先落起點，載入失敗不復活舊輪。
	if not _run_store.write(RunSnapshot.capture(_level_path, {"loadout": {}, "world": {}, "position": [-1, -1], "health": difficulty.player_max_health}), true):
		EventBus.toast_requested.emit("新遊戲尚未保存，原檔已保留；會再嘗試保存。")
	_load_level(Transition.Kind.SCAN)


func _on_continue_requested() -> void:
	if _route_pending():
		return
	var data: Dictionary = _read_continue().get("data", {})
	if data.is_empty():
		_show_main_menu()
		return
	if not _import_path.is_empty():
		push_warning("[RunSave] 從其他累積版本接續：%s；原檔不修改，之後保存到 %s" % [_import_path, _run_store.path])
	_active_run = false
	_restore_publish_pending = true
	RunSnapshot.apply(data, false)
	_level_path = data["level"]
	_resume_runtime = data["runtime"]
	_resume_runtime["cinematic"] = data["cinematic"]
	_resume_runtime["cinematic_context"] = data.get("cinematic_context", {}).duplicate(true)
	_chapter_complete = data["chapter_complete"]
	_cinematic_context = data.get("cinematic_context", {}).duplicate(true)
	_cinematic_request = 0
	_cinematic = data["cinematic"]
	_cinematic_entry = data.duplicate(true) if _cinematic != "" else {}
	_active_run = true
	_bind_navigation()
	var notices: Array = data.get("notices", [])
	if not notices.is_empty():
		EventBus.toast_requested.emit(str(notices[0]))
	var terminal := load(_level_path) as LevelData
	var next := _next_level(terminal) if _chapter_complete else null
	if next != null:
		# 較舊累積版本在章末保存；本版本收錄下一章時從下一章入口接續，不重看結算。
		GameState.carry_over(_resume_runtime.get("loadout", {}))
		_enter_next_level(next, _resume_runtime)
	elif _chapter_complete:
		_show_victory(terminal.chapter)
	else:
		_load_level(Transition.Kind.SCAN)


## 下一個區域：存在、型別正確且屬於本版本收錄的章節才接續；否則視為本版本的章末。
func _next_level(data: LevelData) -> LevelData:
	if data == null or data.next_level.is_empty():
		return null
	var next := RunSaveCodec.resource(data.next_level, "level", "res://data/levels/") as LevelData
	if next == null:
		push_error("[Main] 找不到下一關：%s，直接進入結算。" % data.next_level)
		return null
	if not CampaignEdition.current().includes_level(next):
		print("[Main] %s 收錄到此；下一章 %s 不在本版本。" % [CampaignEdition.current().title(), next.chapter])
		return null
	return next


## 章節之間的接續：帶著裝備與成長進下一區，從入口開始、補滿血量。
func _enter_next_level(next: LevelData, runtime: Dictionary) -> void:
	# Prepare the next chapter's checkpoint state without consuming the live
	# carried loadout or clearing the old checkpoint before a successful write.
	var carried := GameState._carried_loadout.duplicate(true)
	var state_changes := {"level_start_loadout": carried, "checkpoint_loadout": carried.duplicate(true),
		"pending_portal": "", "carried_health": -1, "has_checkpoint": false,
		"checkpoint_position": [0.0, 0.0], "checkpoint_level_path": "", "checkpoint_world": {},
		"checkpoint_progress": {}, "level_start_progress": Progression.snapshot()}
	runtime = runtime.duplicate(true)
	runtime["ending"] = false
	runtime["position"] = [-1, -1]
	runtime["health"] = GameState.difficulty.player_max_health
	if not _save_destination(runtime, next.resource_path, state_changes):
		_show_destination_failure(_enter_next_level.bind(next, runtime), false, "chapter")
		return
	_chapter_complete = false
	GameState.enter_level()
	_resume_runtime = runtime if _restore_publish_pending else {}
	_load_level(Transition.Kind.ELEVATOR)


func _load_level(kind := Transition.Kind.IRIS, caption := "", hold := 0.0) -> void:
	var data: LevelData = load(_level_path) as LevelData if ResourceLoader.exists(_level_path) else null
	if data == null:
		push_error("[Main] 無法載入關卡：%s" % _level_path)
		_restore_publish_pending = false
		_show_main_menu()
		return
	var level := Level.new()
	level.configure(data)
	if not _resume_runtime.is_empty():
		level.configure_resume(_resume_runtime)
		_resume_runtime = {}
	level.critical_save_requested.connect(_save_run)
	level.retry_requested.connect(_on_retry_requested.bind(level), CONNECT_DEFERRED)
	level.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	level.completed.connect(_on_level_completed.bind(data, weakref(level)), CONNECT_DEFERRED)
	level.area_requested.connect(_on_area_requested, CONNECT_DEFERRED)
	_switch_to(level, kind, Vector2(0.5, 0.5), caption, hold)


## 死亡後重來用雜訊溶解並標示回溯編號；暫停選單的「從檢查點重來」用光圈。
func _on_retry_requested(level: Level) -> void:
	if _route_pending():
		return
	Story.reset_active_presentation(&"retry")
	# 檢查點在別的區域（區域組）：回到那個區域；舊式關卡的檢查點一定在同一關。
	var checkpoint_level := GameState.checkpoint_level_path
	var destination_path := _level_path
	if GameState.has_checkpoint and not checkpoint_level.is_empty() and RunSaveCodec.resource(checkpoint_level, "level", "res://data/levels/") != null:
		destination_path = checkpoint_level
	var runtime := level.run_snapshot()
	runtime["loadout"] = GameState.checkpoint_loadout.duplicate(true)
	var restore_progression: Variant = null
	if not level.data.persistent_world:
		restore_progression = GameState.checkpoint_progress if GameState.checkpoint_applies(destination_path) else GameState.level_start_progress
	runtime["dead"] = false
	runtime["ending"] = false
	runtime["health"] = GameState.difficulty.player_max_health
	runtime["position"] = [-1, -1]
	runtime["velocity"] = [0, 0]
	runtime["crouching"] = false
	if not _save_destination(runtime, destination_path, {"pending_portal": "", "carried_health": -1}, restore_progression):
		_show_destination_failure(_on_retry_requested.bind(level), not level.died, "respawn" if level.died else "retry")
		return
	GameState.pending_portal = &""
	GameState.carried_health = -1
	if restore_progression is Dictionary:
		Progression.restore(restore_progression)
	_clear_cinematic()
	if is_instance_valid(level) and level.died:
		_load_level(Transition.Kind.GLITCH, RETRY_CAPTION % GameState.deaths, RETRY_HOLD)
	else:
		_load_level(Transition.Kind.IRIS)


## 穿過出入口：載入目標區域（玩家出現在 GameState.pending_portal 指定的出入口）。
func _on_area_requested(level_path: String) -> void:
	if _route_pending():
		return
	# 撤回未完成演出的暫定效果，再保存新區入口；入口Portal由實際路由保留。
	var portal := GameState.pending_portal
	Story.reset_active_presentation(&"route")
	GameState.pending_portal = portal
	var target := RunSaveCodec.resource(level_path, "level", "res://data/levels/") as LevelData
	if target != null and not CampaignEdition.current().includes_level(target):
		GameState.pending_portal = &""
		EventBus.toast_requested.emit("這條路通往本版本未收錄的%s。" % CampaignEdition.current().chapter_title(target.chapter))
		return
	# The source slot describes the current room, not the destination portal.
	GameState.pending_portal = &""
	_save_run()
	GameState.pending_portal = portal
	# 保存目標入口而不是舊區位置；切換中關閉也能進新區。
	var runtime := (_screen as Level).run_snapshot() if _screen is Level else {}
	runtime["position"] = [-1, -1]
	if not _save_destination(runtime, level_path):
		GameState.pending_portal = &""
		_show_destination_failure(func() -> void:
			GameState.pending_portal = portal
			_on_area_requested(level_path), true, "area")
		return
	_load_level(Transition.Kind.FADE)


## 過關：有下一關就接續（帶著成長與裝備），否則進入結算畫面。下一關讀不到時退回結算，不會卡住。
func _on_level_completed(data: LevelData, source_ref: WeakRef = null) -> void:
	if _route_pending():
		return
	var source := _screen as Level
	if source_ref != null and source_ref.get_ref() != source:
		push_warning("[Main] 拒絕舊畫面的關卡完成：received=%s current=%s" % [data.resource_path if data != null else "<null>", source.data.resource_path if source != null and source.data != null else _level_path])
		return
	if source == null or data == null or source.data != data:
		var received := data.resource_path if data != null else "<null>"
		var current := source.data.resource_path if source != null and source.data != null else _level_path
		push_warning("[Main] 拒絕無效或過時關卡完成：received=%s current=%s（畫面=%s）" % [received, current, _screen.get_class() if is_instance_valid(_screen) else "<null>"])
		return
	var next := _next_level(data)
	if next != null:
		_save_run()
		_enter_next_level(next, (_screen as Level).run_snapshot())
	else:
		var completed := RunSnapshot.capture(_level_path, source.run_snapshot(), "", true)
		if not _run_store.write(completed):
			_show_destination_failure(_on_level_completed.bind(data, weakref(source)), false, "ending")
			return
		_chapter_complete = true
		_show_victory(data.chapter)


func _show_victory(chapter: StringName) -> void:
	var screen := VictoryScreen.new()
	screen.chapter = chapter
	screen.replay_requested.connect(_on_start_requested.bind(GameState.difficulty), CONNECT_DEFERRED)
	screen.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	_switch_to(screen, Transition.Kind.BLINDS)


func _route_pending() -> bool:
	return Story.result_publication_active() or _quitting or _publishing_restore or is_instance_valid(_destination_save_prompt) or (is_instance_valid(_pending_screen) and not _pending_screen.is_inside_tree())


func _bind_navigation() -> void:
	if _navigation != null and _navigation.changed.is_connected(_queue_runtime_save):
		_navigation.changed.disconnect(_queue_runtime_save)
	_navigation = QuestMapState.for_run()
	_navigation.changed.connect(_queue_runtime_save)


func _queue_runtime_save() -> void:
	if not _active_run or _runtime_save_queued or _restore_publish_pending or _publishing_restore:
		return
	_runtime_save_queued = true
	get_tree().create_timer(1.0, true, false, true).timeout.connect(func() -> void:
		_runtime_save_queued = false
		_queue_save())


func _queue_save() -> void:
	if is_instance_valid(_destination_save_prompt):
		return
	if (is_instance_valid(_story_completion) and _story_completion.blocks_save()) or (is_instance_valid(_result_completion) and _result_completion.blocks_save()):
		return
	if not _active_run or _save_queued or _restore_publish_pending or _publishing_restore:
		return
	_save_queued = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	_save_queued = false
	_save_run()


func _save_run() -> void:
	if is_instance_valid(_destination_save_prompt):
		return
	if (is_instance_valid(_story_completion) and _story_completion.blocks_save()) or (is_instance_valid(_result_completion) and _result_completion.blocks_save()):
		return
	if not _active_run or _destination_pending or _restore_publish_pending or _publishing_restore or not is_instance_valid(_screen) or not _screen is Level:
		return
	var level := _screen as Level
	if not level.is_inside_tree() or level.is_queued_for_deletion():
		return
	if level.data.resource_path != _level_path:
		return  # 轉場期間已保存新區入口，不拿舊畫面的座標覆蓋。
	var runtime := level.run_snapshot()
	if runtime.is_empty():
		return
	var snapshot := RunSnapshot.capture(_level_path, runtime, _cinematic, _chapter_complete, _cinematic_context)
	if _cinematic != "" and not _cinematic_entry.is_empty():
		# 尚未結束的選項／物品／款項皆暫定；完整入口快照避免A殘留再選B。
		snapshot = _cinematic_entry.duplicate(true)
		snapshot["cinematic"] = _cinematic
		snapshot["cinematic_context"] = _cinematic_context.duplicate(true)
	var saved := _run_store.write(snapshot)
	if not saved:
		EventBus.toast_requested.emit("存檔未成功，原進度仍保留。")


func _save_destination(runtime: Dictionary, destination_path := "", state_changes: Dictionary = {}, progression: Variant = null) -> bool:
	var path := _level_path if destination_path.is_empty() else destination_path
	var destination := RunSaveCodec.resource(path, "level", "res://data/levels/") as LevelData
	if destination == null:
		push_warning("[RunSave] run/level 目的地無效：%s，原存檔保留並返回選單" % path)
		_show_main_menu()
		return false
	var entry := runtime.duplicate(true)
	var snapshot := RunSnapshot.capture(path, entry)
	var state: Dictionary = snapshot["state"]
	for key: String in state_changes:
		state[key] = state_changes[key]
	if progression is Dictionary:
		snapshot["progression"] = progression.duplicate(true)
	var area := {"consumed": {}, "damage": {}, "world": {}}
	if destination.persistent_world:
		area = (state["area_states"].get(String(destination.id), area) as Dictionary).duplicate(true)
	elif state["has_checkpoint"] and (str(state["checkpoint_level_path"]).is_empty() or state["checkpoint_level_path"] == path):
		area["world"] = state["checkpoint_world"].duplicate(true)
	entry["world"] = area["world"].duplicate(true)
	entry["area"] = area
	entry["loose"] = []
	entry["enemies"] = []
	entry["encounters"] = {}
	entry["arena"] = false
	entry["boss_pending"] = false
	entry["velocity"] = [0, 0]
	entry["facing"] = 1
	entry["aim_dir"] = [1, 0]
	entry["crouching"] = false
	entry["guard"] = 100
	entry["dead"] = false
	entry["death_entry"] = {}
	entry["death_cause"] = "unknown"
	entry["ending"] = false
	if not _run_store.write(snapshot):
		EventBus.toast_requested.emit("區域進度尚未保存，請稍後再試；原存檔仍保留。")
		return false
	# Only an accepted destination can replace routing metadata or its caller's
	# runtime. Queued saves must now keep the old screen from overwriting it.
	runtime.assign(entry)
	_level_path = path
	_destination_pending = true
	return true


func _on_scene_started(id: StringName, mode: StringName) -> void:
	if not _active_run or not is_instance_valid(_screen) or not _screen is Level or mode not in [Story.MODE_CINEMATIC, Story.MODE_ANIMATED]:
		return
	_cinematic_context = Story.current_presentation_context()
	_cinematic_request = Story.current_presentation_request()
	_cinematic_entry = RunSnapshot.capture(_level_path, (_screen as Level).run_snapshot(), "", false, _cinematic_context)
	_cinematic = String(id)
	_queue_save()


func _on_scene_finished(id: StringName) -> void:
	var request := Story.finished_presentation_request()
	if _cinematic == String(id) and (request == 0 or request == _cinematic_request):
		_clear_cinematic()
	_queue_save()


func _clear_cinematic() -> void:
	_cinematic = ""
	_cinematic_entry = {}
	_cinematic_context = {}
	_cinematic_request = 0


func _show_destination_failure(retry: Callable, can_stay: bool, purpose: String) -> void:
	if not is_inside_tree() or not _active_run or is_instance_valid(_destination_save_prompt):
		return
	_destination_retry = retry
	_destination_save_lock = GameplayLock.acquire(self, Input.MOUSE_MODE_VISIBLE)
	var canvas := CanvasLayer.new()
	canvas.layer = 110
	add_child(canvas)
	_destination_save_prompt = preload("res://ui/destination_save_prompt.gd").new()
	_destination_save_prompt.can_stay = can_stay
	_destination_save_prompt.purpose = purpose
	_destination_save_prompt.retry_requested.connect(_retry_destination_save)
	_destination_save_prompt.cancel_requested.connect(_clear_destination_failure)
	canvas.add_child(_destination_save_prompt)


func _retry_destination_save() -> void:
	var retry := _destination_retry
	_clear_destination_failure()
	if retry.is_valid():
		retry.call()


func _clear_destination_failure() -> void:
	if is_instance_valid(_destination_save_prompt):
		_destination_save_prompt.hide()
		_destination_save_prompt.get_parent().queue_free()
	_destination_save_prompt = null
	_destination_retry = Callable()
	GameplayLock.release(_destination_save_lock)
	_destination_save_lock = 0


func _exit_tree() -> void:
	_clear_destination_failure()


## 純取消不套完成旗標。死亡通知在Level結算前抵達，只撤回暫定資料，保留live玩家死亡演出。
func _on_presentation_cancelled(id: StringName, _context: Dictionary, reason: StringName, request: int) -> void:
	if _cinematic != String(id) or (_cinematic_request != 0 and request != _cinematic_request):
		return
	var level: Level = _screen as Level if is_instance_valid(_screen) else null
	var rolled_back := false
	if _active_run and not _destination_pending and level != null and level.data.resource_path == _level_path \
			and reason in [&"death", &"route", &"retry", &"leave"] and not _cinematic_entry.is_empty():
		var entry := _cinematic_entry.duplicate(true)
		_publishing_restore = true
		RunSnapshot.rollback_presentation(entry, false)
		_clear_cinematic()
		if level.is_inside_tree() and not level.is_queued_for_deletion():
			level.rollback_presentation_world(entry.get("runtime", {}))
		rolled_back = true
	_clear_cinematic()
	if rolled_back:
		_bind_navigation()
		RunSnapshot.publish_restored()
		_publishing_restore = false
		_queue_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _quit(exit_code := 0) -> void:
	if _publishing_restore or Story.result_publication_active():
		_quit.call_deferred(exit_code)
		return
	if _quitting:
		return
	_quitting = true
	_save_run()
	_clear_destination_failure()
	_active_run = false
	Story.reset_active_presentation(&"quit")
	Transition.abort()
	# 切換途中尚未加入樹的目標畫面也必須釋放。
	if is_instance_valid(_pending_screen) and not _pending_screen.is_inside_tree():
		_pending_screen.free()
	_pending_screen = null
	if is_instance_valid(_screen):
		_screen.queue_free()
	await get_tree().process_frame
	await AudioRelease.settle(get_tree())
	get_tree().quit(exit_code)
