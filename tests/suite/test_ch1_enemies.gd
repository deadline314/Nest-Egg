class_name Chapter1EnemiesSuite
extends EnemySuiteBase
## 第一章（傘）的敵人（ST-7）：清掃兵、收帳人（槍手、打手）與迷你頭目看門狗。
## 資料與圖鑑卡片、音效與特效檔、三種難度都能擊敗；看門狗不鎖場、血量保留、打倒後升起隔牆而不結束章節。

const SWEEPER_PATH := "res://data/enemies/sweeper.tres"
const GUNNER_PATH := "res://data/enemies/collector_gunner.tres"
const BRUTE_PATH := "res://data/enemies/collector_brute.tres"
const WATCHDOG_PATH := "res://data/enemies/watchdog.tres"
const INSPECTOR_PATH := "res://data/enemies/ch1_inspector.tres"
const ALL: Array[String] = [SWEEPER_PATH, GUNNER_PATH, BRUTE_PATH, WATCHDOG_PATH, INSPECTOR_PATH]


func run() -> void:
	_test_data()
	await _test_watchdog_flow()
	_test_watchdog_pattern_data()
	await _test_watchdog_habits()
	await _test_watchdog_leash_yank()
	await _test_watchdog_phases()
	await _test_watchdog_missiles_dodgeable()
	await _test_watchdog_melee_windows()
	await check_defeatable_on_every_difficulty(ALL)


func _test_data() -> void:
	check_enemy_data(ALL, [&"sweeper_shot", &"sweeper_contact", &"collector_shot", &"collector_gunner_contact", &"collector_brute_contact", &"watchdog_contact", &"ch1_inspector_contact"])
	for path in ALL:
		var data := load(path) as EnemyData
		check(CharacterSounds.name_for(data.id, &"death") != &"", "%s has a death sound through its profile" % data.id)
		check(ResourceLoader.exists(EnemyVfx.PATH % String(data.id)), "%s has its own effects file" % data.id)
		check(not data.is_boss, "%s is not a level-ending boss" % data.id)
	check(CharacterSounds.validate().is_empty(), "the character sound table is valid after adding the chapter 1 roster: %s" % [CharacterSounds.validate()])
	var watchdog := load(WATCHDOG_PATH) as EnemyData
	check(watchdog.persists_damage, "the watchdog keeps its wounds")
	check(watchdog.max_health < load("res://data/enemies/warden.tres").max_health, "the watchdog is weaker than the warden")
	for path in [SWEEPER_PATH, GUNNER_PATH, BRUTE_PATH]:
		check(not (load(path) as EnemyData).persists_damage, "an ordinary enemy does not keep its wounds: %s" % path)
	var sweeper := load(SWEEPER_PATH) as EnemyData
	var collector := load(GUNNER_PATH) as EnemyData
	check(collector.max_health > sweeper.max_health and collector.attack_cooldown >= sweeper.attack_cooldown, "the collector gunner is tougher and slower than a sweeper")


## 看門狗：睡到玩家靠近、不發出 boss_defeated、打倒後打開 watchdog_gate、受傷的血量可還原。
func _test_watchdog_flow() -> void:
	await open_level(8.0)
	level.player.health.setup(999, 0.0)
	var toggled: Array[StringName] = []
	var defeated: Array[bool] = []
	var on_toggle := func(channel: StringName, active: bool) -> void:
		if active:
			toggled.append(channel)
	var on_defeated := func() -> void: defeated.append(true)
	EventBus.mechanism_toggled.connect(on_toggle)
	EventBus.boss_defeated.connect(on_defeated)
	var dog := spawn(WATCHDOG_PATH, 70.0) as Enemy
	check(dog.fsm.is_in(&"dormant"), "the watchdog sleeps until the player comes close")
	dog.restore_lost_health(10)
	check(dog.health.current == dog.health.max_health - 10, "saved damage is restored (%d)" % dog.health.current)
	check(dog.lost_health() == 10, "lost health is reported for saving")
	dog.restore_lost_health(9999)
	check(dog.health.current == 1, "restored damage never kills it on arrival (%d)" % dog.health.current)
	place_player(58.0)
	for i in 120:
		await physics_frames(1)
		if not dog.fsm.is_in(&"dormant"):
			break
	check(not dog.fsm.is_in(&"dormant"), "it wakes when the player comes close")
	dog.hurtbox.receive(lethal())
	for i in 60 * 4:
		await physics_frames(1)
		if not is_instance_valid(dog) or dog.is_queued_for_deletion():
			break
	await physics_frames(2)
	check(toggled.has(&"watchdog_gate"), "defeating it raises the bulkhead %s" % [toggled])
	check(not toggled.has(&"custodian_gate"), "it does not touch the chapter 2 gate")
	check(defeated.is_empty(), "defeating the watchdog does not end the level")
	EventBus.mechanism_toggled.disconnect(on_toggle)
	EventBus.boss_defeated.disconnect(on_defeated)
	await end_level(level)


