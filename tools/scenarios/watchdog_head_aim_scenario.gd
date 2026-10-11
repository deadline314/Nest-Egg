class_name WatchdogHeadAimScenario
extends ScenarioBase
## 玩家視角瞄頭（NE-252）：正式第一章碼頭倉庫，主角站在看門狗前後各種距離（站著、蹲著），
## 用真正的滑鼠移動事件把準星放在畫面上的頭，按射擊鍵開槍，逐發記錄子彈打到哪個部位（頭、砲塔、身體、沒打到）與是否被裝甲擋下。
## 平常（頭有裝甲）與吠叫預兆（頭打開）各量一輪；--capture 時每輪拍幾張開受擊框的命中瞬間。
## 看門狗的冷卻拉長、移動速度歸零，只是讓牠停在原地、照常面向玩家，不改判定與外觀。
## 用法：godot --fixed-fps 60 res://tools/screenshot.tscn -- --out=<資料夾> --scenario=watchdog_head_aim [--capture]
## 一定要加 --fixed-fps 60：軟體渲染很慢，不固定影格時預兆會在開槍前就結束，量到的不是玩家看到的時機。

const LEVEL := "res://data/levels/ch1_warehouse.tres"
## 主角相對看門狗的水平距離（像素，負＝在牠左邊）；左邊受貨櫃與鍊長限制，取前廳地板上站得到的位置。
const OFFSETS: Array[float] = [-150.0, -100.0, -70.0, -45.0, 45.0, 70.0, 100.0, 150.0]
const SHOTS_PER_SPOT := 2
const RESULT_WAIT := 0.35

var _dog: PatternBoss
var _capture := false
var _last_hit := ""
var _rows: PackedStringArray = []
var _tally: Dictionary = {}


func run() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	Enemy.activation_culling_enabled = false
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(9999, 0.0)
	if _capture:
		level.hud.visible = false  # 只拍主角、看門狗與命中；教學提示會蓋住畫面
		var camera := get_viewport().get_camera_2d() as LevelCamera
		if camera != null:
			camera.set_physics_process(false)  # 固定鏡頭（平常的前瞻會把主角擠到畫面邊緣）
	for node in level._entities.get_children():
		if node is PatternBoss and (node as PatternBoss).data.id == &"watchdog":
			_dog = node
	if _dog == null:
		push_error("[WatchdogHeadAim] 倉庫裡找不到看門狗")
		await finish()
		return
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node != _dog:
			node.queue_free()
	_dog.data = _dog.data.duplicate()
	_dog.data.attack_cooldown = 999.0
	_dog.data.move_speed = 0.0
	_dog.health.setup(9999, 0.0)
	_watch(_dog.hurtbox)
	for part in _dog.hurtbox.parts:
		_watch(part)
	await _stand(-100.0, false)
	await wait(2.0)  # 醒來與登場
	if _capture:
		await wait(8.0)  # 等倉庫開場的通訊播完，通訊框不蓋住狗頭
	# 截圖模式只拍站著、左右兩種距離（軟體渲染很慢）；量測模式跑全部位置。
	var offsets: Array[float] = OFFSETS.duplicate()
	var poses: Array[bool] = [false, true]
	if _capture:
		offsets.assign([-150.0, 70.0])
		poses.assign([false])
	for mode: String in ["idle", "bark"]:
		for crouch: bool in poses:
			for offset in offsets:
				await _sample(offset, crouch, mode)
	_release()
	print("HEAD_AIM summary: %s" % JSON.stringify(_tally))
	for row in _rows:
		print("HEAD_AIM %s" % row)
	Enemy.debug_hurtboxes = false
	await finish()


func _watch(box: Hurtbox) -> void:
	var id := String(box.part_id) if box.part_id != &"" else "body"
	box.hit_received.connect(func(_info: DamageInfo) -> void: _last_hit = id)
	box.hit_blocked.connect(func(_info: DamageInfo) -> void: _last_hit = id + "(擋下)")


func _stand(offset: float, crouch: bool) -> void:
	player.global_position = Vector2(_dog.global_position.x + offset, player.global_position.y)
	player.velocity = Vector2.ZERO
	_press(&"move_down", crouch)
	snap_camera()
	if _capture:
		var camera := get_viewport().get_camera_2d()
		if camera != null:
			camera.global_position = (player.global_position + _dog.global_position) * 0.5 + Vector2(0, -24.0)
			camera.reset_smoothing()
	await wait(0.5)


func _sample(offset: float, crouch: bool, mode: String) -> void:
	await _stand(offset, crouch)
	for shot in SHOTS_PER_SPOT:
		if mode == "bark":
			_dog.set("_move_id", &"bark")
			_dog.fsm.transition(&"windup")
			await wait(0.3)  # 抬頭到位
		var head := _part_center(&"head")
		_aim_at(head)
		await settle(2)
		_last_hit = "沒打到"
		var shoot_capture := _capture and shot == 0 and absf(offset) in [70.0, 150.0] and not crouch
		Enemy.debug_hurtboxes = shoot_capture
		Input.action_press(&"shoot")
		await settle(2)
		Input.action_release(&"shoot")
		if shoot_capture:
			# 等子彈真的打到再拍（命中火花與受擊框同一格）。
			for frame in 90:  # 用影格數等（軟體渲染很慢，不能用實際毫秒）
				if _last_hit != "沒打到":
					break
				await get_tree().physics_frame
			_dog.queue_redraw()
			await settle(1)
			capture("NE-252-aim-%s-%s%d" % [mode, "L" if offset < 0.0 else "R", int(absf(offset))])
		Enemy.debug_hurtboxes = false
		await wait(RESULT_WAIT)
		var key := "%s|%s" % [mode, _last_hit]
		_tally[key] = int(_tally.get(key, 0)) + 1
		_rows.append("mode=%s offset=%+d crouch=%s head=(%.0f,%.0f) muzzle=(%.0f,%.0f) result=%s" % [
				mode, int(offset), crouch, head.x, head.y, player.muzzle_position().x, player.muzzle_position().y, _last_hit])
		if mode == "bark":
			_dog.fsm.transition(&"idle")
			await wait(0.2)


func _aim_at(target: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = get_viewport().get_final_transform() * player.get_canvas_transform() * target
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(motion.position)  # 畫面上的準星也放在頭上


func _part_center(id: StringName) -> Vector2:
	for part in _dog.hurtbox.parts:
		if part.part_id == id:
			return part.center()
	return _dog.hurtbox.center()


func _press(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release() -> void:
	for action: StringName in [&"move_down", &"shoot"]:
		Input.action_release(action)
