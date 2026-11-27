class_name SkyBehindScenario
extends ScenarioBase
## 垂掛物後面是不是天空（BG-73）：向陽區的垂葉壓在深色巨構上會糊成一團，要垂在有天空的地方。
## 1. 掃描：鏡頭依序對準每一欄，量「垂掛物會在的位置」後面的背景亮度（近前景藏起來），印出來給資料挑位置用。
## 2. 檢查：鏡頭對準每一件實際放的、零件庫標了 needs_sky 的垂掛物（枝葉），量它後面的背景亮度，低於 SKY_MIN 算失敗。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=sky_behind

const AREA := "ch3_glass_edge"
## 背景亮度（sRGB 平均亮度 0~1）至少要這麼亮才算天空；巨構與立面的暗部約 0.1~0.2，天空約 0.6。
const SKY_MIN := 0.4
## 掃描時假設的垂掛物大小（遊戲像素）。
const PROBE := Vector2(72, 80)


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(load("res://data/levels/%s.tres" % AREA) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	await clear_enemies()
	await wait(TITLE_CARD_TIME)
	var near := level.find_child("NearForeground", true, false) as CanvasItem
	if near != null:
		near.visible = false
	var layout: LevelLayout = level._layout
	var tile := float(layout.tile_size)
	var line := PackedStringArray()
	for col in range(0, layout.width, 2):
		var center := col * tile + tile * 0.5
		var floor_y := level.surface_y_at(center)
		var area := Rect2(center - PROBE.x * 0.5, floor_y - NearForeground.DEFAULT_ABOVE, PROBE.x, PROBE.y)
		line.append("%d:%.2f" % [col, await _brightness_behind(center, area)])
	print("SKY_SWEEP %s %s" % [AREA, " ".join(line)])
	# 實際的垂掛物。
	var rows: Variant = level.data.load_layout_value("near_foreground")
	# 和關卡一樣避開敵人出生點附近（戰鬥範圍不放垂掛物）。
	var enemy_x := PackedFloat32Array()
	for spawn in layout.spawns:
		if spawn["resource"] is EnemyData:
			enemy_x.append((spawn["position"] as Vector2).x)
	var placements := NearForeground.plan(rows, level.surface_y_at, enemy_x, tile, AREA, layout.ground_y)
	var hanging := 0
	for entry in placements:
		var info: Variant = NearForeground.library().get(entry["id"])
		if entry["anchor"] != "top" or typeof(info) != TYPE_DICTIONARY or (info as Dictionary).get("needs_sky", false) != true:
			continue
		hanging += 1
		var rect: Rect2 = entry["rect"]
		var value := await _brightness_behind(rect.get_center().x, rect)
		print("SKY_PIECE %s %s col=%d brightness=%.2f" % [AREA, entry["id"], int(rect.get_center().x / tile), value])
		if value < SKY_MIN:
			failures += 1
			push_error("[SkyBehindScenario] %s 的垂掛物 %s（第 %d 欄）後面不是天空（亮度 %.2f < %.2f）" % [AREA, entry["id"], int(rect.get_center().x / tile), value, SKY_MIN])
	print("SKY_BEHIND %s hanging=%d failures=%d" % [AREA, hanging, failures])
	if near != null:
		near.visible = true
	await finish()


## 主角站在 x（鏡頭對準），量世界座標 area 在畫面上那一塊的平均亮度（sRGB）。
func _brightness_behind(x: float, area: Rect2) -> float:
	var y := level.surface_y_at(x) - 2.0
	player.global_position = Vector2(x, y)
	player.velocity = Vector2.ZERO
	snap_camera()
	await settle(3)
	var viewport := get_viewport()
	var image := viewport.get_texture().get_image()
	var to_screen := viewport.get_canvas_transform()
	var ratio := Vector2(image.get_size()) / viewport.get_visible_rect().size
	var top_left := (to_screen * area.position) * ratio
	var bottom_right := (to_screen * area.end) * ratio
	var total := 0.0
	var count := 0
	var px := maxf(0.0, top_left.x)
	while px < minf(float(image.get_width()), bottom_right.x):
		var py := maxf(0.0, top_left.y)
		while py < minf(float(image.get_height()), bottom_right.y):
			var color := image.get_pixel(int(px), int(py))
			if viewport.use_hdr_2d:
				color = color.linear_to_srgb()
			total += color.get_luminance()
			count += 1
			py += 4.0
		px += 4.0
	return total / count if count > 0 else 0.0
