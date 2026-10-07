class_name StrikeEnemiesSuite
extends EnemySuiteBase
## 非槍械的敵人攻擊（NE-118）：電鋸臂、液壓鉗、電漿鞭、鎖鏈鐵鉤。
## 資料有效、預兆不短於現有最短預兆、判定只在出招區間、各自的應對（拉開、跳過、蹲下、打斷鎖鏈、衝刺掙脫）有效、沒有一擊必殺、動作資料各自獨立。

const DIR := "res://data/enemies/strike"
const IDS: Array[String] = ["chainsaw_arm", "hydraulic_claw", "plasma_whip", "chain_hook"]


func run() -> void:
	_test_data()
	_test_chapter_placement()
	await _test_chainsaw()
	await _test_claw()
	await _test_whip()
	await _test_hook()
	await _test_hook_blocked_by_wall()


func _path(id: String) -> String:
	return "%s/%s.tres" % [DIR, id]


func _test_data() -> void:
	var shortest := INF
	for file in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			shortest = minf(shortest, (load("res://data/enemies/" + file) as EnemyData).telegraph_time)
	var actions: Dictionary = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	var owners: Dictionary = {}
	for dir in ["res://data/enemies", DIR]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tres") and not file.get_basename() in IDS:
				for state: Variant in (load(dir + "/" + file) as EnemyData).rig_actions.keys():
					owners[str((load(dir + "/" + file) as EnemyData).rig_actions[state])] = file
	for id in IDS:
		var data := load(_path(id)) as EnemyData
		check(data != null and data.validate().is_empty(), "%s data is valid" % id)
		if data == null:
			continue
		var errors := StrikeSpec.validate(data)
		check(errors.is_empty(), "%s strike data has no errors: %s" % [id, ", ".join(errors)])
		check(data.telegraph_time >= shortest, "%s telegraph (%.2f) is not shorter than the shortest existing one (%.2f)" % [id, data.telegraph_time, shortest])
		check(data.attack_category == &"melee" and data.credit_value > 0, "%s is a melee attacker that drops credits" % id)
		var spec := StrikeSpec.resolve(data)
		check(DefeatCodex.has_card(StringName(str(spec["source_id"]))) and DefeatCodex.has_card(data.contact_source_id), "%s attack and contact have codex cards" % id)
		for card in DefeatCodex.get_all_cards():
			if card["id"] == StringName(str(spec["source_id"])):
				check(not str(card.get("hint", "")).is_empty(), "%s codex card gives a strategy hint" % id)
		var source := (data.behavior as GDScript).source_code
		for state: Variant in data.rig_actions.keys():
			var name := str(data.rig_actions[state])
			check(actions.has(name) and name.begins_with(id + "."), "%s plays its own action %s" % [id, name])
			check(not owners.has(name), "action %s is not shared with another enemy" % name)
			check(source.contains('&"%s"' % str(state)), "%s has a state named %s" % [id, state])
	var bad := EnemyData.new()
	bad.id = &"test_bad_strike"
	bad.telegraph_time = 0.1
	bad.strike = {"reach": -1.0, "band": [10.0, 5.0], "no_such_field": 1}
	check(StrikeSpec.validate(bad).size() >= 4, "bad strike data is reported (%d problems)" % StrikeSpec.validate(bad).size())


