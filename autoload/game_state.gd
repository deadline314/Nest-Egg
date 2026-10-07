extends Node
## 一輪遊戲的狀態：難度、檢查點、殘機與統計。
## 關卡重載時由此還原進度，關卡本身保持無狀態。

const DIFFICULTY_PATHS: Array[String] = [
	"res://data/difficulty/assist.tres",
	"res://data/difficulty/standard.tres",
	"res://data/difficulty/hardcore.tres",
]
const DEFAULT_DIFFICULTY_INDEX := 1

var difficulties: Array[DifficultyData] = []
var difficulty: DifficultyData

var has_checkpoint := false
var checkpoint_position := Vector2.ZERO
var checkpoint_loadout: Dictionary = {}
## 檢查點當下的世界狀態（被打破的箱子、開關、閘門、電力…，見 WorldState），重生時還原。
var checkpoint_world: Dictionary = {}
## 檢查點當下的成長進度（信用點、改裝，見 Progression）。
var checkpoint_progress: Dictionary = {}
## 進入這個關卡時的成長進度：沒有檢查點時（例如殘機用盡）從這裡重來。
var level_start_progress: Dictionary = {}
## 進入這個關卡時的武器欄與消耗品（上一關帶過來的）；沒有檢查點時從這裡重來，第一關是空的（預設武器）。
var level_start_loadout: Dictionary = {}
## 通關時由關卡存下、帶進下一關的武器欄與消耗品。
var _carried_loadout: Dictionary = {}

## 檢查點所在的區域（LevelData 的 .tres 路徑）。空白代表舊式單一關卡（任何關卡都算數）。
var checkpoint_level_path := ""
## 目前正在玩的區域（由 Level 在建立時填入；電話亭啟動時據此記錄檢查點所在區域）。
var current_level_path := ""
## 下一次建立區域時，玩家要出現的出入口 id；空白＝不是穿過出入口進來的（用檢查點或起點）。
var pending_portal: StringName = &""
## 穿過出入口時帶過去的生命值（-1＝沒有，用滿血）。
var carried_health := -1
## 本輪各區域的世界狀態（只有 LevelData.persistent_world 的區域使用），以區域 id 為鍵：
##   {"consumed": {生成格鍵: true}, "damage": {生成格鍵: 已損血量}, "world": WorldState 快照}
var area_states: Dictionary = {}
## 本輪的劇情旗標（旗標名 -> true／數字／字串），開始新的一輪時清空。
var world_flags: Dictionary = {}
var flag_defaults: Dictionary = {}
const STORY_SAVE_PATH := "user://story_progress.json"
## Main enables disk autosave; isolated simulations remain free of real-user writes.
var story_autosave := false
var _story_save_queued := false


var lives_left := -1
## 本輪累計死亡次數（死亡畫面的「NEST 回溯紀錄 #n」、劇情的措辭變化都看它）。
## 屬於本輪進度，不存進檢查點：回溯、重開關卡、換關都不會歸零，只有開始新的一輪才歸零。
var deaths := 0
## 最近一次死亡當下的世界時間（廣播念出來用，見 world_clock_text）；還沒死過是空字串。
var last_death_clock := ""
## 剛死亡、下一次建立關卡就是重生（關卡建立時消耗，播出重生後的反應通訊）。
var respawn_pending := false
## 剛替玩家登記了復原點（第一次死亡的診間之後）：下一次重生時提示「電話亭已登記」，只提示一次。
var checkpoint_notice_pending := false
var kills := 0
var finishers := 0
var run_time := 0.0

## 世界時鐘：一輪從晚上 21:00 開始，現實 1 秒是世界 10 秒（第一章結束時剛好是凌晨三點多）。
const WORLD_CLOCK_START_MINUTES := 21 * 60
const WORLD_SECONDS_PER_SECOND := 10.0


func _ready() -> void:
	_load_difficulties()
	EventBus.enemy_killed.connect(_on_enemy_killed)


func _load_difficulties() -> void:
	for path in DIFFICULTY_PATHS:
		var res: DifficultyData = load(path) as DifficultyData if ResourceLoader.exists(path) else null
		if res == null:
			push_error("[GameState] 無法載入難度資料：%s" % path)
			continue
		difficulties.append(res)
	if difficulties.is_empty():
		push_warning("[GameState] 沒有任何難度資料，改用內建預設值。")
		difficulties.append(DifficultyData.new())
	difficulty = difficulties[clampi(DEFAULT_DIFFICULTY_INDEX, 0, difficulties.size() - 1)]


