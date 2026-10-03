class_name ReconEnemiesSuite
extends EnemySuiteBase
## 偵察與狙擊型敵人（NE-46）：探照無人機（光束、警報、切電）與狙擊手（掃描、鎖定閃三下、開火、掩體）。
## 使用有掩體牆的測試場地（tests/fixtures/cover_map.json），敵人由測試直接生成。

const DRONE_PATH := "res://data/enemies/searchlight_drone.tres"
const SNIPER_PATH := "res://data/enemies/sniper.tres"


func run() -> void:
	_test_data()
	_test_level_placement()
	await _test_alert_rules()
	await _test_drone_detection()
	await _test_drone_alarm()
	await _test_drone_cover_and_power()
	await _test_sniper()
	await _test_sniper_dodge_and_cover()
	await _test_defeat_cards()
	await check_defeatable_on_every_difficulty([DRONE_PATH, SNIPER_PATH])


func _test_data() -> void:
	check_enemy_data([DRONE_PATH, SNIPER_PATH], [&"sniper_shot", &"sniper_contact", &"searchlight_contact"])
	var sniper := load(SNIPER_PATH) as EnemyData
	check(sniper.telegraph_time / float(Sniper.FLASHES) >= 0.15, "each sniper laser flash is long enough to see")
	check(sniper.projectile.speed > load(GRUNT_PATH).projectile.speed, "the sniper's shot is faster than a trooper's")


## 配置：第一章後半（欄 175 之後）與第二章夾層區（140～214）各有探照無人機與狙擊手，第一次遭遇的左邊有安全空間。
func _test_level_placement() -> void:
	check_level_placement({
		"res://data/levels/level_01.tres": [[&"searchlight_drone", 175, 350], [&"sniper", 175, 350]],
		"res://data/levels/level_02.tres": [[&"searchlight_drone", 140, 215], [&"sniper", 140, 215]],
	})


## 警報（Enemy.raise_alert）：偵測範圍變大、巡邏改往警報地點聚集、時間到恢復、死亡的敵人不受影響。
func _test_alert_rules() -> void:
	await open_level(10.0)
	var grunt := spawn(GRUNT_PATH, 70.0)
	# 距離 352 像素：超過保全的偵測範圍 260，戒備後的範圍 390 看得到。
	place_player(70.0 - 22.0)
	await physics_frames(5)
	check(not grunt._can_see_target(grunt.data.detect_range), "outside the detect range an enemy does not see the player")
	grunt.raise_alert(level.player.global_position, 3.0)
	check(grunt.is_alerted() and grunt._can_see_target(grunt.data.detect_range), "an alerted enemy sees farther")
	# 戒備中的巡邏會往警報地點走。
	grunt.set_physics_process(false)
	grunt._alert_point = Vector2(20 * 16.0, FLOOR_Y)
	grunt._patrol(grunt.data.move_speed)
	check(grunt.facing == -1 and grunt.velocity.x < -grunt.data.move_speed, "an alerted patrol heads for the alarm and walks faster")
	grunt.set_physics_process(true)
	grunt._alert_left = 0.05
	await physics_frames(10)
	check(not grunt.is_alerted(), "the alert wears off")
	grunt.raise_alert(Vector2.ZERO, 5.0)
	var lethal := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	lethal.bypass_guard = true
	grunt.hurtbox.receive(lethal)
	grunt._alert_left = 0.0
	grunt.raise_alert(Vector2.ZERO, 5.0)
	check(not grunt.is_alerted(), "a dying enemy cannot be alerted")
	await physics_frames(90)
	await end_level(level)


func _drone_in_open(player_tile := 30.0) -> SearchlightDrone:
	var drone := spawn(DRONE_PATH, player_tile, FLOOR_Y - 110.0) as SearchlightDrone
	place_player(player_tile)
	return drone


## 站在光束下：圓環填滿前有預兆（telegraph、嗶聲、圓環），離開光束圓環退回去。
func _test_drone_detection() -> void:
	await open_level(40.0)
	var drone := _drone_in_open(40.0)
	await physics_frames(20)
	check(drone.is_powered_on() and not drone.fsm.is_in(&"unpowered"), "the drone starts powered with its light on")
	check(drone._shaft != null and drone._shaft.intensity > 0.0, "the beam is visible while patrolling")
	# 光束掃過玩家頭頂（玩家站在巡邏範圍的正下方）：自然鎖定。
	var spotted := await wait_state(drone, &"spot", 60 * 20)
	check(spotted, "the drone spots a player standing in its beam")
	check(drone.is_telegraphing(), "being spotted shows the warning telegraph")
	var before := drone.charge()
	await physics_frames(10)
	check(drone.charge() > before or drone.fsm.is_in(&"alarm"), "the alarm ring fills while the player stays in the beam")
	# 躲開（離開光束）：圓環退回、回到巡邏。
	place_player(5.0)
	var recovered := await wait_state(drone, &"patrol", 60 * 4)
	check(recovered and drone.charge() < 0.2, "leaving the beam lets the ring drain and the drone goes back to patrol")
	await physics_frames(5)
	await end_level(level)


