extends ScenarioBase
## NE-47 情境：火焰兵（點火預熱、噴射、背後燃料罐爆炸）與重裝機槍手（槍管加速、掃射、過熱空檔）。
## 在偏暗的電力室光影下拍，確認預兆自帶光。

const FLAMER := "res://data/enemies/flamer.tres"
const GUNNER := "res://data/enemies/heavy_gunner.tres"
const LIGHTING := "res://data/lighting/power_room.tres"


func run() -> void:
	await open_arena(LIGHTING, 14.0)
	await _flamer()
	await clear_enemies()
	await _gunner()
	await finish()


func _flamer() -> void:
	var flamer := spawn_enemy(FLAMER, 22.0) as Flamer
	place_player(15.0)
	while not flamer.fsm.is_in(&"ignite"):
		await wait(0.05)
	await wait(0.45)
	capture("NE-47-flamer-ignite")
	while not flamer.fsm.is_in(&"burn"):
		await wait(0.03)
	await wait(0.3)
	capture("NE-47-flamer-burn")
	while not flamer.fsm.is_in(&"patrol"):
		await wait(0.05)
	# 繞到背後打燃料罐：兩發引爆。
	var info := DamageInfo.create(1, Combat.Team.PLAYER, &"scenario")
	info.ignore_invulnerability = true
	flamer.tank.hurtbox.receive(info)
	await wait(0.3)
	capture("NE-47-flamer-tank-hit")
	var second := DamageInfo.create(1, Combat.Team.PLAYER, &"scenario")
	second.ignore_invulnerability = true
	flamer.tank.hurtbox.receive(second)
	await wait(0.28)
	capture("NE-47-flamer-tank-blast")
	await wait(1.5)


func _gunner() -> void:
	place_player(12.0)
	var gunner := spawn_enemy(GUNNER, 25.0) as HeavyGunner
	while not gunner.fsm.is_in(&"spin_up"):
		await wait(0.05)
	await wait(gunner.data.telegraph_time * 0.85)
	capture("NE-47-gunner-spin-up")
	while not gunner.fsm.is_in(&"fire"):
		await wait(0.03)
	await wait(gunner.data.ability_time * 0.7)
	capture("NE-47-gunner-fire")
	while not gunner.fsm.is_in(&"vent"):
		await wait(0.03)
	await wait(0.7)
	capture("NE-47-gunner-vent")
