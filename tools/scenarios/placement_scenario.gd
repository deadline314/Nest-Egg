extends ScenarioBase
## 敵人在真正關卡裡的配置截圖：把玩家放在指定敵人的左邊幾格，等一下再拍，確認第一次遭遇的畫面。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=placement --enemies=sniper,searchlight_drone [--tag=NE-46] [--levels=level_01,level_02] [--back=8]
## 每個關卡裡每種敵人只拍第一個配置（檔名 <tag>-<關卡>-<敵人>.png）。

var _enemies: PackedStringArray = []
var _levels: PackedStringArray = ["level_01", "level_02"]
var _tag := "placement"
var _back_tiles := 8.0


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			_enemies = arg.trim_prefix("--enemies=").split(",", false)
		elif arg.begins_with("--levels="):
			_levels = arg.trim_prefix("--levels=").split(",", false)
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--back="):
			_back_tiles = float(arg.trim_prefix("--back="))
	for level_id in _levels:
		await _shoot_level(level_id)


func _shoot_level(level_id: String) -> void:
	var data := load("res://data/levels/%s.tres" % level_id) as LevelData
	if data == null:
		push_error("[PlacementScenario] 找不到關卡：%s" % level_id)
		return
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(25)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	await wait(TITLE_CARD_TIME)
	for enemy_id in _enemies:
		var cells := PlacementChecks.cells_of(level._layout, StringName(enemy_id))
		if cells.is_empty():
			continue
		var cell := cells[0]
		var layout: LevelLayout = level._layout
		var x := maxf(2.0, cell.x - _back_tiles)
		var column := int(x)
		var y := layout.surface_heights[column] - 2.0
		if layout.surface_heights[column] < layout.tile_size * 4.0:
			y = layout.floor_below(column, 4) - 2.0
		player.global_position = Vector2(x * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		snap_camera()
		await wait(1.6)
		capture("%s-%s-%s" % [_tag, level_id, enemy_id])
	level.queue_free()
	await settle(4)
