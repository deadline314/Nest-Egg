class_name FxMeleePickupsScenario
extends ScenarioBase
## 截圖情境（NE-101）：近戰武器各自的軌跡樣式與顏色（匕首刺擊、長刀斬擊、液壓錘砸擊、戰戟刺擊、鞭子甩擊）、終結技、拾取特效。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=fx_melee_pickups

const LIGHTING := "res://data/lighting/neutral.tres"
const SLOWMO := 0.12
const WEAPONS: Array[String] = ["melee_dagger", "melee_blade", "melee_maul", "melee_glaive", "melee_whip"]
const DISTANCES := {"melee_dagger": 1.1, "melee_blade": 1.5, "melee_maul": 1.5, "melee_glaive": 2.8, "melee_whip": 4.2}


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	player.health.setup(999, 0.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	for id in WEAPONS:
		player.loadout.equip(load("res://data/weapons/melee/%s.tres" % id) as WeaponData)
		player.facing = 1
		player.aim_dir = Vector2.RIGHT
		var enemy := _dummy(12.0 + float(DISTANCES[id]))
		await wait(0.3)
		player._melee_cooldown_left = 0.0
		player._try_melee()
		while player._melee_phase != Player.MeleePhase.ACTIVE and player._melee_phase != Player.MeleePhase.NONE:
			await get_tree().physics_frame
		# 慢動作拍：截圖環境的畫面更新很慢，揮擊的軌跡只有零點一秒，不放慢會錯過。
		Engine.time_scale = SLOWMO
		for k in 6:
			await get_tree().process_frame
			if k == 2 or k == 5:
				capture("%s_swing%d" % [id, k])
		Engine.time_scale = 1.0
		await wait(0.6)
		enemy.queue_free()
		player._end_melee()
	# 終結技：把敵人打到破防再終結。
	player.loadout.select(0)
	var victim := _dummy(14.0)
	victim.health.setup(10, 0.0)
	var wound := DamageInfo.create(8, Combat.Team.PLAYER, &"scenario")
	wound.bypass_guard = true
	victim.hurtbox.receive(wound)
	victim.stun(3.0)
	await wait(0.3)
	print("finisher ready: ", victim.can_be_finished())
	player.facing = 1
	player._melee_cooldown_left = 0.0
	player._try_melee()
	Engine.time_scale = SLOWMO
	for k in 8:
		await get_tree().process_frame
		if k == 2 or k == 6:
			capture("finisher_%d" % k)
	Engine.time_scale = 1.0
	await wait(0.8)
	# 拾取特效：醫療、信用點、武器。
	player.global_position = Vector2(12.0 * 16.0, FLOOR_Y)
	var items: Array[Pickup] = []
	var heal := HealthPickup.new()
	var credit := CreditPickup.new()
	var gun := WeaponPickup.new()
	gun.configure(load("res://data/weapons/melee/melee_blade.tres") as WeaponData)
	items.append_array([heal, credit, gun])
	var x := 17.0
	for item in items:
		item.global_position = Vector2(x * 16.0, FLOOR_Y)
		level._entities.add_child(item)
		x += 3.0
	await wait(0.4)
	capture("pickups_idle")
	for item in items:
		item._on_body_entered(player)
	Engine.time_scale = SLOWMO
	for k in 5:
		await get_tree().process_frame
	capture("pickups_collected")
	Engine.time_scale = 1.0
	AimInput.using_gamepad = false
	await finish()


func _dummy(tile: float) -> Enemy:
	var enemy := spawn_enemy("res://data/enemies/grunt.tres", tile)
	enemy.health.setup(999, 0.0)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	return enemy
