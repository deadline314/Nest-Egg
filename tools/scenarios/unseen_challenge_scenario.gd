class_name UnseenChallengeScenario
extends ScenarioBase
## 「不被發現」區域挑戰（NE-411）：第二章裝卸區。主角實際按住「往右」走兩趟：
## 一趟走上方走道到吊著的貨箱上方（應該完成）、一趟走地面（應該被發現而失敗）。保留 HUD，拍走道途中、完成提示、失敗提示三張，
## 並印出兩趟的結果。走道那趟沒完成、或地面那趟沒失敗就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=unseen_challenge

const LEVEL := "res://data/levels/ch2_loading.tres"
const WALKWAY_ROW := 29
const START_CELL_X := 14
const TIME_LIMIT := 30.0


func run() -> void:
	var high := await _attempt(true)
	var low := await _attempt(false)
	print("UNSEEN_CHALLENGE walkway=%s floor=%s" % [high, low])
	if high != "done" or low != "failed":
		failures += 1
		push_error("[UnseenChallengeScenario] 走道應該完成、地面應該失敗：%s / %s" % [high, low])
	await finish()


func _attempt(walkway: bool) -> String:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	var challenge: AreaChallenge
	for node in get_tree().get_nodes_in_group(AreaChallenge.GROUP):
		challenge = node as AreaChallenge
	if challenge == null:
		push_error("[UnseenChallengeScenario] %s 沒有區域挑戰" % LEVEL)
		level.queue_free()
		await settle(4)
		return "missing"
	await wait(AreaChallenge.INTRO_DELAY + 0.4)
	var tile := float(level._layout.tile_size)
	var row := WALKWAY_ROW if walkway else level._layout.height - 5
	player.global_position = Vector2((START_CELL_X + 0.5) * tile, row * tile)
	player.velocity = Vector2.ZERO
	snap_camera()
	await settle(4)
	Input.action_press(&"move_right")
	var elapsed := 0.0
	var mid_shot := false
	var finish_x := (challenge.data.finish_cell_x + 0.5) * tile
	while elapsed < TIME_LIMIT and not challenge.done and not challenge.failed:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if walkway and not mid_shot and player.global_position.x > finish_x - 260.0:
			mid_shot = true
			capture("NE-411-unseen-0-walkway")
	Input.action_release(&"move_right")
	await wait(0.5)
	var result := "done" if challenge.done else ("failed" if challenge.failed else "timeout")
	capture("NE-411-unseen-%s-%s" % ["1" if walkway else "2", result])
	level.queue_free()
	await settle(4)
	return result
