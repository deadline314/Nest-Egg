extends Node
## 開發工具：實際渲染每一章的每個區段，量測暗場的可讀性（玩家輪廓與地面邊緣的對比），低於門檻就以非零代碼結束。
## 用法（需要可渲染的環境）：godot --path . res://tools/readability_check.tscn
## 量測方式：對每個區段截圖（隱藏 HUD），比較「玩家身體範圍」的亮部（第 90 百分位亮度，看輪廓與亮處）與
##   「周圍一圈」的平均亮度、「地面頂面亮邊」與「正下方 6 像素」的平均亮度。對比 = (內 − 外) / (外 + 0.02)。

## 要量測的關卡與取樣點 [名稱, 欄]。第一章設施入口後段是停電走廊，另外量測；
## 室內的關卡（有天花板）取樣高度用「從第 4 列往下的第一個地面」，第一章維持原本的規則。
const LEVELS: Array[Dictionary] = [
	{"path": "res://data/levels/level_01.tres", "spots": [["屋頂巷弄", 30], ["霓虹市集", 115], ["貨運站", 200], ["設施入口", 252], ["停電走廊", 275], ["頭目機庫", 330]]},
	{"path": "res://data/levels/level_02.tres", "spots": [["升降井入口", 30], ["升降井", 100, 14, 108], ["夾層區", 175], ["中庭", 232], ["回收燈幕", 304], ["電力室", 350, 20, 356], ["看守長場地", 400], ["轉運站", 425], ["病房區", 455], ["回收員場地", 492]]},
]
## 門檻與量測範圍見 ContrastProbe（與光影預設場景量測共用）。敵人站在玩家前方 ENEMY_DISTANCE 像素、不動。
const ENEMY_DISTANCE := 96.0
const SAMPLES := 16
const SAMPLE_INTERVAL := 0.2

var _failed := false
var _out_dir := ""
var _capture_prefix := "ST-6"
var _results: Array[Dictionary] = []
## --spots=夾層區,中庭：只量測指定名稱的取樣點（開發時加快迭代）。
var _only_spots: PackedStringArray = []


## Subclasses provide campaign targets while sharing the exact probe and thresholds.
func targets() -> Array[Dictionary]:
	return LEVELS


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	AimInput.using_gamepad = true
	AimInput._last_stick_dir = Vector2.RIGHT
	# --level=level_01 只量測指定的關卡（開發時加快迭代）；--quality=low|medium|high 改用該光影品質檔位量測。
	var only := ""
	var original_quality := Settings.get_light_quality()  # 量測會暫時改設定檔裡的光影品質，結束時還原
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			Settings.set_light_quality({"low": LightQuality.Tier.LOW, "medium": LightQuality.Tier.MEDIUM, "high": LightQuality.Tier.HIGH}.get(arg.trim_prefix("--quality="), LightQuality.Tier.HIGH))
		if arg.begins_with("--level="):
			only = arg.trim_prefix("--level=")
		if arg.begins_with("--spots="):
			_only_spots = arg.trim_prefix("--spots=").split(",", false)
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--capture-prefix="):
			_capture_prefix = arg.trim_prefix("--capture-prefix=").get_file()
	if not _out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var matched := 0
	for entry in targets():
		if only == "" or str(entry["path"]).contains(only):
			matched += 1
			await _check_level(entry["path"], entry["spots"], str(entry.get("enemy_path", "res://data/enemies/grunt.tres")))
	if matched == 0 or _results.is_empty():
		printerr("[readability_check] No sample matches --level=%s / --spots=%s" % [only, _only_spots])
		_failed = true
	if not _out_dir.is_empty():
		var report := FileAccess.open(_out_dir.path_join("readability-report.json"), FileAccess.WRITE)
		if report == null:
			printerr("[readability_check] Cannot write report to %s" % _out_dir)
			_failed = true
		else:
			report.store_string(JSON.stringify({"version": 1, "engine": Engine.get_version_info().string,
				"light_quality": Settings.get_light_quality(), "brightness": Settings.get_brightness(),
				"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
				"samples_per_spot": SAMPLES, "sample_interval": SAMPLE_INTERVAL,
				"screenshot_encoding": "sRGB", "contrast_encoding": "native viewport (linear HDR)",
				"thresholds": {"player": ContrastProbe.MIN_PLAYER_CONTRAST, "edge": ContrastProbe.MIN_EDGE_CONTRAST, "enemy": ContrastProbe.MIN_ENEMY_CONTRAST},
				"results": _results}, "  ") + "\n")
			report.close()
	Settings.set_light_quality(original_quality)
	get_tree().quit(1 if _failed else 0)


