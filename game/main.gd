extends Node
## 遊戲進入點與畫面路由：主選單 → 關卡 → 過關畫面。
## 同一時間只存在一個畫面；切換時舊畫面完整釋放，避免記憶體累積。

## 新遊戲的第一個區域的預設值；實際起點以 data/release/campaign.json 為準（CampaignEdition.first_level）。
## 舊的雨夜關卡在 data/levels/level_01.tres 保留給既有測試與開發用，只有開發版可進入。
const FIRST_LEVEL := CampaignEdition.DEFAULT_FIRST_LEVEL
const RETRY_HOLD := 0.22
const SAVE_FAILURE_TOAST := "存檔未成功，原進度仍保留。"
const SAVE_FAILURE_TRANSLATIONS: Dictionary[String, String] = {
	"ja": "保存できませんでした。前回のセーブは残っています。",
	"en": "Save failed. Your last save is intact.",
}
const AREA_SAVE_FAILURE_TRANSLATIONS: Dictionary[String, String] = {
	"ja": "エリアの進行状況を保存できませんでした。もう一度お試しください。",
	"en": "Could not save this area. Try again. Your last save is intact.",
}

const SAVE_MENU_NOTICES := {
	"unsupported": [
		"此版本無法讀取存檔。原檔已保留，請使用相容的遊戲版本。",
		"このセーブは読み込めません。元のデータは残っています。対応するバージョンを使ってください。",
		"This version cannot read your save. It was kept. Use a compatible game version.",
	],
	"unreadable": [
		"存檔讀取失敗，原檔已保留。可開始新遊戲。",
		"セーブを読み込めませんでした。元のデータは残っています。新しく始めることもできます。",
		"Could not read your save. It was kept. You can start a new game.",
	],
	"backup": [
		"已從備份恢復進度，可以繼續遊戲。",
		"バックアップから復元しました。ゲームを再開できます。",
		"Your backup was recovered. You can continue.",
	],
	"new_run": [
		"已恢復先前確認的新遊戲，可以繼續遊戲。",
		"開始した新しいゲームを復元しました。続きから再開できます。",
		"Your new game was recovered. You can continue.",
	],
	"legacy": [
		"舊版只保存故事，無法繼續整輪。可開始新遊戲，原故事檔會保留。",
		"旧版はストーリーのみを保存します。元のデータを残したまま、新しく始められます。",
		"The old save contains story progress only. You can start a new game and keep it.",
	],
}

var _result_completion: Node
var _world_item_completion: Node
var _training_completion: Node
var _skip_completion: Node
var _channel_completion: Node
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
var _writing_autosave := false
var _autosave_queued := false
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
var _route_preparing := false
var _route_generation := 0
var _restore_publish_pending := false
var _publishing_restore := false
var _destination_save_prompt: Control
var _destination_retry: Callable
var _destination_purpose := ""
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
	_world_item_completion = preload("res://game/world_item_completion.gd").new()
	_world_item_completion.main = self
	add_child(_world_item_completion)
	_training_completion = preload("res://game/training_completion.gd").new()
	_training_completion.main = self
	add_child(_training_completion)
	_skip_completion = preload("res://game/skip_completion.gd").new()
	_skip_completion.main = self
	add_child(_skip_completion)
	_channel_completion = preload("res://game/channel_completion.gd").new()
	_channel_completion.main = self
	add_child(_channel_completion)
	_run_store.validator = _prepare_run_snapshot
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
	var level := screen as Level
	if level != null:
		while is_instance_valid(level) and level.is_building_entry() and not _quitting:
			await get_tree().process_frame
		if _quitting or not is_instance_valid(level) or _screen != level:
			return
		if not level.is_initialized():
			_restore_publish_pending = false
			await _open_main_menu()
			return  # A failed entry never publishes or saves partial state.
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
	await _open_main_menu()


