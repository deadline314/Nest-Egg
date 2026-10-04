extends ScenarioBase
## NE-74 之後各個敵人重畫票共用：把指定的敵人排成一排站在轉運站光影裡（頭頂一盞暖光燈），旁邊站一個舊的小兵當大小對照，
## 各拍站姿與逐片脫落的裝甲（生命 100%、60%、30%、0%）。碰撞框畫成綠框。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=cast_lineup --enemies=grunt,elite_grunt [--tag=NE-74]
##        [--lighting=transfer]（改用 data/lighting/ 底下的其他光影）[--ratios=1.0,0.6]（只拍指定的生命比例）[--no-lamp]（不放暖光燈，只看光影設定本身）

var _enemies: PackedStringArray = ["grunt"]
var _tag := "cast"
var _lighting := "transfer"
var _lamp := true
var _ratios: Array[float] = [1.0, 0.6, 0.3, 0.0]


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			_enemies = arg.trim_prefix("--enemies=").split(",", false)
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--lighting="):
			_lighting = arg.trim_prefix("--lighting=")
		elif arg == "--no-lamp":
			_lamp = false
		elif arg.begins_with("--ratios="):
			_ratios.clear()
			for text in arg.trim_prefix("--ratios=").split(",", false):
				_ratios.append(text.to_float())
	await open_arena("res://data/lighting/%s.tres" % _lighting, 6.0)
	player.global_position = Vector2(4 * 16.0, FLOOR_Y)
	if _lamp:
		var lamp := LightKit.create_point_light(Color(1.0, 0.88, 0.7), 300.0, 1.0, false)
		lamp.global_position = Vector2(10.5 * 16.0, FLOOR_Y - 60.0)
		level.add_child(lamp)
	for id in _enemies:
		for ratio in _ratios:
			await _shoot(id, ratio)
	await finish()


func _shoot(id: String, ratio: float) -> void:
	var enemy := spawn_enemy("res://data/enemies/%s.tres" % id, 12.0)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var rig := enemy.get("rig") as CharacterRig
	if rig != null:
		rig.set_armor_ratio(ratio, false)
	place_player(8.0)
	player.velocity = Vector2.ZERO
	await wait(1.4)
	# 衝刺型的敵人在關卡開場就已經動起來，停用處理前移動過的位置拉回排隊的地方。
	enemy.global_position = Vector2(12.0 * 16.0, FLOOR_Y)
	enemy.velocity = Vector2.ZERO
	await settle(2)
	capture("%s_%s_hp%d" % [_tag, id, int(ratio * 100.0)])
	enemy.queue_free()
	await settle(3)