func start_new_run(p_difficulty: DifficultyData) -> void:
	if p_difficulty != null:
		difficulty = p_difficulty
	clear_checkpoint()
	lives_left = difficulty.lives
	deaths = 0
	last_death_clock = ""
	respawn_pending = false
	checkpoint_notice_pending = false
	checkpoint_level_path = ""
	current_level_path = ""
	pending_portal = &""
	carried_health = -1
	area_states = {}
	world_flags = flag_defaults.duplicate(true)
	kills = 0
	finishers = 0
	run_time = 0.0
	Story.reset_progress()
	StoryItems.reset_run()
	Progression.reset_run()
	level_start_progress = Progression.snapshot()
	level_start_loadout = {}
	_carried_loadout = {}
	checkpoint_loadout = {}
	EventBus.lives_changed.emit(lives_left)
	request_story_save()


func set_checkpoint(position: Vector2, loadout_snapshot: Dictionary, world_snapshot: Dictionary = {}, progress_snapshot: Dictionary = {}) -> void:
	has_checkpoint = true
	checkpoint_position = position
	checkpoint_level_path = current_level_path
	checkpoint_loadout = loadout_snapshot.duplicate(true)
	checkpoint_world = world_snapshot.duplicate(true)
	checkpoint_progress = progress_snapshot.duplicate(true)
	EventBus.checkpoint_reached.emit(position)


func clear_checkpoint() -> void:
	has_checkpoint = false
	checkpoint_position = Vector2.ZERO
	checkpoint_level_path = ""
	checkpoint_loadout = level_start_loadout.duplicate(true)
	checkpoint_world = {}
	checkpoint_progress = {}


## 這個區域是不是有可用的檢查點（舊式關卡的檢查點沒有記錄區域，任何關卡都算數）。
func checkpoint_applies(level_path: String) -> bool:
	return has_checkpoint and (checkpoint_level_path.is_empty() or level_path.is_empty() or checkpoint_level_path == level_path)


## 取出並清除「要出現的出入口」（Level 建立時呼叫一次）。
func take_pending_portal() -> StringName:
	var portal := pending_portal
	pending_portal = &""
	return portal


## 某個區域本輪的世界狀態（沒有就建立空的）。回傳的是參考，修改會直接寫回。
func area_state(area_id: StringName) -> Dictionary:
	var key := String(area_id)
	if not area_states.has(key):
		area_states[key] = {"consumed": {}, "damage": {}, "world": {}}
	return area_states[key]


func set_flag(flag: StringName, value: Variant = true) -> void:
	if flag == &"":
		push_warning("[GameState] set_flag：旗標名稱是空的")
		return
	if not _flag_value_valid(value):
		push_warning("[GameState] flags/%s 無效，保留預設值" % flag)
		return
	world_flags[String(flag)] = value
	request_story_save()


func has_flag(flag: StringName) -> bool:
	return flag != &"" and bool(get_flag(flag, false))


func get_flag(flag: StringName, default: Variant = null) -> Variant:
	return world_flags.get(String(flag), flag_defaults.get(String(flag), default))


func clear_flag(flag: StringName) -> void:
	world_flags.erase(String(flag))
	request_story_save()


## 通關時呼叫：記下要帶進下一關的武器欄與消耗品。
func carry_over(loadout_snapshot: Dictionary) -> void:
	_carried_loadout = loadout_snapshot.duplicate(true)


## 進入新關卡：清掉檢查點，記下此刻的成長進度，並帶入上一關的武器與消耗品（成長與裝備都會帶到下一關）。
func enter_level() -> void:
	level_start_loadout = _carried_loadout
	_carried_loadout = {}
	pending_portal = &""
	carried_health = -1
	clear_checkpoint()
	level_start_progress = Progression.snapshot()


## 記錄一次死亡。回傳 true = 可從檢查點續玩；false = 殘機用盡，進度重置。
func register_death() -> bool:
	deaths += 1
	request_story_save()
	last_death_clock = world_clock_text()
	respawn_pending = true
	if not difficulty.has_limited_lives():
		return true
	lives_left -= 1
	if lives_left > 0:
		EventBus.lives_changed.emit(lives_left)
		return true
	clear_checkpoint()
	lives_left = difficulty.lives
	EventBus.lives_changed.emit(lives_left)
	return false


