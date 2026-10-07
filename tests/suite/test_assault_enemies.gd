class_name AssaultEnemiesSuite
extends EnemySuiteBase
## 突襲型敵人（NE-48）：電擊犬（成群、低吼刨地蓄力後撲咬、站上平台就安全、範圍武器有效）
## 與偽裝箱（看起來是貨箱、被打震動現形、靠近彈起咬人、爆炸無視外殼）。

const HOUND_PATH := "res://data/enemies/shock_hound.tres"
const MIMIC_PATH := "res://data/enemies/mimic.tres"
## 平台（欄 50～56，第 16 列）上玩家的腳。
const PLATFORM_Y := 16 * 16.0


func run() -> void:
	_test_data()
	_test_level_placement()
	await _test_pack_attack()
	await _test_platform_is_safe()
	await _test_area_weapon_and_stun()
	await _test_mimic_disguise()
	await _test_mimic_probe_and_range()
	await _test_mimic_ambush()
	await _test_mimic_explosion_and_stun()
	await _test_codex_unlocks()
	await check_defeatable_on_every_difficulty([HOUND_PATH, MIMIC_PATH])


func _test_data() -> void:
	check_enemy_data([HOUND_PATH, MIMIC_PATH], [&"shock_hound_pounce", &"shock_hound_contact", &"mimic_bite", &"mimic_contact"])
	var hound := load(HOUND_PATH) as EnemyData
	var mimic := load(MIMIC_PATH) as EnemyData
	# 牠們跳不高：撲咬的最高點加身高要比一格平台（4 格＝64 像素）矮很多。
	var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 900.0))
	var apex := ShockHound.LEAP_VELOCITY * ShockHound.LEAP_VELOCITY / (2.0 * gravity)
	check(apex + hound.body_size.y < 48.0, "a hound cannot reach a player standing on a platform (apex %.0f + body %.0f)" % [apex, hound.body_size.y])
	check(hound.max_health <= 3, "hounds are fragile enough for an area weapon to clear a pack")
	check(mimic.max_health > hound.max_health, "the mimic is sturdier than a hound")
	check(mimic.ability_radius < mimic.detect_range, "the mimic ambushes at close range only")


## 配置：第一章貨運站（160～239）；第二章升降井（70～139）與轉運站（275～299，頭目戰場地之前）。
func _test_level_placement() -> void:
	check_level_placement({
		"res://data/levels/level_01.tres": [[&"shock_hound", 160, 240], [&"mimic", 160, 240]],
	})
	var layout := LevelBuilder.parse(load("res://data/levels/level_01.tres") as LevelData)
	check(PlacementChecks.cells_of(layout, &"shock_hound").size() >= 3, "the first-chapter demo retains a pack of three hounds")


## 成群：第一隻低吼就呼喚同伴、同伴的蓄力錯開；撲咬命中會受到電擊傷害。
func _test_pack_attack() -> void:
	await open_level(45.0)
	level.player.health.setup(60, 0.0)
	var hounds: Array = []
	for x in [60.0, 61.0, 62.0]:
		hounds.append(spawn(HOUND_PATH, x))
	var before := level.player.health.current
	var growl_frame := {}
	var saw_telegraph := false
	var pounced := false
	for frame in 60 * 8:
		await physics_frames(1)
		for hound: ShockHound in hounds:
			if hound.fsm.is_in(&"growl") and not growl_frame.has(hound):
				growl_frame[hound] = frame
				saw_telegraph = saw_telegraph or hound.is_telegraphing()
			pounced = pounced or hound.fsm.is_in(&"pounce")
		if growl_frame.size() >= 3 and pounced and level.player.health.current < before:
			break
	check(saw_telegraph, "a hound telegraphs its pounce with a growl")
	check(growl_frame.size() >= 2, "the pack growls one after another (%d hounds)" % growl_frame.size())
	if growl_frame.size() >= 2:
		var frames_sorted := growl_frame.values()
		frames_sorted.sort()
		check(float(frames_sorted[1] - frames_sorted[0]) / 60.0 >= 0.25, "the pack's pounces are staggered (%.2f s apart)" % (float(frames_sorted[1] - frames_sorted[0]) / 60.0))
	check(hounds[1].is_alerted() or hounds[2].is_alerted() or growl_frame.size() >= 3, "the first growl calls the rest of the pack")
	check(pounced and level.player.health.current < before, "a pounce shocks the player on the ground")
	for hound in hounds:
		hound.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 站上平台就安全：玩家腳比牠們高過撲咬能到的高度，牠們只在底下打轉、低吼。
