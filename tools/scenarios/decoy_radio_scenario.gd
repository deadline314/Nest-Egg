class_name DecoyRadioScenario
extends ScenarioBase
## 誘餌收音機（NE-404）：第三章泵室，兩台抽水巡檢器之間的地上有一台收音機。主角從左邊遠處射中它。
## 拍三張：射中前（有提示）、播放中兩台巡檢器走過去、主角溜到左邊那台背後。印出巡檢器有沒有被吸引、有沒有發現主角。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=decoy_radio

const LEVEL := "res://data/levels/ch3_pump.tres"


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	var radio: DecoyRadio
	for node in get_tree().get_nodes_in_group(DecoyRadio.GROUP):
		radio = node as DecoyRadio
		break
	if radio == null:
		failures += 1
		push_error("[DecoyRadioScenario] %s 裡沒有收音機" % LEVEL)
		await finish()
		return
	var near: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and absf(enemy.global_position.y - radio.global_position.y) < 32.0:
			near.append(enemy)
	near.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.global_position.x < b.global_position.x)
	await wait(TITLE_CARD_TIME + 0.5)
	# 用虛擬手把往右瞄：面向收音機，鏡頭往前看。
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right", 1.0)
	# 主角站在收音機左邊；拍第一張之前巡檢器先停住（鏡頭只看得到約 330 像素寬，站得夠近才拍得到收音機）。
	for enemy in near:
		enemy.fsm.transition(&"patrol")
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = radio.global_position + Vector2(-150.0, 0.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(0.8)
	capture("NE-404-radio-0-before")
	# 開槍時退到巡檢器的視線外。
	player.global_position = radio.global_position + Vector2(-260.0, 0.0)
	snap_camera()
	radio.hurtbox.receive(DamageInfo.create(1, Combat.Team.PLAYER, &"decoy_radio_scenario"))
	for enemy in near:
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
	for step in 4:
		await wait(0.55)
	capture("NE-404-radio-1-lured")
	# 溜到左邊那台背後。
	if not near.is_empty():
		var left := near[0]
		player.global_position = left.global_position + Vector2(-float(left.facing) * 36.0, 0.0)
		snap_camera()
	await wait(0.6)
	capture("NE-404-radio-2-behind")
	var lured := 0
	var engaged := 0
	for enemy in near:
		lured += int(enemy.is_lured())
		engaged += int(enemy.is_engaged())
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	print("DECOY_RADIO enemies=%d lured=%d engaged=%d playing=%s" % [near.size(), lured, engaged, radio.is_playing()])
	if near.is_empty() or lured < near.size() or engaged > 0:
		failures += 1
		push_error("[DecoyRadioScenario] 巡檢器沒有全部被收音機吸引，或發現了背後的主角")
	await finish()
