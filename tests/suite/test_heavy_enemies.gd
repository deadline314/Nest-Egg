class_name HeavyEnemiesSuite
extends EnemySuiteBase
## 重裝型敵人（NE-47）：火焰兵（點火預熱、噴射範圍與持續時間、背後燃料罐爆炸）
## 與重裝機槍手（槍管加速、停步掃射、過熱空檔、正面裝甲、爆炸無視裝甲）。

const FLAMER_PATH := "res://data/enemies/flamer.tres"
const GUNNER_PATH := "res://data/enemies/heavy_gunner.tres"
const WARDEN_PATH := "res://data/enemies/warden.tres"


func run() -> void:
	_test_data()
	_test_level_placement()
	await _test_flamer_attack()
	await _test_flamer_range_and_interrupt()
	await _test_flamer_tank()
	await _test_flamer_tank_shots()
	await _test_gunner_sequence()
	await _test_gunner_armor()
	await _test_warden_core_cannon()
	await _test_codex_unlocks()
	await check_defeatable_on_every_difficulty([FLAMER_PATH, GUNNER_PATH])


func _test_data() -> void:
	check_enemy_data([FLAMER_PATH, GUNNER_PATH], [&"flamer_burn", &"flamer_contact", &"flamer_tank_blast", &"heavy_gunner_shot", &"heavy_gunner_contact"])
	var gunner := load(GUNNER_PATH) as EnemyData
	var flamer := load(FLAMER_PATH) as EnemyData
	check(gunner.telegraph_time >= 0.8, "the gunner's barrel spin-up is a long windup")
	check(gunner.max_health > load(GRUNT_PATH).max_health * 2, "the heavy gunner is much tougher than a trooper")
	check(flamer.ability_damage >= 1 and flamer.projectile != null and flamer.projectile.explosion_radius > 0.0, "the flamer's fuel tank has durability and a blast")
	check(flamer.projectile.explosion_damage >= flamer.max_health * 0.5, "the fuel tank blast takes at least half of the flamer's health")


## 配置：第二章升降井（70～139）、夾層區後段（180～214）與電力室（215～274）。
func _test_level_placement() -> void:
	check_level_placement({
		"res://data/levels/level_02.tres": [[&"flamer", 70, 140], [&"flamer", 325, 385], [&"heavy_gunner", 180, 215], [&"heavy_gunner", 325, 385]],
	})


## 點火預熱（預兆、火舌逐漸變長）→ 噴射（範圍、持續時間）→ 收火，期間站在火裡會受傷。
func _test_flamer_attack() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	place_player(40.0 - 3.0)
	level.player.health.setup(50, 0.0)
	var before := level.player.health.current
	var ignited := await wait_state(flamer, &"ignite", 60 * 3)
	check(ignited, "the flamer ignites when the player is within reach")
	check(flamer.is_telegraphing(), "igniting is a telegraph")
	check(not flamer._flame_box.active, "no flame damage during the warm-up")
	await physics_frames(20)
	var early_length := flamer.flame_length
	var burning := await wait_state(flamer, &"burn", 60 * 3)
	check(burning, "the flame jets after the warm-up")
	check(flamer._flame_box.active and early_length < flamer.data.attack_range * 0.5, "the flame grows during the warm-up (%.0f) and is live while burning" % early_length)
	for i in 240:
		if flamer.fsm.time_in_state >= 0.4:
			break
		await physics_frames(1)
	check(absf(flamer.flame_length - flamer.data.attack_range) < 1.0, "the flame reaches its full length (%.1f)" % flamer.flame_length)
	check(flamer._flame_light.enabled, "the flame lights its surroundings")
	check(level.player.health.current < before, "standing in the flame hurts")
	var burn_seconds := 0.0
	for i in 60 * 6:
		if not flamer.fsm.is_in(&"burn"):
			break
		burn_seconds = flamer.fsm.time_in_state
		await physics_frames(1)
	check(flamer.fsm.is_in(&"recover") and not flamer._flame_box.active, "the flame goes out after its duration")
	check(absf(burn_seconds - flamer.data.ability_time) < 0.15, "the burn lasts the configured time (%.2f s of %.1f)" % [burn_seconds, flamer.data.ability_time])
	var back := await wait_state(flamer, &"patrol", 60 * 3)
	check(back and flamer._cooldown > 0.0, "the flamer has a cooldown after burning")
	flamer.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 火焰有固定射程：遠一點的玩家不會受傷；暈眩（完美格擋）會中斷噴射。
