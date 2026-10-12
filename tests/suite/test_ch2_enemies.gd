class_name Chapter2EnemiesSuite
extends EnemySuiteBase
## 第二章（鷺）的戰鬥（NE-265、NE-266）：頭目阿勇與兩種市集新敵人（押運手、票據投手）。
## 阿勇：鐵棍蓄力重擊（預兆約 0.8 秒、撲空有反擊空檔）、慢速紙頁扇形、利息標記與結帳地墊、增援上限、
## 血量 25% 的安全暫停與兩條路（斷連：隔離箱 → 制伏；保留：真正倒下並復原一次 → 暫停閂 → 制伏）、死亡重試從正確的階段開始。
## 也驗證第二章遭遇的配置；共用框架新增欄位的讀取與防呆在 Chapter1EnemiesSuite。

const ESCORT_PATH := "res://data/enemies/ch2_escort.tres"
const THROWER_PATH := "res://data/enemies/ch2_bill_thrower.tres"
const YONG_PATH := "res://data/enemies/yong.tres"
const OFFICE_PATH := "res://data/levels/ch2_ledger_office.tres"
const DESIGN_PATH := "res://data/levels/ch2_design.json"
const YONG_TILE := 40.0
const FLAGS: Array[StringName] = [&"yong_link_choice", &"yong_link_isolated", &"yong_link_revoked", &"yong_revival_done", &"ch2_yong_subdued"]


func run() -> void:
	_test_data()
	await _test_slam()
	await _test_paper_fan()
	await _test_interest_mark()
	await _test_habits()
	await _test_summons()
	await _test_cut_route()
	await _test_keep_route()
	await _test_retry_stages()
	await _test_escort_dash()
	await _test_thrower_fan_and_bypass()
	await _test_office_glass()
	_test_encounters()
	await check_defeatable_on_every_difficulty([ESCORT_PATH, THROWER_PATH])


func _test_data() -> void:
	check_enemy_data([ESCORT_PATH, THROWER_PATH, YONG_PATH], [&"ch2_escort_contact", &"ch2_escort_baton", &"ch2_bill_thrower_contact", &"bill_paper",
			&"yong_contact", &"yong_baton", &"yong_jab", &"yong_paper"])
	BossPattern.clear_cache()
	var pattern := BossPattern.load_for(&"yong")
	check(pattern.errors.is_empty(), "yong's boss data loads without errors: %s" % [pattern.errors])
	for set_name in ["subdue", "subdue_revived", "disarmed", "disarmed_revived", "revived"]:
		check(pattern.phase_sets.has(set_name), "yong has the %s phase set" % set_name)
	check(str(pattern.phases[1]["event"]) == "choice" and is_equal_approx(float(pattern.phases[0]["until"]), 0.25), "yong's fight pauses for the choice at 25%")
	for index in GameState.difficulties.size():
		GameState.difficulty = GameState.difficulties[index]
		var slam := float(pattern.moves[&"slam"]["telegraph"]) * lerpf(1.0, GameState.difficulty.enemy_cooldown_multiplier, 0.5)
		check(slam >= 0.7 and slam <= 1.0, "the baton slam winds up for about 0.8 s on %s (%.2f s)" % [GameState.difficulty.id, slam])
	GameState.difficulty = GameState.difficulties[1]


func _reset_flags() -> void:
	for flag in FLAGS:
		GameState.set_flag(flag, false, false)
	GameState.set_flag(&"yong_link_choice", "unset", false)


func _spawn_yong(wake := true) -> PatternBoss:
	if GameState.get_flag(&"yong_link_choice") == null:
		_reset_flags()
	var yong := spawn(YONG_PATH, YONG_TILE) as PatternBoss
	await physics_frames(3)
	if wake and is_instance_valid(yong):
		yong.call(&"_wake")
		await wait_state(yong, &"idle", 120)
	return yong


func _force_move(boss: PatternBoss, id: StringName) -> void:
	boss.set("_move_id", id)
	boss.fsm.transition(&"windup")


