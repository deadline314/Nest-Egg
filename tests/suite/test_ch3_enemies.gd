class_name Chapter3EnemiesSuite
extends EnemySuiteBase
## 第三章（晴岸）的敵人：抽水巡檢器、絕緣巡檢器（NE-272）與頭目守門人 JANUS（NE-271）。
## 預兆時間、看得懂的應對（跳過亮線、蹲過水平脈衝、站上吊軌上方就安全）、圖鑑卡片、三種難度都能擊敗，
## 以及第三章關卡的擺放（只在預留的戰鬥區、每場最多三個、安全區沒有敵人）。

const PUMP_PATH := "res://data/enemies/pump_inspector.tres"
const INSULATION_PATH := "res://data/enemies/insulation_inspector.tres"
const ALL: Array[String] = [PUMP_PATH, INSULATION_PATH]
const CH3_LEVELS: Array[String] = ["ch3_pawnshop", "ch3_plaza", "ch3_pump", "ch3_mezzanine", "ch3_clinic", "ch3_gate_hall", "ch3_glass_edge", "ch3_showroom", "ch3_office_hall"]
## 每張地圖的普通敵人數（頭目另算）；沒列的地圖是安全區，一個都不能有。
const EXPECTED_COUNTS := {"ch3_pump": 3, "ch3_mezzanine": 2}
## 吊軌在地面上方多高（像素）：測試場地沒有天花板，直接懸空生成。
const RAIL_ABOVE := 80.0


func run() -> void:
	_test_data()
	await _test_pump_telegraph_and_path()
	await _test_pump_ignores_player_above()
	await _test_pump_ram_unlocks_card()
	await _test_insulation_crouch_and_stand()
	await _test_insulation_safe_above_rail()
	_test_ch3_placement()
	await check_defeatable_on_every_difficulty(ALL)
	_test_janus_data()
	await _test_janus_wakes_after_intro()
	await _test_janus_person_protected()
	await _test_janus_shield_cracks()
	await _test_janus_bash_hit_is_not_a_miss()
	await _test_janus_scan_interrupt()
	await _test_janus_comm_and_backup()
	await _test_janus_forgetting_loop()
	await _test_janus_halt_and_pin()
	await _test_janus_retry_keeps_parts()
	await _test_janus_in_gate_hall()


func _test_data() -> void:
	check_enemy_data(ALL, [&"pump_inspector_ram", &"pump_inspector_contact", &"insulation_pulse", &"insulation_inspector_contact"])
	var pump := load(PUMP_PATH) as EnemyData
	var insulation := load(INSULATION_PATH) as EnemyData
	check(is_equal_approx(pump.telegraph_time, 0.7), "the pump inspector lights the floor for about 0.7 s (%.2f)" % pump.telegraph_time)
	check(is_equal_approx(insulation.telegraph_time, 0.8), "the insulation inspector charges for about 0.8 s (%.2f)" % insulation.telegraph_time)
	check(pump.attack_category != insulation.attack_category, "one inspector is melee and the other ranged")
	check(not insulation.uses_gravity and insulation.knockback_scale == 0.0, "the insulation inspector hangs from its rail and is not knocked off it")
	for path in ALL:
		var data := load(path) as EnemyData
		check(ResourceLoader.exists(EnemyVfx.PATH % String(data.id)), "%s has its own effects file" % data.id)
		check(not data.is_boss and not data.persists_damage, "%s is an ordinary enemy" % data.id)


## 抽水巡檢器：同一層、在攻擊距離內就預兆（地上亮線），路線停在牆前；衝撞不超過亮線的終點。
func _test_pump_telegraph_and_path() -> void:
	await open_level(26.0)
	var pump := spawn(PUMP_PATH, 20.0) as PumpInspector
	await physics_frames(2)
	check(await wait_state(pump, &"windup", 120), "the pump inspector starts its telegraph when the player is close on the same floor")
	var end_x: float = pump.get("_ram_end_x")
	var wall_x := 30.0 * 16.0
	check(end_x + pump.data.body_size.x * 0.5 <= wall_x + 0.5, "the lit path stops before the cover wall (end %.1f, wall %.1f)" % [end_x, wall_x])
	check(absf(end_x - pump.global_position.x) <= pump.data.ability_radius + 0.5, "the lit path is a short ram (%.1f px)" % absf(end_x - pump.global_position.x))
	var windup_frames := 0
	while pump.fsm.is_in(&"windup") and windup_frames < 120:
		windup_frames += 1
		await physics_frames(1)
	var seconds := windup_frames / float(Engine.physics_ticks_per_second)
	check(seconds >= 0.6, "the floor lights up long enough to react (%.2f s)" % seconds)
	var furthest := pump.global_position.x
	for i in 90:
		if not (pump.fsm.is_in(&"ram") or pump.fsm.is_in(&"recover")):
			break  # 喘息結束後牠會重新巡邏、下一次預兆另畫一條線
		furthest = maxf(furthest, pump.global_position.x)
		await physics_frames(1)
	check(furthest <= end_x + 2.0, "the ram never goes past the lit path (%.1f vs %.1f)" % [furthest, end_x])
	await end_level(level)


