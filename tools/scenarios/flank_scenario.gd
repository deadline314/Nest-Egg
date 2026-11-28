class_name FlankScenario
extends ScenarioBase
## 繞後的切割者（NE-424）：第四章中繼站東端，主角正面看著切割者。依序拍：對峙、蹲下預告翻越（地上有落點弧線）、
## 翻過主角頭頂、落在背後蓄力、撲斬。其他敵人先停下並隱藏，畫面與攻擊令牌只留給這名切割者。
## 沒翻過去或沒從背後出手就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=flank

const LEVEL := "res://data/levels/ch4_factory_relay.tres"
## 中繼站東端頭頂沒有走道的一段（翻越需要頭頂空間）：主角站在這裡面向東，切割者在牆邊。
const PLAYER_TILE := 88.5
const SLASHER_TILE := 92.0


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
	var slasher: Enemy
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.id == &"slasher":
			slasher = enemy
	if slasher == null:
		failures += 1
		push_error("[FlankScenario] %s 找不到切割者" % LEVEL)
		await finish()
		return
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node != slasher:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
			(node as CanvasItem).visible = false
	slasher.process_mode = Node.PROCESS_MODE_DISABLED
	# 旁邊電纜的操作提示會蓋住翻越的畫面，拍照時藏起來。
	await wait(TITLE_CARD_TIME + 0.3)
	for prompt in level.find_children("*", "WorldPrompt", true, false):
		prompt.set(&"enabled", false)
	var spot := Vector2(SLASHER_TILE * 16.0, slasher.global_position.y)
	slasher.global_position = spot
	player.global_position = Vector2(PLAYER_TILE * 16.0, spot.y)
	player.velocity = Vector2.ZERO
	AimInput.set_virtual_gamepad(player, true)
	AimInput.restore_direction(Vector2.RIGHT)
	snap_camera()
	await wait(0.4)
	slasher.process_mode = Node.PROCESS_MODE_INHERIT
	var shots := {}
	var player_x := player.global_position.x
	var elapsed := 0.0
	var peak_y := INF
	while elapsed < 8.0 and not shots.has("4"):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		player.velocity.x = 0.0
		if not shots.has("0") and slasher.fsm.is_in(&"stalk") and slasher.fsm.time_in_state > 0.8:
			shots["0"] = "standoff %.0f px" % absf(slasher.global_position.x - player_x)
			capture("NE-424-flank-0-standoff")
		elif not shots.has("1") and slasher.fsm.is_in(&"vault_tell") and slasher.fsm.time_in_state > 0.28:
			shots["1"] = "vault tell"
			capture("NE-424-flank-1-tell")
		elif slasher.fsm.is_in(&"vault"):
			peak_y = minf(peak_y, slasher.global_position.y)
			if not shots.has("2") and absf(slasher.global_position.x - player_x) < 8.0:
				shots["2"] = "over the head, %.0f px up" % (spot.y - slasher.global_position.y)
				capture("NE-424-flank-2-vault")
		elif not shots.has("3") and slasher.fsm.is_in(&"windup") and slasher.fsm.time_in_state > 0.4:
			shots["3"] = "windup behind=%s at %.0f px" % [slasher.get("striking_from_behind"), slasher.global_position.x - player_x]
			capture("NE-424-flank-3-windup")
		elif shots.has("3") and not shots.has("4") and slasher.fsm.is_in(&"leap") and slasher.fsm.time_in_state > 0.08:
			shots["4"] = "slash"
			capture("NE-424-flank-4-slash")
	print("FLANK %s" % JSON.stringify(shots))
	AimInput.set_virtual_gamepad(player, false)
	if not shots.has("2") or not shots.has("3") or not str(shots["3"]).contains("behind=true"):
		failures += 1
		push_error("[FlankScenario] 切割者沒有翻到主角背後出手：%s（狀態 %s）" % [shots, slasher.fsm.current])
	await finish()