func _test_slam() -> void:
	await open_level(YONG_TILE - 3.0)
	var yong := await _spawn_yong()
	yong.mark.stop()
	yong.global_position.x = YONG_TILE * 16.0
	place_player(YONG_TILE - 3.0)
	await physics_frames(2)
	var before := level.player.health.current
	_force_move(yong, &"slam")
	check(yong.telegraph_seconds(&"slam") >= 0.7, "the slam telegraph lasts about 0.8 s")
	await wait_state(yong, &"recover", 120)
	check(yong.last_slam_result() == &"hit" and before - level.player.health.current == 2, "a slam that lands deals 2 (%s, %d)" % [yong.last_slam_result(), before - level.player.health.current])
	await wait_state(yong, &"idle", 120)
	place_player(YONG_TILE - 12.0)
	await physics_frames(2)
	_force_move(yong, &"slam")
	await physics_frames(10)
	place_player(YONG_TILE - 14.0)  # 看到判定區後退開
	await wait_state(yong, &"recover", 120)
	check(yong.last_slam_result() == &"whiff" and yong.recover_left() >= 1.0, "a whiffed slam leaves a punish window of at least 1 s (%.2f s)" % yong.recover_left())
	await wait_state(yong, &"idle", 160)
	place_player(YONG_TILE - 3.0)
	_force_move(yong, &"slam")
	await physics_frames(20)
	yong.stun(0.3)  # 完美格擋讓攻擊者暈眩
	await physics_frames(1)
	check(yong.fsm.is_in(&"yanked"), "a perfect parry staggers yong out of the slam")
	await end_level(level)


func _test_paper_fan() -> void:
	await open_level(YONG_TILE - 12.0)
	var yong := await _spawn_yong()
	yong.mark.stop()
	_force_move(yong, &"paper_fan")
	await wait_state(yong, &"recover", 120)
	var sheets: Array[Projectile] = []
	for child: Node in ProjectilePool.container().get_children():
		var shot := child as Projectile
		if shot != null and shot.active and shot.spec.source_id == &"yong_paper":
			sheets.append(shot)
	check(sheets.size() == 5, "the paper fan throws five sheets (%d)" % sheets.size())
	if sheets.size() == 5:
		var slowest := INF
		for shot in sheets:
			slowest = minf(slowest, shot.velocity.length())
		check(slowest < 130.0, "the sheets are slow enough to read (%.0f px/s)" % slowest)
		var angles: Array[float] = []
		for shot in sheets:
			angles.append(shot.velocity.angle())
		angles.sort()
		check(angles[1] - angles[0] >= deg_to_rad(8.0), "there are gaps between the sheets to jump or crouch through")
	await end_level(level)


func _test_interest_mark() -> void:
	await open_level(YONG_TILE - 20.0)
	var yong := await _spawn_yong()
	yong.set_physics_process(false)
	var mark := yong.mark
	var player := level.player
	check(mark != null and mark.active and mark.pad_count() == 3, "yong's interest mark is active with three pads")
	for i in 3:
		_enemy_hit(player, 1)
	check(mark.stacks == 3 and is_equal_approx(player.hurtbox.damage_scale, 1.3), "each hit adds one interest stack, +10%% each (%d, %.2f)" % [mark.stacks, player.hurtbox.damage_scale])
	var before := player.health.current
	_enemy_hit(player, 2)
	check(before - player.health.current == 3, "the next hit is heavier with three stacks (2 -> %d)" % [before - player.health.current])
	for i in 4:
		_enemy_hit(player, 1)
	check(mark.stacks == 5, "interest stops at five stacks (%d)" % mark.stacks)
	await _wait_for_lit_pad(mark)
	var pad := mark.lit_pad()
	player.global_position = mark.pad_position(pad)
	player.velocity = Vector2.ZERO
	await physics_frames(6)
	check(mark.stacks == 0 and is_equal_approx(player.hurtbox.damage_scale, 1.0) and mark.lit_pad() != pad, "stepping on the lit pad clears interest and darkens that pad")
	_enemy_hit(player, 1)
	player.global_position.x = YONG_TILE * 16.0 - 300.0
	await physics_frames(int(6.2 * 60))
	check(mark.stacks == 0, "six seconds without being hit clears interest")
	await _wait_for_lit_pad(mark)
	var lit := mark.lit_pad()
	mark.boss_arrived(mark.pad_position(lit))
	check(mark.lit_pad() == -1, "when yong reaches the lit pad first it is used up")
	_enemy_hit(player, 1)
	mark.stop()
	check(is_equal_approx(player.hurtbox.damage_scale, 1.0), "stopping the mark restores the player's damage scale")
	await end_level(level)


