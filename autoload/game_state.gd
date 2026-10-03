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
var deaths := 0
var kills := 0
var finishers := 0
var run_time := 0.0


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


func _on_enemy_killed(_enemy_id: StringName, by_finisher: bool) -> void:
	kills += 1
	if by_finisher:
		finishers += 1