## 玩家站在上方平台：不同一層，不出招（上橋與照護步道就是這樣繞過牠）。
func _test_pump_ignores_player_above() -> void:
	await open_level(53.0)
	place_player(53.0, 16 * 16.0)
	var pump := spawn(PUMP_PATH, 47.0) as PumpInspector
	var started := false
	for i in 120:
		await physics_frames(1)
		started = started or pump.fsm.is_in(&"windup") or pump.fsm.is_in(&"ram")
	check(not started, "the pump inspector never rams a player standing on the platform above")
	await end_level(level)


func _test_pump_ram_unlocks_card() -> void:
	await open_level(14.0)
	level.player.health.setup(1, 0.0)
	spawn(PUMP_PATH, 8.0)
	await expect_codex_unlock(&"pump_inspector_ram", "the pump inspector ram", 300)
	await end_level(level)


## 絕緣巡檢器：探頭降到玩家胸口、水平打出脈衝；蹲下就從頭上過去，站著會被打到。
func _test_insulation_crouch_and_stand() -> void:
	await open_level(44.0)
	var inspector := spawn(INSULATION_PATH, 40.0, FLOOR_Y - RAIL_ABOVE) as InsulationInspector
	await physics_frames(2)
	check(await wait_state(inspector, &"charge", 180), "the insulation inspector charges when the player stands below its rail")
	while inspector.fsm.is_in(&"charge") and not inspector.is_locked():
		await physics_frames(1)
	var height := inspector.probe_height_above_floor()
	check(height > Player.CROUCH_HEIGHT + 2.0 and height < Player.BODY_SIZE.y - 2.0,
			"the locked pulse is above a crouching player and inside a standing one (%.1f px above the floor)" % height)
	Input.action_press(&"move_down")
	var before := level.player.health.current
	for i in 60:
		await physics_frames(1)
	Input.action_release(&"move_down")
	check(level.player.health.current == before, "crouching under the pulse avoids it")
	level.player.health.setup(1, 0.0)
	await expect_codex_unlock(&"insulation_pulse", "the insulation pulse", 400)
	await end_level(level)


## 玩家在吊軌上方（照護步道、上橋）：不充電。
func _test_insulation_safe_above_rail() -> void:
	await open_level(53.0)
	place_player(53.0, 16 * 16.0)
	var inspector := spawn(INSULATION_PATH, 53.0, FLOOR_Y - 40.0) as InsulationInspector
	var charged := false
	for i in 150:
		await physics_frames(1)
		charged = charged or inspector.fsm.is_in(&"charge")
	check(not charged, "a player above the rail is out of the inspector's reach")
	await end_level(level)


## 第三章擺放：泵室與夾層的遭遇只在預留的戰鬥區，每場最多三個、近戰與遠距最多各一；其他地圖（安全區）沒有普通敵人。
func _test_ch3_placement() -> void:
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/ch3_design.json"))
	for ident in CH3_LEVELS:
		var layout := LevelBuilder.parse(load("res://data/levels/%s.tres" % ident) as LevelData)
		var zones: Array = (design["areas"] as Dictionary).get(ident.trim_prefix("ch3_"), {}).get("encounters", [])
		var count := 0
		for spawn: Dictionary in layout.spawns:
			var enemy := spawn["resource"] as EnemyData
			if enemy == null or enemy.is_boss or enemy.id == &"janus":
				continue  # 頭目另外檢查
			count += 1
			check(enemy.id == &"pump_inspector" or enemy.id == &"insulation_inspector", "%s only uses this chapter's inspectors (%s)" % [ident, enemy.id])
			var cell: Vector2i = spawn["cell"]
			var inside := false
			for zone: Dictionary in zones:
				inside = inside or (cell.x >= int(zone["x0"]) and cell.x <= int(zone["x1"]))
			check(inside, "%s: %s at column %d stands inside a reserved combat zone" % [ident, enemy.id, cell.x])
			check(PlacementChecks.first_encounter_clear(layout, cell), "%s: %s at column %d has room on its left" % [ident, enemy.id, cell.x])
		check(count == int(EXPECTED_COUNTS.get(ident, 0)), "%s places %d ordinary enemies (expected %d)" % [ident, count, int(EXPECTED_COUNTS.get(ident, 0))])
		for zone: Dictionary in zones:
			var members: Array = zone.get("members", [])
			check(members.size() <= 3 and members.count("抽水巡檢器") <= 1 and members.count("絕緣巡檢器") <= 1,
					"%s / %s keeps at most three on screen, one melee and one ranged (%s)" % [ident, zone["name"], members])