# ---------------------------------------------------------------------------
# 看門狗的打法（NE-253）：資料、攻擊習慣、鍊子與背部電源、階段、死後保留、預兆可躲
# ---------------------------------------------------------------------------

const DOG_TILE := 52.0
const PISTOL_SHOT := "res://data/projectiles/pistol_shot.tres"


func _test_watchdog_pattern_data() -> void:
	var pattern := BossPattern.load_for(&"watchdog")
	check(pattern.errors.is_empty(), "the watchdog pattern loads cleanly: %s" % [pattern.errors])
	check(pattern.phases.size() >= 3, "the watchdog has three phases")
	var kinds := {}
	for id: StringName in pattern.moves:
		kinds[pattern.moves[id]["kind"]] = true
	check(kinds.size() >= 4, "the watchdog mixes at least four kinds of attack: %s" % [kinds.keys()])
	for i in pattern.phases.size():
		var phase_kinds := {}
		for id: StringName in pattern.phases[i]["moves"]:
			phase_kinds[pattern.moves[id]["kind"]] = true
		check(phase_kinds.size() >= 3, "phase %d offers three different kinds of attack" % [i + 1])
	check(pattern.leash_length > 0.0 and pattern.gate_channel == &"watchdog_gate", "the watchdog is chained and opens its gate")
	# 動作是看門狗自己的：引用的每個姿勢都是四足零件外觀（art/creatures/watchdog.json）裡的狀態。
	var states: Dictionary = RigLibrary.load_json(PartCreature.PATH % "watchdog").get("states", {})
	var poses: Array = pattern.state_poses.values()
	for id: StringName in pattern.moves:
		for key in ["pose_windup", "pose_act"]:
			if pattern.moves[id][key] != &"":
				poses.append(pattern.moves[id][key])
	for pose: StringName in poses:
		check(states.has(String(pose)), "watchdog pose %s is one of its own creature states" % pose)
	# 損毀的資料：記錄位置並退回安全預設，不崩潰。
	var broken := BossPattern.parse({"moves": {"x": {"kind": "teleport"}}, "phases": [{"moves": ["missing"]}], "parts": {"a": {"open": "sometimes"}}}, "test://broken", true)
	check(broken.errors.size() >= 3 and broken.errors[0].contains("test://broken"), "broken boss data reports where it failed: %s" % [broken.errors])
	check(broken.moves.has(BossPattern.FALLBACK_MOVE) and not (broken.phases[0]["moves"] as Array).is_empty(), "broken boss data falls back to a safe burst")


func _spawn_dog() -> PatternBoss:
	var dog := spawn(WATCHDOG_PATH, DOG_TILE) as PatternBoss
	await physics_frames(2)
	dog.call(&"_wake")
	return dog


