class_name HitReactionSuite
extends EnemySuiteBase
## 敵人受擊方向反應與依力道的死亡倒法（NE-103）也在這裡：正面／背面中彈身體往不同方向、倒法依方向與力道、屍體上限、脫落零件物件池。
## 機械類與觸手生物的受擊反應、損傷狀態、斷肢（NE-105）也在這裡。
## 部位受擊框與弱點（NE-104）也在這裡：頭的傷害倍率、同一發只算一次、判定跟著姿勢、爆炸與近戰不分部位、壞資料的容錯。
## 敵人受擊分層與命中頓幀（NE-102）：輕擊只閃白、累積畏縮、重擊硬直、出招中的霸體、反應後的保護時間、
## 頭目幾乎不畏縮、局部頓幀只凍結指定節點且重疊取最長。

const ELITE_PATH := "res://data/enemies/elite_grunt.tres"
const WARDEN_PATH := "res://data/enemies/warden.tres"
const RECLAIMER_PATH := "res://data/enemies/reclaimer.tres"
const KNOCKBACK := 40.0


func run() -> void:
	_test_impact_values()
	_test_data()
	await _test_light_hits()
	await _test_accumulated_flinch()
	await _test_heavy_hit_staggers()
	await _test_armor_states()
	await _test_no_lock_after_reaction()
	await _test_boss_is_hard_to_move()
	await _test_local_freeze()
	await _test_hurt_direction()
	await _test_death_direction_and_force()
	await _test_corpse_cap()
	await _test_debris_pool()
	await _test_armor_still_flies_off()
	await _test_player_clothing_does_not_fly_off()
	_test_hurt_part_data()
	await _test_head_and_body_shots()
	await _test_parts_follow_the_pose()
	await _test_explosion_hits_once()
	await _test_bad_part_data()
	_test_machine_reaction_data()
	await _test_machine_kick_and_stall()
	await _test_damage_stages()
	await _test_tentacle_wave_and_sever()


## 一發步槍彈等級的輕擊（傷害 1、擊退 40）。
func _light() -> DamageInfo:
	var info := hit(1)
	info.knockback = Vector2(KNOCKBACK, 0.0)
	return info


func _heavy(impact: float) -> DamageInfo:
	var info := hit(1)
	info.impact = impact
	return info


## 生成一隻生命很多的步兵（不會因為血量低進入終結狀態），並複製資料讓測試可以改。
func _spawn_trooper() -> Enemy:
	var enemy := spawn(GRUNT_PATH, 60.0)
	enemy.data = enemy.data.duplicate()
	enemy.health.setup(999, 0.0)
	return enemy


func _test_impact_values() -> void:
	var plain := DamageInfo.create(1, Combat.Team.PLAYER, &"t")
	check(is_equal_approx(plain.get_impact(), 1.0), "impact without knockback equals the damage")
	var rifle := DamageInfo.create(1, Combat.Team.PLAYER, &"t", Vector2(40, 0))
	check(is_equal_approx(rifle.get_impact(), 1.4), "impact adds knockback / 100 (%.2f)" % rifle.get_impact())
	var melee := DamageInfo.create(1, Combat.Team.PLAYER, &"t")
	melee.impact = 6.0
	check(is_equal_approx(melee.get_impact(), 6.0), "an explicit impact overrides the derived one")


func _test_data() -> void:
	for path: String in [GRUNT_PATH, ELITE_PATH, WARDEN_PATH, RECLAIMER_PATH]:
		var data := load(path) as EnemyData
		check(data.poise > 0.0 and data.flinch_time > 0.0 and data.stagger_time > data.flinch_time, "%s has sane reaction data" % data.id)
	check((load(WARDEN_PATH) as EnemyData).poise >= 50.0 and (load(RECLAIMER_PATH) as EnemyData).poise >= 50.0, "bosses barely flinch")
	check((load(ELITE_PATH) as EnemyData).poise > (load(GRUNT_PATH) as EnemyData).poise, "elite troopers are tougher than troopers")
	var armor := (load(GRUNT_PATH) as EnemyData).armor_states
	check(armor.has("leap") and armor.has("charge") and not armor.has("patrol") and not armor.has("aim") and not armor.has("windup"), "attack states carry armor; patrol, aim and wind-ups do not")


