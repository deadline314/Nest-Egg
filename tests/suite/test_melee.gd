class_name MeleeSuite
extends EnemySuiteBase
## 近戰三段（NE-142）：資料定義前搖、出招、收招、前衝與取消窗口；揮空吃滿收招、命中可提早取消；
## 一揮對同一目標只命中一次；輸入緩衝接續連段（輕、輕、重）；重斬比輕斬重；資料壞掉時退回預設不崩潰。

const DT := 1.0 / 60.0


func run() -> void:
	_test_data()
	await _test_phases_and_single_hit()
	await _test_whiff_recovers_fully()
	await _test_expired_early_command()
	await _test_hit_cancel_and_combo()
	await _test_dash_lock()
	await _test_trails()
	_test_bad_data()
	_test_module_format()
	await _test_data_only_weapon()
	await _test_weapon_holds()
	await _test_input_parity()
	await preload("res://tests/helpers/melee_trigger_edge_checks.gd").run(self)
	await _test_visual_reach()


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
	# 使用實際瞄準輸入，避免前一套件留下的手把方向在物理影格覆蓋 facing。
	AimInput.using_gamepad = true
	Input.action_press(&"aim_left" if offset_px < 0.0 else &"aim_right")
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


func _test_expired_early_command() -> void:
	await open_level(10.0)
	var player := level.player
	# 用真長起手武器確保期限先到；快速頭招在正常速度下可能合法接續。
	player.loadout.reset(load("res://data/weapons/melee/melee_maul.tres") as WeaponData)
	var enemy := await _target_at(-16.0)
	check(player._try_melee() and player._try_melee(), "an early windup press queues one real command")
	var damage := int(player._melee_attack["damage"])
	check(float(player._melee_attack["windup"]) > MeleeData.buffer_time(), "the real long windup outlasts the command without changing timing data")
	var deadline := player._melee_commands._deadline_ms
	var observed_hitstop := false
	var auto_chained := false
	var guard := 180
	while player._melee_phase != Player.MeleePhase.NONE and guard > 0:
		observed_hitstop = observed_hitstop or Fx._frozen.has(player)
		auto_chained = auto_chained or player._melee_index > 0
		await physics_frames(1)
		guard -= 1
	check(guard > 0, "the expired-command swing naturally finishes within its physics guard")
	check(observed_hitstop and enemy.health.current == 999 - damage, "the early-command regression includes one real hit and natural local hitstop")
	check(player._melee_commands.remaining() == 0.0 and player._melee_commands._deadline_ms == deadline, "the old command really expires without extending its deadline through hitstop")
	check(not auto_chained, "an early command that expires before cancellation cannot automatically advance the combo")
	_combo_trace("expired-early-command", player, enemy)
	await _frames_until(player, Player.MeleePhase.NONE)
	await physics_frames(3)
	await end_level(level)


func _test_hit_cancel_and_combo() -> void:
	await open_level(10.0)
	# 擷取分支讓正式章節卡自然淡出，避免文字遮住原生動作；一般測試不等。
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--melee-evidence-out="):
			await runner.get_tree().create_timer(4.2, true, false, true).timeout
	var player := level.player
	player.facing = -1
	var enemy := await _target_at(-16.0)
	check(player._try_melee(), "the first combo swing starts")
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	check(player._melee_landed, "the first swing connected")
	check(player.facing == -1 and player._melee_swing_direction == Vector2.LEFT, "the fixture keeps actual aim and locked swing direction toward the target")
	check(not player.is_melee_cancellable(), "the fresh recovery press precedes the paid cancel window")
	# 期限按實際時間走；起手同格點兩次會在低 render rate 的真 hitstop 後過期。
	# 有效接續在收招初期點按，不延長 buffer、不跳過 hitstop 或取消成本。
	check(player._try_melee(), "the fresh recovery command is accepted")
	check(player._melee_buffer_left > 0.0, "pressing during the swing is buffered")
	_combo_trace("fresh-first-recovery-command", player, enemy)
	var cancel_frames := 0
	while player._melee_index == 0 and cancel_frames < 60:
		await physics_frames(1)
		cancel_frames += 1
	_combo_trace("second-observation", player, enemy)
	var first: Dictionary = MeleeData.attack(str(MeleeData.combo()[0]))
	check(player._melee_index == 1, "the buffered press chains into the second swing")
	check(cancel_frames <= int(float(first["recovery"]) * 60.0) - 3, "a hit cancels the recovery early (%d frames of %d)" % [cancel_frames, int(float(first["recovery"]) * 60.0)])
	# 第三段仍用真有效期限；第二招若揮空，保留完整收招成本。
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	check(player._try_melee(), "the third command is buffered during the second recovery")
	_combo_trace("fresh-second-recovery-command", player, enemy)
	var guard := 0
	while player._melee_index == 1 and guard < 60:
		await physics_frames(1)
		guard += 1
	check(player._melee_index == 2 and int(player._melee_attack["damage"]) == int(MeleeData.attack("heavy")["damage"]), "the third swing of the combo is the heavy slash")
	_combo_trace("third-observation", player, enemy)
	await _capture_combo(player)
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


