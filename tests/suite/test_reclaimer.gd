class_name ReclaimerSuite
extends TestSuite
## 第二章頭目「回收員」（NE-29）：資料與圖鑑、每個招式的預兆與效果（衝刺斬、瞬移射擊、電軌通電）、
## 階段轉換、擊敗流程、三種難度下的長時間運作（所有招式都會出現、不報錯）。使用空曠測試場地。

const BOSS_PATH := "res://data/enemies/reclaimer.tres"
const FLOOR_Y := 20 * 16.0
const ARENA := Rect2(8 * 16.0, 0.0, 50 * 16.0, 23 * 16.0)
const MIN_TELEGRAPH := 0.3


func run() -> void:
	_test_data()
	await _test_dash()
	await _test_blink()
	await _test_rails()
	await _test_phases_and_defeat()
	await _test_soak()


func _data() -> EnemyData:
	return load(BOSS_PATH) as EnemyData


func _open() -> Level:
	var level := await start_level(NewEnemiesSuite.arena_data())
	level.player.health.setup(999, 0.0)
	level.player.global_position = Vector2(14 * 16.0, FLOOR_Y)
	return level


func _spawn_boss(level: Level, x_tile := 48.0) -> Enemy:
	var boss := level._create_enemy(_data())
	boss.position = Vector2(x_tile * 16.0, FLOOR_Y)
	boss.call(&"set_arena", ARENA)
	level._entities.add_child(boss)
	return boss


func _wait_state(boss: Enemy, state: StringName, frames_max: int) -> bool:
	for i in frames_max:
		if boss.fsm.is_in(state):
			return true
		await physics_frames(1)
	return boss.fsm.is_in(state)


func _hurt(boss: Enemy, amount: int) -> void:
	var info := DamageInfo.create(amount, Combat.Team.PLAYER, &"test")
	info.ignore_invulnerability = true
	boss.hurtbox.receive(info)


func _test_data() -> void:
	var data := _data()
	check(data != null and data.validate().is_empty() and data.is_boss, "reclaimer data valid and a boss")
	check(DefeatCodex.has_card(data.contact_source_id) and DefeatCodex.has_card(data.projectile.source_id), "reclaimer contact and shot have codex cards")
	for id in [&"reclaimer_dash", &"reclaimer_rail"]:
		check(DefeatCodex.has_card(id), "codex card exists: %s" % id)
	var found := 0
	for card in DefeatCodex.get_all_cards():
		if str(card["id"]).begins_with("reclaimer_"):
			found += 1
			check(not str(card["hint"]).is_empty(), "reclaimer card has a strategy: %s" % card["id"])
	check(found == 4, "four reclaimer codex cards (got %d)" % found)
	check(data.credit_value > 0 and data.max_health > load("res://data/enemies/shield_rusher.tres").max_health, "boss is tougher than regular enemies and drops credits")
	check(data.behavior != load("res://data/enemies/warden.tres").behavior, "a different behaviour from the warden")
	# 難度公平性：任何預兆都至少 0.3 秒（第二階段與連續衝刺已經是最短的）。
	for difficulty in GameState.difficulties:
		var shortest := data.telegraph_time * 0.8 * 0.6
		check(shortest >= MIN_TELEGRAPH, "shortest reclaimer telegraph is readable on %s (%.2f)" % [difficulty.id, shortest])
		check(data.attack_cooldown * difficulty.enemy_cooldown_multiplier * 0.7 >= 0.4, "reclaimer idle gap is fair on %s" % difficulty.id)


func _test_dash() -> void:
	var level := await _open()
	var boss := _spawn_boss(level)
	await _wait_state(boss, &"idle", 120)
	check(boss.fsm.is_in(&"idle"), "intro ends and the boss idles")
	boss.fsm.transition(&"dash_windup")
	await physics_frames(2)
	check(boss.is_telegraphing(), "the dash has a telegraph")
	check(not boss.fsm.is_in(&"dash"), "the dash does not start before the telegraph ends")
	var started := await _wait_state(boss, &"dash", 120)
	check(started, "the dash starts after the telegraph")
	check(boss.contact.damage == boss.data.ability_damage and boss.contact.source_id == &"reclaimer_dash", "dash uses dash damage and source")
	var recovered := await _wait_state(boss, &"dash_recover", 120)
	check(recovered, "the dash ends in a recovery")
	check(boss.is_vulnerable() and boss.hurtbox.damage_scale > 1.0, "recovery exposes the core with bonus damage")
	check(boss.contact.damage == boss.data.contact_damage, "contact damage resets after the dash")
	var idle := await _wait_state(boss, &"idle", 180)
	check(idle and not boss.is_vulnerable() and is_equal_approx(boss.hurtbox.damage_scale, 1.0), "damage bonus ends after the recovery")
	var arena_ok := boss.global_position.x >= ARENA.position.x and boss.global_position.x <= ARENA.end.x
	check(arena_ok, "the boss stays inside the arena (x = %.0f)" % boss.global_position.x)
	await physics_frames(60)
	await end_level(level)


func _test_blink() -> void:
	var level := await _open()
	var boss := _spawn_boss(level)
	await _wait_state(boss, &"idle", 120)
	boss.fsm.transition(&"blink_out")
	await physics_frames(20)
	check(boss.is_telegraphing() and boss._alpha < 1.0, "blink: the boss fades out with a telegraph")
	var marker: float = boss._blink_x
	check(marker >= ARENA.position.x and marker <= ARENA.end.x, "the reappear marker is inside the arena")
	var aimed := await _wait_state(boss, &"blink_aim", 120)
	check(aimed and absf(boss.global_position.x - marker) < 1.0 and is_equal_approx(boss._alpha, 1.0), "the boss reappears at the marker")
	check(boss.is_telegraphing(), "reappearing starts a second telegraph (aim line)")
	var before := ProjectilePool.active_count()
	var left := await _wait_state(boss, &"idle", 120)
	check(left and ProjectilePool.active_count() > before, "the blink shot fires a fan of bullets")
	await physics_frames(60)
	await end_level(level)