# ---------------------------------------------------------------------------
# 守門人 JANUS（NE-271）
# ---------------------------------------------------------------------------

const JANUS_PATH := "res://data/enemies/janus.tres"
const JANUS_TILE := 40.0
const JANUS_FLAGS: Array[StringName] = [&"ch3_janus_intro_seen", &"ch3_janus_disabled", &"ch3_janus_shield_misses",
		&"ch3_janus_comm_broken", &"ch3_janus_device_stability", &"ch3_janus_lost_once"]


func _clear_janus_flags() -> void:
	for flag in JANUS_FLAGS:
		GameState.world_flags.erase(String(flag))


func _spawn_janus(player_tile: float, awake := true) -> JanusBoss:
	await open_level(player_tile)
	_clear_janus_flags()
	if awake:
		GameState.set_flag(&"ch3_janus_intro_seen", true, false)
	var janus := spawn(JANUS_PATH, JANUS_TILE) as JanusBoss
	await physics_frames(2)
	return janus


## 讓守門人立刻出某一招（略過選招與冷卻）。
func _force_move(janus: JanusBoss, move: StringName) -> void:
	janus.set("_move_id", move)
	janus.set("_last_move", move)
	janus.fsm.transition(&"windup")


func _janus_hit(janus: JanusBoss, part: StringName, from_x: float, projectile := true, amount := 1) -> Hurtbox.Result:
	var box: Hurtbox = janus._parts_by_id.get(part, janus.hurtbox) if part != &"" else janus.hurtbox
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	info.is_projectile = projectile
	info.origin = Vector2(from_x, janus.global_position.y - 24.0)
	info.knockback = Vector2(signf(janus.global_position.x - from_x) * 100.0, 0)
	return box.receive(info)


func _test_janus_data() -> void:
	var pattern := BossPattern.parse(JSON.parse_string(FileAccess.get_file_as_string("res://data/bosses/janus.json")), "janus.json", true)
	check(pattern.errors.is_empty(), "the gatekeeper's boss data reads cleanly: %s" % [pattern.errors])
	check(pattern.bar_name == "門禁裝置穩定度", "the boss bar is the device's stability, not the man's life")
	check(pattern.gate_channel == &"ch3_janus_down", "shutting him down opens the ch3_janus_down channel")
	check(float(pattern.moves[&"shield_bash"]["telegraph"]) >= 1.0, "the shield bash is raised for about a second")
	for id: StringName in [&"scan_low", &"scan_high", &"call_backup"]:
		check(is_equal_approx(float(pattern.moves[id]["telegraph"]), 0.8), "%s is telegraphed for about 0.8 s" % id)
	var low := float(pattern.moves[&"scan_low"]["params"]["height"])
	var high := float(pattern.moves[&"scan_high"]["params"]["height"])
	check(low < 12.0, "the low scan line can be jumped (%.0f px above the floor)" % low)
	check(high > Player.CROUCH_HEIGHT + 3.0 and high < Player.BODY_SIZE.y - 3.0, "the high scan line passes over a crouching player and hits a standing one (%.0f px)" % high)
	var data := load(JANUS_PATH) as EnemyData
	check(data.validate().is_empty() and data.rig_skin == "janus", "the gatekeeper uses his own character art")
	check(not data.is_boss and data.credit_value <= 1, "the gatekeeper does not end the level and is not a source of money")
	for card: StringName in [&"janus_shield_bash", &"janus_scan"]:
		check(DefeatCodex.has_card(card), "the gatekeeper's %s has a defeat card" % card)
	check(ResourceLoader.exists(EnemyVfx.PATH % "janus"), "the gatekeeper has his own effects file")


