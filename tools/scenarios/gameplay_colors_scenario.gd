class_name GameplayColorsScenario
extends ScenarioBase
## 區域色調不能吃掉遊戲性的顏色（BG-78）：每個有色彩腳本的區域，在該區的光影下畫出
## 危險預兆（Palette.DANGER）、互動標記（Palette.CYAN）並看主角本身（粉紅頭髮與霓虹），量畫面上的色相與飽和度。
## 色塊用原本的顏色、不加 HDR 亮度：加亮的紅在紅色版到頂後本來就會偏白（沒有任何調色也是），量不出調色的影響。
## 門檻：預兆與標記的色相和原色相差不超過 MAX_HUE_SHIFT 度、飽和度（接近螢幕顯示的值）至少 MIN_SATURATION；
## 主角最鮮豔的 5% 像素飽和度至少 MIN_PLAYER_SATURATION。不合格的區域記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=gameplay_colors [--areas=a,b]

const MAX_HUE_SHIFT := 20.0
## 原色的飽和度：DANGER 0.69、CYAN 0.79；門檻是保留原色飽和度的約 65%（旁邊有彩色燈時會被照偏一點，例如閘門廳的青色電話亭燈）。
const MIN_SATURATION := 0.45
const MIN_PLAYER_SATURATION := 0.4
const PROBE := Vector2(20, 20)


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	Settings.set_reduce_flashes(true)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var areas := Array(ColorScript.area_ids())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--areas="):
			areas = Array(arg.trim_prefix("--areas=").split(",", false))
	areas.sort()
	var worst := {"danger": 0.0, "marker": 0.0, "player": 1.0}
	for area: String in areas:
		GameState.start_new_run(GameState.difficulties[1])
		level = Level.new()
		level.configure(load("res://data/levels/%s.tres" % area) as LevelData)
		add_child(level)
		await settle(30)
		player = level.player
		player.health.setup(999, 0.0)
		level.hud.visible = false
		level._next_story_trigger = level._layout.story_triggers.size()
		await clear_enemies()
		snap_camera()
		await wait(TITLE_CARD_TIME)
		# 轉場或章末卡還在時等它結束（演出線的 UiLayers.presentation_busy），取樣才不會拍到黑幕。
		while UiLayers.presentation_busy(get_tree()):
			await get_tree().process_frame
		var feet := player.global_position
		var danger := _probe(Palette.DANGER, feet + Vector2(40, -64))
		var marker := _probe(Palette.CYAN, feet + Vector2(72, -40))
		get_tree().paused = true
		await settle(4)
		capture(area)
		var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
		var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
		var ratio := Vector2(image.get_size()) / (get_viewport().get_final_transform() * get_viewport().get_visible_rect().size)
		var danger_hsv := _mean_hsv(image, _screen_rect(danger, to_screen, ratio))
		var marker_hsv := _mean_hsv(image, _screen_rect(marker, to_screen, ratio))
		var player_sat := _vivid_saturation(image, _screen_rect_world(Rect2(feet - Vector2(26, 64), Vector2(52, 62)), to_screen, ratio))
		get_tree().paused = false
		var danger_shift := ColorScript.hue_distance(danger_hsv.x, Palette.DANGER.h * 360.0)
		var marker_shift := ColorScript.hue_distance(marker_hsv.x, Palette.CYAN.h * 360.0)
		print("GAMEPLAY_COLOR %s danger hue %.0f(+%.0f) sat %.2f | marker hue %.0f(+%.0f) sat %.2f | player sat %.2f"
			% [area, danger_hsv.x, danger_shift, danger_hsv.y, marker_hsv.x, marker_shift, marker_hsv.y, player_sat])
		var problems := PackedStringArray()
		if danger_shift > MAX_HUE_SHIFT or danger_hsv.y < MIN_SATURATION:
			problems.append("危險預兆（色相偏 %.0f 度、飽和度 %.2f）" % [danger_shift, danger_hsv.y])
		if marker_shift > MAX_HUE_SHIFT or marker_hsv.y < MIN_SATURATION:
			problems.append("互動標記（色相偏 %.0f 度、飽和度 %.2f）" % [marker_shift, marker_hsv.y])
		if player_sat < MIN_PLAYER_SATURATION:
			problems.append("主角（最鮮豔的 5%% 像素飽和度 %.2f）" % player_sat)
		if not problems.is_empty():
			failures += 1
			push_error("[GameplayColorsScenario] %s 的光影吃掉了遊戲性的顏色：%s" % [area, "、".join(problems)])
		worst["danger"] = maxf(worst["danger"], danger_shift)
		worst["marker"] = maxf(worst["marker"], marker_shift)
		worst["player"] = minf(worst["player"], player_sat)
		level.queue_free()
		await settle(4)
	print("GAMEPLAY_COLORS areas=%d worst danger shift %.0f marker shift %.0f player sat %.2f failures=%d" % [areas.size(), worst["danger"], worst["marker"], worst["player"], failures])
	await finish()


## 一塊畫在世界裡、跟預兆同樣材質路徑（一般的畫布項目，受環境光與後製影響）的色塊。
func _probe(color: Color, center: Vector2) -> Polygon2D:
	var probe := Polygon2D.new()
	probe.color = color
	probe.polygon = PackedVector2Array([-PROBE * 0.5, Vector2(PROBE.x, -PROBE.y) * 0.5, PROBE * 0.5, Vector2(-PROBE.x, PROBE.y) * 0.5])
	probe.global_position = center
	probe.z_as_relative = false
	probe.z_index = WorldLayers.FX
	level._world.add_child(probe)
	return probe


func _screen_rect(probe: Polygon2D, to_screen: Transform2D, ratio: Vector2) -> Rect2:
	return _screen_rect_world(Rect2(probe.global_position - PROBE * 0.3, PROBE * 0.6), to_screen, ratio)


static func _screen_rect_world(world: Rect2, to_screen: Transform2D, ratio: Vector2) -> Rect2:
	var a := (to_screen * world.position) * ratio
	var b := (to_screen * world.end) * ratio
	return Rect2(a, b - a).abs()


## 一塊的平均色相（度）、平均飽和度（接近螢幕顯示的值）。
static func _mean_hsv(image: Image, rect: Rect2) -> Vector2:
	var area := Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var sum := Vector2.ZERO
	var saturation := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 2):
		for x in range(area.position.x, area.end.x, 2):
			var color := image.get_pixel(x, y)
			sum += Vector2.from_angle(color.h * TAU)
			saturation += color.s
			count += 1
	if count == 0:
		return Vector2(-1, 0)
	return Vector2(fposmod(rad_to_deg(sum.angle()), 360.0), saturation / count)


## 主角範圍裡最鮮豔的那 5% 像素的飽和度（頭髮、鞋與霓虹；衣服大半是深色的）。
static func _vivid_saturation(image: Image, rect: Rect2) -> float:
	var area := Rect2i(rect).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var values: Array[float] = []
	for y in range(area.position.y, area.end.y, 2):
		for x in range(area.position.x, area.end.x, 2):
			var color := image.get_pixel(x, y)
			if color.v > 0.15:
				values.append(color.s)
	if values.is_empty():
		return 0.0
	values.sort()
	return values[int(values.size() * 0.95)]
