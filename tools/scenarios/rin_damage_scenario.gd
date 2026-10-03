extends ScenarioBase
## NE-70 情境：凜在轉運站光影下被一槍一槍打中，衣物依序脫落（夾克 → 連身衣 → 絲襪）。
## 每次受傷各拍一張（hit_N），第一次脫落（夾克）另外拍一張噴飛中的畫面（fly）。
## 最後回滿血再拍一張（healed）：衣物片全部回來。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=rin_damage

const MAX_HEALTH := 6


func run() -> void:
	await open_arena("res://data/lighting/transfer.tres", 20.0)
	player.health.setup(MAX_HEALTH, 0.0)
	player.global_position = Vector2(20 * 16.0, FLOOR_Y)
	snap_camera()
	# 頭頂一盞暖光燈（沒有燈的話整個場地黑到看不清衣物）。
	var lamp := LightKit.create_point_light(Color(1.0, 0.85, 0.6), 190.0, 1.6, false)
	lamp.global_position = player.global_position + Vector2(-26, -64)
	level.add_child(lamp)
	await wait(1.6)
	capture("rin_damage_hit0")
	for hit in range(1, MAX_HEALTH):
		var info := DamageInfo.create(1, Combat.Team.ENEMY, &"test")
		info.ignore_invulnerability = true
		player.health.take_damage(info)
		if hit == 2:
			await wait(0.18)
			capture("rin_damage_fly")
		await wait(1.1)
		capture("rin_damage_hit%d" % hit)
	# 吃補給回血：衣物依比例回來。
	player.health.heal(MAX_HEALTH)
	await wait(1.0)
	capture("rin_damage_healed")
	await finish()