## 登場劇情看過、玩家走近才醒；血條名稱是門禁裝置穩定度。
func _test_janus_wakes_after_intro() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 8.0, false)
	await physics_frames(20)
	check(janus.fsm.is_in(&"dormant"), "before the C10 intro the gatekeeper does not fight")
	var names: Array[String] = []
	var on_start := func(boss_name: String, _max: int) -> void: names.append(boss_name)
	EventBus.boss_started.connect(on_start)
	GameState.set_flag(&"ch3_janus_intro_seen", true, false)
	await physics_frames(10)
	EventBus.boss_started.disconnect(on_start)
	check(janus.is_awake() and names.has("門禁裝置穩定度"), "after the intro he wakes and the bar reads 門禁裝置穩定度 (%s)" % [names])
	check(not Story.was_seen(&"ch3_c11_defeat_hint"), "no defeat hint before the player has lost to him")
	level.player.health.take_damage(lethal_to_player())
	await physics_frames(5)
	check(GameState.has_flag(&"ch3_janus_lost_once"), "losing to him is remembered")
	await end_level(level)
	var again := await _spawn_janus(JANUS_TILE - 8.0, false)
	GameState.set_flag(&"ch3_janus_lost_once", true, false)
	GameState.set_flag(&"ch3_janus_intro_seen", true, false)
	await physics_frames(10)
	check(again.is_awake() and Story.was_seen(&"ch3_c11_defeat_hint"), "after the first defeat, meeting him again plays the defeat hint")
	_clear_janus_flags()
	await end_level(level)


func lethal_to_player() -> DamageInfo:
	var info := DamageInfo.create(999, Combat.Team.ENEMY, &"janus_shield_bash")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	return info


## 人物是保護區：打到身體（子彈、近戰）都被擋下、穩定度不變；完整的盾架也擋子彈。
func _test_janus_person_protected() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 6.0)
	var before := janus.health.current
	var front := janus.global_position.x + janus.facing * 60.0
	check(_janus_hit(janus, &"", front, true, 5) == Hurtbox.Result.BLOCKED, "a bullet on the man is blocked")
	check(_janus_hit(janus, &"", front, false, 5) == Hurtbox.Result.BLOCKED, "a melee hit on the man is blocked")
	check(_janus_hit(janus, &"shield", front, true, 5) == Hurtbox.Result.BLOCKED, "the intact shield rack blocks bullets")
	check(janus.health.current == before, "nothing hurt the man or the device (%d/%d)" % [janus.health.current, before])
	await end_level(level)


## 盾擊撲空三次盾架裂開，次數寫進旗標；裂開後盾架打得動。
func _test_janus_shield_cracks() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 9.0)
	await wait_state(janus, &"idle", 120)
	janus.set_physics_process(true)
	for attempt in 3:
		place_player(JANUS_TILE - 9.0)
		janus.global_position.x = JANUS_TILE * 16.0
		janus.facing = -1
		_force_move(janus, &"shield_bash")
		await physics_frames(int(1.0 * Engine.physics_ticks_per_second) + 30)
		check(janus.fsm.is_in(&"yanked"), "a missed bash leaves him staggered (attempt %d, state %s)" % [attempt + 1, janus.fsm.current])
		check(janus.is_part_open(&"shield_lock"), "the shield lock is exposed after a miss")
		await wait_state(janus, &"idle", 200)
	check(janus.shield_cracked and int(GameState.get_flag(&"ch3_janus_shield_misses", 0)) == 3, "three missed bashes crack the shield and are saved")
	var before := janus.health.current
	check(_janus_hit(janus, &"shield", janus.global_position.x - 60.0, true, 2) == Hurtbox.Result.DAMAGED and janus.health.current < before,
			"the cracked shield takes damage from the front")
	await end_level(level)


## 盾擊打中玩家不算撲空。
func _test_janus_bash_hit_is_not_a_miss() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 4.0)
	await wait_state(janus, &"idle", 120)
	janus.facing = -1
	var health_before := level.player.health.current
	_force_move(janus, &"shield_bash")
	await physics_frames(int(1.0 * Engine.physics_ticks_per_second) + 30)
	check(level.player.health.current < health_before, "a bash that reaches the player hurts")
	check(janus.shield_misses == 0, "a bash that lands does not count as a miss")
	check(janus.global_position.x > level.player.global_position.x, "the bash stops on contact instead of pushing through the player")
	await end_level(level)


