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
	EventBus.lives_changed.emit(lives_left)


func set_checkpoint(position: Vector2, loadout_snapshot: Dictionary) -> void:
	has_checkpoint = true
	checkpoint_position = position
	checkpoint_loadout = loadout_snapshot.duplicate(true)
	EventBus.checkpoint_reached.emit(position)


func clear_checkpoint() -> void:
	has_checkpoint = false
	checkpoint_position = Vector2.ZERO
	checkpoint_loadout = {}


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
