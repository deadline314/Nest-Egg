extends Node
## 遊戲進入點與畫面路由：主選單 → 關卡 → 過關畫面。
## 同一時間只存在一個畫面；切換時舊畫面完整釋放，避免記憶體累積。

const FIRST_LEVEL := "res://data/levels/level_01.tres"
const RETRY_CAPTION := "回溯 #%d"
const RETRY_HOLD := 0.22

var _screen: Node
## 目前這一關的資料路徑（重試會重載同一關；通關後依 LevelData.next_level 接續）。
var _level_path := FIRST_LEVEL


func _ready() -> void:
	add_child(LightKit.create_environment())
	_show_main_menu()


## 換畫面：用轉場蓋住 → 釋放舊畫面並加入新畫面 → 揭開。
func _switch_to(screen: Node, kind := Transition.Kind.FADE, center := Vector2(0.5, 0.5),
		caption := "", hold := 0.0) -> void:
	await Transition.play(kind, _swap_screen.bind(screen), -1.0, center, caption, hold)


func _swap_screen(screen: Node) -> void:
	if is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
	get_tree().paused = false
	Fx.reset_time()
	_screen = screen
	add_child(screen)


func _show_main_menu() -> void:
	var menu := MainMenu.new()
	menu.start_requested.connect(_on_start_requested, CONNECT_DEFERRED)
	menu.quit_requested.connect(get_tree().quit, CONNECT_DEFERRED)
	_switch_to(menu, Transition.Kind.SCAN)


func _on_start_requested(difficulty: DifficultyData) -> void:
	GameState.start_new_run(difficulty)
	_level_path = FIRST_LEVEL
	_load_level(Transition.Kind.SCAN)


func _load_level(kind := Transition.Kind.IRIS, caption := "", hold := 0.0) -> void:
	var data: LevelData = load(_level_path) as LevelData if ResourceLoader.exists(_level_path) else null
	if data == null:
		push_error("[Main] 無法載入關卡：%s" % _level_path)
		_show_main_menu()
		return
	var level := Level.new()
	level.configure(data)
	level.retry_requested.connect(_on_retry_requested.bind(level), CONNECT_DEFERRED)
	level.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	level.completed.connect(_on_level_completed.bind(data), CONNECT_DEFERRED)
	_switch_to(level, kind, Vector2(0.5, 0.5), caption, hold)


## 死亡後重來用雜訊溶解並標示回溯編號；暫停選單的「從檢查點重來」用光圈。
func _on_retry_requested(level: Level) -> void:
	if is_instance_valid(level) and level.died:
		_load_level(Transition.Kind.GLITCH, RETRY_CAPTION % GameState.deaths, RETRY_HOLD)
	else:
		_load_level(Transition.Kind.IRIS)


## 過關：有下一關就接續（帶著成長與裝備），否則進入結算畫面。下一關讀不到時退回結算，不會卡住。
func _on_level_completed(data: LevelData) -> void:
	if not data.next_level.is_empty() and ResourceLoader.exists(data.next_level):
		_level_path = data.next_level
		GameState.enter_level()
		_load_level(Transition.Kind.ELEVATOR)
	else:
		if not data.next_level.is_empty():
			push_error("[Main] 找不到下一關：%s，直接進入結算。" % data.next_level)
		_show_victory()


func _show_victory() -> void:
	var screen := VictoryScreen.new()
	screen.replay_requested.connect(_on_start_requested.bind(GameState.difficulty), CONNECT_DEFERRED)
	screen.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	_switch_to(screen, Transition.Kind.BLINDS)
