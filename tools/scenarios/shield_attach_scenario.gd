class_name ShieldAttachScenario
extends ScenarioBase
## 截圖情境（NE-239）：用真正的按鍵舉盾、手把右搖桿瞄準，拍不同武器、上中下瞄準與跳躍時，盾由前手手腕投射的樣子。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=shield_attach

const LIGHTING := "res://data/lighting/neutral.tres"
const WEAPONS := ["pistol", "rifle", "launcher", "railgun"]
const AIMS := {"mid": Vector2.RIGHT, "up": Vector2(1, -1), "down": Vector2(1, 0.8)}


func run() -> void:
	await open_arena(LIGHTING, 20.0)
	await clear_enemies()
	AimInput.set_virtual_gamepad(player, true)
	for id: String in WEAPONS:
		player.loadout.reset(load("res://data/weapons/%s.tres" % id) as WeaponData)
		for aim_name: String in AIMS:
			place_player(20.0)
			_stick((AIMS[aim_name] as Vector2).normalized())
			Input.action_press(&"block")
			await wait(0.35)
			capture("NE-239-attach-%s-%s" % [id, aim_name])
			Input.action_release(&"block")
			await wait(0.25)
	# 跳起舉盾：空中也接在手腕上。
	player.loadout.reset(load("res://data/weapons/rifle.tres") as WeaponData)
	_stick(Vector2.RIGHT)
	Input.action_press(&"block")
	Engine.time_scale = 0.25
	Input.action_press(&"jump")
	await settle(8)
	capture("NE-239-attach-rifle-air")
	Engine.time_scale = 1.0
	for action: StringName in [&"jump", &"block", &"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		Input.action_release(action)
	AimInput.set_virtual_gamepad(player, false)
	await finish()


func _stick(direction: Vector2) -> void:
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
