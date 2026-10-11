class_name Chapter3EnemiesSuite
extends EnemySuiteBase
## 第三章（晴岸）的敵人：抽水巡檢器、絕緣巡檢器（NE-272）。
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
			if enemy == null or enemy.is_boss:
				continue
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