func _test_rails() -> void:
	var level := await _open()
	var player := level.player
	var boss := _spawn_boss(level)
	await _wait_state(boss, &"idle", 120)
	await physics_frames(3)
	var rails: Array[ElectricRail] = boss._rails
	check(rails.size() >= 4, "the arena is covered with rails (%d)" % rails.size())
	player.global_position = Vector2(boss._rails[3].rect.get_center().x, FLOOR_Y)
	boss.fsm.transition(&"rail_windup")
	await physics_frames(2)
	check(boss.is_telegraphing(), "the rail attack has a telegraph")
	var armed := 0
	for i in 200:
		await physics_frames(1)
		armed = rails.filter(func(r: ElectricRail) -> bool: return r.state != ElectricRail.State.IDLE).size()
		if armed > 0:
			break
	boss.set_physics_process(false)  # 之後不要再出新招，只觀察這一輪電軌
	check(armed >= 1 and armed < rails.size(), "some, but never all, rails are armed (%d of %d)" % [armed, rails.size()])
	check(rails[3].state == ElectricRail.State.WARNING, "the player's own section is marked with a warning first")
	check(not rails[3].is_live(), "a rail is not live during its warning")
	# 預警期間站在上面不會受傷；通電後會。
	var health := player.health.current
	await physics_frames(int(ElectricRail.State.WARNING) * 20)
	check(player.health.current == health, "standing on a warning rail is safe")
	var live := false
	for i in 120:
		await physics_frames(1)
		if rails[3].is_live():
			live = true
			break
	check(live, "the warned rail becomes live")
	player.global_position = Vector2(rails[3].rect.get_center().x, FLOOR_Y - 1.0)
	await physics_frames(20)
	check(player.health.current < health, "a live rail hurts the player standing on it")
	# 通電結束後恢復平靜。
	# 受傷會有短暫的時間減慢（Fx.hitstop），所以用「等到熄滅」而不是固定影格數。
	for i in 900:
		if rails.all(func(r: ElectricRail) -> bool: return r.state == ElectricRail.State.IDLE):
			break
		await physics_frames(1)
	var still: Array[String] = []
	for i in rails.size():
		if rails[i].state != ElectricRail.State.IDLE:
			still.append("%d:%d" % [i, rails[i].state])
	check(still.is_empty(), "rails switch off again (still active: %s)" % [still])
	await physics_frames(60)
	await end_level(level)


func _test_phases_and_defeat() -> void:
	var level := await _open()
	var boss := _spawn_boss(level)
	await _wait_state(boss, &"idle", 120)
	check(boss._phase == 1, "starts in phase 1")
	var defeated := [0]
	var on_defeat := func() -> void: defeated[0] += 1
	EventBus.boss_defeated.connect(on_defeat)
	_hurt(boss, boss.health.max_health / 2 + 1)
	await physics_frames(3)
	check(boss._phase == 2 and boss.fsm.is_in(&"phase_shift"), "dropping below half health starts phase 2")
	check(boss.is_telegraphing(), "the phase shift has a telegraph")
	var calm := await _wait_state(boss, &"idle", 240)
	check(calm, "the boss resumes fighting after the phase shift")
	# 第二階段的衝刺會連續兩次。
	boss._dash_count = 0
	boss.fsm.transition(&"dash_recover")
	var again := await _wait_state(boss, &"dash_windup", 240)
	check(again and boss._dash_count == 1, "phase 2 chains a second dash")
	# 擊敗：通知過關、電軌清除。
	var rails: Array[ElectricRail] = boss._rails.duplicate()
	_hurt(boss, boss.health.current + 5)
	await physics_frames(int(2.0 * 60.0))
	check(defeated[0] == 1, "defeating the boss reports exactly once (%d)" % defeated[0])
	await physics_frames(10)
	check(rails.all(func(r) -> bool: return not is_instance_valid(r) or r.is_queued_for_deletion()), "the rails are removed with the boss")
	EventBus.boss_defeated.disconnect(on_defeat)
	await end_level(level)


## 長時間運作：玩家站著不動（無敵），三種難度下各跑一段，所有招式都要出現且不報錯；
## 中途打到第二階段，確認階段轉換也走得過。
func _test_soak() -> void:
	for difficulty_index in GameState.difficulties.size():
		var level := await start_level(NewEnemiesSuite.arena_data(), difficulty_index)
		level.player.health.setup(9999, 0.0)
		level.player.global_position = Vector2(20 * 16.0, FLOOR_Y)
		var boss := _spawn_boss(level, 40.0)
		var visited: Dictionary[StringName, bool] = {}
		for i in int(40.0 * 60.0):
			await physics_frames(1)
			if not is_instance_valid(boss):
				break
			visited[boss.fsm.current] = true
			if i == int(18.0 * 60.0):
				_hurt(boss, boss.health.max_health / 2 + 1)
			if level.player.global_position.distance_to(boss.global_position) < 20.0:
				level.player.global_position = Vector2(20 * 16.0, FLOOR_Y)
		var difficulty := GameState.difficulties[difficulty_index]
		for state in [&"dash", &"blink_aim", &"rail_windup", &"phase_shift", &"dash_recover"]:
			check(visited.has(state), "%s: the boss performs %s within 40s" % [difficulty.id, state])
		check(is_instance_valid(boss) and not boss.health.is_dead, "%s: the boss survives the soak test" % difficulty.id)
		await end_level(level)