func _test_flamer_range_and_interrupt() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	place_player(40.0 - 11.0)
	level.player.health.setup(50, 0.0)
	var before := level.player.health.current
	flamer.fsm.transition(&"ignite")
	await wait_state(flamer, &"burn", 60 * 3)
	for i in 50:
		await physics_frames(1)
		place_player(40.0 - 11.0)
	check(level.player.health.current == before, "a player beyond the flame's reach is not hurt (11 tiles away)")
	# 暈眩中斷：噴射中被格擋。
	flamer.fsm.transition(&"burn")
	flamer.stun(0.5)
	await physics_frames(2)
	check(flamer.fsm.is_in(&"recover") and not flamer._flame_box.active, "a stun cuts the flame off")
	flamer.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 監管者的核心砲（NE-89 專屬骨頭範例）：第二階段才會用；預兆時胸甲（掛在專屬骨頭 core_plate 上）掀開，
## 發射從專屬骨頭 core_port 出去，發射後核心部位判定外露時雙倍、收起來回到一般。原有招式不受影響。
func _test_warden_core_cannon() -> void:
	await open_level(10.0)
	var warden := spawn(WARDEN_PATH, 30.0)
	place_player(24.0)
	await physics_frames(3)
	var rig := warden.rig
	check(rig != null and rig.has_bone(&"core_plate") and rig.has_bone(&"core_port"), "the warden rig declares its dedicated bones")
	check(rig.parent_of(&"core_plate") == &"chest" and rig.parent_of(&"core_port") == &"chest", "the dedicated bones hang off the chest")
	var plate_sprite := rig.bone(&"core_plate").get_node_or_null("armor_chest")
	check(plate_sprite != null, "the chest plate is mounted on the dedicated plate bone")
	var core_part: Hurtbox = null
	for part in warden.hurtbox.parts:
		if part.part_id == &"core":
			core_part = part
	check(core_part != null and core_part.damage_scale == 1.0, "the core hurt part exists and counts as normal while closed")
	var phase_one_moves := {}
	for i in 40:
		phase_one_moves[warden.call(&"_choose_attack")] = true
	check(not phase_one_moves.has(&"core_windup"), "phase one never uses the core cannon")
	warden.set("_phase", 2)
	var moves := {}
	for i in 80:
		moves[warden.call(&"_choose_attack")] = true
		warden.set("_last_attack", &"")
	check(moves.has(&"core_windup") and moves.has(&"burst_windup") and moves.has(&"leap_windup"), "phase two adds the core cannon to the old moves")
	var rest_angle := rig.bone(&"core_plate").rotation
	warden.fsm.transition(&"core_windup")
	await physics_frames(20)
	check(absf(rig.bone(&"core_plate").rotation - rest_angle) > 0.3, "the plate swings open while the cannon charges (%.2f)" % rig.bone(&"core_plate").rotation)
	var port_world := rig.bone(&"core_port").global_position
	check(warden._core_point().distance_to(warden.to_local(port_world)) < 0.01, "the glow ring and the aim line sit on the core port bone")
	var before := ProjectilePool.active_count()
	var fired := await wait_state(warden, &"core_recover", 90)
	check(fired, "the charge ends in the recover state")
	await physics_frames(1)
	check(ProjectilePool.active_count() >= before + 3, "the cannon fires its volley (%d -> %d)" % [before, ProjectilePool.active_count()])
	check(core_part.damage_scale == 2.0, "the core takes double damage while exposed")
	var exposed := await wait_state(warden, &"idle", 150)
	check(exposed and core_part.damage_scale == 1.0, "the core closes again afterwards")
	await physics_frames(60)
	await end_level(level)


