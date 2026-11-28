class_name CallerScenario
extends ScenarioBase
## 收帳人·聯絡員（NE-476）：第二章裝卸區，打下吊掛貨箱。
## 第一段：主角站在空地上，聯絡員講完回報，增援從牠背後過來（拍：拿起話筒、圓環過半與落點記號、增援到場）。
## 第二段：聯絡員講到一半，主角蹲到落地的貨箱後面，回報斷掉（拍：躲進去、掛斷）。
## 其他敵人停下並隱藏，操作提示關掉。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=caller

const LEVEL := "res://data/levels/ch2_loading.tres"
const CALLER := "res://data/enemies/collector_caller.tres"

var _report := {}


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
	for node in get_tree().get_nodes_in_group(&"enemies"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(node as CanvasItem).visible = false
	await wait(TITLE_CARD_TIME + 0.3)
	for prompt in level.find_children("*", "WorldPrompt", true, false):
		prompt.set(&"enabled", false)
	var crate := get_tree().get_first_node_in_group(SuspendedLoad.GROUP) as SuspendedLoad
	if crate == null:
		_fail("%s 找不到吊掛貨箱" % LEVEL)
		await finish()
		return
	crate.hurtbox.receive(DamageInfo.create(99, Combat.Team.PLAYER, &"caller_scenario"))
	while crate.state != SuspendedLoad.State.LANDED:
		await get_tree().physics_frame
	var floor_y := crate.global_position.y
	AimInput.set_virtual_gamepad(player, true)
	AimInput.restore_direction(Vector2.RIGHT)
	# 第一段：空地上，講完。
	var open_spot := Vector2(crate.global_position.x + 40.0, floor_y)
	player.global_position = open_spot
	snap_camera()
	await wait(0.3)
	var caller := _spawn(Vector2(crate.global_position.x + 200.0, floor_y))
	var shots := 0
	var elapsed := 0.0
	while elapsed < 8.0 and shots < 3:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_hold(open_spot)
		var progress := float(caller.get("call_progress"))
		if shots == 0 and caller.fsm.is_in(&"call") and progress >= 0.25:
			capture("NE-476-0-call")
			shots = 1
		elif shots == 1 and caller.fsm.is_in(&"call") and progress >= 0.75:
			capture("NE-476-1-marks")
			shots = 2
		elif shots == 2 and int(caller.get("calls_made")) > 0 and caller.fsm.time_in_state > 0.5:
			capture("NE-476-2-backup")
			shots = 3
	_report["complete"] = "shots %d, backup %d" % [shots, int(caller.call("alive_summons"))]
	if shots < 3:
		_fail("聯絡員沒有講完回報（狀態 %s）" % caller.fsm.current)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if (node as Node).process_mode != Node.PROCESS_MODE_DISABLED:
			(node as Node).queue_free()
	await wait(0.3)
	# 第二段：講到一半躲到貨箱後面。
	player.global_position = open_spot
	snap_camera()
	caller = _spawn(Vector2(crate.global_position.x + 200.0, floor_y))
	var hide := Vector2(crate.global_position.x - crate.size_px.x * 0.5 - 8.0, floor_y)
	var hid := false
	var hung_up := false
	elapsed = 0.0
	while elapsed < 8.0 and not hung_up:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_hold(hide if hid else open_spot)
		if not hid and caller.fsm.is_in(&"call") and float(caller.get("call_progress")) >= 0.4:
			hid = true
			_hold(hide)
			Input.action_press(&"move_down")
			await wait(0.25)
			capture("NE-476-3-hide")
		elif hid and caller.fsm.is_in(&"patrol"):
			hung_up = true
			await wait(0.15)
			capture("NE-476-4-hangup")
	_report["broken"] = "hid %s, hung up %s, calls %d" % [hid, hung_up, int(caller.get("calls_made"))]
	if not hung_up or int(caller.get("calls_made")) != 0:
		_fail("躲到貨箱後面沒有讓回報斷掉")
	Input.action_release(&"move_down")
	print("CALLER %s" % JSON.stringify(_report))
	AimInput.set_virtual_gamepad(player, false)
	await finish()


func _spawn(at: Vector2) -> Enemy:
	var enemy := level._create_enemy(load(CALLER) as EnemyData)
	enemy.position = at
	level._entities.add_child(enemy)
	return enemy


func _hold(at: Vector2) -> void:
	player.global_position = at
	player.velocity = Vector2.ZERO


func _fail(message: String) -> void:
	failures += 1
	push_error("[CallerScenario] " + message)