## 攻擊習慣：太近就吠、地盤裡撲咬、地盤外開槍（第二階段改叫飛彈）；每種難度的預兆都至少 0.5 秒。
func _test_watchdog_habits() -> void:
	await open_level(DOG_TILE - 20.0)
	var dog := await _spawn_dog()
	dog.set_physics_process(false)
	var cases := [[DOG_TILE + 2.0, 0, &"bark"], [DOG_TILE + 7.0, 0, &"lunge"], [DOG_TILE + 18.0, 0, &"burst"], [DOG_TILE + 18.0, 1, &"missiles"]]
	for entry: Array in cases:
		dog.call(&"_apply_phase", int(entry[1]), false)
		place_player(float(entry[0]))
		await physics_frames(1)
		dog.set("_last_move", &"")
		dog.set("_yanked_recently", false)
		var choice := dog.choose_move()
		check(choice == entry[2], "player at tile %.0f in phase %d -> the watchdog uses %s (got %s)" % [entry[0], int(entry[1]) + 1, entry[2], choice])
	for index in GameState.difficulties.size():
		GameState.difficulty = GameState.difficulties[index]
		for phase in dog.pattern.phases.size():
			dog.call(&"_apply_phase", phase, false)
			for id: StringName in dog.pattern.moves:
				check(dog.telegraph_seconds(id) >= 0.5, "%s telegraph on %s phase %d is readable (%.2f s)" % [id, GameState.difficulty.id, phase + 1, dog.telegraph_seconds(id)])
	GameState.difficulty = GameState.difficulties[1]
	await end_level(level)


## 鍊子：玩家站在鍊子盡頭外，撲咬停在盡頭、被扯回並硬直；背部電源只在硬直時打開，打中算 2.5 倍弱點；之後先換招。
func _test_watchdog_leash_yank() -> void:
	await open_level(DOG_TILE - 20.0)
	var dog := await _spawn_dog()
	await wait_state(dog, &"idle", 120)
	# 玩家站在黃黑線內側一點：撲咬的終點（玩家再往前一點）越過鍊子盡頭。
	var reach := dog.anchor().x + dog.pattern.leash_length
	dog.global_position.x = reach - 110.0
	place_player((reach - 8.0) / 16.0)
	level.player.set_physics_process(false)
	var hurt: Array = []
	var on_hurt := func(info: DamageInfo) -> void: hurt.append(info.source_id)
	level.player.health.damaged.connect(on_hurt)
	var back: Hurtbox = null
	for part in dog.hurtbox.parts:
		if part.part_id == &"back_power":
			back = part
	check(back != null and not back.enabled, "the back power source is closed while the watchdog stands")
	dog.set("_move_id", &"lunge")
	dog.fsm.transition(&"windup")
	var yanked := await wait_state(dog, &"yanked", 150)
	check(yanked, "a lunge that hits the end of the chain yanks the watchdog back")
	check(dog.global_position.x <= reach + 4.0, "the lunge stops at the chain's end (%.0f <= %.0f)" % [dog.global_position.x, reach])
	check(hurt.is_empty() or not hurt.has(&"watchdog_contact") or level.player.global_position.x <= reach + 8.0, "the lunge never passes the chain's end: %s" % [hurt])
	await physics_frames(2)
	check(back.enabled, "the back power source opens while it is yanked")
	var aim := back.center()
	var hits: Array = []
	var record := func(info: DamageInfo) -> void: hits.append([info.part, info.amount, info.weak_hit])
	dog.health.damaged.connect(record)
	# 玩家站在牠前方的地上：子彈從低處斜向上、從頭底下穿過，射向發橙光的背部電源（槍臂硬直時垂下，不擋）。
	var front := float(dog.facing)
	# 被扯回時牠還在往後滑：子彈飛行的這幾格先停住牠，量的是命中位置，不是追不追得上。
	var origin := aim + Vector2(front * 70.0, 24.0)
	dog.set_physics_process(false)
	ProjectilePool.spawn(load(PISTOL_SHOT) as ProjectileSpec, origin, (aim - origin).normalized(), Combat.Team.PLAYER)
	await physics_frames(12)
	dog.set_physics_process(true)
	dog.health.damaged.disconnect(record)
	var base := roundi((load(PISTOL_SHOT) as ProjectileSpec).damage)
	check(hits.size() == 1 and hits[0][0] == &"back_power" and hits[0][2] and hits[0][1] == roundi(base * 2.0), "the exposed back takes a 2x weak hit: %s" % [hits])
	var recovered := await wait_state(dog, &"idle", 150)
	await physics_frames(2)
	check(recovered and not back.enabled, "the back closes again once it recovers")
	var gap_before := absf(dog.global_position.x - dog.anchor().x)
	await physics_frames(30)
	check(dog.fsm.is_in(&"idle") and absf(dog.global_position.x - dog.anchor().x) < gap_before - 4.0, "after a yank it backs off toward its kennel before attacking again")
	place_player((reach - 8.0) / 16.0)
	dog.set("_last_move", &"")
	var after := dog.choose_move()
	check(dog.pattern.habits["after_yank"].has(after), "after being yanked it switches to another attack first (%s)" % after)
	level.player.health.damaged.disconnect(on_hurt)
	level.player.set_physics_process(true)
	await end_level(level)