func _test_light_hits() -> void:
	await open_level(10.0)
	var enemy := _spawn_trooper()
	enemy.hurtbox.receive(_light())
	await physics_frames(1)
	check(enemy._flinch_left <= 0.0 and not enemy.is_stunned(), "one light hit neither flinches nor staggers")
	check(enemy.fsm.current == &"patrol" or enemy.fsm.current == &"aim", "a light hit does not change the current action (%s)" % enemy.fsm.current)
	await end_level(level)


func _test_accumulated_flinch() -> void:
	await open_level(10.0)
	var enemy := _spawn_trooper()
	for i in 2:
		enemy.hurtbox.receive(_light())
	check(enemy._flinch_left <= 0.0, "two light hits are still just light")
	enemy.hurtbox.receive(_light())
	check(enemy._flinch_left > 0.0 and not enemy.is_stunned(), "enough light hits make it flinch without a full stagger")
	check(Fx._frozen.has(enemy), "a flinch freezes the target for a moment")
	# 畏縮期間動作暫停，結束後回來。
	var held := enemy.fsm.time_in_state
	await physics_frames(3)
	check(is_equal_approx(enemy.fsm.time_in_state, held), "the current action's timer is paused during the flinch")
	for i in int(ceil(enemy.data.flinch_time * 60.0)) + 12:
		await physics_frames(1)
	check(enemy._flinch_left <= 0.0 and not enemy.is_stunned(), "the flinch ends by itself without a stun")
	await end_level(level)


func _test_heavy_hit_staggers() -> void:
	await open_level(10.0)
	var enemy := _spawn_trooper()
	enemy.hurtbox.receive(_heavy(6.0))
	check(enemy.is_stunned(), "a single heavy hit (melee, reflected shot, blast) staggers a trooper")
	check(is_equal_approx(enemy._stun_left, enemy.data.stagger_time), "the stagger lasts the data's stagger_time (%.2f)" % enemy._stun_left)
	await end_level(level)


func _test_armor_states() -> void:
	await open_level(10.0)
	var enemy := _spawn_trooper()
	enemy.data.armor_states = PackedStringArray([String(enemy.fsm.current)])
	for i in 6:
		enemy.hurtbox.receive(_light())
	check(enemy._flinch_left <= 0.0 and not enemy.is_stunned(), "light hits cannot interrupt an armored (attacking) state")
	enemy.hurtbox.receive(_heavy(enemy.data.poise * Enemy.STAGGER_RATIO + 0.5))
	check(not enemy.is_stunned(), "a normal heavy hit still cannot stagger an armored state")
	enemy.hurtbox.receive(_heavy(enemy.data.poise * Enemy.BREAK_RATIO + 0.5))
	check(enemy.is_stunned(), "only a break-level hit staggers an armored state")
	await end_level(level)


## 畏縮後的保護時間：連續射擊不會把敵人鎖在畏縮裡。
func _test_no_lock_after_reaction() -> void:
	await open_level(10.0)
	var enemy := _spawn_trooper()
	for i in 3:
		enemy.hurtbox.receive(_light())
	check(enemy._flinch_left > 0.0, "setup: the trooper flinched")
	enemy._flinch_left = 0.0
	for i in 8:
		enemy.hurtbox.receive(_light())
	check(enemy._flinch_left <= 0.0, "right after a reaction, more light hits do not flinch it again (no lock)")
	await end_level(level)


func _test_boss_is_hard_to_move() -> void:
	await open_level(10.0)
	var boss := spawn(WARDEN_PATH, 60.0)
	boss.health.setup(9999, 0.0)
	for i in 6:
		boss.hurtbox.receive(_light())
	boss.hurtbox.receive(_heavy(6.0))
	check(boss._flinch_left <= 0.0 and not boss.is_stunned(), "the boss shrugs off light hits and a melee-strength hit")
	await end_level(level)