func _test_trails() -> void:
	await open_level(10.0)
	var player := level.player
	var visual: PlayerVisual = player._visual
	var trail: Dictionary = MeleeData.attack("heavy")["trail"]
	check(float(trail["life"]) >= MeleeData.TRAIL_LIFE_RANGE.x - 0.0001 and float(trail["life"]) <= MeleeData.TRAIL_LIFE_RANGE.y + 0.0001, "trail lasts 80 to 120 ms")
	check(float(trail["brightness"]) <= MeleeData.TRAIL_BRIGHTNESS_MAX, "trail brightness stays under the cap")
	for i in 5:
		visual.notify_melee_swing(trail, 1)
	check(visual._trails.size() <= MeleeData.MAX_TRAILS, "at most two trails at once (%d)" % visual._trails.size())
	await physics_frames(3)
	var life_frames := int(float(trail["life"]) * 60.0) + 12
	for i in life_frames:
		await frames(1)
	check(visual._trails.is_empty(), "trails disappear after their life")
	# 超過亮度上限的資料在檢查時被指出（過曝防護）。
	var bad := MeleeData.attack("light_1").duplicate(true)
	check(float((bad["trail"] as Dictionary)["brightness"]) <= MeleeData.TRAIL_BRIGHTNESS_MAX, "default trail is under the brightness cap")
	await physics_frames(3)
	await end_level(level)


func _combo_trace(label: String, player: Player, enemy: Enemy) -> void:
	print("MELEE_COMBO_TRACE ", JSON.stringify({"label":label,"wall_ms":Time.get_ticks_msec(),
		"phase":player._melee_phase,"phase_time":player._melee_time,"index":player._melee_index,
		"remaining":player._melee_commands.remaining(),"deadline_ms":player._melee_commands._deadline_ms,
		"frozen":Fx._frozen.has(player),"landed":player._melee_landed,"facing":player.facing,
		"aim": [player.aim_dir.x,player.aim_dir.y],"target_hp":enemy.health.current,
		"target_offset":[enemy.global_position.x-player.global_position.x,enemy.global_position.y-player.global_position.y]}))


## 可選真 Forward+ 證據；一般 headless suite 不擷取、不改鏡頭。
func _capture_combo(player: Player) -> void:
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--melee-evidence-out="):
			out = argument.trim_prefix("--melee-evidence-out=")
	if out.is_empty():
		return
	check(out.is_absolute_path() and RenderingServer.get_current_rendering_method() == "forward_plus", "combo evidence uses an absolute destination and actual Forward+ renderer")
	if not out.is_absolute_path():
		return
	DirAccess.make_dir_recursive_absolute(out)
	var camera := runner.get_viewport().get_camera_2d()
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE * 3.4
	camera.global_position = player.global_position + Vector2(-25.0, -42.0)
	await _frames_until(player, Player.MeleePhase.ACTIVE)
	await RenderingServer.frame_post_draw
	var image := preload("res://tools/viewport_capture.gd").image(runner.get_viewport())
	check(image.save_png(out.path_join("NE-237-default-combo-natural.png")) == OK, "the natural third combo frame is saved at native viewport resolution")
	print("MELEE_COMBO_RENDER ", JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"width":image.get_width(),"height":image.get_height(),
		"phase":player._melee_phase,"index":player._melee_index,"pose_t":player.melee_pose_progress(),"zoom":camera.zoom.x}))


# ---------------------------------------------------------------------------
# 近戰模組（NE-277）：完整招式格式、資料檢查、多段判定、按住招式，以及「只加資料就能新增一把武器」。
# ---------------------------------------------------------------------------

const TEST_WEAPON_PROFILE := "test_spear"
const TEST_WEAPON_DATA := "res://tests/fixtures/melee/test_spear.json"
const HOLD_WEAPONS := {"melee_blade": 30.0, "melee_dagger": 16.0, "melee_glaive": 46.0, "melee_maul": 26.0, "melee_whip": 64.0}


