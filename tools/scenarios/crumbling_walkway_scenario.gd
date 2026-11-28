class_name CrumblingWalkwayScenario
extends ScenarioBase
## 會塌的走道（NE-420）：第一章屋頂。連拍：起點的提示 → 跑到一半 → 抵達對面時身後最後幾片還在抖、在掉 → 全部塌完；再站在中間不動：預警 → 掉下去 → 落在屋頂上。
## 印出每一段的量測（掉了幾片、主角最低點、最後落點）；跑過去卻掉下去、或站著不動卻沒掉，記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=crumbling_walkway

const LEVEL := "res://data/levels/ch1_rooftop.tres"


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
	var walkway: CrumblingWalkway
	for node in get_tree().get_nodes_in_group(CrumblingWalkway.GROUP):
		walkway = node as CrumblingWalkway
		break
	if walkway == null:
		failures += 1
		push_error("[CrumblingWalkwayScenario] %s 裡沒有會塌的走道" % LEVEL)
		await finish()
		return
	var top := walkway.deck_top()
	var start_x := walkway.segment_rect(0).position.x
	var end_x := walkway.segment_rect(walkway.segment_count() - 1).end.x
	var fell := [0]
	walkway.segment_fell.connect(func(_index: int) -> void: fell[0] += 1)
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right", 1.0)
	await wait(TITLE_CARD_TIME + 0.5)

	# 起點：站在走道左邊的踏板上，提示展開、對面的信用點看得到。
	player.global_position = Vector2(start_x - 14.0, top)
	player.velocity = Vector2.ZERO
	await settle(2)
	snap_camera()
	await wait(0.9)
	capture("NE-420-walkway-0-start")

	# 一路往右跑：跑到一半拍一張；過了一半鏡頭改看走道本身（不往前看），抵達時拍到身後最後幾片在抖、在掉。
	var camera := get_viewport().get_camera_2d() as LevelCamera
	Input.action_press(&"move_right")
	var lowest := top
	var shot_mid := false
	var framed := false
	var elapsed := 0.0
	while player.global_position.x < end_x + 20.0 and elapsed < 4.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		lowest = maxf(lowest, player.global_position.y)
		if not shot_mid and player.global_position.x >= start_x + (end_x - start_x) * 0.45:
			shot_mid = true
			capture("NE-420-walkway-1-running")
			framed = camera != null and camera.acquire_presentation_focus(self, Vector2(start_x + (end_x - start_x) * 0.72, top - 24.0))
	Input.action_release(&"move_right")
	await wait(0.12)
	capture("NE-420-walkway-2-behind")
	await wait(0.9)
	capture("NE-420-walkway-3-across")
	var crossed := player.global_position.x >= end_x and lowest < top + 3.0
	print("WALKWAY run: crossed=%s lowest=%.1f deck=%.1f fell=%d/%d" % [crossed, lowest, top, fell[0], walkway.segment_count()])
	if not crossed or fell[0] < walkway.segment_count() - 2:
		failures += 1
		push_error("[CrumblingWalkwayScenario] 一路跑過去應該不掉、身後的片應該塌掉")

	# 等片補回，站在走道中間不動：預警時一張、掉下去時一張、落地一張。鏡頭對著那一片。
	await wait(walkway.data.respawn_seconds + CrumblingWalkway.RETURN_SECONDS + 0.6)
	var middle := walkway.segment_rect(walkway.segment_count() / 2)
	if framed:
		camera.release_presentation_focus(self)
	framed = camera != null and camera.acquire_presentation_focus(self, Vector2(middle.get_center().x, top + 8.0))
	await wait(1.2)
	player.global_position = Vector2(middle.get_center().x, top)
	player.velocity = Vector2.ZERO
	await wait(walkway.data.warn_seconds * 0.6)
	capture("NE-420-walkway-4-warning")
	await wait(walkway.data.warn_seconds * 0.4 + 0.12)
	capture("NE-420-walkway-5-falling")
	await wait(0.8)
	capture("NE-420-walkway-6-landed")
	if framed:
		camera.release_presentation_focus(self)
	var dropped := player.global_position.y - top
	print("WALKWAY still: dropped=%.1f on_floor=%s health=%d" % [dropped, player.is_on_floor(), player.health.current])
	if dropped < 48.0 or not player.is_on_floor():
		failures += 1
		push_error("[CrumblingWalkwayScenario] 站著不動應該跟著掉到屋頂地面")
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	await finish()
