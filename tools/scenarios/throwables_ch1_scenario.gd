class_name ThrowablesCh1Scenario
extends ScenarioBase
## 連續畫面（NE-254）：在正式第一章的地圖上，用地圖本來就擺好的投擲物與油桶演一遍——
## 街道廣場（撿木箱丟清掃兵、射油桶）、街道路障（撿鐵管斜丟高台上的槍手）、
## 碼頭倉庫前廳（撿木箱丟貨櫃頂的槍手、射看門狗地盤旁的油桶）。
## 物件不是工具放的：每一段先在地圖裡找最近的那一件，找不到就報錯並跳過那一段。
## 為了看得清楚每一格在做什麼，敵人站在地圖原本的位置不行動（照樣會受傷、被炸死），主角不會受傷，
## 沿路的通訊與鎖場遭遇先關掉（它們會凍結世界或加派敵人）。其餘都是正式關卡的資料、擺放與光影。
## 敵人會動、會開火時的互動（受傷會掉東西、拿著時衝刺與格擋）由 ThrowablesSuite 的自動測試驗。
## 用法（原生 Forward+）：
##   godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=throwables_ch1 [--pad] [--only=plaza,barricade,foyer]
##   --pad：改送真正的手把按鍵與搖桿事件（合成裝置，提示會換成手把按鍵；不是實體手把驗收）。
## 每 FRAME_GAP 秒存一格：NE-254-ch1-<段>[-pad]-<序號>.png。

const FRAME_GAP := 0.14
const STREET := "res://data/levels/ch1_street.tres"
const WAREHOUSE := "res://data/levels/ch1_warehouse.tres"
const SYNTHETIC_DEVICE := 999
## 每一段：關卡、主角起點（欄）、依序要撿起來丟的東西 [種類, 它在地圖上的欄, 丟向哪一欄哪一列附近的敵人]、
## 之後要用槍射的油桶在哪一欄（-1＝不射）與站在哪一欄射。
const BEATS := [
	{"id": "plaza", "level": STREET, "start": 93.0, "barrel_tile": -1, "shoot_from": 0.0,
		"throws": [[&"crate_small", 95, Vector2(98, 19)], [&"fuel_barrel", 104, Vector2(111, 19)]]},
	{"id": "barricade", "level": STREET, "start": 153.0, "barrel_tile": -1, "shoot_from": 0.0,
		"throws": [[&"pipe", 155, Vector2(166, 14)]]},
	{"id": "foyer", "level": WAREHOUSE, "start": 41.5, "barrel_tile": 56, "shoot_from": 51.0,
		"throws": [[&"crate_small", 43, Vector2(47, 13)]]},
]

var _use_pad := false
var _only: PackedStringArray = []
var _filming := false
var _film_tag := ""
var _film_index := 0
var _film_left := 0.0
var _hold_left := 0.0


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--pad":
			_use_pad = true
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	Enemy.activation_culling_enabled = false
	var previous_gamepad := InputBindings.using_gamepad
	var previous_device := InputBindings.active_device
	var previous_aim := AimInput.using_gamepad
	for beat: Dictionary in BEATS:
		if not _only.is_empty() and not _only.has(str(beat["id"])):
			continue
		await _play(beat)
	InputBindings._set_device(previous_gamepad, previous_device)
	AimInput.using_gamepad = previous_aim
	await finish()


func _process(delta: float) -> void:
	# 敵人（含晚一點才生成的）停在原地：只停掉行動的那一段，受擊、血量與死亡照常。
	_hold_left -= delta
	if _hold_left <= 0.0 and level != null:
		_hold_left = 0.25
		for node in get_tree().get_nodes_in_group(&"enemies"):
			if node.is_physics_processing():
				node.set_physics_process(false)
	if not _filming:
		return
	_film_left -= delta
	if _film_left <= 0.0:
		_film_left = FRAME_GAP
		capture("%s-%02d" % [_film_tag, _film_index])
		_film_index += 1