func _open_main_menu() -> void:
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
	await _switch_to(menu, Transition.Kind.SCAN)


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
		if _run_store.required_edition != null:
			return _edition_save_notice(_run_store.required_edition, false)
		return _save_menu_text("unsupported")
	if not _import_path.is_empty():
		return _edition_save_notice(lineage["edition"], true)
	if lineage.has("newer"):
		return _edition_save_notice(lineage["newer"], false)
	match _run_store.read_recovery:
		RunSaveStore.ReadRecovery.BACKUP:
			return _save_menu_text("backup")
		RunSaveStore.ReadRecovery.NEW_RUN:
			return _save_menu_text("new_run")
	if not _run_store.issues.is_empty() and _continue_data.is_empty():
		return _save_menu_text("unreadable")
	if not notices.is_empty():
		return notices[0]
	if _continue_data.is_empty() and FileAccess.file_exists(GameState.STORY_SAVE_PATH):
		return _save_menu_text("legacy")
	return ""


static func _save_menu_text(key: String) -> String:
	var language := maxi(0, StoryLocale.LANGUAGES.find(Story.language))
	return SAVE_MENU_NOTICES[key][language]


static func _edition_save_notice(edition: CampaignEdition, can_resume: bool) -> String:
	var title := edition.title(Story.language)
	match Story.language:
		"ja":
			return ("「%s」から再開できます。元のセーブは保持されます。" if can_resume else
					"再開するには「%s」を開いてください。セーブは保持されます。") % title
		"en":
			return ("Continue from %s. Your original save stays intact." if can_resume else
					"Open %s to continue. That save stays intact.") % title
	return ("可接續「%s」的進度，原存檔不會被修改。" if can_resume else
			"找到「%s」的存檔，請用該版本繼續；那份存檔不受影響。") % title


func _on_start_requested(difficulty: DifficultyData) -> void:
	if _route_pending():
		return
	await _cover_route(Transition.Kind.SCAN, _start_run.bind(difficulty))


func _start_run(difficulty: DifficultyData) -> void:
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
	if await _route_frame():
		await _load_level(Transition.Kind.SCAN)


func _on_continue_requested() -> void:
	if _route_pending():
		return
	await _cover_route(Transition.Kind.SCAN, _continue_run)


func _continue_run() -> void:
	var data: Dictionary = _read_continue().get("data", {})
	if data.is_empty():
		await _open_main_menu()
		return
	if not await _route_frame():
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
	_cinematic_entry = data.duplicate(true) if _cinematic != "" and Story.scene_mode(StringName(_cinematic)) != Story.MODE_RADIO else {}
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
		await _enter_next_level(next, _resume_runtime)
	elif _chapter_complete:
		await _show_victory(terminal.chapter)
	else:
		await _load_level(Transition.Kind.SCAN)


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
		_show_destination_failure(_retry_chapter_route.bind(next, runtime), false, "chapter")
		return
	_chapter_complete = false
	GameState.enter_level()
	_resume_runtime = runtime if _restore_publish_pending else {}
	if await _route_frame():
		await _load_level(Transition.Kind.ELEVATOR)


func _retry_chapter_route(next: LevelData, runtime: Dictionary) -> void:
	await _cover_route(Transition.Kind.ELEVATOR, _enter_next_level.bind(next, runtime))


func _load_level(kind := Transition.Kind.IRIS, caption := "", hold := 0.0) -> void:
	var data: LevelData = load(_level_path) as LevelData if ResourceLoader.exists(_level_path) else null
	if data == null:
		push_error("[Main] 無法載入關卡：%s" % _level_path)
		_restore_publish_pending = false
		await _open_main_menu()
		return
	var level := Level.new()
	level.configure(data, not Transition.instant)
	if not _resume_runtime.is_empty():
		level.configure_resume(_resume_runtime)
		_resume_runtime = {}
	level.critical_save_requested.connect(_save_run)
	level.retry_requested.connect(_on_retry_requested.bind(level), CONNECT_DEFERRED)
	level.menu_requested.connect(_on_level_menu_requested.bind(weakref(level)), CONNECT_DEFERRED)
	level.completed.connect(_on_level_completed.bind(data, weakref(level)), CONNECT_DEFERRED)
	level.area_requested.connect(_on_area_requested, CONNECT_DEFERRED)
	await _switch_to(level, kind, Vector2(0.5, 0.5), _loading_caption(caption), hold)


