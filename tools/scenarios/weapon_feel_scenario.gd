class_name WeaponFeelScenario
extends ScenarioBase
## 截圖情境（NE-139）：每把武器各在一個位置開一發槍口回饋（閃光、光、火花），0.04 秒後拍一張；再各打一個命中標記。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=weapon_feel

const LIGHTING := "res://data/lighting/neutral.tres"
const WEAPONS: Array[String] = ["pistol", "smg", "rifle", "laser", "spread", "launcher", "railgun", "mech_cannon"]


func run() -> void:
	await open_arena(LIGHTING, 6.0)
	place_player(3.0)
	await wait(0.5)
	WeaponSystem._last_muzzle_fx.clear()
	for i in WEAPONS.size():
		var weapon := load("res://data/weapons/%s.tres" % WEAPONS[i]) as WeaponData
		var origin := Vector2((6.0 + float(i) * 2.6) * 16.0, FLOOR_Y - 34.0)
		WeaponSystem.muzzle_feedback(weapon, origin, Vector2.RIGHT)
		HitFeedback.reset_budget()
		HitFeedback.play(&"armor", origin + Vector2(30, 6), Vector2.LEFT, weapon.color, {"weak": i % 3 == 2})
	await wait(0.04)
	capture("weapons_0")
	await wait(0.1)
	capture("weapons_1")
	await finish()