func _test_module_format() -> void:
	var move := {"windup": 0.1, "active": 0.1, "recovery": 0.3, "damage": 2, "range": 30, "stagger": 2, "pose": "slash",
			"follow": 0.1, "hits": [{"at": 0.0, "length": 0.1}], "body": {"step": 2}, "grip": {"hands": 1}, "feedback": {"reaction": "light"}}
	var missing := MeleeMove.completeness_problems(move, "test/attacks/x")
	check(missing.size() == 1 and missing[0].contains("test/attacks/x/path"), "the data check names the missing field with its location: %s" % ", ".join(missing))
	check(MeleeMove.completeness_problems(move, "test/attacks/x", false).is_empty(), "an unarmed move (gun in hand) needs no weapon path")
	var bad := move.duplicate(true)
	bad["hits"] = [{"at": 0.0, "length": 0.08}, {"at": 0.05, "length": 0.05}]
	bad["feedback"] = {"reaction": "heavy"}
	bad["path"] = [{"t": 0.0, "angle": 0.0, "reach": 20.0}]
	var problems := MeleeMove.problems(bad, "test/attacks/bad")
	check(problems.size() >= 3, "overlapping or late hit windows, a reaction that contradicts stagger and a short or unreachable path are refused: %s" % ", ".join(problems))
	# 搬到新格式之前的每一招都是「出招開始時一段、持續整個出招」：搬完的時間、距離、傷害不變。
	var sets: Array[MeleeSet] = [MeleeData.default_set()]
	for id: String in HOLD_WEAPONS:
		sets.append(MeleeData.set_of(load("res://data/weapons/melee/%s.tres" % id) as WeaponData))
	for set in sets:
		var ids: Array = set.combo()
		if not set.extension_attack().is_empty():
			ids.append(set.extension_attack())
		for id: Variant in ids:
			var def := set.attack(str(id), str(id) == set.extension_attack())
			var hits := MeleeMove.hits(def)
			check(hits.size() == 1 and is_zero_approx(float(hits[0]["at"])) and is_equal_approx(float(hits[0]["length"]), float(def["active"])) and MeleeMove.hit_damage(def, 0) == int(def["damage"]),
					"%s/%s keeps one hit over the whole active part with its old damage" % [set.path, id])
			check(MeleeMove.reaction(def) == ("heavy" if int(def["stagger"]) >= 3 else "light"), "%s/%s declares the enemy reaction that matches its stagger" % [set.path, id])
		check(set.path == MeleeData.PATH or not set.hold_hint().is_empty(), "%s has a hold move with a one-line hint" % set.path)


## 只有資料的測試武器（tests/fixtures/melee/test_spear.json）：沒有任何專屬程式也能連段、多段判定與按住蓄力。
func _test_data_only_weapon() -> void:
	var set := MeleeSet.new(TEST_WEAPON_DATA)
	check(set.validate().is_empty(), "the data-only test weapon passes the full move check: %s" % ", ".join(set.validate()))
	MeleeData._profiles[TEST_WEAPON_PROFILE] = set
	var weapon := (load("res://data/weapons/melee/melee_glaive.tres") as WeaponData).duplicate() as WeaponData
	weapon.id = &"test_spear"
	weapon.melee_profile = TEST_WEAPON_PROFILE
	await open_level(10.0)
	var player := level.player
	player.loadout.equip(weapon)
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	player._melee_cooldown_left = 0.0
	var enemy := await _target_at(24.0)
	enemy.health.setup(999, 0.0)
	var before := enemy.health.current
	check(player._try_melee() and str(player._melee_attack.get("pose", "")) == "ion_glaive_thrust", "the test weapon swings its own first move")
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	player._try_melee()
	var hits_seen := 0
	var last := enemy.health.current
	for frame in 90:
		await physics_frames(1)
		if enemy.health.current < last:
			hits_seen += 1
			last = enemy.health.current
		if player._melee_phase == Player.MeleePhase.NONE:
			break
	check(before - enemy.health.current == 2 + 3 and hits_seen == 3, "jab then a three-window stab: every window hits the same target again (lost %d over %d hits)" % [before - enemy.health.current, hits_seen])
	await physics_frames(40)
	Input.action_press(&"melee")
	var charging_frames := 0
	var lost_before := -1
	for frame in 150:
		await physics_frames(1)
		if player.melee.hold_mode == "charge" and player._melee_phase == Player.MeleePhase.WINDUP:
			if lost_before < 0:
				lost_before = enemy.health.current
			charging_frames += 1
		if player.melee.charged:
			break
	await _frames_until(player, Player.MeleePhase.RECOVERY)
	Input.action_release(&"melee")
	check(charging_frames >= int((0.1 + 0.3) * 60.0) - 2, "holding keeps the charge wind-up past its normal length (%d frames)" % charging_frames)
	check(lost_before - enemy.health.current == 9, "a full charge strikes with the hold move's full damage")
	await physics_frames(60)
	await end_level(level)
	MeleeData._profiles.erase(TEST_WEAPON_PROFILE)


