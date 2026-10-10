extends Node
## 60 Hz 真實 Player/Hurtbox/Enemy 的訓練場量測。固定目標距離以分開測攻擊節奏與追逐；不是人工遊玩。
const IDS := ["dagger", "blade", "maul", "glaive", "whip"]
const OFFSETS := [20.0, 24.0, 24.0, 50.0, 72.0]
const TARGETS := ["grunt", "collector_brute", "watchdog"]
var output := "res://pm/Nest-Egg/attachments/NE-236-measurements.json"
var samples: Array[Dictionary] = []
var upgraded := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg == "--upgraded":
			upgraded = true
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	# headless 沒有繪製可見區域，與正式測試相同地停用畫面外的 activation culling。
	Enemy.activation_culling_enabled = false
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	for difficulty in GameState.difficulties.size():
		for target in TARGETS:
			for i in IDS.size():
				await _sample(i, target, difficulty, false)
	for i in IDS.size():
		await _sample(i, "grunt", 1, true)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "hz": Engine.physics_ticks_per_second,
		"method": "6s 60Hz Input.action_press/release polling taps every 8 ticks; target pinned at documented offset, real damage/reaction/charge; miss at +180px; wall-clock hitstop included",
		"upgraded": upgraded, "samples": samples}, "\t") + "\n")
	file.close()
	print("BALANCE_SAMPLES ", samples.size(), " ", output)
	get_tree().quit()


func _sample(index: int, target_id: String, difficulty: int, miss: bool) -> void:
	GameState.start_new_run(GameState.difficulties[difficulty])
	var weapon := load("res://data/weapons/melee/melee_%s.tres" % IDS[index]) as WeaponData
	var level := Level.new()
	level.configure(EnemySuiteBase.map_data())
	add_child(level)
	for tick in 8:
		await get_tree().physics_frame
	var player := level.player
	player.global_position = Vector2(160.0, EnemySuiteBase.FLOOR_Y)
	player.health.setup(999, 0.0)
	player.loadout.reset(weapon)
	if upgraded:
		Progression.add_credits(1000)
		var upgrade := Progression.find_upgrade(StringName("technique_" + IDS[index]))
		if upgrade == null or not Progression.buy_upgrade(weapon, upgrade):
			push_error("upgrade unavailable: " + IDS[index])
			get_tree().quit(1)
			return
	if upgraded and not Progression.has_upgrade(player.loadout.active_weapon(), StringName("technique_" + IDS[index])):
		push_error("measurement lost the purchased technique after spawn")
		get_tree().quit(1)
		return
	player.facing = 1
	player.aim_dir = Vector2.RIGHT
	player._melee_cooldown_left = 0.0
	var enemy := level._create_enemy(load("res://data/enemies/%s.tres" % target_id))
	enemy.position = player.position + Vector2(OFFSETS[index] + (180.0 if miss else 0.0), 0)
	level._entities.add_child(enemy)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.health.setup(999, 0.0)
	var hits: Array[Dictionary] = []
	var started := Time.get_ticks_msec()
	var first_physics_frame := Engine.get_physics_frames()
	enemy.health.damaged.connect(func(info: DamageInfo) -> void:
		hits.append({"at_ms": Time.get_ticks_msec() - started, "damage": info.amount, "knockback_x": info.knockback.x,
			"physics_tick": Engine.get_physics_frames() - first_physics_frame, "source": info.source_id,
			"response_velocity_x": enemy.velocity.x, "stun_s": enemy._stun_left, "impact": info.get_impact(), "attack": player.melee_pose(), "guard_at_hit": player.guard}))
	var locked := 0
	var swings := 0
	var previous_phase := Player.MeleePhase.NONE
	var max_step := 0
	for tick in 360:
		enemy.global_position = Vector2(player.global_position.x + OFFSETS[index] + (180.0 if miss else 0.0), EnemySuiteBase.FLOOR_Y)
		enemy.velocity = Vector2.ZERO
		if tick % 8 == 0:
			Input.action_press(&"melee")
		elif tick % 8 == 1:
			Input.action_release(&"melee")
		await get_tree().physics_frame
		if player.is_melee_locked() or player._melee_cooldown_left > 0.0:
			locked += 1
		if player._melee_phase == Player.MeleePhase.WINDUP and previous_phase != Player.MeleePhase.WINDUP:
			swings += 1
		max_step = maxi(max_step, player._melee_index)
		previous_phase = player._melee_phase
	Input.action_release(&"melee")
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	var damage := 999 - enemy.health.current
	if not miss and damage <= 0:
		push_error("measurement fixture failed to connect: %s / %s" % [weapon.id, target_id])
		get_tree().quit(1)
		return
	var row := {"weapon": weapon.id, "target": target_id, "difficulty": GameState.difficulties[difficulty].id,
		"miss": miss, "offset_px": OFFSETS[index] + (180.0 if miss else 0.0), "wall_seconds": elapsed,
		"damage": damage, "dps": damage / maxf(elapsed, 0.01), "first_hit_ms": hits[0].at_ms if not hits.is_empty() else -1,
		"first_hit_physics_ms": hits[0].physics_tick * 1000.0 / Engine.physics_ticks_per_second if not hits.is_empty() else -1,
		"locked_physics_ticks": locked, "swings": swings, "max_combo_step": max_step, "guard_remaining": player.guard,
		"charge_remaining": player.loadout.mag_in(0), "hits": hits}
	row["upgrade_owned"] = Progression.has_upgrade(player.loadout.active_weapon(), StringName("technique_" + IDS[index]))
	if upgraded and not miss and max_step < MeleeData.set_of(weapon).combo().size():
		push_error("upgraded measurement did not exercise the optional tail: " + IDS[index])
		get_tree().quit(1)
		return
	samples.append(row)
	print("BALANCE_ROW ", JSON.stringify(row))
	Fx.thaw_all()
	level.queue_free()
	for tick in 4:
		await get_tree().physics_frame