func _on_level_menu_requested(origin: WeakRef) -> void:
	if origin.get_ref() == _screen:
		_show_main_menu()


## 死亡後重來用雜訊溶解並標示回溯編號；暫停選單的「從檢查點重來」用光圈。
func _on_retry_requested(level: Level) -> void:
	if _route_pending() or not is_instance_valid(level) or level.channel_result_pending:
		return
	var kind := Transition.Kind.GLITCH if level.died else Transition.Kind.IRIS
	var caption := DeathScreen.record_title(GameState.deaths) if level.died else ""
	var hold := RETRY_HOLD if level.died else 0.0
	await _cover_route(kind, _retry_run.bind(level, kind, caption, hold), caption, hold)


func _retry_run(level: Level, kind: Transition.Kind, caption: String, hold: float) -> void:
	if not is_instance_valid(level):
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
	if await _route_frame():
		await _load_level(kind, caption, hold)


## 穿過出入口：載入目標區域（玩家出現在 GameState.pending_portal 指定的出入口）。
func _on_area_requested(level_path: String) -> void:
	if is_instance_valid(_channel_completion) and _channel_completion.defer_area(level_path): return
	if _route_pending():
		return
	await _cover_route(Transition.Kind.FADE, _commit_area_route.bind(level_path))


func _commit_area_route(level_path: String) -> void:
	# The previous area stays active until the destination has passed validation.
	var target := RunSaveCodec.resource(level_path, "level", "res://data/levels/") as LevelData
	var source := _screen as Level
	if target == null:
		if source != null:
			source.reject_area_destination(level_path)
		else:
			push_error("[Main] 無法載入關卡：%s" % level_path)
		return
	if not CampaignEdition.current().includes_level(target):
		if source != null:
			source.cancel_area_route()
		GameState.pending_portal = &""
		EventBus.toast_requested.emit("這條路通往本版本未收錄的%s。" % CampaignEdition.current().chapter_title(target.chapter))
		return
	# 撤回未完成演出的暫定效果，再保存新區入口；入口Portal由實際路由保留。
	var portal := GameState.pending_portal
	Story.reset_active_presentation(&"route")
	GameState.pending_portal = portal
	# The source slot describes the current room, not the destination portal.
	GameState.pending_portal = &""
	_save_run(true)
	if not await _route_frame():
		return
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
	if await _route_frame():
		await _load_level(Transition.Kind.FADE)


## 過關：有下一關就接續（帶著成長與裝備），否則進入結算畫面。下一關讀不到時退回結算，不會卡住。
func _on_level_completed(data: LevelData, source_ref: WeakRef = null) -> void:
	if _defer_world_operation(_on_level_completed.bind(data, source_ref)): return
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
		await _cover_route(Transition.Kind.ELEVATOR, _handoff_chapter.bind(next, source))
	else:
		await _cover_route(Transition.Kind.BLINDS, _finish_chapter.bind(data, source))


func _handoff_chapter(next: LevelData, source: Level) -> void:
	_save_run()
	if await _route_frame():
		await _enter_next_level(next, source.run_snapshot())


func _finish_chapter(data: LevelData, source: Level) -> void:
	var completed := RunSnapshot.capture(_level_path, source.run_snapshot(), "", true)
	if not _run_store.write(completed):
		_show_destination_failure(_on_level_completed.bind(data, weakref(source)), false, "ending")
		return
	_chapter_complete = true
	await _show_victory(data.chapter)


func _show_victory(chapter: StringName) -> void:
	var screen := VictoryScreen.new()
	screen.chapter = chapter
	screen.replay_requested.connect(_on_start_requested.bind(GameState.difficulty), CONNECT_DEFERRED)
	screen.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	await _switch_to(screen, Transition.Kind.BLINDS)


