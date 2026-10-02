extends Node
## 遊戲進入點與畫面路由：主選單 → 關卡 → 過關畫面。
## 同一時間只存在一個畫面；切換時舊畫面完整釋放，避免記憶體累積。

const LEVEL_PATH := "res://data/levels/level_01.tres"

var _screen: Node


func _ready() -> void:
	add_child(LightKit.create_environment())
	_show_main_menu()


func _switch_to(screen: Node) -> void:
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
	_switch_to(menu)


func _on_start_requested(difficulty: DifficultyData) -> void:
	GameState.start_new_run(difficulty)
	_load_level()


func _load_level() -> void:
	var data: LevelData = load(LEVEL_PATH) as LevelData if ResourceLoader.exists(LEVEL_PATH) else null
	if data == null:
		push_error("[Main] 無法載入關卡：%s" % LEVEL_PATH)
		_show_main_menu()
		return
	var level := Level.new()
	level.configure(data)
	level.retry_requested.connect(_load_level, CONNECT_DEFERRED)
	level.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	level.completed.connect(_show_victory, CONNECT_DEFERRED)
	_switch_to(level)


func _show_victory() -> void:
	var screen := VictoryScreen.new()
	screen.replay_requested.connect(_on_start_requested.bind(GameState.difficulty), CONNECT_DEFERRED)
	screen.menu_requested.connect(_show_main_menu, CONNECT_DEFERRED)
	_switch_to(screen)
