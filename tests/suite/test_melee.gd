class_name MeleeSuite
extends EnemySuiteBase
## 近戰三段（NE-142）：資料定義前搖、出招、收招、前衝與取消窗口；揮空吃滿收招、命中可提早取消；
## 一揮對同一目標只命中一次；輸入緩衝接續連段（輕、輕、重）；重斬比輕斬重；資料壞掉時退回預設不崩潰。

const DT := 1.0 / 60.0


func run() -> void:
	_test_data()
	await _test_phases_and_single_hit()
	await _test_whiff_recovers_fully()
	await _test_hit_cancel_and_combo()
	await _test_dash_lock()
	_test_bad_data()


func _test_data() -> void:
	var errors: PackedStringArray = MeleeData.validate()
	check(errors.is_empty(), "melee data has no errors: %s" % ", ".join(errors))
	var combo := MeleeData.combo()
	check(combo.size() >= 3, "combo has light, light and heavy")
	var light := MeleeData.attack(str(combo[0]))
	var heavy := MeleeData.attack(str(combo[combo.size() - 1]))
	check(int(heavy["damage"]) > int(light["damage"]) and float(heavy["windup"]) > float(light["windup"]) and float(heavy["recovery"]) > float(light["recovery"]) and float(heavy["advance"]) > float(light["advance"]), "heavy slash is clearly heavier than a light one")
	check(float(light["cancel_after"]) < float(light["recovery"]), "a hit can cancel earlier than a whiff recovers")


func _target_at(offset_px: float) -> Enemy:  # 呼叫端要 await（等物理空間收錄）
	var enemy := spawn(GRUNT_PATH, 10.0)
	enemy.position = Vector2(level.player.global_position.x + offset_px, FLOOR_Y)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.health.setup(999, 0.0)
	await physics_frames(3)
	return enemy


func _frames_until(player: Player, phase: int, limit := 120) -> int:
	var frames := 0
	while player._melee_phase != phase and frames < limit:
		await physics_frames(1)
		frames += 1
	return frames


func _test_phases_and_single_hit() -> void:
	await open_level(10.0)
	var player := level.player
	player.facing = -1
	var enemy := await _target_at(-16.0)
	var before := enemy.health.current
	check(player._try_melee(), "the melee key starts an attack")
	check(player._melee_phase == Player.MeleePhase.WINDUP and enemy.health.current == before, "the wind-up deals no damage yet")
	await _frames_until(player, Player.MeleePhase.ACTIVE)
	await physics_frames(1)
	check(enemy.health.current == before - int(player._melee_attack["damage"]), "damage lands once the swing becomes active")
	await physics_frames(6)
	check(enemy.health.current == before - int(MeleeData.attack(str(MeleeData.combo()[0]))["damage"]), "one swing hits the same target only once")
	await physics_frames(3)
	await end_level(level)


func _test_whiff_recovers_fully() -> void:
	await open_level(10.0)
	var player := level.player
	player.facing = -1
	player._try_melee()
	var attack: Dictionary = player._melee_attack
	var started := 0
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	check(not player._melee_landed and not player.is_melee_cancellable(), "a whiff cannot be cancelled right after the swing")
	var frames := 0
	while player._melee_phase != Player.MeleePhase.NONE and frames < 120:
		await physics_frames(1)
		frames += 1
	check(frames >= int(float(attack["recovery"]) * 60.0) - 2, "a whiff takes the full recovery (%d frames)" % frames)
	await physics_frames(3)
	await end_level(level)


func _test_hit_cancel_and_combo() -> void:
	await open_level(10.0)
	var player := level.player
	player.facing = -1
	var enemy := await _target_at(-16.0)
	player._try_melee()
	player._try_melee()  # 出招期間再按：緩衝
	check(player._melee_buffer_left > 0.0, "pressing during the swing is buffered")
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	check(player._melee_landed, "the first swing connected")
	var cancel_frames := 0
	while player._melee_index == 0 and cancel_frames < 60:
		await physics_frames(1)
		cancel_frames += 1
	var first: Dictionary = MeleeData.attack(str(MeleeData.combo()[0]))
	check(player._melee_index == 1, "the buffered press chains into the second swing")
	check(cancel_frames <= int(float(first["recovery"]) * 60.0) - 3, "a hit cancels the recovery early (%d frames of %d)" % [cancel_frames, int(float(first["recovery"]) * 60.0)])
	# 第三段是重斬。
	player._try_melee()
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	var guard := 0
	while player._melee_index == 1 and guard < 60:
		await physics_frames(1)
		guard += 1
	check(player._melee_index == 2 and int(player._melee_attack["damage"]) == int(MeleeData.attack("heavy")["damage"]), "the third swing of the combo is the heavy slash")
	# 連段視窗過了就回到第一招。
	player._end_melee()
	await physics_frames(int(MeleeData.combo_window() * 60.0) + 10)
	player._try_melee()
	check(player._melee_index == 0, "the combo restarts after the window closes")
	enemy.queue_free()
	await physics_frames(3)
	await end_level(level)


func _test_dash_lock() -> void:
	await open_level(10.0)
	var player := level.player
	player.facing = -1
	player._try_melee()
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	check(player.is_melee_locked(), "a whiff recovery blocks dashing")
	player._try_dash(1.0)
	check(player.state != Player.State.DASH, "dash is refused while the recovery is locked")
	await physics_frames(40)
	check(player._melee_phase == Player.MeleePhase.NONE and not player.is_melee_locked(), "the lock ends with the recovery")
	await physics_frames(3)
	await end_level(level)


func _test_bad_data() -> void:
	var fallback := MeleeData.attack("test_no_such_attack")
	check(float(fallback["windup"]) > 0.0 and int(fallback["damage"]) > 0, "an unknown attack falls back to safe defaults")