## 掃描蓄力：正面射臂鎖有傷害但打不斷，近戰（或從背後）一下就打斷，第一次會道歉。
func _test_janus_scan_interrupt() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 6.0)
	await wait_state(janus, &"idle", 120)
	janus.facing = -1
	_force_move(janus, &"scan_high")
	await physics_frames(3)
	check(janus.is_part_open(&"arm_lock"), "the arm lock glows orange while the scanner charges")
	var front := janus.global_position.x - 60.0
	_janus_hit(janus, &"arm_lock", front, true)
	await physics_frames(1)
	check(janus.fsm.is_in(&"windup"), "a bullet from the front does not interrupt the scan")
	_janus_hit(janus, &"arm_lock", front, false)
	await physics_frames(1)
	check(janus.fsm.is_in(&"yanked"), "a melee hit on the arm lock interrupts the scan")
	check(Story.was_seen(&"ch3_c11_bark_sorry"), "the first interruption plays his apology")
	await wait_state(janus, &"idle", 200)
	janus.facing = -1
	_force_move(janus, &"scan_low")
	await physics_frames(3)
	_janus_hit(janus, &"arm_lock", janus.global_position.x + 60.0, true)
	await physics_frames(1)
	check(janus.fsm.is_in(&"yanked"), "a bullet from behind interrupts the scan too")
	await end_level(level)


## 通訊器只能從背後打；打壞後不再增援，旗標保留。增援最多兩台、含頭目同屏最多三個。
func _test_janus_comm_and_backup() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 12.0)
	await wait_state(janus, &"idle", 120)
	janus.set_physics_process(false)
	janus.facing = -1
	place_player(JANUS_TILE - 12.0)
	janus.set("_move_id", &"call_backup")
	for i in 2:
		check(janus.call(&"_custom_move_usable", &"call_backup", &"call_backup"), "he can call backup while fewer than two are alive (%d)" % i)
		janus.call(&"_call_backup")
	check(janus.call(&"_living_backups") == 2 and not janus.call(&"_custom_move_usable", &"call_backup", &"call_backup"),
			"at most two inspectors, three on screen with him")
	janus.call(&"_refresh_parts")
	check(not janus.is_part_open(&"comm"), "the comm unit is not hittable from the front")
	place_player(JANUS_TILE + 6.0)
	janus.call(&"_refresh_parts")
	check(janus.is_part_open(&"comm"), "from behind the comm unit glows orange")
	for i in 6:
		_janus_hit(janus, &"comm", janus.global_position.x + 60.0, true)
	check(janus.comm_broken and GameState.has_flag(&"ch3_janus_comm_broken"), "six hits break the comm unit and the flag is saved")
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		if node != janus:
			node.queue_free()
	await physics_frames(2)
	check(not janus.call(&"_custom_move_usable", &"call_backup", &"call_backup"), "a broken comm unit never calls backup again")
	await end_level(level)


## 遺忘迴圈：約三成機率重播上一招，連續重播最多兩次。
func _test_janus_forgetting_loop() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 6.0)
	janus.set_physics_process(false)
	janus.facing = -1
	var replays := 0
	for i in 400:
		janus.set("_last_move", &"scan_high")
		janus.set("_replay_pending", false)
		janus.set("_rolled_this_move", false)
		janus.call(&"_on_janus_part_hit", DamageInfo.new(), &"shield_lock")
		if janus.replay_pending():
			replays += 1
	var rate := replays / 400.0
	check(rate > 0.22 and rate < 0.38, "an effective hit makes him repeat about three times in ten (%.2f)" % rate)
	janus.set("_replay_pending", false)
	janus.set("_replay_chain", 0)
	var chain: Array[StringName] = []
	for i in 3:
		janus.set("_last_move", &"scan_high")
		janus.set("_replay_pending", true)
		chain.append(janus.choose_move())
	check(chain[0] == &"scan_high" and chain[1] == &"scan_high", "a pending replay repeats the previous move with its full telegraph")
	check(Story.was_seen(&"ch3_c11_bark_repeat"), "the first replay plays Rin's warning bark")
	check(janus.get("_replay_chain") <= 2 and not (chain[2] == &"scan_high" and janus.is_replaying()), "no more than two replays in a row (%s)" % [chain])
	await end_level(level)