## 階段：60% 槍臂壞（不再點射、槍臂判定消失）、30% 鍊斷（不再受鍊子限制，連撲撲完會失衡）。
## 死後回來（持久世界還原損血）時直接套用到對應階段，不重播演出。
func _test_watchdog_phases() -> void:
	await open_level(DOG_TILE - 20.0)
	var dog := await _spawn_dog()
	await wait_state(dog, &"idle", 120)
	var gun: Hurtbox = null
	for part in dog.hurtbox.parts:
		if part.part_id == &"gun_arm":
			gun = part
	check(gun != null and gun.enabled and dog.is_leashed(), "phase one: gun arm is a target and the chain holds")
	dog.hurtbox.receive(hit(int(dog.health.max_health * 0.45), true))
	await physics_frames(2)
	check(dog.phase == 1 and dog.fsm.is_in(&"phase_shift"), "losing 45%% health breaks the gun arm with a pause (phase %d, %s)" % [dog.phase + 1, dog.fsm.current])
	check(not gun.enabled and not (dog.current_phase()["moves"] as Array).has(&"burst"), "the broken gun arm stops the burst")
	await physics_frames(2)
	var turret := dog.creature.joint_of("turret") if dog.creature != null else null
	check(turret != null and not turret.visible, "the broken turret is gone from its back, not just switched off")
	check(dog.current_phase()["armored"] and dog.is_leashed(), "phase two keeps the armour and the chain")
	dog.hurtbox.receive(hit(int(dog.health.max_health * 0.3), true))
	await physics_frames(2)
	check(dog.phase == 2 and not dog.is_leashed() and dog.current_phase()["armored"], "below 30% the chain snaps; the armour still deflects body shots")
	await wait_state(dog, &"idle", 120)
	# 第三階段：連撲撲完會失衡，背部電源打開。
	place_player(dog.global_position.x / 16.0 + 6.0)
	dog.set("_move_id", &"lunge_twice")
	dog.fsm.transition(&"windup")
	var staggered := await wait_state(dog, &"yanked", 180)
	await physics_frames(1)
	check(staggered and dog.is_part_open(&"back_power"), "the unchained double lunge over-extends and opens the back")
	dog.queue_free()
	place_player(DOG_TILE - 30.0)
	await physics_frames(2)
	var revived := spawn(WATCHDOG_PATH, DOG_TILE) as PatternBoss
	await physics_frames(2)
	revived.restore_lost_health(int(revived.health.max_health * 0.75))
	await physics_frames(1)
	check(revived.phase == 2 and revived.fsm.is_in(&"dormant") and not revived.is_leashed(), "coming back after a death keeps the snapped chain without replaying the shift (phase %d, %s)" % [revived.phase + 1, revived.fsm.current])
	await end_level(level)


