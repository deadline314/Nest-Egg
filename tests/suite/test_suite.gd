@abstract
class_name TestSuite
extends RefCounted
## 測試套件基底：每個功能一份套件（tests/suite/），由 smoke_test.gd 依序執行，
## 斷言與失敗統計共用同一個執行器，輸出格式不變。
## 子類別實作 run()（可以 await），用 check() 斷言。

var runner: Node


func _init(p_runner: Node) -> void:
	runner = p_runner


@abstract func run() -> void


func check(condition: bool, message: String) -> void:
	runner._check(condition, message)


func frames(count: int) -> void:
	await runner._frames(count)


func physics_frames(count: int) -> void:
	for i in count:
		await runner.get_tree().physics_frame


## 以指定關卡資料開一輪新遊戲並建立關卡（回傳已加入場景樹的 Level）。
func start_level(data: LevelData, difficulty_index := 1) -> Level:
	GameState.start_new_run(GameState.difficulties[difficulty_index])
	return await spawn_level(data)


## 建立關卡但不重置本輪狀態（模擬死亡後從檢查點重生）。
func spawn_level(data: LevelData) -> Level:
	var level := Level.new()
	level.configure(data)
	runner.get_tree().root.add_child(level)
	await frames(3)
	return level


func end_level(level: Level) -> void:
	await runner._end_level(level)
