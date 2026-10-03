extends Node
## 開發工具：實際渲染每一章的每個區段，量測暗場的可讀性（玩家輪廓與地面邊緣的對比），低於門檻就以非零代碼結束。
## 用法（需要可渲染的環境）：godot --path . res://tools/readability_check.tscn
## 量測方式：對每個區段截圖（隱藏 HUD），比較「玩家身體範圍」的亮部（第 90 百分位亮度，看輪廓與亮處）與
##   「周圍一圈」的平均亮度、「地面頂面亮邊」與「正下方 6 像素」的平均亮度。對比 = (內 − 外) / (外 + 0.02)。

## 要量測的關卡與取樣點 [名稱, 欄]。第一章設施入口後段是停電走廊，另外量測；
## 室內的關卡（有天花板）取樣高度用「從第 4 列往下的第一個地面」，第一章維持原本的規則。
const LEVELS: Array[Dictionary] = [
	{"path": "res://data/levels/level_01.tres", "spots": [["屋頂巷弄", 30], ["霓虹市集", 115], ["貨運站", 200], ["設施入口", 252], ["停電走廊", 275], ["頭目機庫", 330]]},
	{"path": "res://data/levels/level_02.tres", "spots": [["升降井入口", 30], ["升降井", 100], ["夾層區", 175], ["電力室", 240], ["轉運站", 285], ["回收員場地", 322]]},
]
const MIN_PLAYER_CONTRAST := 0.6
const MIN_EDGE_CONTRAST := 1.0
## 敵人（站在玩家前方 ENEMY_DISTANCE 像素、不動）的輪廓對比門檻（BG-13）。2026-10-04 新增量測時第一章各區段最低 0.46（貨運站），
## 這個值是「不得更差」的防線；要再提高得靠敵人本身的美術（輪廓光、自發光點），調光影參數沒有效果。
const MIN_ENEMY_CONTRAST := 0.45
const ENEMY_DISTANCE := 96.0
const PLAYER_BOX := Rect2(-9, -44, 18, 40)
const RING := 20.0
const SAMPLES := 8
const SAMPLE_INTERVAL := 0.2

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	# --level=level_01 只量測指定的關卡（開發時加快迭代）；--quality=low|medium|high 改用該光影品質檔位量測。
	var only := ""
	var original_quality := Settings.get_light_quality()  # 量測會暫時改設定檔裡的光影品質，結束時還原
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			Settings.set_light_quality({"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}.get(arg.trim_prefix("--quality="), LightQuality.Tier.HIGH))
		if arg.begins_with("--level="):
			only = arg.trim_prefix("--level=")
	for entry in LEVELS:
		if only == "" or str(entry["path"]).contains(only):
			await _check_level(entry["path"], entry["spots"])
	Settings.set_light_quality(original_quality)
	get_tree().quit(1 if _failed else 0)


func _check_level(path: String, spots: Array) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(path))
	add_child(level)
	for i in 20:
		await get_tree().process_frame
	var player := level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_") or id.begins_with("c2_radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	print("== %s" % path.get_file())
	print("%-8s  %-8s  %-8s  %-8s" % ["區段", "玩家對比", "邊緣對比", "敵人對比"])
	for spot: Array in spots:
		var tile: int = spot[1]
		var y := layout.surface_heights[tile] - 2.0
		# 室內區段最上面的「地面」是天花板：第一章改用檢查點的高度，其他關卡取第 4 列以下的第一個地面。
		if spot[0] == "設施入口" or spot[0] == "停電走廊" or spot[0] == "頭目機庫":
			y = layout.checkpoints[3].y - 2.0
		elif layout.surface_heights[tile] < layout.tile_size * 4.0:
			y = layout.floor_below(tile, 4) - 2.0
		player.global_position = Vector2(tile * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		for node in get_tree().get_nodes_in_group(&"enemies"):
			node.queue_free()
		for i in 60:
			await get_tree().process_frame
		var foe := _spawn_foe(level, player.global_position + Vector2(ENEMY_DISTANCE, 0.0))
		await get_tree().create_timer(1.2).timeout
		# 警報與霓虹會閃爍：連續取樣幾張取平均，量測才穩定。
		var player_contrast := 0.0
		var edge_contrast := 0.0
		var enemy_contrast := 0.0
		for sample in SAMPLES:
			var image := get_viewport().get_texture().get_image()
			var scale := float(image.get_width()) / get_viewport().get_visible_rect().size.x
			var to_screen := get_viewport().get_canvas_transform()
			var feet := player.global_position
			player_contrast += _contrast(image, scale, to_screen, Rect2(feet + PLAYER_BOX.position, PLAYER_BOX.size), RING) / float(SAMPLES)
			# 地面頂面亮邊：腳下 1~3 像素 vs 再往下 6~12 像素。
			var edge_rect := Rect2(feet + Vector2(-24, 0), Vector2(48, 3))
			var below_rect := Rect2(feet + Vector2(-24, 8), Vector2(48, 6))
			var below := _mean_luma(image, scale, to_screen, below_rect)
			edge_contrast += ((_mean_luma(image, scale, to_screen, edge_rect) - below) / (below + 0.02)) / float(SAMPLES)
			if is_instance_valid(foe):
				enemy_contrast += _contrast(image, scale, to_screen, Rect2(foe.global_position + PLAYER_BOX.position, PLAYER_BOX.size), RING) / float(SAMPLES)
			await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		var ok := player_contrast >= MIN_PLAYER_CONTRAST and edge_contrast >= MIN_EDGE_CONTRAST and enemy_contrast >= MIN_ENEMY_CONTRAST
		_failed = _failed or not ok
		print("%-8s  %-8.2f  %-8.2f  %-8.2f  %s" % [spot[0], player_contrast, edge_contrast, enemy_contrast, "OK" if ok else "太暗（門檻 %.1f / %.1f / %.1f）" % [MIN_PLAYER_CONTRAST, MIN_EDGE_CONTRAST, MIN_ENEMY_CONTRAST]])
	remove_child(level)
	level.free()
	await get_tree().process_frame


## 一隻站著不動的敵人（小兵），量測它的輪廓對比用。
func _spawn_foe(level: Level, position: Vector2) -> Enemy:
	var enemy := level._create_enemy(load("res://data/enemies/grunt.tres") as EnemyData)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.position = position
	enemy.facing = -1
	level._entities.add_child(enemy)
	enemy.health.setup(999, 0.0)
	return enemy


## 方框內與外圈（向外擴 ring 像素）平均亮度的對比：亮部比周圍亮多少，或身體比周圍暗多少（剪影），取較大者（BG-13）。
func _contrast(image: Image, scale: float, to_screen: Transform2D, box: Rect2, ring: float) -> float:
	var inner := _percentile_luma(image, scale, to_screen, box, 0.9)
	var outer_box := box.grow(ring)
	var outer_total := _luma_sum(image, scale, to_screen, outer_box) - _luma_sum(image, scale, to_screen, box)
	var outer_count := _pixel_count(scale, outer_box) - _pixel_count(scale, box)
	var outer := outer_total / maxf(1.0, outer_count)
	var bright := (inner - outer) / (outer + 0.02)
	# 暗的剪影站在較亮的背景前也看得見（輪廓清楚）：用身體的中位亮度量「比周圍暗多少」，兩種取較大者。
	var body := _percentile_luma(image, scale, to_screen, box, 0.5)
	var dark := (outer - body) / (outer + 0.02)
	return maxf(bright, dark)


## 方框內像素亮度的第 q 百分位（0~1）。
func _percentile_luma(image: Image, scale: float, to_screen: Transform2D, world_rect: Rect2, q: float) -> float:
	var rect := _screen_rect(scale, to_screen, world_rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var values: Array[float] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			values.append(LightKit.luminance(image.get_pixel(x, y)))
	if values.is_empty():
		return 0.0
	values.sort()
	return values[clampi(int(float(values.size() - 1) * q), 0, values.size() - 1)]


func _mean_luma(image: Image, scale: float, to_screen: Transform2D, world_rect: Rect2) -> float:
	return _luma_sum(image, scale, to_screen, world_rect) / maxf(1.0, _pixel_count(scale, world_rect))


func _screen_rect(scale: float, to_screen: Transform2D, world_rect: Rect2) -> Rect2i:
	var a := to_screen * world_rect.position * scale
	var b := to_screen * world_rect.end * scale
	return Rect2i(Vector2i(a.floor()), Vector2i((b - a).ceil()))


func _pixel_count(scale: float, world_rect: Rect2) -> float:
	return world_rect.size.x * scale * world_rect.size.y * scale


func _luma_sum(image: Image, scale: float, to_screen: Transform2D, world_rect: Rect2) -> float:
	var rect := _screen_rect(scale, to_screen, world_rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var total := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			total += LightKit.luminance(image.get_pixel(x, y))
	return total