## 五把近戰武器的按住招式：第一招打完還按著就接上；蓄力停在前搖、持續的招式一直判定、重複的招式多段命中。
func _test_weapon_holds() -> void:
	for id: String in HOLD_WEAPONS:
		await open_level(10.0)
		var player := level.player
		var weapon := load("res://data/weapons/melee/%s.tres" % id) as WeaponData
		player.loadout.equip(weapon)
		player.facing = 1
		player.aim_dir = Vector2.RIGHT
		AimInput.using_gamepad = true
		AimInput._last_stick_dir = Vector2.RIGHT
		player._melee_cooldown_left = 0.0
		var enemy := await _target_at(HOLD_WEAPONS[id])
		enemy.health.setup(999, 0.0)
		var set := MeleeData.set_of(weapon)
		var spec := set.hold()
		var hold_def := set.attack(str(spec.get("attack", "")))
		Input.action_press(&"melee")
		var started := false
		var windup_frames := 0
		var active_frames := 0
		var hits_during_hold := 0
		var last := enemy.health.current
		for frame in 220:
			await physics_frames(1)
			enemy.global_position.x = player.global_position.x + float(HOLD_WEAPONS[id])
			if player.melee.hold_mode != "":
				started = true
				if player._melee_phase == Player.MeleePhase.WINDUP:
					windup_frames += 1
				elif player._melee_phase == Player.MeleePhase.ACTIVE:
					active_frames += 1
				if enemy.health.current < last:
					hits_during_hold += 1
			last = enemy.health.current
			if started and player._melee_phase == Player.MeleePhase.RECOVERY and str(spec["mode"]) != "repeat":
				break
		Input.action_release(&"melee")
		check(started and player._melee_index <= 0, "%s: keeping the key held after the first move starts its hold move without advancing the combo" % id)
		match str(spec.get("mode", "")):
			"charge":
				check(windup_frames >= int((float(hold_def["windup"]) + float(spec["max"])) * 60.0) - 3, "%s: the charge holds the raised pose while the key is held (%d frames)" % [id, windup_frames])
			"sustain":
				check(active_frames > int(float(hold_def["active"]) * 60.0) + 20 and hits_during_hold >= 2, "%s: the sustained move stays out and keeps hitting (%d frames, %d hits)" % [id, active_frames, hits_during_hold])
			"repeat":
				check(hits_during_hold >= MeleeMove.hits(hold_def).size(), "%s: the repeated move lands every stab window (%d hits)" % [id, hits_during_hold])
		for frame in 120:
			if player._melee_phase == Player.MeleePhase.NONE:
				break
			await physics_frames(1)
		check(player._melee_phase == Player.MeleePhase.NONE and player.melee.hold_mode == "", "%s: releasing ends the hold move cleanly" % id)
		Input.action_release(&"aim_right")
		await end_level(level)


## 鍵鼠與手把的近戰規則一致（NE-237）：同一串操作（點一下、出招中提早再按、收招後在接續時間內再按、超過接續時間才按、按住），
## 用鍵盤 F／滑鼠左鍵送一次、用手把 Y／右扳機送一次，每一招開始的影格、第幾段、是不是按住招式都要一樣。
## 這是合成的輸入事件（走 Input.parse_input_event，和真的按鍵進同一條路），不代表實體手把已經驗過。
const PARITY_FRAMES := 200


