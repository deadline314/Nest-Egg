class_name NewEnemiesSuite
extends TestSuite
## 第二章新敵人（NE-28）：切割者（近戰突進）、迷彩獵手（光學迷彩）、維修機（支援護盾）、精銳保全。
## 使用空曠的測試場地（tests/fixtures/arena_map.json），敵人由測試直接生成。

const MAP_PATH := "res://tests/fixtures/arena_map.json"
const SLASHER_PATH := "res://data/enemies/slasher.tres"
const STALKER_PATH := "res://data/enemies/stalker.tres"
const DRONE_PATH := "res://data/enemies/repair_drone.tres"
const ELITE_PATH := "res://data/enemies/elite_grunt.tres"
const GRUNT_PATH := "res://data/enemies/grunt.tres"
const FLOOR_Y := 20 * 16.0
const MIN_TELEGRAPH := 0.4
const MIN_COOLDOWN := 0.6

var _level: Level


func run() -> void:
	_test_data()
	await _test_slasher()
	await _test_stalker_cloak()
	await _test_repair_drone()
	await _test_shield_rules()


static func arena_data() -> LevelData:
	var data := LevelData.new()
	data.id = &"arena_test"
	data.layout_path = MAP_PATH
	return data


func _open_arena() -> Level:
	_level = await start_level(arena_data())
	_level.player.health.setup(999, 0.0)
	return _level


func _spawn(path: String, x_tile: float) -> Enemy:
	var enemy := _level._create_enemy(load(path) as EnemyData)
	enemy.position = Vector2(x_tile * 16.0, FLOOR_Y)
	_level._entities.add_child(enemy)
	return enemy


func _place_player(x_tile: float) -> void:
	_level.player.global_position = Vector2(x_tile * 16.0, FLOOR_Y)
	_level.player.velocity = Vector2.ZERO


func _test_data() -> void:
	for path in [SLASHER_PATH, STALKER_PATH, DRONE_PATH, ELITE_PATH]:
		var data := load(path) as EnemyData
		check(data != null and data.validate().is_empty(), "new enemy data valid: %s" % path)
		check(data.contact_damage > 0 and DefeatCodex.has_card(data.contact_source_id), "new enemy has a contact codex card: %s" % path)
		var spec: ProjectileSpec = data.projectile
		if spec != null:
			check(DefeatCodex.has_card(spec.source_id), "new enemy projectile has a codex card: %s" % spec.source_id)
	check(DefeatCodex.has_card(&"slasher_lunge"), "slasher lunge has a codex card")
	for id in [&"slasher_lunge", &"slasher_contact", &"stalker_shot", &"stalker_contact", &"medic_contact", &"elite_shot"]:
		var found := false
		for card in DefeatCodex.get_all_cards():
			if card["id"] == id:
				found = true
				check(not str(card.get("hint", "")).is_empty(), "codex card gives a strategy hint: %s" % id)
		check(found, "codex card exists: %s" % id)
	check(load(ELITE_PATH).max_health > load(GRUNT_PATH).max_health, "elite grunt is tougher than a grunt")
	# 難度公平性：任何難度下，預兆至少 0.4 秒、兩次攻擊的間隔至少 0.6 秒（玩家永遠有時間反應）。
	for difficulty in GameState.difficulties:
		for path in [SLASHER_PATH, STALKER_PATH, ELITE_PATH, DRONE_PATH]:
			var enemy_data := load(path) as EnemyData
			check(enemy_data.telegraph_time >= MIN_TELEGRAPH, "%s telegraph is readable on %s" % [enemy_data.id, difficulty.id])
			check(enemy_data.attack_cooldown * difficulty.enemy_cooldown_multiplier >= MIN_COOLDOWN, "%s cooldown is fair on %s (%.2f)" % [enemy_data.id, difficulty.id, enemy_data.attack_cooldown * difficulty.enemy_cooldown_multiplier])


func _test_slasher() -> void:
	var level := await _open_arena()
	var slasher := _spawn(SLASHER_PATH, 20.0)
	_place_player(14.0)
	await physics_frames(10)
	# 發現玩家 → 蓄力（有預兆）。
	var saw_telegraph := false
	for i in 90:
		await physics_frames(1)
		if slasher.fsm.is_in(&"windup") and slasher.is_telegraphing():
			saw_telegraph = true
			break
	check(saw_telegraph, "slasher telegraphs before it lunges")
	# 撲出：接觸傷害變成斬擊傷害，來源是 slasher_lunge。
	var lunged := false
	for i in 90:
		await physics_frames(1)
		if slasher.fsm.is_in(&"leap"):
			lunged = true
			check(slasher.contact.damage == slasher.data.ability_damage and slasher.contact.source_id == &"slasher_lunge", "lunge uses the lunge damage and source")
			check(not slasher.is_telegraphing(), "telegraph ends when the lunge starts")
			break
	check(lunged, "slasher lunges after the telegraph")
	# 落地後恢復成普通接觸傷害並有硬直。
	var recovered := false
	for i in 120:
		await physics_frames(1)
		if slasher.fsm.is_in(&"recover"):
			recovered = true
			check(slasher.contact.damage == slasher.data.contact_damage, "contact damage resets after the lunge")
			break
	check(recovered, "slasher lands into a recovery window")
	# 暈眩（例如被完美格擋）會中斷攻擊。
	slasher.fsm.transition(&"windup")
	await physics_frames(2)
	slasher.stun(0.6)
	await physics_frames(2)
	check(slasher.fsm.is_in(&"recover"), "stun interrupts the slasher's attack")
	check(slasher.health.current == slasher.data.max_health, "slasher test did not damage the slasher")
	await end_level(level)


