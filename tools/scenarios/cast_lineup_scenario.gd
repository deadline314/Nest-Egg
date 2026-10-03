extends ScenarioBase
## NE-74 之後各個敵人重畫票共用：把指定的敵人排成一排站在轉運站光影裡（頭頂一盞暖光燈），旁邊站一個舊的小兵當大小對照，
## 各拍站姿與逐片脫落的裝甲（生命 100%、60%、30%、0%）。碰撞框畫成綠框。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=cast_lineup --enemies=grunt,elite_grunt [--tag=NE-74]

var _enemies: PackedStringArray = ["grunt"]
var _tag := "cast"


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			_enemies = arg.trim_prefix("--enemies=").split(",", false)
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	await open_arena("res://data/lighting/transfer.tres", 6.0)
	player.global_position = Vector2(4 * 16.0, FLOOR_Y)
	var lamp := LightKit.create_point_light(Color(1.0, 0.88, 0.7), 300.0, 1.0, false)
	lamp.global_position = Vector2(10.5 * 16.0, FLOOR_Y - 60.0)
	level.add_child(lamp)
	for id in _enemies:
		for ratio: float in [1.0, 0.6, 0.3, 0.0]:
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
	capture("%s_%s_hp%d" % [_tag, id, int(ratio * 100.0)])
	enemy.queue_free()
	await settle(3)
