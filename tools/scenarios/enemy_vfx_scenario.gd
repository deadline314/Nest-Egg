extends ScenarioBase
## 敵人專屬特效：每個指定的敵人在轉運站光影下被一槍擊殺，擊殺後 0.1 秒拍一張（死亡演出的最亮瞬間）。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=enemy_vfx --enemies=grunt,warden,shock_hound [--tag=vfx]

var _enemies: PackedStringArray = ["grunt"]
var _tag := "vfx"


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			_enemies = arg.trim_prefix("--enemies=").split(",", false)
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	await open_arena("res://data/lighting/transfer.tres", 6.0)
	player.global_position = Vector2(4 * 16.0, FLOOR_Y)
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
		await wait(0.1)
		capture("%s_%s_death" % [_tag, id])
		await wait(0.9)
	await finish()
