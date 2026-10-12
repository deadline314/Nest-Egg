class_name CameraLedgeScenario
extends ScenarioBase
## 往下看落點的對照（NE-256）：主角站在序章搬貨台的邊緣、面向 5 格深的落差。依序拍三張：
## 關掉往下看（拉近之後、修正之前的行為）→ 停住後鏡頭自己往下看到落點 → 再往斜下方瞄準。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=camera_ledge

const LEVEL := "res://data/levels/ch1_prologue.tres"
## 搬貨台右緣（欄、列）；主角面向右邊的落差。
const EDGE := Vector2i(67, 14)
const SETTLE_SECONDS := 1.5


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	AimInput.set_virtual_gamepad(player, true)
	var camera := get_viewport().get_camera_2d() as LevelCamera
	var peek := camera.tuning.ledge_peek_max
	var look := camera.tuning.aim_look_down
	camera.tuning.ledge_peek_max = 0.0
	camera.tuning.aim_look_down = 15.0
	var tile := float(level._layout.tile_size)
	player.global_position = Vector2((EDGE.x + 0.5) * tile, (EDGE.y + 1) * tile)
	player.velocity = Vector2.ZERO
	_aim(Vector2.RIGHT)
	snap_camera()
	await wait(TITLE_CARD_TIME)
	capture("NE-256-ledge-0-before")
	camera.tuning.ledge_peek_max = peek
	camera.tuning.aim_look_down = look
	await wait(SETTLE_SECONDS)
	capture("NE-256-ledge-1-peek")
	_aim(Vector2(1.0, 1.0).normalized())
	await wait(SETTLE_SECONDS)
	capture("NE-256-ledge-2-aim-down")
	_aim(Vector2.ZERO)
	AimInput.set_virtual_gamepad(player, false)
	await finish()


func _aim(direction: Vector2) -> void:
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
