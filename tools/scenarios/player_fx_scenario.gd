class_name PlayerFxScenario
extends ScenarioBase
## 截圖情境（NE-95）：玩家特效的連續畫面——彈道拖尾（手槍、步槍、榴彈）、衝刺殘影、格擋與完美反彈、義體能力、重生淡入、排氣孔噴發與霓虹。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=player_fx [--lighting=market] [--quality=low|medium|high] [--slow=0.5] [--environment-only|--barrel-only]


func run() -> void:
	var original_quality := Settings.get_light_quality()
	var original_scale := Engine.time_scale
	var review_scale := 1.0
	var environment_only := false
	var barrel_only := false
	var lighting := "neutral"
	for arg in OS.get_cmdline_user_args():
		if arg == "--environment-only": environment_only = true
		if arg == "--barrel-only": barrel_only = true
		if arg.begins_with("--lighting="): lighting = arg.trim_prefix("--lighting=")
		if arg.begins_with("--quality="): Settings.set_light_quality({"low": 0, "medium": 1, "high": 2}.get(arg.trim_prefix("--quality="), original_quality))
		if arg.begins_with("--slow="): review_scale = clampf(float(arg.trim_prefix("--slow=")), 0.1, 1.0)
	await open_arena("res://data/lighting/%s.tres" % lighting, 12.0)
	Engine.time_scale = review_scale
	if environment_only or barrel_only:
		if barrel_only:
			await _capture_barrel()
		else:
			await _capture_environment()
		Engine.time_scale = original_scale
		Settings.set_light_quality(original_quality)
		await finish()
		return
	player.health.setup(999, 0.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.facing = 1
	# 彈道拖尾：三種武器各打一發，飛行途中拍一張。
	for id in ["pistol", "rifle", "launcher"]:
		player.loadout.equip(load("res://data/weapons/%s.tres" % id) as WeaponData)
		player._fire_cooldown_left = 0.0
		player._try_fire()
		await RenderingServer.frame_post_draw
		capture("muzzle_%s" % id)
		await wait(0.09 if id != "launcher" else 0.42)  # 榴彈比較慢，等它飛出去一段再拍
		capture("trail_%s" % id)
		await wait(0.5)
	# 衝刺殘影。
	player.loadout.select(0)
	player._dash_cooldown_left = 0.0
	player._try_dash(1.0)
	for i in 4:
		await wait(0.035)
		capture("dash_%d" % i)
	await wait(0.8)
	# 格擋與完美反彈。
	var at: Vector2 = player.aim_origin() + Vector2(14, 0)
	player._on_block(DamageInfo.create(1, Combat.Team.ENEMY, &"test"), at)
	for i in 2:
		await wait(0.04)
		capture("block_%d" % i)
	await wait(0.4)
	player._on_parry(DamageInfo.create(1, Combat.Team.ENEMY, &"test"), at)
	for i in 3:
		await wait(0.04)
		capture("parry_%d" % i)
	await wait(0.5)
	# 義體能力。
	var ability := load("res://data/abilities/emp_pulse.tres") as CyberAbilityData if ResourceLoader.exists("res://data/abilities/emp_pulse.tres") else null
	if ability != null:
		player.cyber.debug_set_ability(ability)
		player.cyber.charge = 100.0
		player.cyber.try_activate()
		await wait(0.18)
		capture("ability")
		await wait(0.6)
	# 重生。
	player.play_respawn_fx()
	await wait(0.15)
	capture("respawn_a")
	await wait(0.25)
	capture("respawn_b")
	await wait(0.6)
	await _capture_environment()
	AimInput.using_gamepad = false
	Engine.time_scale = original_scale
	Settings.set_light_quality(original_quality)
	await finish()


func _capture_environment() -> void:
	# 排氣孔與霓虹。
	var vent := SteamVent.new()
	level.add_child(vent)
	vent.global_position = Vector2(17.0 * 16.0, FLOOR_Y)
	vent._burst_in = 0.35
	var neon := NeonSign.new()
	neon.text = "拉麵"
	neon.color = Palette.MAGENTA
	level.add_child(neon)
	neon.global_position = Vector2(9.0 * 16.0, FLOOR_Y - 90.0)
	await wait(0.2)
	assert(vent._burst_left <= 0.0 and vent._burst_in > 0.0 and vent._burst_in < SteamVent.BURST_WARNING)
	print("STEAM warning remaining=%.3f active=%.3f" % [vent._burst_in, vent._burst_left])
	capture("vent_warning")
	await wait(0.5)
	assert(vent._burst_left > 0.0)
	print("STEAM burst remaining=%.3f active=%.3f" % [vent._burst_in, vent._burst_left])
	capture("vent_burst")
	await wait(0.3)
	neon._burst_flicks = 2
	neon._off_left = 0.05
	await wait(0.12)
	capture("neon_flicker")


func _capture_barrel() -> void:
	player.health.setup(999, 0.0)
	var barrel := Breakable.new()
	barrel.configure(load("res://data/props/barrel.tres") as BreakableData, Vector2i(18, 19), 16)
	barrel.position = Vector2(18 * 16.0, FLOOR_Y)
	level._entities.add_child(barrel)
	await settle(10)
	capture("barrel_before")
	barrel.hit_by_projectile(DamageInfo.create(9, Combat.Team.PLAYER, &"shot"))
	assert(barrel.is_broken)
	var elapsed := 0.0
	for time: float in [0.15, 0.22, 0.4, 0.75]:
		await wait(time - elapsed)
		elapsed = time
		capture("barrel_%03d" % int(time * 100.0))
	print("BARREL actual Breakable hit_by_projectile -> delayed explosion; broken=%s" % barrel.is_broken)