func _check_level(path: String, spots: Array, enemy_path := "res://data/enemies/grunt.tres") -> void:
	GameState.start_new_run(GameState.difficulties[1])
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var data := (load(path) as LevelData).duplicate()
	data.intro_scene = &""
	data.show_chapter_card = false
	var level := Level.new()
	level.configure(data)
	add_child(level)
	# The rendering lab measures stationary silhouettes, not a combat encounter.
	# Keep lighting events active, but prevent boss/wave spawns from pushing a probe.
	level._arena_triggered = true
	for node in level.find_children("*", "", true, false):
		if node is EncounterZone:
			node.restore_state(true)
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
	# Prompts are UI; their bright text must not inflate the body contrast.
	for node in level.find_children("*", "", true, false):
		if node is WorldPrompt:
			node.visible = false
	var layout: LevelLayout = level._layout
	print("== %s" % path.get_file())
	print("%-8s  %-8s  %-8s  %-8s" % ["區段", "玩家對比", "邊緣對比", "敵人對比"])
	for spot: Array in spots:
		if not _only_spots.is_empty() and not _only_spots.has(str(spot[0])):
			continue
		var tile: int = spot[1]
		if tile < 0 or tile * layout.tile_size >= layout.pixel_size().x:
			printerr("[readability_check] %s/%s: column %d is outside the map" % [path, spot[0], tile])
			_failed = true
			continue
		var y := probe_floor(layout, tile, str(spot[0])) - 2.0
		if spot.size() > 2:
			var row := int(spot[2])
			if not layout.cell(tile, row) in ["#", "="]:
				printerr("[readability_check] %s/%s: explicit floor %d/%d has no support" % [path, spot[0], tile, row])
				_failed = true
				continue
			y = float(row) * layout.tile_size - 2.0
		player.global_position = Vector2(tile * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		for node in get_tree().get_nodes_in_group(&"enemies"):
			node.queue_free()
		for i in 60:
			await get_tree().process_frame
		var camera := get_viewport().get_camera_2d() as LevelCamera
		if camera != null:
			camera.snap_to_target()
		var foe: Enemy = null
		var foe_tile := int(spot[3]) if spot.size() > 3 else tile + int(ENEMY_DISTANCE / layout.tile_size)
		var expected_foe_feet := Vector2(foe_tile * layout.tile_size + 8.0, y + 2.0)
		if not enemy_path.is_empty():
			# Legacy probes can put the enemy on a lower, adjacent roof.
			# Validate each actor against its own floor instead of assuming flat ground.
			if spot.size() <= 2:
				expected_foe_feet.y = probe_floor(layout, foe_tile, str(spot[0]))
			foe = _spawn_foe(level, expected_foe_feet - Vector2(0.0, 2.0), enemy_path)
		await get_tree().create_timer(1.2).timeout
		# 警報與霓虹會閃爍：連續取樣幾張取平均，量測才穩定。
		var player_contrast := 0.0
		var edge_contrast := 0.0
		var enemy_contrast := 0.0
		for sample in SAMPLES:
			var probe := ContrastProbe.capture(get_viewport())
			player_contrast += probe.character_contrast(player.global_position) / float(SAMPLES)
			edge_contrast += probe.edge_contrast(player.global_position) / float(SAMPLES)
			if is_instance_valid(foe):
				enemy_contrast += probe.character_contrast(foe.global_position) / float(SAMPLES)
			await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		var expected_feet := Vector2(tile * layout.tile_size + 8.0, y + 2.0)
		var standing := player.global_position.distance_to(expected_feet) <= 4.0
		if not enemy_path.is_empty():
			standing = standing and is_instance_valid(foe) and foe.global_position.distance_to(expected_foe_feet) <= 4.0
		if not standing:
			printerr("[readability_check] %s/%s: invalid floor sample; player=%s expected=%s enemy=%s expected=%s" % [path, spot[0], player.global_position, expected_feet, str(foe.global_position) if is_instance_valid(foe) else "missing", expected_foe_feet])
		var ok := standing and player_contrast >= ContrastProbe.MIN_PLAYER_CONTRAST and edge_contrast >= ContrastProbe.MIN_EDGE_CONTRAST and (enemy_path.is_empty() or (is_instance_valid(foe) and enemy_contrast >= ContrastProbe.MIN_ENEMY_CONTRAST))
		_failed = _failed or not ok
		var result_label := "取樣無效" if not standing else ("OK" if ok else "太暗（門檻 %.2f / %.2f / %.2f）" % [ContrastProbe.MIN_PLAYER_CONTRAST, ContrastProbe.MIN_EDGE_CONTRAST, ContrastProbe.MIN_ENEMY_CONTRAST])
		print("%-8s  %-8.2f  %-8.2f  %-8s  %s" % [spot[0], player_contrast, edge_contrast, "%.2f" % enemy_contrast if not enemy_path.is_empty() else "N/A", result_label])
		var shot := "%s-%s-%d.png" % [_capture_prefix, data.id, tile]
		if not _out_dir.is_empty():
			# Keep ContrastProbe's linear HDR samples; only encode review PNGs for display.
			var capture_error := preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(_out_dir.path_join(shot))
			if capture_error != OK:
				printerr("[readability_check] %s: %s" % [shot, error_string(capture_error)])
				_failed = true
		var materials: Array[String] = []
		if data.environment != null:
			for zone: EnvZone in data.environment.zones:
				materials.append(zone.material.resource_path)
		_results.append({"level": String(data.id), "path": path, "spot": spot[0], "column": tile, "sampling_valid": standing,
			"feet": [player.global_position.x, player.global_position.y], "enemy": enemy_path,
			"enemy_column": foe_tile, "expected_enemy_feet": [expected_foe_feet.x, expected_foe_feet.y],
			"enemy_feet": [foe.global_position.x, foe.global_position.y] if is_instance_valid(foe) else null,
			"player_contrast": player_contrast, "edge_contrast": edge_contrast,
			"enemy_contrast": enemy_contrast if not enemy_path.is_empty() else null, "passed": ok,
			"theme": data.environment.resource_path if data.environment != null else "",
			"materials": materials, "props": data.load_props(), "screenshot": shot})
	remove_child(level)
	level.free()
	await get_tree().process_frame


## 一隻站著不動的敵人（小兵），量測它的輪廓對比用。
func _spawn_foe(level: Level, position: Vector2, path := "res://data/enemies/grunt.tres") -> Enemy:
	var data := load(path) as EnemyData
	if data == null:
		push_error("[readability_check] Missing enemy probe: %s" % path)
		return null
	var enemy := level._create_enemy(data)
	enemy.data = enemy.data.duplicate()
	enemy.data.detect_range = 0.0
	enemy.data.attack_range = 0.0
	enemy.data.move_speed = 0.0
	enemy.position = position
	enemy.facing = -1
	level._entities.add_child(enemy)
	enemy.health.setup(999, 0.0)
	return enemy


## The legacy maps use roofs of different heights and indoor ceilings.
static func probe_floor(layout: LevelLayout, tile: int, spot: String) -> float:
	if tile < 0 or tile >= layout.surface_heights.size():
		return -INF
	if spot in ["設施入口", "停電走廊", "頭目機庫"]:
		return layout.checkpoints[3].y
	var floor_y := layout.surface_heights[tile]
	return layout.floor_below(tile, 4) if floor_y < layout.tile_size * 4.0 else floor_y