func _test_platform_is_safe() -> void:
	await open_level(53.0)
	level.player.health.setup(60, 0.0)
	place_player(53.0, PLATFORM_Y - 1.0)
	level.player.set_physics_process(false)
	var hounds: Array = []
	for x in [44.0, 45.0, 46.0]:
		hounds.append(spawn(HOUND_PATH, x))
	var before := level.player.health.current
	var circled := false
	var attacked := false
	for i in 60 * 6:
		await physics_frames(1)
		for hound in hounds:
			circled = circled or hound.fsm.is_in(&"circle")
			attacked = attacked or hound.fsm.is_in(&"growl") or hound.fsm.is_in(&"pounce")
	check(not hounds[0].can_reach_target(), "a hound cannot reach a player standing on the platform")
	check(circled, "the hounds pace below the platform")
	check(not attacked and level.player.health.current == before, "hounds do not attack a player on the platform")
	# 下來之後又會攻擊。
	level.player.set_physics_process(true)
	place_player(48.0)
	var attacks := false
	for i in 60 * 6:
		await physics_frames(1)
		for hound in hounds:
			attacks = attacks or hound.fsm.is_in(&"growl")
	check(attacks, "stepping off the platform brings the pack back")
	for hound in hounds:
		hound.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 範圍武器一次清一群；撲咬中被暈眩（完美格擋）會中斷。
func _test_area_weapon_and_stun() -> void:
	await open_level(10.0)
	# 死亡的敵人過一會兒就會被釋放，所以用沒有型別的陣列與 is_instance_valid 計算。
	var hounds: Array = []
	for x in [40.0, 40.5, 41.0]:
		hounds.append(spawn(HOUND_PATH, x))
		hounds.back().set_physics_process(false)
	await physics_frames(2)
	Fx.explosion(hounds[1].global_position + Vector2(0, -7), 60.0, 3, Combat.Team.PLAYER, &"test")
	await physics_frames(10)
	var dead := 0
	for hound: Variant in hounds:
		dead += 1 if not is_instance_valid(hound) or (hound as ShockHound).is_dying() else 0
	check(dead == 3, "one explosion clears a clumped pack (%d of 3)" % dead)
	await physics_frames(90)
	await end_level(level)
	await open_level(10.0)
	var hound := spawn(HOUND_PATH, 30.0) as ShockHound
	place_player(14.0)
	await wait_state(hound, &"pounce", 60 * 6)
	check(hound.contact.damage == hound.data.ability_damage and hound.contact.source_id == &"shock_hound_pounce", "the pounce uses the pounce damage and source")
	hound.stun(0.5)
	await physics_frames(2)
	check(hound.fsm.is_in(&"recover") and hound.contact.damage == hound.data.contact_damage, "a stun interrupts the pounce and resets the damage")
	hound.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


func _spawn_mimic(x_tile := 60.0) -> Mimic:
	return spawn(MIMIC_PATH, x_tile) as Mimic


## 偽裝：就是一個貨箱，不會動、不傷人；現形前傷不了牠。
func _test_mimic_disguise() -> void:
	await open_level(10.0)
	var mimic := _spawn_mimic(60.0)
	var start := mimic.global_position
	var before := level.player.health.current
	await physics_frames(60 * 3)
	check(mimic.is_disguised() and mimic.fsm.is_in(&"dormant"), "a mimic far from the player stays a crate")
	check(mimic.global_position.distance_to(start) < 1.0, "a disguised mimic never moves")
	check(mimic.contact != null and not mimic.contact.active, "a disguised mimic does not hurt on contact")
	check(not mimic.is_telegraphing() and level.player.health.current == before, "a disguised mimic gives no warning and does nothing")
	mimic.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 子彈試探：被打到時震動、牙齒亮起並現形，但外殼擋下傷害；現形後保持原地，再打才會受傷。
