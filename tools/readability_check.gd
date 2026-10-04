extends Node
## 開發工具：實際渲染每一章的每個區段，量測暗場的可讀性（玩家輪廓與地面邊緣的對比），低於門檻就以非零代碼結束。
## 用法（需要可渲染的環境）：godot --path . res://tools/readability_check.tscn
## 量測方式：對每個區段截圖（隱藏 HUD），比較「玩家身體範圍」的亮部（第 90 百分位亮度，看輪廓與亮處）與
##   「周圍一圈」的平均亮度、「地面頂面亮邊」與「正下方 6 像素」的平均亮度。對比 = (內 − 外) / (外 + 0.02)。

## 要量測的關卡與取樣點 [名稱, 欄]。第一章設施入口後段是停電走廊，另外量測；
## 室內的關卡（有天花板）取樣高度用「從第 4 列往下的第一個地面」，第一章維持原本的規則。
const LEVELS: Array[Dictionary] = [
	{"path": "res://data/levels/level_01.tres", "spots": [["屋頂巷弄", 30], ["霓虹市集", 115], ["貨運站", 200], ["設施入口", 252], ["停電走廊", 275], ["頭目機庫", 330]]},
	{"path": "res://data/levels/level_02.tres", "spots": [["升降井入口", 30], ["升降井", 100], ["夾層區", 175], ["中庭", 232], ["回收燈幕", 304], ["電力室", 350], ["看守長場地", 400], ["轉運站", 425], ["病房區", 455], ["回收員場地", 492]]},
]
## 門檻與量測範圍見 ContrastProbe（與光影預設場景量測共用）。敵人站在玩家前方 ENEMY_DISTANCE 像素、不動。
const ENEMY_DISTANCE := 96.0
const SAMPLES := 16
const SAMPLE_INTERVAL := 0.2

var _failed := false
## --spots=夾層區,中庭：只量測指定名稱的取樣點（開發時加快迭代）。
var _only_spots: PackedStringArray = []


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
		if arg.begins_with("--spots="):
			_only_spots = arg.trim_prefix("--spots=").split(",", false)
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
		if not _only_spots.is_empty() and not _only_spots.has(str(spot[0])):
			continue
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
			var probe := ContrastProbe.capture(get_viewport())
			player_contrast += probe.character_contrast(player.global_position) / float(SAMPLES)
			edge_contrast += probe.edge_contrast(player.global_position) / float(SAMPLES)
			if is_instance_valid(foe):
				enemy_contrast += probe.character_contrast(foe.global_position) / float(SAMPLES)
			await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		var ok := player_contrast >= ContrastProbe.MIN_PLAYER_CONTRAST and edge_contrast >= ContrastProbe.MIN_EDGE_CONTRAST and enemy_contrast >= ContrastProbe.MIN_ENEMY_CONTRAST
		_failed = _failed or not ok
		print("%-8s  %-8.2f  %-8.2f  %-8.2f  %s" % [spot[0], player_contrast, edge_contrast, enemy_contrast, "OK" if ok else "太暗（門檻 %.1f / %.1f / %.1f）" % [ContrastProbe.MIN_PLAYER_CONTRAST, ContrastProbe.MIN_EDGE_CONTRAST, ContrastProbe.MIN_ENEMY_CONTRAST]])
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
