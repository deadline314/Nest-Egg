extends Node
## 鏡頭走查（NE-256）：在正式關卡上用真正的關卡鏡頭，逐關量三件事——
##   1. 往下跳的地方：站在平台邊緣面向落差，落點看不看得到；看不到時往斜下方瞄準看不看得到。
##   2. 要跳上去的單向平台：站在平台兩端外側的地面上面向它，平台的端點看不看得到。
##   3. 敵人：主角站在敵人出手距離的邊緣（左右各一次），面向敵人與背對敵人各等 1.5 秒，敵人在不在畫面裡。
## 主角用瞄準方向決定面向（和實際操作一樣，瞄準會帶動鏡頭）；量 1、2 時敵人停住，量 3 時敵人照常行動，主角不會受傷。
## 這是鏡頭與地圖的量測，不是實際打一輪：敵人出現的節奏、手感仍要人玩過。
## 用法（不需要顯示卡）：
##   godot --headless --fixed-fps 60 --path . res://tools/camera_walk_probe.tscn -- --out=<絕對資料夾>
##     [--level=ch1_street,ch1_warehouse] [--profile=level_wide] [--tag=<名稱>]
##   --profile=level_wide 用拉近前的鏡頭設定重量一次，兩份結果可以對照。
## 輸出 <tag>-camera-walk.json，並逐關印一行摘要。

const DEFAULT_LEVELS := ["ch1_prologue", "ch1_pawnshop", "ch1_rooftop", "ch1_street", "ch1_booth_alley", "ch1_warehouse", "ch1_vault",
		"ch1_handoff", "ch1_lounge", "ch1_stall"]
const SETTLE_FRAMES := 50
const ENEMY_SETTLE_FRAMES := 90
## 落差至少幾格才算「往下跳」（1 格是台階）。
const MIN_DROP_TILES := 2
## 看得到的判定留一點邊：貼著畫面邊緣的那幾個像素不算看得到。
const VIEW_MARGIN := 6.0
const HEADROOM := 3

var _out := ""
var _tag := "level"
var _levels: PackedStringArray = []
var _profile := &""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--level="):
			_levels = arg.trim_prefix("--level=").split(",", false)
		elif arg.begins_with("--profile="):
			_profile = StringName(arg.trim_prefix("--profile="))
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	if _levels.is_empty():
		_levels = PackedStringArray(DEFAULT_LEVELS)
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[CameraWalkProbe] --out 必須是可建立的絕對路徑：%s" % _out)
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	Story.auto_skip = true
	var report: Array[Dictionary] = []
	for level_id in _levels:
		var path := "res://data/levels/%s.tres" % level_id
		if not ResourceLoader.exists(path):
			push_error("[CameraWalkProbe] 找不到關卡：%s" % path)
			continue
		report.append(await _walk(level_id, load(path) as LevelData))
	var file := FileAccess.open(_out.path_join("%s-camera-walk.json" % _tag), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"profile": String(_profile), "levels": report}, "  "))
	_release_aim()
	get_tree().quit(0)