func _test_local_freeze() -> void:
	var a := Node.new()
	var b := Node.new()
	Fx.freeze([a, null], 0.2)
	check(a.process_mode == Node.PROCESS_MODE_DISABLED and b.process_mode == Node.PROCESS_MODE_INHERIT, "only the listed nodes freeze, a null entry is ignored")
	Fx.freeze([a], 0.02)
	await physics_frames(6)
	check(a.process_mode == Node.PROCESS_MODE_DISABLED, "overlapping freezes keep the longer one instead of adding or shortening")
	for i in 30:
		await physics_frames(1)
	check(a.process_mode == Node.PROCESS_MODE_INHERIT and not Fx._frozen.has(a), "the node is released afterwards with its original mode")
	var c := Node.new()
	Fx.freeze([c], 0.05)
	c.free()
	await physics_frames(10)
	check(not Fx._frozen.has(c), "a node freed during a freeze is dropped safely")
	a.free()
	b.free()


## 還沒走動的步兵：面向左、不偵測、不移動，讓方向測試穩定。
func _spawn_still_trooper(x_tile: float) -> Enemy:
	var enemy := _spawn_trooper_at(x_tile)
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.facing = -1
	return enemy


func _spawn_trooper_at(x_tile: float) -> Enemy:
	var enemy := spawn(GRUNT_PATH, x_tile)
	enemy.data = enemy.data.duplicate()
	enemy.health.setup(999, 0.0)
	return enemy


## 敵人面向左時，往右的受力＝從正面來。
func _push(info: DamageInfo, to_right: bool) -> DamageInfo:
	info.knockback = Vector2(40.0 if to_right else -40.0, 0.0)
	return info


func _test_hurt_direction() -> void:
	await open_level(10.0)
	var front := _spin_still(60.0)
	var back := _spin_still(66.0)
	front.hurtbox.receive(_push(hit(1), true))
	back.hurtbox.receive(_push(hit(1), false))
	check(front._rig_input.hurt_dir > 0.0 and back._rig_input.hurt_dir < 0.0, "a hit from the front and a hit from behind give opposite hurt directions")
	await physics_frames(3)
	var chest_front := front.rig.bone(&"chest").rotation
	var chest_back := back.rig.bone(&"chest").rotation
	check(chest_front < chest_back - 0.03, "hit from the front leans the chest back, from behind leans it forward (%.2f vs %.2f)" % [chest_front, chest_back])
	await end_level(level)


func _spin_still(x_tile: float) -> Enemy:
	var enemy := _spawn_still_trooper(x_tile)
	return enemy


func _kill_with(enemy: Enemy, to_right: bool, impact: float) -> void:
	var info := _push(hit(999), to_right)
	info.impact = impact
	enemy.hurtbox.receive(info)