## 燃料罐：打中兩次爆炸；爆炸傷到敵人（含背著它的火焰兵與旁邊的保全）與玩家，並讓火焰兵暈眩。
func _test_flamer_tank() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	var neighbor := spawn(GRUNT_PATH, 42.0)
	neighbor.set_physics_process(false)
	flamer.set_physics_process(false)
	place_player(37.0)
	await physics_frames(3)
	check(flamer.has_tank(), "the flamer carries a fuel tank")
	var tank_behind := flamer.tank.global_position.x > flamer.global_position.x if flamer.facing < 0 else flamer.tank.global_position.x < flamer.global_position.x
	check(tank_behind, "the tank sits on the flamer's back")
	var flamer_before := flamer.health.current
	var neighbor_before := neighbor.health.current
	var player_before := level.player.health.current
	flamer.tank.hurtbox.receive(hit(1))
	check(not flamer.tank.is_exploded, "one hit does not set off the tank")
	flamer.tank.hurtbox.receive(hit(1))
	check(flamer.tank.is_exploded, "enough hits set off the tank")
	flamer.set_physics_process(true)
	await physics_frames(40)
	check(flamer.health.current < flamer_before, "the blast hurts the flamer wearing the tank (%d -> %d)" % [flamer_before, flamer.health.current])
	check(neighbor.health.current < neighbor_before, "the blast hurts a nearby enemy")
	check(level.player.health.current < player_before, "the blast hurts a nearby player too")
	check(flamer.is_dying() or flamer.is_stunned() or flamer.fsm.is_in(&"recover"), "the blast staggers the flamer")
	check(not flamer.has_tank(), "the tank is gone after exploding")
	await physics_frames(120)
	await end_level(level)


## 子彈打到哪裡：從前面打中身體、從背後打中燃料罐。
func _test_flamer_tank_shots() -> void:
	await open_level(10.0)
	var flamer := spawn(FLAMER_PATH, 50.0) as Flamer
	flamer.set_physics_process(false)
	flamer.facing = -1
	flamer.tank.follow(-1, Flamer.TANK_OFFSET)
	place_player(5.0)
	await physics_frames(3)
	var body_before := flamer.health.current
	var tank_before := flamer.tank.health.current
	var y := FLOOR_Y - 28.0
	# 從前面（左邊）朝右射：打中身體。
	shoot_from(Vector2(44.0 * 16.0, y), Vector2.RIGHT)
	await physics_frames(40)
	check(flamer.health.current < body_before and flamer.tank.health.current == tank_before, "a shot from the front hits the flamer, not the tank")
	body_before = flamer.health.current
	# 從背後（右邊）朝左射：先打中燃料罐。
	shoot_from(Vector2(56.0 * 16.0, y), Vector2.LEFT)
	await physics_frames(40)
	check(flamer.tank.health.current < tank_before and flamer.health.current == body_before, "a shot from behind hits the fuel tank first")
	flamer.set_physics_process(true)
	flamer.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 重裝機槍手：旋轉加速（長前搖、預兆）→ 停步掃射（射速由慢到快）→ 過熱空檔（裝甲打開、受傷加成）。
func _test_gunner_sequence() -> void:
	await open_level(10.0)
	var gunner := spawn(GUNNER_PATH, 27.0) as HeavyGunner
	place_player(10.0)
	level.player.health.setup(200, 0.0)
	var before := level.player.health.current
	var winding := await wait_state(gunner, &"spin_up", 60 * 4)
	check(winding and gunner.is_telegraphing(), "the gunner winds up its barrel with a telegraph")
	var last_spin := 0.0
	var spin_rises := true
	var windup_frames := 0
	for i in 600:
		await physics_frames(1)
		if not gunner.fsm.is_in(&"spin_up"):
			break
		windup_frames += 1
		spin_rises = spin_rises and gunner.spin() >= last_spin - 0.001
		last_spin = gunner.spin()
		check(absf(gunner.velocity.x) < 0.1, "the gunner stands still while winding up")
	var windup_seconds := windup_frames / 60.0
	check(spin_rises and last_spin > 0.8, "the barrel spins faster and faster (%.2f)" % last_spin)
	check(windup_seconds >= gunner.data.telegraph_time * 0.8, "the windup is long (%.2f s)" % windup_seconds)
	check(gunner.fsm.is_in(&"fire"), "the gunner fires after the windup")
	var half := int(gunner.data.ability_time * 60.0 * 0.5)
	await physics_frames(half)
	var first_half := gunner.shots_fired
	check(absf(gunner.velocity.x) < 0.1, "the gunner stands still while firing")
	await wait_state(gunner, &"vent", 60 * 4)
	var second_half := gunner.shots_fired - first_half
	check(first_half >= 3 and second_half > first_half, "the fire rate climbs during the burst (%d then %d shots)" % [first_half, second_half])
	check(level.player.health.current < before, "a player standing in the line of fire is hit")
	check(gunner.is_armor_open() and is_equal_approx(gunner.hurtbox.damage_scale, HeavyGunner.VENT_DAMAGE_SCALE), "the armor opens and damage is boosted while venting")
	check(gunner.heat() > 0.5, "the barrel is hot when the burst ends (%.2f)" % gunner.heat())
	await physics_frames(60)
	check(gunner.heat() < 0.9, "the barrel cools during the vent")
	var back := await wait_state(gunner, &"patrol", 60 * 4)
	check(back and not gunner.is_armor_open() and is_equal_approx(gunner.hurtbox.damage_scale, 1.0), "the armor closes again after the vent")
	check(gunner._cooldown > 0.0, "the gunner rests between bursts")
	gunner.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 正面裝甲：擋下正面的一般攻擊；背後與過熱空檔打得進去；爆炸與終結技無視裝甲。