func _test_mimic_probe_and_range() -> void:
	await open_level(10.0)
	var mimic := _spawn_mimic(60.0)
	var health := mimic.health.current
	shoot_from(Vector2(52.0 * 16.0, FLOOR_Y - 15.0), Vector2.RIGHT)
	await physics_frames(30)
	check(mimic.health.current == health, "a closed mimic shrugs off a bullet")
	check(not mimic.is_disguised(), "a bullet makes the mimic rattle and show its teeth")
	check(mimic.contact.active, "a revealed mimic can hurt on contact")
	var start := mimic.global_position
	var lunged := false
	for i in 60 * 3:
		await physics_frames(1)
		lunged = lunged or mimic.fsm.is_in(&"lunge") or mimic.fsm.is_in(&"shake")
	check(not lunged and mimic.global_position.distance_to(start) < 1.0, "a revealed mimic stays put while the player keeps their distance")
	shoot_from(Vector2(52.0 * 16.0, FLOOR_Y - 15.0), Vector2.RIGHT)
	await physics_frames(30)
	check(mimic.health.current < health, "a revealed mimic takes damage from bullets")
	mimic.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 埋伏：靠近就震動（預兆、縫裡透光）再彈起咬人，咬到會受傷；落地後硬直。
func _test_mimic_ambush() -> void:
	await open_level(10.0)
	level.player.health.setup(60, 0.0)
	var mimic := _spawn_mimic(60.0)
	place_player(60.0 - 2.0)
	var before := level.player.health.current
	var shook := await wait_state(mimic, &"shake", 60 * 2)
	check(shook and mimic.is_telegraphing(), "stepping close makes the crate shake as a warning")
	check(mimic.is_disguised(), "the mimic is still disguised while it shakes")
	var warning_frames := 0
	while mimic.fsm.is_in(&"shake") and warning_frames < 120:
		await physics_frames(1)
		warning_frames += 1
	check(warning_frames / 60.0 >= 0.3, "the warning lasts at least 0.3 s (%.2f s)" % (warning_frames / 60.0))
	check(mimic.fsm.is_in(&"lunge"), "the mimic springs after the warning")
	check(mimic.contact.damage == mimic.data.ability_damage and mimic.contact.source_id == &"mimic_bite", "the bite uses the bite damage and source")
	await physics_frames(30)
	check(level.player.health.current < before, "the bite hurts")
	check(not mimic.is_disguised(), "after the ambush the mimic stays revealed")
	var landed := await wait_state(mimic, &"recover", 60 * 2)
	check(landed, "the mimic lands into a recovery window")
	mimic.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


## 爆炸無視外殼；暈眩（完美格擋）中斷撲咬。
func _test_mimic_explosion_and_stun() -> void:
	await open_level(10.0)
	var mimic := _spawn_mimic(60.0)
	var health := mimic.health.current
	Fx.explosion(mimic.global_position + Vector2(0, -15), 50.0, 3, Combat.Team.PLAYER, &"test")
	await physics_frames(20)
	check(mimic.health.current < health, "an explosion ignores the mimic's shell")
	check(not mimic.is_disguised(), "an explosion also exposes the mimic")
	place_player(60.0 - 2.0)
	await wait_state(mimic, &"lunge", 60 * 3)
	mimic.stun(0.5)
	await physics_frames(2)
	check(mimic.fsm.is_in(&"recover") and mimic.contact.damage == mimic.data.contact_damage, "a stun interrupts the bite")
	mimic.hurtbox.receive(lethal())
	await physics_frames(90)
	await end_level(level)


func _test_codex_unlocks() -> void:
	await open_level(45.0)
	level.player.health.setup(1, 0.0)
	var hounds: Array = []
	for x in [60.0, 61.0, 62.0]:
		hounds.append(spawn(HOUND_PATH, x))
	await expect_codex_unlock(&"shock_hound_pounce", "a hound's pounce", 60 * 10)
	for hound in hounds:
		hound.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)
	await open_level(10.0)
	level.player.health.setup(1, 0.0)
	var mimic := _spawn_mimic(60.0)
	place_player(60.0 - 2.0)
	await expect_codex_unlock(&"mimic_bite", "a mimic's bite", 60 * 4)
	mimic.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)