## 開關卡、生成敵人與玩家：玩家在敵人左邊 gap 像素，生命 20、受傷無敵 1 秒（和遊戲一樣）。
func _setup(id: String, gap: float) -> StrikeEnemy:
	await open_level(10.0)
	var player := level.player
	player.health.setup(20, 1.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.facing = 1
	var enemy := spawn(_path(id), 10.0 + gap / 16.0) as StrikeEnemy
	enemy.position.x = player.global_position.x + gap
	await physics_frames(3)
	return enemy


func _finish(enemy: StrikeEnemy) -> void:
	Input.action_release(&"move_down")
	enemy.queue_free()
	await physics_frames(3)
	await end_level(level)


## 預兆快結束時（出招前約 0.06 秒）才換姿勢，這樣下一個物理影格出招的判定一定看得到新位置。
func _wait_windup_end(enemy: StrikeEnemy) -> void:
	var guard := 0
	while enemy.fsm.is_in(&"windup") and enemy.fsm.time_in_state < enemy.data.telegraph_time - 0.06 and guard < 300:
		await physics_frames(1)
		guard += 1


func _test_chainsaw() -> void:
	var enemy := await _setup("chainsaw_arm", 40.0)
	var player := level.player
	var hp := player.health.current
	check(await wait_state(enemy, &"windup", 240), "the chainsaw winds up when it sees the player")
	check(player.health.current == hp, "the wind-up deals no damage")
	check(enemy._strike_rect().size.y >= 40.0, "the chainsaw band covers the full body height (the telegraph shows it)")
	check(await wait_state(enemy, &"strike", 90), "the chainsaw swings after its telegraph")
	await physics_frames(3)
	check(hp - player.health.current == 1, "one chainsaw swing costs one health, not more (%d)" % (hp - player.health.current))
	check(await wait_state(enemy, &"recover", 120), "the chainsaw ends in a recovery gap")
	var recover_hp := player.health.current
	await physics_frames(10)
	check(player.health.current == recover_hp, "no damage during the recovery")
	await _finish(enemy)
	# 應對：預兆時拉開距離就不會被割到。
	enemy = await _setup("chainsaw_arm", 40.0)
	player = level.player
	hp = player.health.current
	await wait_state(enemy, &"windup", 240)
	player.global_position.x -= 110.0
	player.velocity = Vector2.ZERO
	await wait_state(enemy, &"recover", 240)
	check(player.health.current == hp, "backing away during the telegraph avoids the saw")
	await _finish(enemy)
	# 應對：衝刺（無敵）穿過去。
	enemy = await _setup("chainsaw_arm", 40.0)
	player = level.player
	hp = player.health.current
	await wait_state(enemy, &"strike", 240)
	player.health.grant_invulnerability(0.6)
	await wait_state(enemy, &"recover", 120)
	check(player.health.current == hp, "invulnerability (dash) during the swing avoids the damage")
	await _finish(enemy)


func _test_claw() -> void:
	var enemy := await _setup("hydraulic_claw", 36.0)
	var player := level.player
	var hp := player.health.current
	check(await wait_state(enemy, &"windup", 300), "the claw winds up when it sees the player")
	check(enemy._strike_rect().size.y <= 24.0, "the claw band is low (jump over it)")
	# 跳過去：出招時玩家離地 40 像素以上，低矮的判定打不到。
	await _wait_windup_end(enemy)
	player.global_position.y -= 60.0
	player.velocity = Vector2.ZERO
	check(await wait_state(enemy, &"strike", 120), "the claw clamps after its telegraph")
	await wait_state(enemy, &"recover", 60)
	check(player.health.current == hp, "being in the air during the clamp avoids it")
	await _finish(enemy)
	enemy = await _setup("hydraulic_claw", 36.0)
	player = level.player
	hp = player.health.current
	await wait_state(enemy, &"strike", 400)
	await physics_frames(4)
	check(hp - player.health.current == 2, "a claw hit costs two health, never a one-hit kill (%d)" % (hp - player.health.current))
	await _finish(enemy)


func _test_whip() -> void:
	for variant in [0, 1]:
		var label := "high" if variant == 0 else "low"
		var enemy := await _setup("plasma_whip", 90.0)
		enemy.set("forced_variant", variant)
		var player := level.player
		var hp := player.health.current
		await wait_state(enemy, &"windup", 300)
		var band: Vector2 = enemy._band()
		check((band.y >= 30.0) == (variant == 0), "the %s lash is drawn at the %s height" % [label, label])
		await _wait_windup_end(enemy)
		if variant == 0:
			Input.action_press(&"move_down")  # 蹲下
		else:
			player.global_position.y -= 60.0  # 跳起來
			player.velocity = Vector2.ZERO
		await wait_state(enemy, &"strike", 120)
		await wait_state(enemy, &"recover", 60)
		check(player.health.current == hp, "the %s lash is avoided (crouch for high, jump for low)" % label)
		await _finish(enemy)
		# 沒躲就會被打到，而且只有一點傷害。
		enemy = await _setup("plasma_whip", 90.0)
		enemy.set("forced_variant", variant)
		player = level.player
		hp = player.health.current
		await wait_state(enemy, &"strike", 400)
		await physics_frames(4)
		check(hp - player.health.current == 1, "the %s lash hits a player who stays put for one health (%d)" % [label, hp - player.health.current])
		await _finish(enemy)
	# 貼身欺近：鞭子的判定框從身體前方開始，貼在背後的玩家不會被打到。
	var close := await _setup("plasma_whip", 90.0)
	check(close._strike_rect().position.x != 0.0 and close._strike_rect().size.x > 100.0, "the whip is long but starts in front of the body")
	await _finish(close)


func _test_hook() -> void:
	var enemy := await _setup("chain_hook", 110.0)
	var player := level.player
	var hp := player.health.current
	check(await wait_state(enemy, &"windup", 300), "the hook winds up when it sees the player")
	check(await wait_state(enemy, &"throw", 120), "the hook is thrown after its telegraph")
	check(await wait_state(enemy, &"reel", 120), "a hook that hits pulls the player in")
	check(player.is_pulled() and hp - player.health.current == 1, "being hooked costs one health and starts the pull (%d)" % (hp - player.health.current))
	var x0 := player.global_position.x
	await physics_frames(10)
	check(player.global_position.x > x0 + 4.0, "the pull moves the player toward the hook owner")
	# 打斷鎖鏈：鎖鏈中段的受擊框被打中就解除，鉤子的主人暈眩。
	var link: Hurtbox = enemy.get("_link")
	check(link != null and is_instance_valid(link), "the chain has a hurtbox while reeling")
	if link != null:
		link.receive(hit())
	await physics_frames(2)
	check(not player.is_pulled() and enemy.is_stunned(), "breaking the chain frees the player and stuns the hook owner")
	await _finish(enemy)
	# 衝刺掙脫。
	enemy = await _setup("chain_hook", 110.0)
	player = level.player
	await wait_state(enemy, &"reel", 600)
	player.state = Player.State.NORMAL
	player._dash_cooldown_left = 0.0
	player._try_dash(1.0)
	await physics_frames(2)
	check(not player.is_pulled(), "dashing breaks free of the hook")
	await _finish(enemy)
	# 拉到面前：沒有解開時最後被捅一下（總共兩點傷害，不會一擊必殺）。
	enemy = await _setup("chain_hook", 110.0)
	player = level.player
	hp = player.health.current
	player.health.setup(20, 0.0)
	await wait_state(enemy, &"recover", 900)
	await physics_frames(2)
	check(hp - player.health.current <= 2 and hp - player.health.current >= 1, "a full hook-and-stab costs at most two health (%d)" % (hp - player.health.current))
	check(not player.is_pulled(), "the pull ends after the stab")
	await _finish(enemy)


func _test_hook_blocked_by_wall() -> void:
	# 掩體牆（欄 30～31）擋住鉤子：玩家躲在牆後不會被鉤到。
	await open_level(10.0)
	var player := level.player
	player.health.setup(20, 1.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.LEFT
	place_player(26.0)
	var enemy := spawn(_path("chain_hook"), 36.0) as StrikeEnemy
	var hp := player.health.current
	await physics_frames(3)
	await wait_state(enemy, &"throw", 300)
	await physics_frames(70)
	check(player.health.current == hp and not player.is_pulled(), "a wall in between stops the hook")
	check(enemy.get("_retract") or enemy.fsm.is_in(&"recover") or enemy.fsm.is_in(&"patrol"), "the hook retracts after hitting the wall")
	AimInput.using_gamepad = false
	await _finish(enemy)


func _test_chapter_placement() -> void:
	check_level_placement({"res://data/levels/level_02.tres": [
		[&"chainsaw_arm", 202, 203], [&"hydraulic_claw", 160, 161],
		[&"plasma_whip", 352, 353], [&"chain_hook", 426, 427],
	]})
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/chapter_rosters.json"))["chapters"]
	for id in IDS:
		for chapter: String in roster:
			var configured: Array = roster[chapter]["enemies"] + roster[chapter]["demo_enemies"]
			check(configured.has(id) == (chapter == "chapter_02"), "%s belongs only to chapter two (%s)" % [id, chapter])
	for path in ["res://data/levels/level_01.tres", "res://data/levels/ch1_street.tres", "res://data/levels/ch1_warehouse.tres"]:
		var layout := LevelBuilder.parse(load(path) as LevelData)
		for id in IDS:
			check(PlacementChecks.cells_of(layout, StringName(id)).is_empty(), "%s is absent from %s" % [id, path])
