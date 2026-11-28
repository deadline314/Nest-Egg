class_name LatchDoorScenario
extends ScenarioBase
## 門閂門（NE-430）：第三章天穹辦公接待廊。連拍：從左邊走到門前（門從另一側閂住了）→ 上層走廊繞過門的上方 →
## 從右側下來、門閂那一側的提示 → 拉開門閂 → 門開著，從右邊走回左邊。門沒打開或走不回去就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=latch_door

const LEVEL := "res://data/levels/ch3_office_hall.tres"


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
	var door: Gate
	for node in level._entities.get_children():
		if node is Gate and (node as Gate).data.is_latch_door():
			door = node
	if door == null:
		failures += 1
		push_error("[LatchDoorScenario] %s 裡沒有門閂門" % LEVEL)
		await finish()
		return
	var floor_y := door.global_position.y
	var camera := get_viewport().get_camera_2d() as LevelCamera
	var framed := camera != null and camera.acquire_presentation_focus(self, Vector2(door.global_position.x, floor_y - 60.0))
	await wait(TITLE_CARD_TIME + 0.3)
	# 另一側：門從另一側閂住了。
	player.global_position = Vector2(door.global_position.x - 22.0, floor_y)
	player.velocity = Vector2.ZERO
	await wait(1.0)
	capture("NE-430-latch-0-blocked")
	# 上層走廊：站在門的正上方。
	player.global_position = Vector2(door.global_position.x, floor_y - 6.0 * 16.0)
	player.velocity = Vector2.ZERO
	await wait(0.8)
	capture("NE-430-latch-1-over")
	# 門閂那一側。
	player.global_position = Vector2(door.global_position.x + 22.0, floor_y)
	player.velocity = Vector2.ZERO
	await wait(1.0)
	capture("NE-430-latch-2-latch-side")
	Input.action_press(&"interact")
	await settle(3)
	Input.action_release(&"interact")
	await wait(0.6)
	capture("NE-430-latch-3-open")
	# 走回左邊。
	Input.action_press(&"move_left")
	await wait(0.6)
	Input.action_release(&"move_left")
	await wait(0.2)
	capture("NE-430-latch-4-shortcut")
	var back := player.global_position.x < door.global_position.x - 8.0
	print("LATCH open=%s walked_back=%s" % [door.is_open, back])
	if not door.is_open or not back:
		failures += 1
		push_error("[LatchDoorScenario] 門閂應該在右側拉得開，拉開後可以走回左邊")
	if framed:
		camera.release_presentation_focus(self)
	await finish()
