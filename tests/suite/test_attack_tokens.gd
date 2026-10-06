class_name AttackTokensSuite
extends EnemySuiteBase
## 攻擊令牌（ST-11）：同時攻擊的敵人數有上限（近戰 2、遠程 2、區域可覆蓋）、頭目與輔助類不受限、
## 逾時與死亡自動歸還、設定檔與壞資料的容錯；實際場上一群敵人同時想攻擊時不會超過上限也不會餓死。

const SWEEPER := "res://data/enemies/sweeper.tres"


func run() -> void:
	_test_config()
	_test_claim_release_expiry()
	_test_overrides_and_bad_data()
	await _test_crowd_respects_the_cap()
	await _test_dead_enemy_returns_its_token()
	GameState.start_new_run(GameState.difficulties[1])


func _test_config() -> void:
	var tokens := AttackTokens.new()
	check(tokens.cap_of(&"melee") == 2 and tokens.cap_of(&"ranged") == 2, "default caps: two melee, two ranged")
	check(tokens.group_of(&"charge") == &"melee" and tokens.group_of(&"beam") == &"ranged", "categories map to groups")
	check(tokens.group_of(&"support") == &"", "support attacks are not limited")


func _test_claim_release_expiry() -> void:
	var tokens := AttackTokens.new()
	tokens.hold_margin = 0.0
	check(tokens.claim(1, &"melee", 5.0) and tokens.claim(2, &"melee", 5.0), "two melee enemies get tokens")
	check(not tokens.allows(3, &"melee") and not tokens.claim(3, &"melee", 5.0), "the third waits")
	check(tokens.allows(1, &"melee"), "a holder is still allowed (its own attack continues)")
	check(tokens.allows(3, &"ranged"), "ranged is a separate pool")
	check(tokens.allows(3, &"support") and tokens.claim(3, &"support", 5.0) and tokens.held(&"melee") == 2, "support attacks take no slot")
	tokens.release(1)
	check(tokens.allows(3, &"melee") and tokens.claim(3, &"melee", 5.0), "a released token goes to the next enemy")
	check(tokens.held(&"melee") == 2, "never more than the cap (%d)" % tokens.held(&"melee"))
	var short := AttackTokens.new()
	short.hold_margin = 0.0
	short.claim(10, &"ranged", 0.02)
	short.claim(11, &"ranged", 0.02)
	check(not short.allows(12, &"ranged"), "while the holds last the pool is full")
	OS.delay_msec(60)
	check(short.allows(12, &"ranged") and short.held(&"ranged") == 0, "an expired hold frees the slot (a stuck enemy never blocks the pool)")


func _test_overrides_and_bad_data() -> void:
	var tokens := AttackTokens.new({"melee": 1, "ranged": 0})
	check(tokens.cap_of(&"melee") == 1, "an area can lower the melee cap")
	check(tokens.cap_of(&"ranged") == 1, "a cap below one is raised to one (never zero: nobody could attack)")
	var odd := AttackTokens.new({"test_no_such_group": 3})
	check(odd.cap_of(&"melee") == 2, "an unknown override group is reported and ignored")
	var previous := AttackTokens.active
	AttackTokens.active = null
	var probe := Node.new()
	check(AttackTokens.enemy_allows(probe, &"melee"), "with no level installed nothing is limited")
	AttackTokens.enemy_claim(probe, &"melee", 1.0)
	AttackTokens.enemy_release(probe)
	probe.free()
	AttackTokens.active = previous


## 五個清掃兵（遠程）同時看到玩家：同時預兆的不超過 2 個，而且每一個都輪得到。
func _test_crowd_respects_the_cap() -> void:
	await open_level(8.0)
	check(AttackTokens.active != null, "the level installs its tokens")
	var crowd: Array[Enemy] = []
	for i in 5:
		crowd.append(spawn(SWEEPER, 14.0 + i * 2.0))
	var seen: Dictionary = {}
	var peak := 0
	var over_cap := false
	for frame in 60 * 20:
		await physics_frames(1)
		var now := 0
		for enemy in crowd:
			if is_instance_valid(enemy) and enemy.is_telegraphing():
				now += 1
				seen[enemy.get_instance_id()] = true
		peak = maxi(peak, now)
		over_cap = over_cap or AttackTokens.active.held(&"ranged") > 2
	check(not over_cap, "ranged tokens held never exceed two")
	check(peak >= 1 and peak <= 2, "at most two enemies telegraph at once (peak %d)" % peak)
	check(seen.size() >= 4, "nobody starves: %d of 5 attacked in 20 seconds" % seen.size())
	await end_level(level)


func _test_dead_enemy_returns_its_token() -> void:
	await open_level(8.0)
	var tokens := AttackTokens.active
	var enemies: Array[Enemy] = [spawn(SWEEPER, 14.0), spawn(SWEEPER, 16.0), spawn(SWEEPER, 18.0)]
	var guard := 0
	while tokens.held(&"ranged") < 2 and guard < 600:
		await physics_frames(1)
		guard += 1
	check(tokens.held(&"ranged") == 2, "two attackers hold the pool")
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.health.take_damage(lethal())
	await physics_frames(3)
	check(tokens.held(&"ranged") == 0, "dead enemies return their tokens at once (%d)" % tokens.held(&"ranged"))
	await end_level(level)
	check(AttackTokens.active == null, "leaving the level clears the tokens")