func _wait_for_lit_pad(mark: BossMark) -> void:
	for i in 300:
		if mark.lit_pad() >= 0:
			return
		await physics_frames(1)


func _enemy_hit(player: Player, amount: int) -> void:
	var info := DamageInfo.create(amount, Combat.Team.ENEMY, &"yong_baton")
	info.ignore_invulnerability = true
	info.bypass_guard = true
	player.hurtbox.receive(info)


func _test_habits() -> void:
	await open_level(YONG_TILE - 20.0)
	var yong := await _spawn_yong()
	yong.set_physics_process(false)
	var mark := yong.mark
	var cases := [[YONG_TILE - 2.0, 0, &"slam"], [YONG_TILE - 16.0, 0, &"paper_fan"], [YONG_TILE - 2.0, 3, &"slam_combo"]]
	for entry: Array in cases:
		place_player(float(entry[0]))
		mark.set(&"stacks", int(entry[1]))
		await physics_frames(1)
		var counts := {}
		for i in 12:
			yong.set("_last_move", &"")
			var choice := yong.choose_move()
			counts[choice] = int(counts.get(choice, 0)) + 1
		check(counts.has(entry[2]), "player at tile %.0f with %d interest -> yong uses %s (%s)" % [entry[0], int(entry[1]), entry[2], counts])
	mark.set_physics_process(true)
	await _wait_for_lit_pad(mark)
	var pad := mark.pad_position(mark.lit_pad())
	if absf(pad.y - yong.global_position.y) < 24.0:
		mark.set(&"stacks", 2)
		level.player.global_position = pad + Vector2(-30.0, 0)
		yong.set("_last_move", &"")
		check(yong.choose_move() == &"rush_pad", "with interest and the lit pad close, yong rushes to stamp the pad first")
	mark.set(&"stacks", 0)
	await end_level(level)


func _test_summons() -> void:
	await open_level(YONG_TILE - 20.0)
	var yong := await _spawn_yong()
	yong.mark.stop()
	level.player.set_physics_process(false)
	var most := 0
	for i in 60 * 30:
		await physics_frames(1)
		most = maxi(most, yong.alive_summons())
		if yong.summoned_total() >= 2 and i > 60 * 22:
			break
	check(yong.summoned_total() == 2 and most <= 2, "phase one brings in at most two escorts (total %d, at once %d)" % [yong.summoned_total(), most])
	await end_level(level)


func _damage_to(boss: PatternBoss, hp: int) -> void:
	while boss.health.current > hp and not boss.is_dying():
		var before := boss.health.current
		boss.health.take_damage(hit(mini(4, boss.health.current - hp)))
		if boss.health.current == before:
			break
		await physics_frames(1)