func _play(beat: Dictionary) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(str(beat["level"])) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(9999, 0.0)
	player.health.grant_invulnerability(600.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	for zone in level.find_children("*", "EncounterZone", true, false):
		zone.queue_free()
	var start_tile: float = beat["start"]
	player.global_position = Vector2(start_tile * 16.0, level._layout.floor_below(int(start_tile), 10))
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	if not _use_pad:
		AimInput.set_virtual_gamepad(player, true)
	_film_tag = "NE-254-ch1-%s%s" % [beat["id"], "-pad" if _use_pad else ""]
	_film_index = 0
	_film_left = 0.0
	_filming = true
	await wait(0.4)
	for step: Array in beat["throws"]:
		await _pick_and_throw(beat, step[0], int(step[1]), step[2])
	# 射油桶：走到射擊位置，朝油桶開槍，等引信燒完爆炸。
	var barrel_tile: int = beat["barrel_tile"]
	if barrel_tile >= 0:
		var barrel := _nearest_throwable(&"fuel_barrel", barrel_tile)
		if barrel == null:
			push_error("[ThrowablesCh1] %s 第 %d 欄附近找不到油桶" % [beat["level"], barrel_tile])
		else:
			await _walk_to(float(beat["shoot_from"]) * 16.0)
			_aim((barrel.global_position + Vector2(0.0, -10.0) - (player.global_position + Vector2(0.0, -30.0))).normalized())
			await wait(0.25)
			for i in 8:
				if not is_instance_valid(barrel) or barrel._fuse_left > 0.0:
					break
				await _tap(&"shoot")
				await wait(0.18)
			for i in 90:
				if not is_instance_valid(barrel):
					break
				await get_tree().physics_frame
			await wait(0.9)
			_aim(Vector2.ZERO)
	_filming = false
	await _close()


## 走到物件旁邊（真的走過去，不是瞬移）撿起來，舉著對準目標停一下（看得到拋物線與落點），丟出去。
func _pick_and_throw(beat: Dictionary, kind: StringName, pick_tile: int, target_tile: Vector2) -> void:
	var item := _nearest_throwable(kind, pick_tile)
	if item == null:
		push_error("[ThrowablesCh1] %s 第 %d 欄附近找不到 %s，跳過這一項" % [beat["level"], pick_tile, kind])
		return
	await _walk_to(item.global_position.x - 6.0)
	await _tap(&"interact")
	for i in 60:
		if player.carry.phase == PlayerCarry.Phase.HOLDING:
			break
		await get_tree().physics_frame
	if not player.carry.is_holding():
		push_error("[ThrowablesCh1] %s：按互動鍵後沒有撿起 %s（主角在 %s，物件在 %s）" % [beat["id"], kind, player.global_position, item.global_position])
		return
	var target := _nearest_enemy(target_tile * 16.0)
	var aim_at := target.global_position + Vector2(0.0, -24.0) if target != null else target_tile * 16.0
	_aim(_throw_direction(aim_at))
	await wait(1.0)
	await _tap(&"shoot")
	await wait(1.3)
	_aim(Vector2.ZERO)


func _close() -> void:
	_filming = false
	_release_all()
	if player != null:
		AimInput.set_virtual_gamepad(player, false)
	level.queue_free()
	await settle(6)
	level = null
	player = null


func _nearest_throwable(kind: StringName, tile: int) -> Throwable:
	var best: Throwable = null
	var best_distance := 48.0
	for node in get_tree().get_nodes_in_group(Throwable.GROUP):
		var item := node as Throwable
		if item == null or item.data == null or item.data.id != kind or item.state != Throwable.State.REST:
			continue
		var distance := absf(item.global_position.x - (tile * 16.0 + 8.0))
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


func _nearest_enemy(at: Vector2) -> Enemy:
	var best: Enemy = null
	var best_distance := 96.0
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.health == null or enemy.health.current <= 0:
			continue
		var distance := enemy.global_position.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## 往目標丟要瞄的方向：目標越遠、越高，仰角越大（玩家實際操作時是看著拋物線調的，這裡用同樣的預覽找角度）。
func _throw_direction(target: Vector2) -> Vector2:
	var origin := player.global_position + Vector2(0.0, -40.0)
	var flat := (target - origin).normalized()
	var best := flat
	var best_miss := INF
	for step in 13:
		var candidate := flat.rotated(-deg_to_rad(step * 5.0) * signf(flat.x if flat.x != 0.0 else 1.0))
		var miss := _arc_miss(origin, candidate, target)
		if miss < best_miss:
			best_miss = miss
			best = candidate
	return best


func _arc_miss(origin: Vector2, direction: Vector2, target: Vector2) -> float:
	var data := player.carry.held.data if player.carry.is_holding() else null
	if data == null:
		return origin.distance_to(target)
	var position := origin
	var velocity := direction * data.throw_speed
	var miss := INF
	for i in 90:
		velocity.y += data.gravity / 60.0
		position += velocity / 60.0
		miss = minf(miss, position.distance_to(target))
	return miss


func _walk_to(x: float) -> void:
	var action: StringName = &"move_right" if x > player.global_position.x else &"move_left"
	if absf(x - player.global_position.x) < 3.0:
		return
	_hold(action, true)
	var last_x := player.global_position.x
	var stuck := 0
	var jump_left := 0
	for i in 420:
		if (action == &"move_right" and player.global_position.x >= x) or (action == &"move_left" and player.global_position.x <= x):
			break
		await get_tree().physics_frame
		# 被貨櫃、路障擋住就跳過去（和玩家會做的一樣）。
		stuck = stuck + 1 if absf(player.global_position.x - last_x) < 0.2 else 0
		last_x = player.global_position.x
		if jump_left > 0:
			jump_left -= 1
			if jump_left == 0:
				_hold(&"jump", false)
		elif stuck > 6 and player.is_on_floor():
			_hold(&"jump", true)
			jump_left = 16
			stuck = 0
	_hold(&"jump", false)
	_hold(action, false)
	await wait(0.12)


## 以下三個函式是輸入：預設直接送動作並用虛擬搖桿瞄準；--pad 時送真正的手把事件，經過按鍵綁定才變成動作。
func _tap(action: StringName) -> void:
	_hold(action, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_hold(action, false)
	await get_tree().physics_frame


func _hold(action: StringName, pressed: bool) -> void:
	if not _use_pad:
		if pressed:
			Input.action_press(action)
		else:
			Input.action_release(action)
		return
	if InputBindings.JOY_AXES.has(action) and InputBindings.get_joy_button(action) < 0:
		var axis: Array = InputBindings.JOY_AXES[action]
		_joy_axis(axis[0], float(axis[1]) if pressed else 0.0)
	elif InputBindings.JOY_AXES.has(action) and action in [&"move_left", &"move_right"]:
		var stick: Array = InputBindings.JOY_AXES[action]
		_joy_axis(stick[0], float(stick[1]) if pressed else 0.0)
	else:
		var event := InputEventJoypadButton.new()
		event.device = SYNTHETIC_DEVICE
		event.button_index = InputBindings.get_joy_button(action) as JoyButton
		event.pressed = pressed
		Input.parse_input_event(event)


func _aim(direction: Vector2) -> void:
	if _use_pad:
		_joy_axis(JOY_AXIS_RIGHT_X, direction.x)
		_joy_axis(JOY_AXIS_RIGHT_Y, direction.y)
		return
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = SYNTHETIC_DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _release_all() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump", &"shoot", &"interact"]:
		_hold(action, false)
	_aim(Vector2.ZERO)