## 標記轟炸：落點在預兆開始時決定、不追蹤；離開紅圈就不會受傷，留在圈裡會被炸到。
func _test_watchdog_missiles_dodgeable() -> void:
	for stay: bool in [false, true]:
		await open_level(DOG_TILE - 20.0)
		var dog := await _spawn_dog()
		await wait_state(dog, &"idle", 120)
		dog.call(&"_apply_phase", 1, false)
		place_player(DOG_TILE + 16.0)
		level.player.set_physics_process(false)
		var hurt: Array = []
		var on_hurt := func(info: DamageInfo) -> void: hurt.append(info.source_id)
		level.player.health.damaged.connect(on_hurt)
		dog.set("_move_id", &"missiles")
		dog.fsm.transition(&"windup")
		await physics_frames(3)
		if not stay:
			place_player(DOG_TILE + 24.0)
		await wait_state(dog, &"recover", 120)
		await physics_frames(6)
		level.player.health.damaged.disconnect(on_hurt)
		if stay:
			check(hurt.has(&"watchdog_missile"), "staying in the red circle gets hit: %s" % [hurt])
		else:
			check(hurt.is_empty(), "leaving the red circles avoids every missile: %s" % [hurt])
		level.player.set_physics_process(true)
		await end_level(level)


## 近戰（頭目反制）：平常身體裝甲擋下近戰；被扯回背部打開時，繞到牠背後近戰，打得到背部電源（弱點、兩倍）。
## 牠是四足機械犬，背部電源在後半身的背上：近戰要繞到背後；子彈從正面低處斜射、從頭底下穿過也打得到。
## 用手把右搖桿瞄準（無頭環境讀不到滑鼠）。
func _test_watchdog_melee_windows() -> void:
	await open_level(DOG_TILE - 20.0)
	var dog := await _spawn_dog()
	await wait_state(dog, &"idle", 120)
	dog.set_physics_process(false)
	var player := level.player
	AimInput.set_virtual_gamepad(player, true)
	var hits: Array = []
	var blocked: Array = []
	var record := func(info: DamageInfo) -> void: hits.append([info.part, info.amount, info.weak_hit])
	var on_block := func(_info: DamageInfo) -> void: blocked.append(true)
	dog.health.damaged.connect(record)
	dog.hurtbox.hit_blocked.connect(on_block)
	var melee_damage := int(MeleeData.default_set().attack(str(MeleeData.default_set().combo()[0]))["damage"])
	for side: float in [-1.0, 1.0]:
		var toward := &"aim_right" if side < 0.0 else &"aim_left"
		Input.action_press(toward)
		hits.clear()
		blocked.clear()
		player.global_position = dog.global_position + Vector2(side * 24.0, 0.0)
		player.velocity = Vector2.ZERO
		await physics_frames(25)
		player._try_melee()
		await physics_frames(30)
		check(hits.is_empty() and not blocked.is_empty(), "melee on the armoured watchdog is blocked, not damage (side %d): %s" % [int(side), hits])
		dog.call(&"_yanked_enter")
		# 繞到背後（牠面向的另一側）。
		var behind := -float(dog.facing)
		Input.action_release(toward)
		toward = &"aim_left" if behind > 0.0 else &"aim_right"
		Input.action_press(toward)
		player.global_position = dog.global_position + Vector2(behind * 24.0, 0.0)
		player.velocity = Vector2.ZERO
		await physics_frames(25)
		hits.clear()
		player._try_melee()
		await physics_frames(30)
		check(hits.size() == 1 and hits[0][0] == &"back_power" and hits[0][2] and hits[0][1] == maxi(1, roundi(melee_damage * 2.0)),
				"with the back open, a melee from behind strikes the back power as a weak hit (round %d): %s" % [int(side), hits])
		dog.call(&"_yanked_exit")
		dog.health.setup(dog.data.max_health, 0.0)
		Input.action_release(toward)
		await physics_frames(40)
	AimInput.set_virtual_gamepad(player, false)
	dog.health.damaged.disconnect(record)
	dog.hurtbox.hit_blocked.disconnect(on_block)
	await end_level(level)