func _test_death_direction_and_force() -> void:
	await open_level(10.0)
	var front := _spawn_still_trooper(60.0)
	var back := _spawn_still_trooper(66.0)
	_kill_with(front, true, 1.0)
	_kill_with(back, false, 1.0)
	check(front._rig_input.death_dir > 0.0 and back._rig_input.death_dir < 0.0, "the last hit's direction is passed to the death animation")
	for i in 40:
		await physics_frames(1)
	var hip_front := front.rig.bone(&"hip").rotation
	var hip_back := back.rig.bone(&"hip").rotation
	check(hip_front < -0.5 and hip_back > 0.5, "shot from the front falls backwards, shot from behind falls forwards (%.2f / %.2f)" % [hip_front, hip_back])
	var light := _spawn_still_trooper(72.0)
	var heavy := _spawn_still_trooper(78.0)
	_kill_with(light, true, 1.0)
	_kill_with(heavy, true, 7.0)
	check(is_equal_approx(light._rig_input.death_force, 0.0) and is_equal_approx(heavy._rig_input.death_force, 1.0), "a heavy final blow has full death force, a light one none")
	check(heavy.velocity.x > light.velocity.x and heavy.velocity.y < light.velocity.y, "a heavy kill is pushed further and hops up")
	var blasted := _spawn_still_trooper(84.0)
	var melee_kill := _spawn_still_trooper(90.0)
	var blast_info := hit(999)
	blast_info.impact = 7.0
	blast_info.knockback = Vector2(180.0, -260.0)
	var melee_info := hit(999)
	melee_info.impact = 7.0
	melee_info.knockback = Vector2(180.0, -60.0)
	blasted.hurtbox.receive(blast_info)
	melee_kill.hurtbox.receive(melee_info)
	check(blasted.velocity.y < melee_kill.velocity.y - 20.0, "an explosion throws the victim higher than a melee blow does")
	for i in 14:
		Fx.thaw_all()  # 頓幀看真實時間，機器忙時會讓兩隻凍住的影格數不同，每格解凍才與機器速度無關
		await physics_frames(1)
	check(absf(heavy.rig.bone(&"hip").rotation) > absf(light.rig.bone(&"hip").rotation) + 0.05, "a heavy kill falls faster and further than a light one")
	await end_level(level)


func _test_corpse_cap() -> void:
	await open_level(10.0)
	var group: Array[Enemy] = []
	for i in Enemy.MAX_CORPSES + 5:
		group.append(_spawn_still_trooper(40.0 + i * 3.0))
	for enemy in group:
		_kill_with(enemy, true, 1.0)
	check(Enemy._corpses.size() <= Enemy.MAX_CORPSES, "at most %d corpses are tracked (%d)" % [Enemy.MAX_CORPSES, Enemy._corpses.size()])
	# 淡出靠時間計時，機器忙的時候會慢一點：等到條件成立（最多兩秒）而不是固定等幾格。
	var standing := 0
	for i in 120:
		await physics_frames(1)
		standing = 0
		for enemy in group:
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				standing += 1
		if standing <= Enemy.MAX_CORPSES:
			break
	check(standing <= Enemy.MAX_CORPSES, "the oldest corpses fade out quickly once the cap is passed (%d left)" % standing)
	await end_level(level)


func _test_debris_pool() -> void:
	await open_level(10.0)
	var made: Array[RigDebris] = []
	for i in RigDebris.MAX_ACTIVE + 6:
		var debris := RigDebris.spawn(null, Transform2D.IDENTITY, Vector2.ZERO, Vector2.ZERO)
		if debris != null:
			made.append(debris)
	check(made.size() == RigDebris.MAX_ACTIVE, "no more than %d debris pieces are active at once (%d)" % [RigDebris.MAX_ACTIVE, made.size()])
	check(RigDebris.spawn(null, Transform2D.IDENTITY, Vector2.ZERO, Vector2.ZERO) == null, "a full pool refuses more debris instead of creating nodes")
	for debris in made:
		debris.cancel()
		debris.free()
	var first := RigDebris.spawn(null, Transform2D.IDENTITY, Vector2.ZERO, Vector2.ZERO)
	check(first != null, "after pieces are released new ones can be taken again")
	level.add_child(first)
	first._recycle()
	await physics_frames(2)
	var again := RigDebris.spawn(null, Transform2D.IDENTITY, Vector2.ZERO, Vector2.ZERO)
	check(again == first and first.get_parent() == null, "a finished piece leaves the tree and is reused")
	again.cancel()
	again.free()
	await end_level(level)


## 裝甲片仍然會飛出去（改用物件池之後）。
func _test_armor_still_flies_off() -> void:
	await open_level(10.0)
	var enemy := _spawn_still_trooper(60.0)
	enemy.health.setup(10, 0.0)
	enemy.data.finish_health_ratio = 0.0
	for i in 6:
		enemy.hurtbox.receive(hit(1))
	await physics_frames(3)
	check(level.find_children("*", "RigDebris", true, false).size() > 0, "lost armor still flies off as debris")
	await end_level(level)


