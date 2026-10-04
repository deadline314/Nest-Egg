class_name MeleeWeaponsScenario
extends ScenarioBase
## 截圖情境（NE-117）：每把近戰武器各揮一次，在前搖、出招、收招各拍一張；最後拍武器欄與背包卡片。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=melee_weapons

const LIGHTING := "res://data/lighting/neutral.tres"
const WEAPONS: Array[String] = ["melee_dagger", "melee_blade", "melee_maul", "melee_glaive", "melee_whip"]
const DISTANCES := {"melee_dagger": 1.3, "melee_blade": 2.0, "melee_maul": 2.2, "melee_glaive": 3.4, "melee_whip": 5.5}


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	for id in WEAPONS:
		player.loadout.equip(load("res://data/weapons/melee/%s.tres" % id) as WeaponData)
		player.facing = 1
		player.aim_dir = Vector2.RIGHT
		var enemy := spawn_enemy("res://data/enemies/grunt.tres", 12.0 + float(DISTANCES[id]))
		enemy.health.setup(999, 0.0)
		enemy.data = enemy.data.duplicate()
		enemy.data.detect_range = 0.0
		enemy.data.attack_range = 0.0
		enemy.data.move_speed = 0.0
		await wait(0.3)
		player._melee_cooldown_left = 0.0
		player._try_melee()
		for phase in [Player.MeleePhase.WINDUP, Player.MeleePhase.ACTIVE, Player.MeleePhase.RECOVERY]:
			var guard := 0
			while player._melee_phase != phase and player._melee_phase != Player.MeleePhase.NONE and guard < 60:
				await get_tree().physics_frame
				guard += 1
			await get_tree().physics_frame
			capture("%s_%d" % [id, phase])
		await wait(0.6)
		enemy.queue_free()
		player._end_melee()
	level.hud.visible = true
	await wait(0.4)
	capture("hud_weapon_bar")
	AimInput.using_gamepad = false
	await finish()