func _test_drone_alarm() -> void:
	await open_level(40.0)
	var drone := _drone_in_open(40.0)
	var near := spawn(GRUNT_PATH, 46.0)
	var far := spawn(GRUNT_PATH, 75.0)
	near.set_physics_process(false)
	far.set_physics_process(false)
	drone.fsm.transition(&"spot")
	var alarmed := await wait_state(drone, &"alarm", 60 * 4)
	check(alarmed, "staying in the beam long enough raises the alarm")
	check(near.is_alerted(), "an enemy inside the alarm radius is alerted")
	check(not far.is_alerted(), "an enemy outside the alarm radius is not")
	check(near._alert_left > 0.0 and absf(near._alert_point.x - level.player.global_position.x) < 80.0, "alerted enemies gather where the player is")
	# 警報後有冷卻：回到巡邏後，光束再照到也不會立刻再拉警報。
	var back := await wait_state(drone, &"patrol", 60 * 3)
	check(back, "the drone returns to patrol after the alarm")
	await physics_frames(60)
	check(not drone.fsm.is_in(&"spot") and drone._cooldown > 0.0, "the alarm has a cooldown")
	# 警報的時間走完戒備解除。
	near.set_physics_process(true)
	near._alert_left = 0.05
	await physics_frames(10)
	check(not near.is_alerted(), "alerted enemies calm down again")
	# 打掉無人機：光束熄滅、不再拉警報。
	var lethal := DamageInfo.create(99, Combat.Team.PLAYER, &"test")
	lethal.ignore_invulnerability = true
	drone.hurtbox.receive(lethal)
	await physics_frames(5)
	check(drone.is_dying() and drone._shaft.intensity == 0.0, "a destroyed drone's beam goes out")
	await physics_frames(90)
	await end_level(level)


func _test_drone_cover_and_power() -> void:
	await open_level(26.0)
	# 掩體：牆（欄 30～31，頂端 y = 208）擋住光束就照不到。
	var drone := spawn(DRONE_PATH, 36.0, FLOOR_Y - 100.0) as SearchlightDrone
	drone.set_physics_process(false)
	await physics_frames(3)
	var target := level.player.global_position + Vector2(0, -Enemy.TARGET_HEIGHT)
	drone._angle = (target - drone._beam_origin()).angle()
	check(not drone._player_in_beam(), "a wall between the drone and the player keeps the player out of the beam")
	place_player(36.0)
	await physics_frames(2)
	target = level.player.global_position + Vector2(0, -Enemy.TARGET_HEIGHT)
	drone._angle = (target - drone._beam_origin()).angle()
	check(drone._player_in_beam(), "the player in the open and aimed at is in the beam")
	drone._angle = PI * 0.5 + 1.2
	check(not drone._player_in_beam(), "the player outside the cone is not in the beam")
	drone.set_physics_process(true)
	# 切電：失去動力墜落、光束熄滅、接觸傷害停止；恢復後重新升空。
	var grid := level._power_grid
	grid.register_zone(&"recon_test", 0, 80)
	var home_y := drone._home.y
	grid.set_zone_powered(&"recon_test", false)
	var down := await wait_state(drone, &"unpowered", 60)
	check(down and not drone.is_powered_on(), "cutting the power takes the drone down")
	await physics_frames(100)
	check(drone.global_position.y > home_y + 40.0, "an unpowered drone falls toward the floor (%.0f -> %.0f)" % [home_y, drone.global_position.y])
	check(drone._shaft.intensity == 0.0 and not drone._pool.enabled, "an unpowered drone's beam and light are off")
	check(drone.contact != null and not drone.contact.active, "an unpowered drone no longer hurts on contact")
	grid.set_zone_powered(&"recon_test", true)
	var rebooted := await wait_state(drone, &"reboot", 60)
	check(rebooted, "restoring the power reboots the drone")
	var flying := await wait_state(drone, &"patrol", 60 * 4)
	check(flying and absf(drone.global_position.y - home_y) < 24.0 and drone.contact.active, "the drone rises back to its patrol height")
	await physics_frames(5)
	await end_level(level)


