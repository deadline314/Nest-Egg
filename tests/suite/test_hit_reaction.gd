class_name HitReactionSuite
extends EnemySuiteBase
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