func _publishing_results() -> bool:
	if Story.result_publication_active(): return true
	for owner: Node in [_training_completion, _world_item_completion, _skip_completion, _channel_completion]:
		if is_instance_valid(owner) and owner.publishing(): return true
	return false


## All route preparation runs behind the same transition, including durable
## writes. Nested screen installation is awaited before the cover can reopen.
func _cover_route(kind: Transition.Kind, prepare: Callable, caption := "", hold := 0.0) -> void:
	_route_generation += 1
	var generation := _route_generation
	_route_preparing = true
	_run_store.cancel_deferred_write()
	await Transition.play(kind, _prepare_route.bind(prepare, generation), -1.0, Vector2(0.5, 0.5), _loading_caption(caption), hold)
	_finish_route_preparation(generation)


func _prepare_route(prepare: Callable, generation: int) -> void:
	if await _route_frame():
		await prepare.call()
	_finish_route_preparation(generation)


func _finish_route_preparation(generation: int) -> void:
	if generation == _route_generation and _route_preparing:
		_route_preparing = false
		_queue_save()


func _route_frame() -> bool:
	var covered := Transition.is_active()
	if covered:
		await get_tree().process_frame
	return not _quitting and (not covered or Transition.is_active())


static func _loading_caption(caption: String) -> String:
	if not caption.is_empty():
		return caption
	return StoryLocale.optional_text({"ja": "読み込み中…", "en": "Loading…"}, Story.language, "載入中…")


func _route_pending() -> bool:
	return (_publishing_results() or _quitting or _publishing_restore or _route_preparing
			or is_instance_valid(_destination_save_prompt)
			or (is_instance_valid(_pending_screen) and not _pending_screen.is_inside_tree())
			or (_screen is Level and _screen.is_building_entry()))


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
		_queue_movement_autosave())


func _result_owners() -> Array[Node]:
	return [_story_completion, _result_completion, _world_item_completion, _training_completion, _skip_completion, _channel_completion]


func _story_save_blocked(except_owner: Node = null) -> bool:
	for owner: Node in _result_owners():
		if owner != except_owner and is_instance_valid(owner) and owner.blocks_save():
			return true
	return false


func _world_recovery_pending(except_owner: Node) -> bool:
	for owner: Node in _result_owners():
		if owner != except_owner and is_instance_valid(owner) and owner.blocks_save() and (owner.get("_recovery") == true or owner.get("_reload_original") == true): return true
	return false


func _defer_world_operation(callback: Callable) -> bool:
	return is_instance_valid(_channel_completion) and _channel_completion.defer_operation(callback)


func _defer_world_story(id: StringName, request: int) -> bool:
	return is_instance_valid(_channel_completion) and _channel_completion.defer_story(id, request)


func _queue_save() -> void:
	if is_instance_valid(_destination_save_prompt):
		return
	if _story_save_blocked():
		return
	if not _active_run or _save_queued or _restore_publish_pending or _publishing_restore or _route_preparing:
		return
	_save_queued = true
	_flush_save.call_deferred()


## Movement, exploration and routine player-state changes share one deferred
## draft. Story and explicit saves still use the immediate durability path.
func _queue_movement_autosave() -> void:
	if _save_queued or _autosave_queued or _route_preparing or _quitting or not _can_capture_save():
		return
	if get_tree().paused or Story.is_cinematic_active():
		_queue_save()
		return
	_autosave_queued = true
	if not _writing_autosave:
		_flush_autosave.call_deferred()


func _flush_save() -> void:
	_save_queued = false
	if not _route_preparing:
		_save_run()


func _flush_autosave() -> void:
	if not _autosave_queued or _writing_autosave:
		return
	_autosave_queued = false
	if _save_queued or _route_preparing or _quitting:
		return
	var snapshot := _snapshot_for_save()
	if snapshot.is_empty():
		return
	var owner: WeakRef = weakref(_screen)
	_writing_autosave = true
	var status: RunSaveStore.WriteStatus = await _run_store.write_in_frames(snapshot, get_tree(), _can_finish_autosave.bind(owner))
	_writing_autosave = false
	if status != RunSaveStore.WriteStatus.CANCELLED:
		_report_run_save(status == RunSaveStore.WriteStatus.SAVED)
	if _autosave_queued:
		_flush_autosave.call_deferred()


