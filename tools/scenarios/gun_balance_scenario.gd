class_name GunBalanceScenario
extends ScenarioBase
## 槍械實測（NE-236／NE-241）：空曠訓練場，真正的玩家按住射擊鍵、手把右搖桿瞄準，逐把槍打固定距離的目標，
## 記錄第一次命中時間、擊倒時間、開槍數、命中數、換彈次數與目標被推開的距離。目標不動不還手（只量武器本身）。
## 用法：godot --headless --fixed-fps 60 res://tools/screenshot.tscn -- --out=<資料夾> --scenario=gun_balance
## 結果印成一行一筆的 GUN_BALANCE JSON，並寫入 <資料夾>/gun-balance.json。
## 每把槍量兩輪：基礎、買齊這把槍能用的改裝（upgraded）；另外對打不死的木樁量 SUSTAIN_TIME 秒的持續輸出（含換彈）。

const WEAPONS := ["pistol", "smg", "rifle", "spread", "laser", "railgun", "launcher", "mech_cannon"]
const TARGETS := ["grunt", "collector_brute"]
const DISTANCES := [64.0, 128.0, 224.0]
const LIMIT := 12.0
const PLAYER_TILE := 12.0
const SUSTAIN_TIME := 6.0
const SUSTAIN_DISTANCE := 128.0

var _rows: Array[Dictionary] = []


func run() -> void:
	await open_arena("", PLAYER_TILE)
	await clear_enemies()
	Enemy.activation_culling_enabled = false
	AimInput.set_virtual_gamepad(player, true)
	Progression.credits = 1000000
	for upgraded: bool in [false, true]:
		for weapon_id: String in WEAPONS:
			var weapon := load("res://data/weapons/%s.tres" % weapon_id) as WeaponData
			if weapon == null:
				continue
			if upgraded:
				for upgrade in Progression.upgrades_for(weapon):
					Progression.buy_upgrade(weapon, upgrade)
			for target_id: String in TARGETS:
				for distance: float in DISTANCES:
					var row := await _sample(weapon, target_id, distance)
					row["upgraded"] = upgraded
					_rows.append(row)
			var sustain := await _sample(weapon, "grunt", SUSTAIN_DISTANCE, SUSTAIN_TIME)
			sustain["upgraded"] = upgraded
			sustain["sustain_dps"] = snappedf(float(sustain["damage"]) / SUSTAIN_TIME, 0.01)
			_rows.append(sustain)
	AimInput.set_virtual_gamepad(player, false)
	var file := FileAccess.open(out_dir.path_join("gun-balance.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "hz": Engine.physics_ticks_per_second, "samples": _rows}, "  "))
	await finish()


## sustain_seconds > 0：打不死的木樁，固定量這麼多秒（持續輸出）。
func _sample(weapon: WeaponData, target_id: String, distance: float, sustain_seconds := 0.0) -> Dictionary:
	await clear_enemies()
	place_player(PLAYER_TILE)
	player.loadout.reset(weapon)
	player.health.setup(9999, 0.0)
	var enemy := spawn_enemy("res://data/enemies/%s.tres" % target_id, PLAYER_TILE + distance / 16.0)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	if sustain_seconds > 0.0:
		enemy.health.setup(999999, 0.0)
	# 等上一筆的射擊間隔與換彈結束，每一筆都從「可以開火」開始量。
	for i in 180:
		if player._fire_cooldown_left <= 0.0 and not player.loadout.is_reloading():
			break
		await get_tree().physics_frame
	var target := enemy.hurtbox.center()
	var dir := (target - player.muzzle_position()).normalized()
	for pair: Array in [[&"aim_right", maxf(0.0, dir.x)], [&"aim_left", maxf(0.0, -dir.x)], [&"aim_down", maxf(0.0, dir.y)], [&"aim_up", maxf(0.0, -dir.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
	await get_tree().physics_frame
	var ammo_start := player.loadout.mag_in(player.loadout.active_slot)
	# 用字典累計：GDScript 的 lambda 以值捕捉區域變數，直接 += 整數不會反映到外面。
	var stats := {"hits": 0, "damage": 0, "first_hit": -1.0}
	var shots := 0
	var reloads := 0
	var was_reloading := false
	var peak_push := 0.0
	var record := func(info: DamageInfo) -> void:
		stats["hits"] += 1
		stats["damage"] += info.amount
		if float(stats["first_hit"]) < 0.0:
			stats["first_hit"] = _elapsed
	enemy.health.damaged.connect(record)
	_elapsed = 0.0
	var last_mag := ammo_start
	Input.action_press(&"shoot")
	var limit := sustain_seconds if sustain_seconds > 0.0 else LIMIT
	while _elapsed < limit and is_instance_valid(enemy) and not enemy.is_dying():
		await get_tree().physics_frame
		_elapsed += get_physics_process_delta_time()
		var mag := player.loadout.mag_in(player.loadout.active_slot)
		if mag < last_mag:
			shots += last_mag - mag
		last_mag = mag
		var reloading := player.loadout.is_reloading()
		if reloading and not was_reloading:
			reloads += 1
		was_reloading = reloading
		if is_instance_valid(enemy) and not enemy.is_dying():
			peak_push = maxf(peak_push, absf(enemy.velocity.x))
	Input.action_release(&"shoot")
	var killed := not is_instance_valid(enemy) or enemy.is_dying()
	if is_instance_valid(enemy) and enemy.health.damaged.is_connected(record):
		enemy.health.damaged.disconnect(record)
	var row := {
		"weapon": String(weapon.id), "target": target_id, "distance": distance, "sustain": sustain_seconds > 0.0,
		"killed": killed, "time_to_kill": snappedf(_elapsed, 0.01) if killed else null,
		"first_hit_s": snappedf(float(stats["first_hit"]), 0.01) if float(stats["first_hit"]) >= 0.0 else null,
		"shots": shots, "hits": int(stats["hits"]), "damage": int(stats["damage"]), "reloads": reloads,
		"peak_knockback_speed": snappedf(peak_push, 1.0),
	}
	print("GUN_BALANCE " + JSON.stringify(row))
	await get_tree().create_timer(0.3).timeout
	return row


var _elapsed := 0.0
