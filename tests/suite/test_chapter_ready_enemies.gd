class_name ChapterReadyEnemiesSuite
extends EnemySuiteBase
## 舊開發關卡的敵人放進章節之前的相容檢查（NE-470）：鎮暴員、重裝機槍手、狙擊手、擲彈兵，
## 加上兩種用資料換外觀的收帳人變體（重槍手、盾手）。
## 場地見 EnemySuiteBase：掩體牆在欄 30～31（高 7 格），地面在第 20 列。

const RUSHER := "res://data/enemies/shield_rusher.tres"
const GUNNER := "res://data/enemies/heavy_gunner.tres"
const SNIPER := "res://data/enemies/sniper.tres"
const MORTAR := "res://data/enemies/mortar.tres"
const COLLECTOR_HEAVY := "res://data/enemies/collector_heavy.tres"
const COLLECTOR_SHIELD := "res://data/enemies/collector_shield.tres"


func run() -> void:
	check_enemy_data([RUSHER, GUNNER, SNIPER, MORTAR, COLLECTOR_HEAVY, COLLECTOR_SHIELD],
			[&"collector_heavy_contact", &"collector_shield_contact", &"rusher_charge", &"heavy_gunner_shot"])
	_test_variant_looks()
	await _test_mortar_needs_to_see()
	await _test_gunner_engaged_while_closing()
	await _test_collector_heavy_has_no_front_armor()
	await _test_charge_stops_at_live_water()
	await _test_charge_into_obstacle_dazes()
	await check_defeatable_on_every_difficulty([COLLECTOR_HEAVY, COLLECTOR_SHIELD])


## 收帳人變體沿用原本的行為，只換外觀與數值；名稱不再寫天穹。
func _test_variant_looks() -> void:
	var heavy := load(COLLECTOR_HEAVY) as EnemyData
	var shield := load(COLLECTOR_SHIELD) as EnemyData
	check(heavy.behavior == (load(GUNNER) as EnemyData).behavior and heavy.rig_skin == "collector_brute" and heavy.rig_weapon == "minigun",
			"the collector heavy is the heavy gunner's behaviour on the collector brute's look")
	check(shield.behavior == (load(RUSHER) as EnemyData).behavior and shield.rig_skin == "ch2_escort" and shield.rig_shield,
			"the shield collector is the riot officer's behaviour on the escort's look")
	for data: EnemyData in [heavy, shield]:
		check(not data.display_name.contains("天穹"), "%s is not named after the Dome" % data.id)


## 擲彈兵要先看到玩家才開砲；看到之後幾秒內，玩家躲到掩體後牠還是會越過掩體拋過去。
func _test_mortar_needs_to_see() -> void:
	await open_level(25.0)
	var mortar := spawn(MORTAR, 40.0)
	var aimed := false
	var engaged := false
	for i in 150:
		await physics_frames(1)
		place_player(25.0)
		aimed = aimed or mortar.fsm.is_in(&"aim")
		engaged = engaged or mortar.is_engaged()
	check(not aimed, "the grenadier does not fire at a player it has never seen (behind a wall)")
	check(not engaged, "an unseen player does not put the grenadier into combat (stealth challenges)")
	# 走出掩體：看到了就開砲。
	var seen_aim := false
	for i in 150:
		await physics_frames(1)
		place_player(33.0)
		if mortar.fsm.is_in(&"aim"):
			seen_aim = true
			break
	check(seen_aim, "the grenadier fires once it sees the player")
	# 再躲回牆後：還記得，越過牆拋過去。
	var lobbed_over := false
	for i in 220:
		await physics_frames(1)
		place_player(25.0)
		if i > 40 and mortar.fsm.is_in(&"aim"):
			lobbed_over = true
			break
	check(lobbed_over, "right after seeing the player, the grenadier lobs over the cover")
	# 很久沒看到就忘了。
	await physics_frames(int(60.0 * (4.0 + 1.0)))
	var late_aim := false
	for i in 180:
		await physics_frames(1)
		place_player(25.0)
		late_aim = late_aim or mortar.fsm.is_in(&"aim")
	check(not late_aim, "after a while out of sight the grenadier stops firing at the hidden player")
	await end_level(level)