func _can_finish_autosave(owner: WeakRef) -> bool:
	return (not _quitting and not _route_preparing and not _save_queued
			and not get_tree().paused and owner.get_ref() == _screen and _can_capture_save())


func _save_run(route_source := false) -> void:
	var snapshot := _snapshot_for_save(route_source)
	if not snapshot.is_empty():
		_autosave_queued = false
		_report_run_save(_run_store.write(snapshot))


## Reuse the active area's authored layout. Cold and cross-area reads still parse their own layout.
func _prepare_run_snapshot(raw: Dictionary) -> Dictionary:
	var level := _screen as Level
	if is_instance_valid(level) and level.is_initialized():
		return RunSnapshot.prepare(raw, level.data, level._layout)
	return RunSnapshot.prepare(raw)


func _can_capture_save() -> bool:
	if is_instance_valid(_destination_save_prompt) or _story_save_blocked():
		return false
	if not _active_run or _destination_pending or _restore_publish_pending or _publishing_restore or not is_instance_valid(_screen) or not _screen is Level:
		return false
	var level := _screen as Level
	# 轉場已存新區入口時，不用舊畫面的座標覆蓋。
	return level.is_inside_tree() and not level.is_queued_for_deletion() and level.is_initialized() and level.data.resource_path == _level_path


func _snapshot_for_save(route_source := false) -> Dictionary:
	if not _can_capture_save():
		return {}
	var level := _screen as Level
	if not is_instance_valid(level.player) or level._layout == null:
		return {}
	if _cinematic != "" and not _cinematic_entry.is_empty():
		# The locked scene owns its entry state until the result is durable.
		var checkpoint := _cinematic_entry.duplicate(true)
		checkpoint["cinematic"] = _cinematic
		checkpoint["cinematic_context"] = _cinematic_context.duplicate(true)
		return checkpoint
	var runtime := level.run_snapshot()
	if runtime.is_empty():
		return {}
	if route_source:
		runtime["ending"] = false
	return RunSnapshot.capture(_level_path, runtime, _cinematic, _chapter_complete, _cinematic_context)


func _report_run_save(saved: bool) -> void:
	var warning := StoryLocale.optional_text(SAVE_FAILURE_TRANSLATIONS, Story.language, SAVE_FAILURE_TOAST)
	if not saved:
		EventBus.toast_requested.emit(warning)
	else:
		EventBus.toast_dismiss_requested.emit(warning)


func _save_destination(runtime: Dictionary, destination_path := "", state_changes: Dictionary = {}, progression: Variant = null) -> bool:
	if is_instance_valid(_channel_completion) and _channel_completion.blocks_save(): return false
	var path := _level_path if destination_path.is_empty() else destination_path
	var prepared := preload("res://core/run_destination.gd").prepare(RunSnapshot.capture(path, runtime), path, state_changes, progression)
	if prepared.has("error"):
		push_warning("[RunSave] run/level 目的地無效：%s，原存檔保留並返回選單" % path)
		_open_main_menu()
		return false
	if not _run_store.write(prepared["data"]):
		EventBus.toast_requested.emit(StoryLocale.optional_text(AREA_SAVE_FAILURE_TRANSLATIONS, Story.language,
			"區域進度尚未保存，請稍後再試；原存檔仍保留。"))
		return false
	# Only an accepted destination can replace routing metadata or its caller's
	# runtime. Queued saves must now keep the old screen from overwriting it.
	runtime.assign(prepared["data"]["runtime"])
	_level_path = path
	_destination_pending = true
	return true


