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