func _walk(level_id: String, data: LevelData) -> Dictionary:
	GameState.start_new_run(GameState.difficulties[1])
	Enemy.activation_culling_enabled = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	await _frames(30)
	var player := level.player
	player.health.setup(9999, 0.0)
	player.health.grant_invulnerability(100000.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	AimInput.set_virtual_gamepad(player, true)
	var camera := get_viewport().get_camera_2d() as LevelCamera
	if camera == null:
		push_error("[CameraWalkProbe] %s 沒有關卡鏡頭" % level_id)
		level.queue_free()
		return {"level": level_id, "error": "no camera"}
	if _profile != &"":
		camera.tuning = CameraTuning.profile(_profile)
	var layout: LevelLayout = level._layout
	# 遭遇區的敵人要主角走進去才會出現：先沿著每一層地面走一遍把牠們都叫出來，再開始量。
	for y in range(1, layout.height - 1):
		for x in range(2, layout.width - 2, 6):
			if _standable(layout, x, y):
				player.global_position = Vector2((x + 0.5) * layout.tile_size, (y + 1) * layout.tile_size)
				player.velocity = Vector2.ZERO
				await _frames(3)
	var enemies: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node is Enemy and not node is PatternBoss:
			enemies.append(node)
	for enemy in enemies:
		enemy.set_physics_process(false)
	var result := {"level": level_id, "zoom": camera.tuning.zoom, "enemies": enemies.size()}
	result.merge(await _measure_drops(layout, player, camera))
	result.merge(await _measure_platforms(layout, player, camera))
	for enemy in enemies:
		enemy.set_physics_process(true)
	result.merge(await _measure_enemies(layout, player, camera, enemies))
	print("CAMERA_WALK %s drops %d blind %d (aim-down still blind %d) | platforms %d hidden %d | enemies %d: facing unseen %d, back turned unseen %d" % [
			level_id, result["drops"], result["drops_blind"], result["drops_blind_aiming_down"], result["platforms"], result["platforms_hidden"],
			result["enemy_samples"], result["enemy_unseen_facing"], result["enemy_unseen_back"]])
	_release_aim()
	level.queue_free()
	await _frames(6)
	return result


## 往下跳的地方：站得住的格子，旁邊一格是空的、而且腳下沒有地面。
func _measure_drops(layout: LevelLayout, player: Player, camera: LevelCamera) -> Dictionary:
	var total := 0
	var blind := 0
	var blind_aim := 0
	var worst: Array[Dictionary] = []
	for y in range(1, layout.height - 1):
		for x in range(1, layout.width - 1):
			if not _standable(layout, x, y):
				continue
			for dir: int in [-1, 1]:
				var nx := x + dir
				if nx < 1 or nx >= layout.width - 1 or not _empty(layout, nx, y) or _is_floor(layout, nx, y + 1):
					continue
				var land_y := layout.floor_below(nx, y + 1)
				if land_y == INF:
					continue  # 掉出地圖的坑不是「落點」
				var drop_tiles := int(land_y / layout.tile_size) - (y + 1)
				if drop_tiles < MIN_DROP_TILES:
					continue
				total += 1
				var landing := Vector2((nx + 0.5) * layout.tile_size, land_y)
				await _stand(player, layout, x, y, Vector2(dir, 0))
				if _visible(camera, landing):
					continue
				blind += 1
				await _stand(player, layout, x, y, Vector2(dir * 0.6, 0.8))
				var still := not _visible(camera, landing)
				if still:
					blind_aim += 1
				if worst.size() < 12:
					worst.append({"tile": [x, y], "dir": dir, "drop_tiles": drop_tiles, "visible_aiming_down": not still})
	return {"drops": total, "drops_blind": blind, "drops_blind_aiming_down": blind_aim, "drops_blind_list": worst}


## 單向平台：每一段平台的左右端，站在外側兩格的地面上面向它。
func _measure_platforms(layout: LevelLayout, player: Player, camera: LevelCamera) -> Dictionary:
	var total := 0
	var hidden := 0
	var worst: Array[Dictionary] = []
	for y in range(1, layout.height - 1):
		var x := 1
		while x < layout.width - 1:
			if layout.cell(x, y) != "=":
				x += 1
				continue
			var start := x
			while x < layout.width - 1 and layout.cell(x, y) == "=":
				x += 1
			var ends := [[start, -1], [x - 1, 1]]
			for pair: Array in ends:
				var end_x: int = pair[0]
				var side: int = pair[1]
				var stand_x := end_x + side * 2
				if stand_x < 1 or stand_x >= layout.width - 1:
					continue
				var floor_y := layout.floor_below(stand_x, y)
				if floor_y == INF:
					continue
				var stand_y := int(floor_y / layout.tile_size) - 1
				var rise := stand_y + 1 - y
				if rise < 2 or rise > 6 or not _standable(layout, stand_x, stand_y):
					continue  # 太低是台階、太高跳不上去
				total += 1
				await _stand(player, layout, stand_x, stand_y, Vector2(-side, 0))
				if not _visible(camera, Vector2((end_x + 0.5) * layout.tile_size, y * layout.tile_size)):
					hidden += 1
					if worst.size() < 12:
						worst.append({"platform_end": [end_x, y], "from": [stand_x, stand_y], "rise_tiles": rise})
	return {"platforms": total, "platforms_hidden": hidden, "platforms_hidden_list": worst}


## 敵人：主角站在牠出手距離的邊緣，面向牠與背對牠各一次，等鏡頭與敵人反應之後看牠在不在畫面裡。
func _measure_enemies(layout: LevelLayout, player: Player, camera: LevelCamera, enemies: Array[Enemy]) -> Dictionary:
	var samples := 0
	var unseen_facing := 0
	var unseen_back := 0
	var worst: Array[Dictionary] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.data == null:
			continue
		var home := enemy.global_position
		var reach := enemy.data.attack_range if enemy.data.attack_range > 0.0 else enemy.data.detect_range
		if reach <= 0.0:
			continue
		for side: int in [-1, 1]:
			var x := int((home.x + side * (reach - 8.0)) / layout.tile_size)
			# 敵人的腳底可能差零點幾像素沒貼齊格線，先四捨五入到最近的地面列。
			var y := roundi(home.y / layout.tile_size) - 1
			if x < 1 or x >= layout.width - 1 or not _standable(layout, x, y):
				continue
			for toward: bool in [true, false]:
				if not is_instance_valid(enemy):
					break
				enemy.global_position = home
				var aim := Vector2(-side if toward else side, 0)
				await _stand(player, layout, x, y, aim, ENEMY_SETTLE_FRAMES)
				if not is_instance_valid(enemy):
					break
				samples += 1
				var seen := _visible(camera, enemy.global_position + Vector2(0, -enemy.data.body_size.y * 0.5))
				if seen:
					continue
				if toward:
					unseen_facing += 1
				else:
					unseen_back += 1
				if worst.size() < 12:
					worst.append({"enemy": String(enemy.data.id), "enemy_tile": [int(home.x / layout.tile_size), int(home.y / layout.tile_size)],
							"player_tile": [x, y], "facing_enemy": toward, "distance": snappedf(absf(enemy.global_position.x - player.global_position.x), 1.0),
							"engaged": enemy.is_engaged()})
	return {"enemy_samples": samples, "enemy_unseen_facing": unseen_facing, "enemy_unseen_back": unseen_back, "enemy_unseen_list": worst}


func _stand(player: Player, layout: LevelLayout, x: int, y: int, aim: Vector2, frames := SETTLE_FRAMES) -> void:
	player.global_position = Vector2((x + 0.5) * layout.tile_size, (y + 1) * layout.tile_size)
	player.velocity = Vector2.ZERO
	_aim(aim)
	await _frames(frames)


func _visible(camera: LevelCamera, point: Vector2) -> bool:
	var half := get_viewport().get_visible_rect().size * 0.5 / camera.zoom
	var center := camera.get_screen_center_position()
	return Rect2(center - half, half * 2.0).grow(-VIEW_MARGIN).has_point(point)


func _is_floor(layout: LevelLayout, x: int, y: int) -> bool:
	var c := layout.cell(x, y)
	return c == "#" or c == "="


func _empty(layout: LevelLayout, x: int, y: int) -> bool:
	return layout.cell(x, y) != "#"


func _standable(layout: LevelLayout, x: int, y: int) -> bool:
	if not _is_floor(layout, x, y + 1):
		return false
	for k in HEADROOM:
		if layout.cell(x, y - k) == "#":
			return false
	return true


func _aim(direction: Vector2) -> void:
	for pair: Array in [[&"aim_right", maxf(0.0, direction.x)], [&"aim_left", maxf(0.0, -direction.x)], [&"aim_down", maxf(0.0, direction.y)], [&"aim_up", maxf(0.0, -direction.y)]]:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])


func _release_aim() -> void:
	for action: StringName in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		Input.action_release(action)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