func _test_cut_route() -> void:
	await open_level(YONG_TILE - 20.0)
	var yong := await _spawn_yong()
	var player := level.player
	await _damage_to(yong, 1)
	check(yong.health.current == ceili(yong.health.max_health * 0.25) and not yong.is_dying(), "yong cannot be pushed past 25%% before the choice (%d)" % yong.health.current)
	check(str(yong.get("stage")) == "parley" or yong.fsm.is_in(&"parley"), "at 25%% the fight pauses for the choice")
	for i in 240:
		if str(yong.get("stage")) == "cut_box":
			break
		await physics_frames(1)
	check(GameState.get_flag(&"yong_link_choice") == "cut" and str(yong.get("stage")) == "cut_box", "the default (skipped) choice goes down the cut route")
	var box := yong.call(&"isolation_box") as BossHoldPoint
	check(box != null and box.enabled, "the main isolation box can be operated after choosing cut")
	player.set_physics_process(false)
	player.global_position = box.global_position
	yong.set_physics_process(false)  # 只驗箱子的規則：按住期間不讓他出招（實戰裡他會用有預兆的重擊打斷你）
	Input.action_press(&"interact")
	await physics_frames(50)
	_enemy_hit(player, 1)
	await physics_frames(2)
	check(box.progress() < 0.1 and GameState.get_flag(&"yong_link_isolated") != true, "getting hit interrupts the box and nothing is written")
	await physics_frames(int(1.6 * 60))
	Input.action_release(&"interact")
	await physics_frames(2)
	check(GameState.get_flag(&"yong_link_isolated") == true and GameState.get_flag(&"yong_link_revoked") == true, "holding the box for 1.5 s permanently revokes the link")
	yong.set_physics_process(true)
	check(str(yong.get("stage")) == "subdue" and yong.has_tag("subdue") and yong.is_part_open(&"baton_lock"), "the health bar becomes subdue progress and the baton lock opens")
	check(GameState.get_flag(&"yong_revival_done") != true, "the cut route never revives yong")
	await _subdue_and_pull(yong, player)
	await end_level(level)


func _subdue_and_pull(yong: PatternBoss, player: Player) -> void:
	var lock: Hurtbox = null
	for part in yong.hurtbox.parts:
		if part.part_id == &"baton_lock":
			lock = part
	for i in 3:
		lock.receive(hit(1, true))
		await physics_frames(1)
	check(yong.call(&"is_disarmed") and yong.phase_set.begins_with("disarmed"), "breaking the baton lock three times disarms him (short punches)")
	await _damage_to(yong, 1)
	check(yong.health.current == 1 and not yong.is_dying(), "subdue progress empties without killing him")
	var cell := yong.call(&"power_cell") as BossHoldPoint
	var pulled := false
	for attempt in 6:
		await wait_state(yong, &"idle", 200)
		player.global_position = yong.global_position + Vector2(-90.0, 0)
		_force_move(yong, &"jab")
		await wait_state(yong, &"recover", 120)
		if not yong.call(&"can_pull_cell"):
			continue
		player.global_position = cell.global_position + Vector2(0, -cell.global_position.y + yong.global_position.y)
		Input.action_press(&"interact")
		await physics_frames(50)
		Input.action_release(&"interact")
		if yong.call(&"is_subdued"):
			pulled = true
			break
	check(pulled, "after a whiffed punch the power cell can be pulled to finish the subdue")
	check(not yong.is_dying() and yong.call(&"is_subdued"), "yong is subdued alive, not killed")


func _test_keep_route() -> void:
	await open_level(YONG_TILE - 20.0)
	_reset_flags()
	GameState.set_flag(&"yong_link_choice", "keep", false)
	var yong := await _spawn_yong()
	var player := level.player
	await _damage_to(yong, 1)
	for i in 400:
		if str(yong.get("stage")) == "revived":
			break
		await physics_frames(1)
	check(GameState.get_flag(&"yong_revival_done") == true and str(yong.get("stage")) == "revived", "the keep route: yong truly falls once and revives")
	check(yong.phase_set == "revived" and float(yong.current_phase()["speed"]) < 1.0 and int(yong.current_phase()["damage_bonus"]) >= 1,
			"phase two is slower and each hit is heavier")
	check(yong.health.current == ceili(yong.health.max_health * 0.6), "he comes back at 60%% (%d)" % yong.health.current)
	await _damage_to(yong, 1)
	for i in 400:
		if str(yong.get("stage")) == "subdue":
			break
		await physics_frames(1)
	check(GameState.get_flag(&"yong_link_isolated") == true and yong.phase_set == "subdue_revived", "egret's pause latch switches the bar to subdue progress")
	check(GameState.get_flag(&"yong_link_revoked") != true, "the keep route keeps the link eligibility")
	await _subdue_and_pull(yong, player)
	await end_level(level)


