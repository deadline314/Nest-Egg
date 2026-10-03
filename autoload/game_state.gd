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

var lives_left := -1
## 本輪累計死亡次數（死亡畫面的「NEST 回溯紀錄 #n」、劇情的措辭變化都看它）。
## 屬於本輪進度，不存進檢查點：回溯、重開關卡、換關都不會歸零，只有開始新的一輪才歸零。
var deaths := 0
## 最近一次死亡當下的世界時間（廣播念出來用，見 world_clock_text）；還沒死過是空字串。
var last_death_clock := ""
## 剛死亡、下一次建立關卡就是重生（關卡建立時消耗，播出重生後的反應通訊）。
var respawn_pending := false
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


func set_checkpoint(position: Vector2, loadout_snapshot: Dictionary, world_snapshot: Dictionary = {}, progress_snapshot: Dictionary = {}) -> void:
	has_checkpoint = true
	checkpoint_position = position
	checkpoint_loadout = loadout_snapshot.duplicate(true)
	checkpoint_world = world_snapshot.duplicate(true)
	checkpoint_progress = progress_snapshot.duplicate(true)
	EventBus.checkpoint_reached.emit(position)


func clear_checkpoint() -> void:
	has_checkpoint = false
	checkpoint_position = Vector2.ZERO
	checkpoint_loadout = level_start_loadout.duplicate(true)
	checkpoint_world = {}
	checkpoint_progress = {}


## 通關時呼叫：記下要帶進下一關的武器欄與消耗品。
func carry_over(loadout_snapshot: Dictionary) -> void:
	_carried_loadout = loadout_snapshot.duplicate(true)


## 進入新關卡：清掉檢查點，記下此刻的成長進度，並帶入上一關的武器與消耗品（成長與裝備都會帶到下一關）。
func enter_level() -> void:
	level_start_loadout = _carried_loadout
	_carried_loadout = {}
	clear_checkpoint()
	level_start_progress = Progression.snapshot()


## 記錄一次死亡。回傳 true = 可從檢查點續玩；false = 殘機用盡，進度重置。
func register_death() -> bool:
	deaths += 1
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


func _on_enemy_killed(_enemy_id: StringName, by_finisher: bool) -> void:
	kills += 1
	if by_finisher:
		finishers += 1