## 穩定度歸零：工作架停住（人活著），要拔插銷才停機；拔了才送出頻道並淡出。
func _test_janus_halt_and_pin() -> void:
	var janus := await _spawn_janus(JANUS_TILE - 6.0)
	var toggled: Array[StringName] = []
	var on_toggle := func(channel: StringName, active: bool) -> void:
		if active:
			toggled.append(channel)
	EventBus.mechanism_toggled.connect(on_toggle)
	janus.health.take_damage(lethal())
	await physics_frames(2)
	check(janus.halted and not janus.is_dying() and janus.fsm.is_in(&"halted"), "zero stability halts the rig instead of killing the man")
	check(int(GameState.get_flag(&"ch3_janus_device_stability", -1)) == 0, "zero stability is saved")
	check(toggled.is_empty(), "the gate stays shut until the pin is pulled")
	place_player(JANUS_TILE - 6.0)
	check(not janus.pin_reachable(), "the pin is on his back, out of reach from the front")
	place_player(JANUS_TILE + 0.8)
	await physics_frames(1)
	check(janus.pin_reachable(), "standing behind him the pin can be pulled")
	janus.pull_pin()
	check(toggled.has(&"ch3_janus_down"), "pulling the pin opens ch3_janus_down")
	await physics_frames(int(2.0 * Engine.physics_ticks_per_second))
	check(not is_instance_valid(janus), "the rig powers down and hands over to the seated gatekeeper")
	EventBus.mechanism_toggled.disconnect(on_toggle)
	await end_level(level)


## 重試：盾裂、通訊器壞與剩餘穩定度照旗標還原；穩定度 0 直接停住等拔插銷；已停機就不再出現。
func _test_janus_retry_keeps_parts() -> void:
	await open_level(JANUS_TILE - 6.0)
	_clear_janus_flags()
	GameState.set_flag(&"ch3_janus_intro_seen", true, false)
	GameState.set_flag(&"ch3_janus_shield_misses", 3, false)
	GameState.set_flag(&"ch3_janus_comm_broken", true, false)
	GameState.set_flag(&"ch3_janus_device_stability", 40, false)
	var janus := spawn(JANUS_PATH, JANUS_TILE) as JanusBoss
	await physics_frames(2)
	janus.restore_lost_health(50)
	check(janus.shield_cracked and janus.comm_broken, "a cracked shield and broken comm unit stay broken on retry")
	check(janus.health.current == ceili(janus.health.max_health * 0.4), "the remaining stability is restored once, not doubled (%d)" % janus.health.current)
	check(janus.phase == 1, "40%% stability resumes in the second phase")
	janus.queue_free()
	GameState.set_flag(&"ch3_janus_device_stability", 0, false)
	var halted := spawn(JANUS_PATH, JANUS_TILE) as JanusBoss
	await physics_frames(3)
	check(halted.halted, "zero stability without the pin pulled comes back halted, ready for the pin")
	halted.queue_free()
	GameState.set_flag(&"ch3_janus_disabled", true, false)
	var gone := spawn(JANUS_PATH, JANUS_TILE) as JanusBoss
	await physics_frames(2)
	check(not is_instance_valid(gone), "once shut down he never fights again")
	_clear_janus_flags()
	await end_level(level)


## 門禁大廳：守門人在預留的戰鬥區；拔插銷後關卡寫入停機旗標。
func _test_janus_in_gate_hall() -> void:
	var layout := LevelBuilder.parse(load("res://data/levels/ch3_gate_hall.tres") as LevelData)
	var cells := PlacementChecks.cells_of(layout, &"janus")
	check(cells.size() == 1 and cells[0].x >= 18 and cells[0].x <= 62, "the gatekeeper stands in the reserved boss zone of the gate hall (%s)" % [cells])
	_clear_janus_flags()
	GameState.start_new_run(GameState.difficulties[1])
	GameState.set_flag(&"ch3_janus_intro_seen", true, false)
	level = await spawn_level(load("res://data/levels/ch3_gate_hall.tres") as LevelData)
	await physics_frames(5)
	var janus: JanusBoss = null
	for node in level.get_tree().get_nodes_in_group(&"enemies"):
		if node is JanusBoss:
			janus = node
	check(janus != null, "the gate hall spawns the gatekeeper")
	if janus != null:
		janus.health.take_damage(lethal())
		await physics_frames(2)
		janus.pull_pin()
		await physics_frames(5)
		check(GameState.has_flag(&"ch3_janus_disabled"), "the gate hall writes ch3_janus_disabled when the pin is pulled")
	_clear_janus_flags()
	await end_level(level)
