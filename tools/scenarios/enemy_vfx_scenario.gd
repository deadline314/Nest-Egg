extends ScenarioBase
## 敵人專屬特效：每個指定的敵人在轉運站光影下被一槍擊殺，擊殺後 0.1 秒拍一張（死亡演出的最亮瞬間）。
## --times=0.05,0.2,0.5：改成在擊殺後這幾個時間點各拍一張（看死亡演出怎麼演進）；沒指定就是 0.1 秒一張。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=enemy_vfx --enemies=grunt,warden,shock_hound [--tag=vfx] [--times=0.05,0.2,0.5]

var _enemies: PackedStringArray = ["grunt"]
var _tag := "vfx"
var _times: Array[float] = [0.1]


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			_enemies = arg.trim_prefix("--enemies=").split(",", false)
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--times="):
			_times.clear()
			for part in arg.trim_prefix("--times=").split(",", false):
				_times.append(float(part))
	await open_arena("res://data/lighting/transfer.tres", 6.0)
	player.global_position = Vector2(4 * 16.0, FLOOR_Y)
	var lamp := LightKit.create_point_light(Color(0.75, 0.85, 1.0), 220.0, 0.55, false)  # 冷光，讓身體看得到但特效的暖色仍然突出
	lamp.global_position = Vector2(11.0 * 16.0, FLOOR_Y - 70.0)
	level.add_child(lamp)
	for id in _enemies:
		var enemy := spawn_enemy("res://data/enemies/%s.tres" % id, 12.0, FLOOR_Y - (40.0 if "drone" in id else 0.0))
		enemy.process_mode = Node.PROCESS_MODE_DISABLED if false else Node.PROCESS_MODE_INHERIT
		place_player(8.0)
		await wait(0.6)
		var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
		lethal.ignore_invulnerability = true
		lethal.bypass_guard = true
		lethal.origin = player.global_position
		enemy.health.take_damage(lethal)
		var elapsed := 0.0
		for time in _times:
			await wait(maxf(0.0, time - elapsed))
			elapsed = time
			capture("%s_%s_death_%03d" % [_tag, id, int(time * 100.0)])
		await wait(1.2)
	await finish()