func _test_gunner_armor() -> void:
	await open_level(10.0)
	var gunner := spawn(GUNNER_PATH, 40.0) as HeavyGunner
	gunner.set_physics_process(false)
	gunner.facing = -1
	place_player(20.0)
	await physics_frames(2)
	var front := gunner.global_position + Vector2(-30, -20)
	var back := gunner.global_position + Vector2(30, -20)
	var before := gunner.health.current
	check(gunner.hurtbox.receive(hit(1, false, front)) == Hurtbox.Result.BLOCKED and gunner.health.current == before, "the front armor blocks an ordinary hit")
	check(gunner.hurtbox.receive(hit(1, false, back)) == Hurtbox.Result.DAMAGED and gunner.health.current == before - 1, "the back is not armored")
	before = gunner.health.current
	check(gunner.hurtbox.receive(hit(1, true, front)) == Hurtbox.Result.DAMAGED and gunner.health.current == before - 1, "explosions ignore the armor")
	before = gunner.health.current
	gunner.fsm.transition(&"vent")
	check(gunner.hurtbox.receive(hit(2, false, front)) == Hurtbox.Result.DAMAGED and gunner.health.current == before - 3, "venting opens the armor and boosts damage (2 -> 3)")
	# 暈眩（完美格擋）會中斷掃射並進入過熱空檔。
	gunner.fsm.transition(&"fire")
	gunner.stun(0.5)
	await physics_frames(2)
	check(gunner.fsm.is_in(&"vent"), "a stun cuts the burst short")
	gunner.set_physics_process(true)
	gunner.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 被每種敵人擊敗一次：死因對應的敗北圖鑑卡片會解鎖（火焰、燃料罐爆炸、機槍子彈）。
func _test_codex_unlocks() -> void:
	# 火焰：站在火裡直到倒下。
	await open_level(10.0)
	level.player.health.setup(1, 0.0)
	var flamer := spawn(FLAMER_PATH, 40.0) as Flamer
	place_player(37.0)
	await expect_codex_unlock(&"flamer_burn", "the flamer's fire", 60 * 8)
	flamer.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)
	# 燃料罐爆炸：貼著火焰兵打爆燃料罐。
	await open_level(10.0)
	flamer = spawn(FLAMER_PATH, 40.0) as Flamer
	flamer.set_physics_process(false)
	level.player.health.setup(1, 0.0)
	place_player(41.0)
	flamer.tank.hurtbox.receive(hit(5))
	await expect_codex_unlock(&"flamer_tank_blast", "the fuel tank blast", 60 * 3)
	await physics_frames(120)
	await end_level(level)
	# 機槍子彈：站著挨掃射。
	await open_level(10.0)
	level.player.health.setup(1, 0.0)
	var gunner := spawn(GUNNER_PATH, 27.0) as HeavyGunner
	await expect_codex_unlock(&"heavy_gunner_shot", "the heavy gunner's bullets", 60 * 8)
	gunner.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)