## 現在（或指定的遊玩秒數）的世界時間，格式「11 點 40 分」。
func world_clock_text(seconds := -1.0) -> String:
	var elapsed := run_time if seconds < 0.0 else seconds
	var minutes := WORLD_CLOCK_START_MINUTES + int(elapsed * WORLD_SECONDS_PER_SECOND / 60.0)
	return "%d 點 %d 分" % [(minutes / 60) % 24, minutes % 60]


## 這次建立關卡是不是死亡後重生（只回傳一次）。
func consume_respawn() -> bool:
	var pending := respawn_pending
	respawn_pending = false
	return pending


## 取出並清除「剛登記復原點」的提示（重生時呼叫一次）。
func consume_checkpoint_notice() -> bool:
	var pending := checkpoint_notice_pending
	checkpoint_notice_pending = false
	return pending


func _on_enemy_killed(_enemy_id: StringName, by_finisher: bool) -> void:
	kills += 1
	if by_finisher:
		finishers += 1


## Defaults only accept scalar JSON values; invalid chapter/save data cannot reach story comparisons.
func register_flag_defaults(raw: Variant, where: String) -> void:
	if not raw is Dictionary:
		push_warning("[GameState] %s/flag_defaults 不是物件，使用空預設值" % where)
		return
	for flag: Variant in raw:
		if str(flag).is_empty() or not _flag_value_valid(raw[flag]):
			push_warning("[GameState] %s/flag_defaults/%s 無效，已略過" % [where, flag])
			continue
		flag_defaults[str(flag)] = raw[flag]


func _flag_value_valid(value: Variant) -> bool:
	return typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_STRING] or (value is float and is_finite(value))


func story_progress_snapshot() -> Dictionary:
	return {"version": 1, "flags": world_flags.duplicate(true), "seen": Story.progress_snapshot(), "items": StoryItems.snapshot(), "deaths": deaths}


## This component can be embedded in a future whole-run save without creating a second quest list.
func restore_story_progress(raw: Variant, where := STORY_SAVE_PATH) -> void:
	world_flags = flag_defaults.duplicate(true)
	var data: Dictionary = raw if raw is Dictionary else {}
	if not raw is Dictionary:
		push_warning("[GameState] %s 不是物件，故事進度退回預設值" % where)
	var flags: Variant = data.get("flags", {})
	if not flags is Dictionary:
		push_warning("[GameState] %s/flags 損毀，退回預設值" % where)
		flags = {}
	for flag: Variant in flags:
		var value: Variant = flags[flag]
		var valid := not str(flag).is_empty() and _flag_value_valid(value)
		if flag_defaults.has(str(flag)):
			var fallback: Variant = flag_defaults[str(flag)]
			valid = valid and (typeof(value) == typeof(fallback) or (value is float and fallback is int and value == floor(value)))
		if valid:
			world_flags[str(flag)] = int(value) if flag_defaults.get(str(flag)) is int else value
		else:
			push_warning("[GameState] %s/flags/%s 損毀，退回預設值" % [where, flag])
	for flag: Variant in flag_defaults:
		if not flags.has(flag):
			push_warning("[GameState] %s/flags/%s 缺漏，退回預設值" % [where, flag])
	Story.restore_progress(data.get("seen", []), where + "/seen")
	StoryItems.restore(data.get("items", {}), where + "/items")
	var count: Variant = data.get("deaths", 0)
	deaths = maxi(0, int(count)) if count is int or count is float else 0


func save_story_progress(path := STORY_SAVE_PATH) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("[GameState] 無法寫入 %s（%s）" % [temp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(story_progress_snapshot()))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_warning("[GameState] 寫入 %s 失敗（%s），原存檔保留" % [temp, error])
		return false
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if error != OK:
		push_warning("[GameState] 無法替換存檔 %s（%s），原存檔保留" % [path, error])
	return error == OK


func load_story_progress(path := STORY_SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[GameState] 無法讀取 %s，故事進度退回預設值" % path)
		restore_story_progress({}, path)
		return false
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		push_warning("[GameState] %s:%d 存檔損毀：%s，故事進度退回預設值" % [path, parser.get_error_line(), parser.get_error_message()])
		restore_story_progress({}, path)
		return false
	restore_story_progress(parser.data, path)
	return true


func request_story_save() -> void:
	if not story_autosave or _story_save_queued:
		return
	_story_save_queued = true
	_flush_story_save.call_deferred()


func _flush_story_save() -> void:
	_story_save_queued = false
	if story_autosave:
		save_story_progress()