func _test_stalker_cloak() -> void:
	var level := await _open_arena()
	var stalker := _spawn(STALKER_PATH, 40.0) as Stalker
	_place_player(10.0)
	await physics_frames(40)
	check(stalker.is_cloaked(), "stalker is cloaked in the dark (no lights nearby)")
	check(stalker._visibility <= Stalker.HIDDEN_ALPHA + 0.01, "cloaked stalker is nearly invisible")
	# 被燈照到：現形。
	var lamp := LightKit.create_point_light(Color.WHITE, 140.0, 1.4)
	lamp.global_position = stalker.global_position + Vector2(0, -30)
	level.add_child(lamp)
	await physics_frames(30)
	check(LightKit.light_level_at(get_tree_root(), stalker._center()) >= Stalker.LIT_THRESHOLD, "light_level_at sees the lamp")
	check(not stalker.is_cloaked(), "stalker reveals itself under a lamp")
	# 燈熄滅（斷電）後又隱形。
	lamp.enabled = false
	await physics_frames(int(2.5 * 60.0))
	check(stalker.is_cloaked(), "stalker cloaks again when the light goes out")
	lamp.queue_free()
	# 被打到：現形並維持一段時間。
	var info := DamageInfo.create(1, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	stalker.hurtbox.receive(info)
	await physics_frames(30)
	check(not stalker.is_cloaked(), "a hit reveals the stalker")
	check(stalker._reveal_left > 0.0, "the reveal lasts for a while")
	await end_level(level)

	# 貼近玩家也會現形；開火前有預兆。
	level = await _open_arena()
	stalker = _spawn(STALKER_PATH, 20.0) as Stalker
	_place_player(16.0)
	await physics_frames(40)
	check(not stalker.is_cloaked(), "stalker reveals itself when the player is right next to it")
	_place_player(5.0)
	var telegraphed := false
	var fired := false
	var shots := [0]
	var counter := func(_s: ProjectileSpec) -> void: shots[0] += 1
	for i in 600:
		await physics_frames(1)
		if stalker.fsm.is_in(&"aim") and stalker.is_telegraphing():
			telegraphed = true
		if stalker.fsm.is_in(&"burst"):
			fired = true
			check(not stalker.is_cloaked() or stalker._visibility > 0.3, "stalker is visible while it fires")
			break
	check(telegraphed, "stalker telegraphs its shot with a visible aim line")
	check(fired, "stalker fires a burst after the telegraph")
	await end_level(level)


## RefCounted 沒有 get_tree()，經由執行器取得場景樹。
func get_tree_root() -> SceneTree:
	return runner.get_tree()


func _test_repair_drone() -> void:
	var level := await _open_arena()
	var grunt := _spawn(GRUNT_PATH, 30.0)
	var drone := _spawn(DRONE_PATH, 31.0)
	drone.position.y = FLOOR_Y - 60.0
	_place_player(3.0)
	check(grunt.shield == 0, "ally starts without a shield")
	var channeled := false
	for i in 600:
		await physics_frames(1)
		if drone.fsm.is_in(&"channel"):
			channeled = true
			check(drone.is_telegraphing(), "the repair drone's beam has a charge-up telegraph")
			break
	check(channeled, "repair drone starts channeling to an ally")
	var shielded := false
	for i in 240:
		await physics_frames(1)
		if grunt.shield > 0:
			shielded = true
			break
	check(shielded, "repair drone gives its ally a shield")
	# 護盾擋一次攻擊，之後正常受傷。
	var before := grunt.health.current
	var shot := DamageInfo.create(1, Combat.Team.PLAYER, &"test")
	shot.ignore_invulnerability = true
	var shield_before := grunt.shield
	var result := grunt.hurtbox.receive(shot)
	check(result == Hurtbox.Result.BLOCKED and grunt.shield == shield_before - 1 and grunt.health.current == before, "a shield layer absorbs one hit")
	await end_level(level)

	# 光束連結時擊落維修機：護盾不會生效。
	level = await _open_arena()
	grunt = _spawn(GRUNT_PATH, 30.0)
	drone = _spawn(DRONE_PATH, 31.0)
	drone.position.y = FLOOR_Y - 60.0
	_place_player(3.0)
	for i in 600:
		await physics_frames(1)
		if drone.fsm.is_in(&"channel"):
			break
	check(drone.fsm.is_in(&"channel"), "drone channels again in a fresh arena")
	var lethal := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	drone.hurtbox.receive(lethal)
	await physics_frames(int(2.0 * 60.0))
	check(grunt.shield == 0, "killing the drone mid-channel prevents the shield")
	await physics_frames(60)
	await end_level(level)


func _test_shield_rules() -> void:
	var level := await _open_arena()
	var grunt := _spawn(GRUNT_PATH, 30.0)
	_place_player(3.0)
	grunt.add_shield(10)
	check(grunt.shield == Enemy.MAX_SHIELD, "shield layers are capped")
	grunt.add_shield(-5)
	check(grunt.shield == Enemy.MAX_SHIELD, "negative shield input is ignored")
	# 爆炸無視護盾。
	var blast := DamageInfo.create(1, Combat.Team.PLAYER, &"test")
	blast.bypass_guard = true
	blast.ignore_invulnerability = true
	var before := grunt.health.current
	grunt.hurtbox.receive(blast)
	check(grunt.health.current == before - 1 and grunt.shield == Enemy.MAX_SHIELD, "explosions ignore shields")
	# 死亡的敵人不再接受護盾。
	var lethal := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	lethal.bypass_guard = true
	grunt.hurtbox.receive(lethal)
	grunt.shield = 0
	grunt.add_shield(2)
	check(grunt.shield == 0, "dying enemies cannot be shielded")
	# 死亡演出（碎片、掉落）是延後加入場景的，等它們完成再釋放關卡，避免殘留節點。
	await physics_frames(90)
	await end_level(level)