## 死亡重試：依旗標直接從正確的階段開始。
func _test_retry_stages() -> void:
	var hp := (load(YONG_PATH) as EnemyData).max_health
	var cases := [
		[{&"yong_link_choice": "cut"}, "cut_box", ceili(hp * 0.25)],
		[{&"yong_link_choice": "cut", &"yong_link_isolated": true}, "subdue", ceili(hp * 0.25)],
		[{&"yong_link_choice": "keep"}, "keep_first", ceili(hp * 0.25)],
		[{&"yong_link_choice": "keep", &"yong_revival_done": true}, "revived", ceili(hp * 0.6)],
		[{&"yong_link_choice": "keep", &"yong_revival_done": true, &"yong_link_isolated": true}, "subdue", ceili(hp * 0.35)],
	]
	for entry: Array in cases:
		await open_level(YONG_TILE - 20.0)
		_reset_flags()
		for flag: StringName in entry[0]:
			GameState.set_flag(flag, entry[0][flag], false)
		var yong := await _spawn_yong(false)
		check(str(yong.get("stage")) == entry[1] and yong.health.current == int(entry[2]), "retry with %s starts at %s with %d HP (got %s, %d)" % [entry[0], entry[1], entry[2], yong.get("stage"), yong.health.current])
		await end_level(level)
	await open_level(YONG_TILE - 20.0)
	_reset_flags()
	GameState.set_flag(&"ch2_yong_subdued", true, false)
	var gone := spawn(YONG_PATH, YONG_TILE)
	await physics_frames(3)
	check(not is_instance_valid(gone) or gone.is_queued_for_deletion(), "after the subdue yong does not appear again")
	await end_level(level)
	_reset_flags()


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


## 小薇的玻璃隔間：從戰區朝她射的子彈會先撞到玻璃。
func _test_office_glass() -> void:
	_reset_flags()
	var office := await start_level(load(OFFICE_PATH) as LevelData)
	await physics_frames(5)
	var xiaowei: Node2D = null
	for node in office.find_children("*", "NpcActor", true, false):
		var actor := node as NpcActor
		if actor.data != null and actor.data.resource_path.get_file().get_basename() == "ch2_xiaowei":
			xiaowei = actor
	check(xiaowei != null, "xiaowei is placed in the ledger office")
	if xiaowei != null:
		# 從戰區各處（地面、兩層平台、高處）朝她的頭與身體開槍：都在碰到她之前被玻璃或高臺擋下。
		var space := office.get_world_2d().direct_space_state
		var blocked := 0
		var total := 0
		for origin: Vector2 in [Vector2(30, 18), Vector2(48, 18), Vector2(24, 14), Vector2(46, 14), Vector2(54, 8), Vector2(40, 7)]:
			for height: float in [8.0, 20.0, 30.0]:
				var target := xiaowei.global_position + Vector2(0, -height)
				var query := PhysicsRayQueryParameters2D.create(origin * 16.0, target, Layers.WORLD)
				var hit := space.intersect_ray(query)
				total += 1
				if not hit.is_empty() and (hit["position"] as Vector2).x < target.x - 6.0:
					blocked += 1
		check(blocked == total, "shots from the arena toward xiaowei are stopped by the glass or her platform (%d/%d)" % [blocked, total])
		check(xiaowei.find_children("*", "Hurtbox", true, false).is_empty(), "xiaowei is not an attack target (no hurtbox)")
	var yong_found := false
	for node in office.get_tree().get_nodes_in_group(&"enemies"):
		if node is PatternBoss and (node as PatternBoss).data.id == &"yong":
			yong_found = true
	check(yong_found, "yong is placed in the ledger office")
	await end_level(office)


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
