extends Node
## 地圖線的新路線實走（NE-419、NE-423）：在正式關卡裡用真的「跳」與「左右移動」輸入，一階一階走完新路線，
## 確認每一階都站得上去、獎勵真的被撿到、最後能走回地面（不卡在平台邊緣）。裂縫牆用真的開槍打開。
## 用法：godot --headless --fixed-fps 60 --path . res://tools/route_walk_probe.tscn [-- --route=ch3_office_hall]
## 每條路線一行 PASS／FAIL，有失敗以代碼 1 結束。新路線加在 ROUTES：
##   start：起點站立格；steps：[站立格, 要不要跳, 說明]；reward：拿到後信用點要增加；break_wall：先往右打開裂縫牆。

const ROUTES := {
	"ch3_office_hall": {"start": Vector2i(47, 19), "reward": true, "steps": [
		[Vector2i(50, 16), true, "右段的矮台"], [Vector2i(44, 13), true, "空調維修廊"],
		[Vector2i(18, 13), false, "維修廊左端的信用點"], [Vector2i(12, 19), false, "從左端落回取件格旁"]]},
	"ch3_clinic": {"start": Vector2i(93, 19), "reward": true, "break_wall": true, "steps": [
		[Vector2i(101, 19), false, "裂縫牆後的備品間"], [Vector2i(90, 19), false, "走回往門禁大廳的門"]]},
	"ch4_nursing_ward": {"start": Vector2i(33, 19), "reward": true, "steps": [
		[Vector2i(35, 17), true, "收音座左邊的矮台"], [Vector2i(42, 15), true, "靠窗的收音座"],
		[Vector2i(50, 11), true, "備品頂架"], [Vector2i(54, 11), false, "頂架盡頭的信用點"], [Vector2i(58, 19), false, "落回內廊門旁"]]},
	"ch4_factory_roof": {"start": Vector2i(33, 19), "reward": true, "steps": [
		[Vector2i(38, 15), true, "欄杆後的踏階"], [Vector2i(43, 12), true, "冷卻機維修平台"],
		[Vector2i(46, 12), false, "平台上的信用點"], [Vector2i(51, 19), false, "從平台右端落回屋頂"]]},
}
const STEP_FRAMES := 240

var _failures := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route="):
			_only = arg.trim_prefix("--route=")
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	for level_id: String in ROUTES:
		if _only.is_empty() or _only == level_id:
			await _walk(level_id, ROUTES[level_id])
	print("ROUTE_WALK failures=%d" % _failures)
	await AudioRelease.settle(get_tree())
	get_tree().quit(1 if _failures > 0 else 0)


func _walk(level_id: String, route: Dictionary) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load("res://data/levels/%s.tres" % level_id) as LevelData)
	add_child(level)
	await _frames(30)
	level._next_story_trigger = level._layout.story_triggers.size()
	var player: Player = level.player
	player.health.setup(9999, 0.0)
	var tile := float(level._layout.tile_size)
	var start: Vector2i = route["start"]
	player.global_position = Vector2((start.x + 0.5) * tile, (start.y + 1) * tile)
	player.velocity = Vector2.ZERO
	await _frames(20)
	var credits_before := Progression.credits
	if route.get("break_wall", false):
		await _break_wall(level, player)
	var ok := true
	for step: Array in route["steps"]:
		if not await _drive(level, step[0], step[1]):
			_fail("%s：走不到「%s」%s（主角停在 %s）" % [level_id, step[2], step[0], _cell_of(player, tile)])
			ok = false
			break
	if ok and route.get("reward", false) and Progression.credits <= credits_before:
		_fail("%s：走完路線但信用點沒有增加（%d）" % [level_id, Progression.credits])
		ok = false
	if ok:
		print("PASS %s：%s（信用點 %d → %d）" % [level_id, " → ".join(route["steps"].map(func(s: Array) -> String: return s[2])),
				credits_before, Progression.credits])
	_release_all()
	level.queue_free()
	await _frames(4)


## 往右瞄準連開槍，直到前面的裂縫牆被打破（最多約 6 秒）。
func _break_wall(level: Level, player: Player) -> void:
	var walls := func() -> int:
		var count := 0
		for node in level.find_children("*", "Breakable", true, false):
			if (node as Breakable).data.look == BreakableData.Look.WALL:
				count += 1
		return count
	var before: int = walls.call()
	AimInput.set_virtual_gamepad(player, true)   # 瞄準跟搖桿走，不跟（不存在的）滑鼠
	_set_input(&"aim_right", true)
	for i in 30:
		_set_input(&"shoot", true)
		await _frames(6)
		_set_input(&"shoot", false)
		await _frames(6)
		if walls.call() < before:
			break
	_set_input(&"aim_right", false)
	AimInput.set_virtual_gamepad(player, false)


func _drive(level: Level, cell: Vector2i, jump: bool) -> bool:
	var tile := float(level._layout.tile_size)
	var goal := Vector2((cell.x + 0.5) * tile, (cell.y + 1) * tile)
	var player: Player = level.player
	_set_input(&"jump", jump)
	var reached := false
	for frame in STEP_FRAMES:
		var offset := goal.x - player.global_position.x
		_set_input(&"move_left", offset < -4.0)
		_set_input(&"move_right", offset > 4.0)
		await get_tree().physics_frame
		if frame > 3 and absf(offset) <= 4.0 and player.is_on_floor() and absf(player.global_position.y - goal.y) < 2.0:
			reached = true
			break
		# 跳起來之後放開，落地再按，才不會一直按著同一下。
		if jump and player.is_on_floor() and frame > 20 and player.global_position.y > goal.y + 2.0:
			_set_input(&"jump", false)
			await get_tree().physics_frame
			_set_input(&"jump", true)
	_release_all()
	await get_tree().physics_frame
	return reached


func _cell_of(player: Player, tile: float) -> Vector2i:
	return Vector2i(int(player.global_position.x / tile), int(player.global_position.y / tile) - 1)


func _set_input(action: StringName, active: bool) -> void:
	if active and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not active and Input.is_action_pressed(action):
		Input.action_release(action)


func _release_all() -> void:
	for action in [&"jump", &"move_left", &"move_right", &"shoot", &"aim_right"]:
		_set_input(action, false)


func _fail(message: String) -> void:
	_failures += 1
	print("FAIL %s" % message)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