const HEAD_ENEMIES := ["grunt", "elite_grunt", "sniper", "stalker", "slasher", "flamer", "shield_rusher", "heavy_gunner"]


func _test_player_clothing_does_not_fly_off() -> void:
	for facing in [1, -1]:
		for side in [1, -1]:
			await open_level(10.0)
			var player := level.player
			var rig: CharacterRig = player._visual.rig
			player.facing = facing
			player.health.setup(6, 0.0)
			rig.set_armor_ratio(1.0, false)
			var before := RigDebris._active
			for i in 5:
				var info := DamageInfo.create(1, Combat.Team.ENEMY, &"clothing_test")
				info.origin = player.global_position + Vector2(side * 30, 0)
				info.ignore_invulnerability = true
				player.health.take_damage(info)
				check(RigDebris._active == before, "Rin's damaged clothing never spawns a complete body part")
			check(rig._armor_visible < rig.armor_count() and rig._under.all(func(part: CanvasItem) -> bool: return part.visible), "Rin's existing clothing damage remains visible")
			player.health.heal(6)
			check(rig._armor_visible == rig.armor_count(), "healing still restores Rin's clothing")
			var fatal := DamageInfo.create(9999, Combat.Team.ENEMY, &"clothing_test")
			fatal.origin = player.global_position + Vector2(side * 30, 0)
			fatal.ignore_invulnerability = true
			player.health.take_damage(fatal)
			await physics_frames(2)
			check(player.is_dead() and rig._armor_visible == 0 and RigDebris._active == before, "a real fatal hit leaves Rin's body intact without physical body-part debris")
			await end_level(level)


func _head_point(enemy: Enemy) -> Vector2:
	return enemy.global_position + (enemy._parts[0]["box"] as Hurtbox).shape_offset()


func _test_hurt_part_data() -> void:
	for id: String in HEAD_ENEMIES:
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		var ok := data.hurt_parts.size() > 0
		for def in data.hurt_parts:
			ok = ok and not str(def.get("id", "")).is_empty() and Vector2(def.get("size", Vector2.ZERO)).x > 0.0 and float(def.get("mult", 0.0)) > 1.0
		check(ok, "%s has a valid weak-point part" % id)


func _test_head_and_body_shots() -> void:
	await open_level(10.0)
	var head_target := _spawn_still_trooper(60.0)
	var body_target := _spawn_still_trooper(70.0)
	await physics_frames(2)
	var hp_head := head_target.health.current
	var hp_body := body_target.health.current
	var head_at := _head_point(head_target)
	shoot_from(head_at + Vector2(-48.0, 0.0), Vector2.RIGHT)
	shoot_from(body_target.global_position + Vector2(-48.0, -18.0), Vector2.RIGHT)
	for i in 30:
		await physics_frames(1)
	check(head_target.health.current == hp_head - 2, "a head shot does 1.5x damage, counted once (%d lost)" % (hp_head - head_target.health.current))
	check(body_target.health.current == hp_body - 1, "a body shot does normal damage (%d lost)" % (hp_body - body_target.health.current))
	# 受擊框層級：頭部位算弱點、身體不是。
	var head_info := hit(1)
	head_target.hurtbox.resolve_at(head_at).receive(head_info)
	var body_info := hit(1)
	body_target.hurtbox.receive(body_info)
	check(head_info.weak_hit and head_info.part == &"head" and not body_info.weak_hit, "a head hit is flagged as a weak-point hit, a body hit is not")
	check(head_target.hurtbox.resolve_at(head_target.global_position + Vector2(0, -8)).part_id == &"", "a point away from the head resolves to the whole body")
	await end_level(level)