## 重裝機槍手看到玩家、正在走近時就算已經發現玩家（還在巡邏狀態裡）。
func _test_gunner_engaged_while_closing() -> void:
	await open_level(10.0)
	var gunner := spawn(GUNNER, 28.0)
	var closing_engaged := false
	for i in 60:
		await physics_frames(1)
		place_player(10.0)
		if gunner.fsm.is_in(&"patrol") and absf(gunner.velocity.x) > 1.0 and signf(gunner.velocity.x) == -1.0:
			closing_engaged = gunner.is_engaged()
			break
	check(closing_engaged, "a heavy gunner walking toward a player it has seen counts as engaged")
	await end_level(level)


## 收帳人·重槍手沒有正面裝甲；天穹的重裝機槍手有。
func _test_collector_heavy_has_no_front_armor() -> void:
	await open_level(10.0)
	var armored := spawn(GUNNER, 20.0)
	var plain := spawn(COLLECTOR_HEAVY, 40.0)
	await physics_frames(4)
	armored.facing = -1
	plain.facing = -1
	var armored_before := armored.health.current
	var plain_before := plain.health.current
	armored.hurtbox.receive(hit(1, false, armored.global_position + Vector2(-40, -20)))
	plain.hurtbox.receive(hit(1, false, plain.global_position + Vector2(-40, -20)))
	check(armored.health.current == armored_before, "the Dome heavy gunner blocks a hit from the front")
	check(plain.health.current == plain_before - 1, "the collector heavy takes a hit from the front")
	await end_level(level)


## 衝鋒到通電的積水邊就停下，不會自己衝進去。
func _test_charge_stops_at_live_water() -> void:
	await open_level(10.0)
	var rusher := spawn(RUSHER, 22.0)
	var water := RefCounted.new()
	var water_rect := Rect2(Vector2(14.0 * 16.0, FLOOR_Y - 40.0), Vector2(48.0, 40.0))
	HazardZones.register(water, water_rect)
	var charged := false
	var entered := false
	for i in 200:
		await physics_frames(1)
		place_player(10.0)
		charged = charged or rusher.fsm.is_in(&"charge")
		entered = entered or water_rect.has_point(rusher.global_position + Vector2(0, -1))
	HazardZones.unregister(water)
	check(charged, "the riot officer charges at the player")
	check(not entered, "its charge stops at the edge of electrified water")
	await end_level(level)


## 衝鋒撞上擋路的實心物（像落地的貨箱，碰撞層和牆一樣）會暈眩並放下盾。
func _test_charge_into_obstacle_dazes() -> void:
	await open_level(10.0)
	var block := StaticBody2D.new()
	block.collision_layer = Layers.WORLD
	block.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	(shape.shape as RectangleShape2D).size = Vector2(32.0, 32.0)
	block.add_child(shape)
	block.position = Vector2(16.0 * 16.0, FLOOR_Y - 16.0)
	level._entities.add_child(block)
	# 玩家站在箱子上：看得到，衝過來就撞上箱子。
	var rusher := spawn(COLLECTOR_SHIELD, 24.0)
	var dazed := false
	for i in 240:
		await physics_frames(1)
		place_player(16.0, FLOOR_Y - 32.0)
		if rusher.fsm.is_in(&"dazed"):
			dazed = true
			break
	check(dazed, "a shield charge into a crate-sized obstacle dazes the charger")
	var before := rusher.health.current
	rusher.hurtbox.receive(hit(1, false, rusher.global_position + Vector2(rusher.facing * 30.0, -20)))
	check(rusher.health.current == before - 1, "a dazed charger can be hit from the front")
	await end_level(level)
