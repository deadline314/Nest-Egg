class_name PlayerFxScenario
extends ScenarioBase
## 截圖情境（NE-95）：玩家特效的連續畫面——彈道拖尾（手槍、步槍、榴彈）、衝刺殘影、格擋與完美反彈、義體能力、重生淡入、排氣孔噴發與霓虹。
## 用法：screenshot.tscn -- --out=<資料夾> --scenario=player_fx

const LIGHTING := "res://data/lighting/neutral.tres"


func run() -> void:
	await open_arena(LIGHTING, 12.0)
	player.health.setup(999, 0.0)
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	player.facing = 1
	# 彈道拖尾：三種武器各打一發，飛行途中拍一張。
	for id in ["pistol", "rifle", "launcher"]:
		player.loadout.equip(load("res://data/weapons/%s.tres" % id) as WeaponData)
		player._fire_cooldown_left = 0.0
		player._try_fire()
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
	# 排氣孔與霓虹。
	var vent := SteamVent.new()
	level.add_child(vent)
	vent.global_position = Vector2(17.0 * 16.0, FLOOR_Y)
	vent._burst_in = 0.1
	var neon := NeonSign.new()
	neon.text = "拉麵"
	neon.color = Palette.MAGENTA
	level.add_child(neon)
	neon.global_position = Vector2(9.0 * 16.0, FLOOR_Y - 90.0)
	await wait(0.2)
	capture("vent_warning")
	await wait(0.5)
	capture("vent_burst")
	await wait(0.3)
	neon._burst_flicks = 2
	neon._off_left = 0.05
	await wait(0.12)
	capture("neon_flicker")
	AimInput.using_gamepad = false
	await finish()