func _test_parts_follow_the_pose() -> void:
	await open_level(10.0)
	var enemy := _spawn_still_trooper(60.0)
	await physics_frames(3)
	var standing_y := (enemy._parts[0]["box"] as Hurtbox).shape_offset().y
	enemy._rig_input.crouching = true
	for i in 30:
		await physics_frames(1)
	var crouch_y := (enemy._parts[0]["box"] as Hurtbox).shape_offset().y
	check(crouch_y > standing_y + 3.0, "the head hurt part drops when the enemy crouches (%.1f -> %.1f)" % [standing_y, crouch_y])
	_kill_with(enemy, true, 1.0)
	check(not (enemy._parts[0]["box"] as Hurtbox).can_receive(), "parts stop receiving hits when the enemy dies")
	await physics_frames(3)  # 死亡掉落與碎片是延遲加入的，等它們進場再結束關卡，才不會變成孤兒節點
	await end_level(level)


func _test_explosion_hits_once() -> void:
	await open_level(10.0)
	var enemy := _spawn_still_trooper(60.0)
	await physics_frames(2)
	var before := enemy.health.current
	Fx.explosion(enemy.global_position + Vector2(0, -22), 60.0, 2, Combat.Team.PLAYER, &"test")
	for i in 6:
		await physics_frames(1)
	check(enemy.health.current == before - 2, "an explosion hits the whole enemy once, ignoring parts (%d lost)" % (before - enemy.health.current))
	await end_level(level)


## 壞的部位資料：記錄具體位置並略過，不崩潰，其他部位照常。
func _test_bad_part_data() -> void:
	await open_level(10.0)
	var enemy := level._create_enemy(load(GRUNT_PATH) as EnemyData)
	enemy.data = enemy.data.duplicate()
	enemy.data.id = &"test_missing_part"
	enemy.data.hurt_parts = Array([{"id": "", "size": Vector2(4, 4), "mult": 2.0}, {"id": "ok", "bone": "no_such_bone", "size": Vector2(4, 4), "mult": 2.0}], TYPE_DICTIONARY, &"", null)
	enemy.position = Vector2(60.0 * 16.0, FLOOR_Y)
	level._entities.add_child(enemy)
	await physics_frames(3)
	check(enemy._parts.size() == 1 and (enemy._parts[0]["box"] as Hurtbox).part_id == &"ok", "a part with a missing bone falls back to a fixed position, an invalid one is skipped")
	await end_level(level)


const MACHINE_IDS := ["drone", "searchlight_drone", "repair_drone", "bomber", "shock_hound", "turret", "mimic"]


func _test_machine_reaction_data() -> void:
	var seen: Dictionary = {}
	for id: String in MACHINE_IDS:
		var data := load("res://data/enemies/%s.tres" % id) as EnemyData
		check(["wobble", "stall", "stumble"].has(data.hit_style) and data.hit_amount > 0.0, "%s has a valid body reaction (%s, %.1f)" % [id, data.hit_style, data.hit_amount])
		var key := "%s:%.1f" % [data.hit_style, data.hit_amount]
		check(not seen.has(key), "%s does not share its reaction with another machine (%s)" % [id, key])
		seen[key] = true
		var sorted := true
		for i in range(1, data.damage_states.size()):
			sorted = sorted and data.damage_states[i] < data.damage_states[i - 1]
		check(sorted and data.damage_states.size() >= 1, "%s has damage states from high to low" % id)


func _test_machine_kick_and_stall() -> void:
	await open_level(10.0)
	var drone := _spawn_machine("drone", 60.0, FLOOR_Y - 52.0)
	var hound := _spawn_machine("shock_hound", 66.0)
	await physics_frames(2)
	var vy := drone.velocity.y
	drone.hurtbox.receive(_heavy(6.0))
	hound.hurtbox.receive(_light())
	check(drone._body_kick > 0.9 and hound._body_kick > 0.2 and hound._body_kick < drone._body_kick, "a heavier hit kicks a machine's body harder")
	check(drone.velocity.y > vy + 50.0, "a flying machine loses lift when it is staggered (%.0f -> %.0f)" % [vy, drone.velocity.y])
	for i in 90:
		await physics_frames(1)
	check(is_zero_approx(drone._body_kick) and is_zero_approx(hound._body_kick), "the body kick settles back to zero")
	await end_level(level)