func _on_scene_started(id: StringName, mode: StringName) -> void:
	if _active_run and _screen is Level and mode == Story.MODE_RADIO and _cinematic == String(id):
		var requests: Array = Story._passive_requests.get(id, [])
		_cinematic_request = int(requests.back()) if not requests.is_empty() else 0
		_cinematic_entry = {} # Flag-only radio has no tentative player/world changes.
		_queue_save()
		return
	if not _active_run or not is_instance_valid(_screen) or not _screen is Level or mode not in [Story.MODE_CINEMATIC, Story.MODE_ANIMATED]:
		return
	_cinematic_context = Story.current_presentation_context()
	_cinematic_request = Story.current_presentation_request()
	_cinematic_entry = RunSnapshot.capture(_level_path, (_screen as Level).run_snapshot(), "", false, _cinematic_context)
	_cinematic = String(id)
	_queue_save()


## A durable world event may carry an unread important radio across restart.
func _remember_world_radio(id: StringName, request := 0) -> void:
	if Story.scene_mode(id) != Story.MODE_RADIO: return
	_cinematic = String(id)
	_cinematic_request = request
	_cinematic_context = {}
	_cinematic_entry = {}


func _on_scene_finished(id: StringName) -> void:
	var request := Story.finished_presentation_request()
	if _cinematic == String(id) and (request == 0 or request == _cinematic_request):
		var entry := _cinematic_entry
		_clear_cinematic()
		if request != 0 and is_instance_valid(_screen) and _screen is Level:
			_apply_legacy_story_health_reward(_screen, entry)
	_queue_save()


func _apply_legacy_story_health_reward(level: Level, entry: Dictionary) -> void:
	if not level.is_initialized() or level.data.story_health_rewards.is_empty() or not is_instance_valid(level.player):
		return
	var ledger: Variant = entry.get("progression", {}).get("story_transactions")
	if not ledger is Dictionary or not ledger.get("receipts") is Dictionary:
		return
	var amount := 0
	for transaction: StringName in level.data.story_health_rewards:
		if not ledger["receipts"].has(String(transaction)) and Progression.story_receipt_status(transaction)["status"] == "recorded":
			amount += level.data.story_health_reward(transaction)
	level.player.health.heal(amount)


## An accepted choice is a durable continuation, not a completed NPC reading.
## Re-capture after synchronous observers so ordinary spending/NEW changes survive.
func _accept_story_choice(target: StringName, request: int, context: Dictionary) -> void:
	_cinematic = String(target)
	_cinematic_request = request
	_cinematic_context = context.duplicate(true)
	_cinematic_entry = RunSnapshot.capture(_level_path, (_screen as Level).run_snapshot(), "", false, context)


func _clear_cinematic() -> void:
	_cinematic = ""
	_cinematic_entry = {}
	_cinematic_context = {}
	_cinematic_request = 0


func _show_destination_failure(retry: Callable, can_stay: bool, purpose: String) -> void:
	if not is_inside_tree() or not _active_run or is_instance_valid(_destination_save_prompt):
		return
	_destination_retry = retry
	_destination_purpose = purpose
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
	_clear_destination_failure(false)
	if retry.is_valid():
		retry.call()


func _clear_destination_failure(stay := true) -> void:
	if stay and _destination_purpose == "area" and is_instance_valid(_screen) and _screen is Level and _screen.data.resource_path == _level_path:
		_screen.cancel_area_route()
		GameState.pending_portal = &""
	if is_instance_valid(_destination_save_prompt):
		_destination_save_prompt.hide()
		_destination_save_prompt.get_parent().queue_free()
	_destination_save_prompt = null
	_destination_retry = Callable()
	_destination_purpose = ""
	GameplayLock.release(_destination_save_lock)
	_destination_save_lock = 0


func _exit_tree() -> void:
	_run_store.cancel_deferred_write()
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
	if rolled_back or reason == &"skip":
		# Explicitly leaving an optional scene also clears the saved playback checkpoint.
		_queue_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _quit(exit_code := 0) -> void:
	if _publishing_restore or _publishing_results():
		_quit.call_deferred(exit_code)
		return
	if _quitting:
		return
	_quitting = true
	AudioRelease.begin_shutdown()
	_run_store.cancel_deferred_write()
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
