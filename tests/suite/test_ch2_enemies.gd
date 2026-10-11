class_name Chapter2EnemiesSuite
extends EnemySuiteBase
## 第二章（鷺）的戰鬥（NE-266）：市集的兩種新敵人（押運手、票據投手）與第二章遭遇的配置；共用頭目框架新增欄位的讀取與防呆在 Chapter1EnemiesSuite。

const ESCORT_PATH := "res://data/enemies/ch2_escort.tres"
const THROWER_PATH := "res://data/enemies/ch2_bill_thrower.tres"
const DESIGN_PATH := "res://data/levels/ch2_design.json"


func run() -> void:
	_test_data()
	await _test_escort_dash()
	await _test_thrower_fan_and_bypass()
	_test_encounters()
	await check_defeatable_on_every_difficulty([ESCORT_PATH, THROWER_PATH])


func _test_data() -> void:
	check_enemy_data([ESCORT_PATH, THROWER_PATH], [&"ch2_escort_contact", &"ch2_escort_baton", &"ch2_bill_thrower_contact", &"bill_paper"])


func _test_escort_dash() -> void:
	await open_level(20.0)
	var escort := spawn(ESCORT_PATH, 27.0)
	await wait_state(escort, &"windup", 240)
	check(escort.fsm.is_in(&"windup"), "the escort winds up when the player is in range")
	var start := escort.global_position.x
	await wait_state(escort, &"strike", 120)
	await wait_state(escort, &"recover", 120)
	check(absf(escort.global_position.x - start) >= 40.0, "the escort dashes forward with the baton (%.0f px)" % absf(escort.global_position.x - start))
	await end_level(level)


func _test_thrower_fan_and_bypass() -> void:
	await open_level(14.0)
	var thrower := spawn(THROWER_PATH, 26.0)
	await wait_state(thrower, &"windup", 300)
	check(thrower.fsm.is_in(&"windup"), "the bill thrower winds up a fan when the player is in range")
	await wait_state(thrower, &"recover", 120)
	var sheets := 0
	for child: Node in ProjectilePool.container().get_children():
		var shot := child as Projectile
		if shot != null and shot.active and shot.spec.source_id == &"bill_paper":
			sheets += 1
	check(sheets == 5, "the bill thrower throws a fan of five slow sheets (%d)" % sheets)
	await end_level(level)
	await open_level(54.0)
	var low := spawn(THROWER_PATH, 46.0)
	place_player(54.0, 16 * 16.0)  # 測試場地的單向平台，比地面高四格（約 64 像素）
	await physics_frames(2)
	level.player.global_position = Vector2(54.0 * 16.0, 12 * 16.0)  # 高處平台：高八格
	level.player.set_physics_process(false)
	await physics_frames(90)
	check(low.fsm.is_in(&"patrol"), "a bill thrower on the ground does not see a player on the high walkway (bypass works)")
	await end_level(level)


## 遭遇配置：每場最多三名普通敵人；安全區沒有敵人；只用本章的新身份。
func _test_encounters() -> void:
	var design: Variant = JSON.parse_string(FileAccess.get_file_as_string(DESIGN_PATH))
	check(design is Dictionary, "chapter 2 design data loads")
	if not design is Dictionary:
		return
	var areas: Dictionary = design["areas"]
	var fights := 0
	for id: String in areas:
		for encounter: Dictionary in areas[id]["encounters"]:
			var regular := (encounter["members"] as Array).filter(func(m: Variant) -> bool: return str(m) != "阿勇")
			check(regular.size() <= 3, "%s / %s has at most three regular enemies (%d)" % [id, encounter["name"], regular.size()])
			for member: Variant in encounter["members"]:
				check(str(member) in ["押運手", "票據投手", "阿勇"], "%s uses only chapter-2 identities (%s)" % [id, member])
			if not regular.is_empty():
				fights += 1
	check(fights == 4, "the market gate and the loading lanes have four short fights (%d)" % fights)
	# 劇本的安全區：當舖、屋頂、阿梨住處、復原館外（客人簿入口）；街道、市集與前室也沒有戰鬥。
	for safe in ["pawnshop", "rooftop", "ali_home", "lounge_front", "harbor_street", "market", "ledger_front"]:
		check(areas.has(safe) and (areas[safe]["encounters"] as Array).is_empty(), "area without fights %s has no enemies" % safe)