func _spawn_machine(id: String, x_tile: float, y := FLOOR_Y) -> Enemy:
	var enemy := spawn("res://data/enemies/%s.tres" % id, x_tile, y)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.facing = -1
	return enemy


func _test_damage_stages() -> void:
	await open_level(10.0)
	var drone := _spawn_machine("drone", 60.0, FLOOR_Y - 52.0)
	drone.data.finish_health_ratio = 0.0
	check(drone._damage_stage == 0, "a fresh machine is undamaged")
	drone.hurtbox.receive(hit(1))
	check(drone._damage_stage == 1, "at about two thirds health the first damage state starts (%d)" % drone._damage_stage)
	drone.hurtbox.receive(hit(1))
	check(drone._damage_stage == 2, "at about one third health the second damage state starts (%d)" % drone._damage_stage)
	for i in 120:
		await physics_frames(1)
	check(not drone.is_dying(), "a damaged machine keeps working while smoking")
	var start_y := drone.position.y
	_kill_with(drone, true, 1.0)
	for i in 20:
		await physics_frames(1)
	check(absf(drone.rotation) > 1.0 and drone.position.y > start_y + 5.0, "a flying machine tumbles and falls when it is destroyed (%.1f rad, %.0f px)" % [drone.rotation, drone.position.y - start_y])
	var humanoid := _spawn_still_trooper(70.0)
	for i in 5:
		humanoid.hurtbox.receive(hit(1))
	check(humanoid._damage_stage == 0, "humanoids use armor shedding, not machine damage states")
	await end_level(level)


func _test_tentacle_wave_and_sever() -> void:
	await open_level(10.0)
	var control := ChainCreature.new()
	var target := ChainCreature.new()
	level.add_child(control)
	level.add_child(target)
	check(control.setup("test_creature") and target.setup("test_creature"), "the test creature loads")
	var dt := 1.0 / 60.0
	for i in 30:
		control.animate(dt, &"idle")
		target.animate(dt, &"idle")
	var mid := target.bone_count() / 2
	target.hit_wave(target.bone_of(2, mid).global_position, 1.0)
	for i in 4:
		control.animate(dt, &"idle")
		target.animate(dt, &"idle")
	var bend := absf(target.bone_of(2, mid).rotation - control.bone_of(2, mid).rotation)
	var other := absf(target.bone_of(0, mid).rotation - control.bone_of(0, mid).rotation)
	check(bend > 0.1, "a hit makes the struck tentacle whip near the hit (%.2f rad)" % bend)
	check(other < 0.01, "the other tentacles are not disturbed by the wave (%.3f rad)" % other)
	var tip_bend := 0.0
	for i in 14:  # 波往尖端傳：約 0.23 秒後尖端附近也在擺
		control.animate(dt, &"idle")
		target.animate(dt, &"idle")
		tip_bend = maxf(tip_bend, absf(target.bone_of(2, target.bone_count() - 2).rotation - control.bone_of(2, target.bone_count() - 2).rotation))
	check(tip_bend > 0.08, "the wave travels towards the tip (%.2f rad)" % tip_bend)
	for i in 80:
		control.animate(dt, &"idle")
		target.animate(dt, &"idle")
	check(absf(target.bone_of(2, mid).rotation - control.bone_of(2, mid).rotation) < 0.02, "the wave dies out")
	# 斷肢
	check(target.alive_tentacles() == 5, "five tentacles at the start")
	check(target.sever(2, Vector2.RIGHT) and target.alive_tentacles() == 4, "severing a tentacle removes exactly that one")
	check(not target.sever(2) and not target.sever(99) and not target.sever(-1), "severing twice or a missing tentacle does nothing")
	await physics_frames(3)
	check(level.find_children("*", "RigDebris", true, false).size() >= 1, "the severed tentacle flies off as a pooled piece")
	for i in 30:
		target.animate(dt, &"lash")
	check(target.alive_tentacles() == 4, "the creature keeps animating with a missing tentacle")
	control.queue_free()
	target.queue_free()
	await physics_frames(2)
	await end_level(level)
