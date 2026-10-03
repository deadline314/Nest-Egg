class_name ScenarioBase
extends Node
## 截圖情境的共用基底（見 tools/screenshot.gd 的派發）：輸出資料夾、等待、截圖、
## 開空曠測試場地與生成敵人。每個情境一個檔案，覆寫 run()。

const FLOOR_Y := 20 * 16.0
## 關卡開場的章節標題卡淡出需要的時間（拍攝前要等它消失）。
const TITLE_CARD_TIME := 3.8

var out_dir := ""
var level: Level
var player: Player


## 覆寫：拍攝流程（可以 await）。
func run() -> void:
	pass


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func capture(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file_name + ".png")
	var err := image.save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])


func snap_camera() -> void:
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera != null:
		camera.snap_to_target()


## 以測試場地開一個關卡（套用指定的光影設定），玩家站在 x_tile；預設是空曠場地，
## 傳入 EnemySuiteBase.map_data() 則是有掩體牆與平台的場地。
func open_arena(lighting_path: String, player_tile := 12.0, base_data: LevelData = null) -> void:
	var data := base_data if base_data != null else NewEnemiesSuite.arena_data()
	if not lighting_path.is_empty():
		var zone := LightingZone.new()
		zone.start_tile = 0
		zone.profile = load(lighting_path)
		data.lighting_zones = [zone]
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(20)
	player = level.player
	player.health.setup(999, 0.0)
	place_player(player_tile)
	level.hud.visible = false
	await wait(TITLE_CARD_TIME)


func place_player(x_tile: float) -> void:
	player.global_position = Vector2(x_tile * 16.0, FLOOR_Y)
	player.velocity = Vector2.ZERO
	snap_camera()


func spawn_enemy(path: String, x_tile: float, y := FLOOR_Y) -> Enemy:
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(x_tile * 16.0, y)
	level._entities.add_child(enemy)
	return enemy


## 清掉場上所有敵人（死亡演出的延遲節點也一併等掉）。
func clear_enemies() -> void:
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	await settle(3)


func finish() -> void:
	if level != null:
		level.queue_free()
	await settle(3)