func _test_sniper() -> void:
	await open_level(10.0)
	var sniper := spawn(SNIPER_PATH, 25.0) as Sniper
	var player_before := level.player.health.current
	var swept := await wait_state(sniper, &"sweep", 60 * 3)
	check(swept, "the sniper starts sweeping its laser when it sees the player")
	check(sniper.laser_phase() > 0.0 and sniper.laser_phase() < 0.9, "the sweep laser is a thin warning line")
	var first_aim := sniper.aim_direction()
	var locked := await wait_state(sniper, &"lock", 60 * 4)
	check(locked, "the laser stops and locks after the sweep")
	check(sniper.is_telegraphing(), "the lock phase is a telegraph")
	var frozen := sniper.aim_direction()
	check(first_aim.distance_to(frozen) > 0.001, "the laser turned during the sweep")
	var max_flash := -1
	var on_seen := false
	var off_seen := false
	var shot := false
	for i in 120:
		await physics_frames(1)
		max_flash = maxi(max_flash, sniper._flash_index)
		if sniper.is_locked():
			check(sniper.aim_direction().is_equal_approx(frozen), "the locked laser does not move")
			on_seen = on_seen or sniper.laser_phase() > 0.9
			off_seen = off_seen or sniper.laser_phase() < 0.2
		if sniper.fsm.is_in(&"recover"):
			shot = true
			break
	check(shot, "the sniper fires after the lock phase")
	check(max_flash == Sniper.FLASHES - 1, "the laser flashes %d times before firing" % Sniper.FLASHES)
	check(on_seen and off_seen, "the laser blinks on and off while locked")
	# 站著不動會被打中。
	await physics_frames(60)
	check(level.player.health.current < player_before, "a player who stays on the line is hit")
	# 開槍後有收槍空檔，空檔後進入冷卻。
	var back := await wait_state(sniper, &"idle", 120)
	check(back, "the sniper lowers the rifle after the shot")
	check(sniper._cooldown > 0.0, "the sniper has a cooldown between shots")
	await end_level(level)


func _test_sniper_dodge_and_cover() -> void:
	# 閃避：鎖定後離開那條線就打不到。
	await open_level(10.0)
	var sniper := spawn(SNIPER_PATH, 25.0) as Sniper
	var player_before := level.player.health.current
	await wait_state(sniper, &"lock", 60 * 6)
	place_player(10.0, FLOOR_Y - 90.0)
	level.player.set_physics_process(false)
	await wait_state(sniper, &"recover", 120)
	await physics_frames(70)
	check(level.player.health.current == player_before, "leaving the locked line avoids the shot")
	level.player.set_physics_process(true)
	await end_level(level)
	# 掩體：牆擋住視線時狙擊手不會掃描。
	await open_level(26.0)
	sniper = spawn(SNIPER_PATH, 40.0) as Sniper
	var swept := false
	for i in 60 * 3:
		await physics_frames(1)
		swept = swept or sniper.fsm.is_in(&"sweep") or sniper.fsm.is_in(&"lock")
	check(not swept, "a sniper without a line of sight does not sweep")
	# 掃描途中失去視線：放棄並回到待命。
	place_player(36.0)
	var started := await wait_state(sniper, &"sweep", 60 * 3)
	check(started, "stepping out of cover gets the sniper's attention")
	place_player(26.0)
	var gave_up := await wait_state(sniper, &"idle", 60 * 2)
	check(gave_up, "ducking behind the wall during the sweep makes the sniper give up")
	await physics_frames(60)
	await end_level(level)


## 被每種敵人擊敗一次：死因對應的敗北圖鑑卡片會解鎖（狙擊手站在雷射線上、探照無人機直接撞上）。
func _test_defeat_cards() -> void:
	await open_level(10.0)
	level.player.health.setup(1, 0.0)
	var sniper := spawn(SNIPER_PATH, 25.0) as Sniper
	await expect_codex_unlock(&"sniper_shot", "the sniper's shot", 60 * 8)
	sniper.set_physics_process(false)
	await physics_frames(120)
	await end_level(level)
	await open_level(30.0)
	level.player.health.setup(1, 0.0)
	var drone := spawn(DRONE_PATH, 30.0, FLOOR_Y - 20.0)
	drone.set_physics_process(false)
	await expect_codex_unlock(&"searchlight_contact", "the drone's body", 120)
	await physics_frames(120)
	await end_level(level)
