class_name RinGaitsScenario
extends ScenarioBase
## 凜的小跑段（NE-481）：第一章倉庫隔牆前的平地，遊戲倍率，三條連續圖各 8 張（每 0.08 秒一張）：
## 手把半推的小跑（右推 0.7，約每秒 105 像素）、倒退（瞄左走右，約 127）、拿著水泥塊走（約 120）。
## 敵人停下並隱藏，操作提示關掉。印出每一段實際的水平速度。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=rin_gaits

const LEVEL := "res://data/levels/ch1_warehouse.tres"
## 起跑的欄（平地，隔牆前）。
const START_TILE := 50.0
const OPEN_ROW := 40
const FRAMES := 8
const INTERVAL := 0.08
const WARMUP := 0.6

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
	AimInput.set_virtual_gamepad(player, true)
	var floor_y := _floor_y_at(START_TILE * 16.0)
	await _strip("jog", Vector2.RIGHT, 0.7, floor_y, null)
	await _strip("backpedal", Vector2.LEFT, 1.0, floor_y, null)
	var chunk := _nearest_throwable()
	if chunk == null:
		_fail("%s 找不到可以拿的東西" % LEVEL)
	else:
		await _strip("carry", Vector2.RIGHT, 1.0, floor_y, chunk)
	print("RIN_GAITS %s" % JSON.stringify(_report))
	AimInput.set_virtual_gamepad(player, false)
	await finish()


## 倉庫上半部是實心的天花板（第 0～35 列），從開放空間（第 40 列）往下找地面。
func _floor_y_at(x: float) -> float:
	return level._layout.floor_below(int(x / 16.0), OPEN_ROW) - 2.0


func _nearest_throwable() -> Throwable:
	var best: Throwable
	for node in level.find_children("*", "Throwable", true, false):
		var item := node as Throwable
		if item != null and (best == null or item.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = item
	return best


func _strip(label: String, aim: Vector2, push: float, floor_y: float, carry_item: Throwable) -> void:
	Input.action_release(&"move_right")
	player.global_position = Vector2(START_TILE * 16.0, floor_y)
	player.velocity = Vector2.ZERO
	AimInput.restore_direction(aim)
	snap_camera()
	await wait(0.3)
	if carry_item != null:
		player.carry.pick(carry_item)
		await wait(0.6)
	Input.action_press(&"move_right", push)
	await wait(WARMUP)
	var speed := 0.0
	for i in FRAMES:
		speed = maxf(speed, absf(player.velocity.x))
		capture("NE-481-%s-%d" % [label, i])
		await wait(INTERVAL)
	Input.action_release(&"move_right")
	_report[label] = "%.0f px/s%s" % [speed, (", holding %s" % carry_item.data.id) if carry_item != null and player.carry.is_holding() else ""]
	if carry_item != null and not player.carry.is_holding():
		_fail("主角沒有拿起 %s" % carry_item.name)
	await wait(0.3)
	if carry_item != null:
		player.carry.put_down()


func _fail(message: String) -> void:
	failures += 1
	push_error("[RinGaitsScenario] " + message)