func _test_input_parity() -> void:
	for id: String in HOLD_WEAPONS:
		var weapon := load("res://data/weapons/melee/%s.tres" % id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var first := set.attack(str(set.combo()[0]))
		var first_frames := int(ceil((float(first["windup"]) + float(first["active"]) + float(first["recovery"])) * 60.0))
		var scripts := {
			"tap": [[0, 3]],
			"early follow-up": [[0, 3], [mini(6, first_frames - 2), mini(9, first_frames)]],
			"follow-up in window": [[0, 3], [first_frames + 4, first_frames + 7]],
			"follow-up too late": [[0, 3], [first_frames + int(set.combo_window() * 60.0) + 24, first_frames + int(set.combo_window() * 60.0) + 27]],
			"hold": [[0, 150]],
		}
		for label: String in scripts:
			var results := {}
			for device: String in ["key_melee", "pad_melee", "mouse_shoot", "pad_shoot"]:
				results[device] = await _timeline(weapon, scripts[label], device)
			check(results["key_melee"] == results["pad_melee"] and results["mouse_shoot"] == results["pad_shoot"] and results["key_melee"] == results["mouse_shoot"] and not (results["key_melee"] as Array).is_empty(),
					"%s %s: keyboard F, mouse, pad Y and pad trigger start the same moves on the same frames %s" % [id, label, results])


## 照腳本按放（[按下的影格, 放開的影格]），回傳每一招開始的 [影格, 第幾段, 按住模式]。
func _timeline(weapon: WeaponData, presses: Array, device: String) -> Array:
	await open_level(10.0)
	var player := level.player
	player.loadout.equip(weapon)
	player._melee_cooldown_left = 0.0
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	await physics_frames(2)
	var starts: Array = []
	var previous := Player.MeleePhase.NONE
	for frame in PARITY_FRAMES:
		for press: Array in presses:
			if frame == int(press[0]):
				_send(device, true)
			elif frame == int(press[1]):
				_send(device, false)
		await physics_frames(1)
		if player._melee_phase == Player.MeleePhase.WINDUP and previous != Player.MeleePhase.WINDUP:
			starts.append([frame, player._melee_index, player.melee.hold_mode])
		previous = player._melee_phase
	_send(device, false)
	InputBindings.clear_held_inputs()
	await end_level(level)
	return starts


func _send(device: String, pressed: bool) -> void:
	var event: InputEvent
	match device:
		"key_melee":
			var key := InputEventKey.new()
			key.physical_keycode = KEY_F
			key.keycode = KEY_F
			key.pressed = pressed
			event = key
		"mouse_shoot":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.pressed = pressed
			event = mouse
		"pad_melee":
			var button := InputEventJoypadButton.new()
			button.button_index = JOY_BUTTON_Y
			button.pressed = pressed
			event = button
		"pad_shoot":
			var axis := InputEventJoypadMotion.new()
			axis.axis = JOY_AXIS_TRIGGER_RIGHT
			axis.axis_value = 1.0 if pressed else 0.0
			event = axis
	Input.parse_input_event(event)
	# 立刻送進遊戲：不然事件要等到下一個畫面才處理，機器忙時一個畫面會補跑好幾個物理步，落在哪一步就不固定。
	Input.flush_buffered_events()


## 畫面上打得到多遠和實際打得到多遠一致（NE-236）：每一招出招段武器最遠的一點（刃尖、錘頭、鞭梢）沿揮擊方向離胸口的距離，
## 不短於判定距離的 85%（看起來沒打到卻打到），也不超過判定距離的 1.3 倍或多 10 像素（看起來打到卻沒打到；短刀以後者為準）。
const REACH_SHORT := 0.85
const REACH_LONG := 1.3
const REACH_SLACK := 10.0


func _test_visual_reach() -> void:
	await open_level(10.0)
	var player := level.player
	for id: String in HOLD_WEAPONS:
		var weapon := load("res://data/weapons/melee/%s.tres" % id) as WeaponData
		var set := MeleeData.set_of(weapon)
		var moves: Array = set.combo()
		moves.append(set.extension_attack())
		moves.append(str(set.hold()["attack"]))
		for move: Variant in moves:
			player._interrupt_melee()
			player.loadout.reset(weapon)  # 每一招都從滿電開始（錘與鞭每揮耗電）
			player._melee_cooldown_left = 0.0
			player._melee_combo_left = 0.0
			place_player(10.0)
			player.facing = 1
			player.aim_dir = Vector2.RIGHT
			AimInput.using_gamepad = true
			AimInput._last_stick_dir = Vector2.RIGHT
			await physics_frames(20)
			player.melee.start_attack(false)
			var def := set.attack(str(move), str(move) == set.extension_attack())
			player.melee.attack = def
			player.melee.swing_direction = player.melee.aim_direction(def)
			var reach := 0.0
			for frame in 240:
				await physics_frames(1)
				if player.melee.phase == MeleeModule.Phase.NONE:
					break
				if player.melee.phase == MeleeModule.Phase.ACTIVE:
					var chest := player.global_position + Vector2(0.0, -Player.BODY_SIZE.y * 0.55)
					reach = maxf(reach, (player._visual.melee_held().tip_point() - chest).dot(player.melee.swing_direction))
			var hit_range := float(def["range"])
			check(reach >= hit_range * REACH_SHORT and reach <= maxf(hit_range * REACH_LONG, hit_range + REACH_SLACK),
					"%s/%s: the weapon on screen reaches %.1f px for a %.0f px hit range" % [id, move, reach, hit_range])
	await end_level(level)

