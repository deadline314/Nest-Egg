class_name ColorScriptScenario
extends ScenarioBase
## 色彩腳本（BG-74）：每章幾個區域，主角站在固定的欄位各拍一張，修前修後用同一組位置對照，再拼成整章的縮圖帶。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=color_script
##   [--shots=區域:欄[:列],...]（欄寫 -1 用出生點；列和可讀性檢查的取樣點同義；不寫就拍 SHOTS）。檔名是 區域 或 區域-欄。
## 檢查（BG-75）：每張的平均色相（依飽和度與亮度加權）。區域自己有色相範圍的（當舖）單獨檢查；其餘依章節累計，
## 每個區域一票（同一區拍幾張先平均成一個色相），整章的平均色相要落在色彩腳本那一章的範圍裡。不在範圍裡算失敗。

## 區域與主角站的欄（-1：區域的出生點；有些區域在固定欄位會落在沒有燈的地方）。
const SHOTS := [
	["ch1_booth_alley", 20], ["ch1_street", 60], ["ch1_warehouse", -1], ["ch1_rooftop", 30],
	["ch2_harbor_street", 30], ["ch2_market", 40], ["ch2_loading", 30], ["ch2_ledger_office", 20],
	["ch3_plaza", 30], ["ch3_clinic", -1], ["ch3_pump", -1], ["ch3_glass_edge", 30],
	["ch4_factory_approach", -1], ["ch4_factory_loading", 30], ["ch4_nursing_ward", -1],
]


## 主角腳下到畫面底（BG-77 起；原本是固定的畫面下方 40%）裡「接近純黑」（sRGB 最亮的色版低於 BLACK_LEVEL；深藍的夜空不算黑，只有三個色版都很暗才算）的像素比例上限（BG-76）：
## 只檢查有地面剖面的區域。2026-11-28 量（第一章十個位置）：修前 0.20～0.61，修後 0.06～0.30；向陽區樣板 0.29（近前景的剪影本來就暗）。
const BOTTOM_SHARE := 0.4
const BLACK_LEVEL := 0.05
const MAX_BLACK := 0.35
## 從主角腳下再往下多少（畫面高度的比例）開始量（避開走道本身）；這一段至少多高。
const FEET_CLEAR := 0.03
const MIN_BELOW := 0.15

var _area_hue := {}


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	# 量測靜態畫面：關掉閃電等閃光，每次拍到的亮度才一致。
	Settings.set_reduce_flashes(true)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	for shot: Array in _shots():
		var area: String = shot[0]
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
		var layout: LevelLayout = level._layout
		if int(shot[1]) >= 0:
			var col := mini(int(shot[1]), layout.width - 2)
			# 有寫列（和可讀性檢查的取樣點同一個寫法）就站在那一列的地面上；沒寫就站在那一欄最高的可走地面。
			var y: float = float(shot[3]) * layout.tile_size - 2.0 if shot.size() > 3 and int(shot[3]) >= 0 else layout.surface_heights[col] - 2.0
			player.global_position = Vector2(col * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		player.facing = 1
		snap_camera()
		await wait(TITLE_CARD_TIME)
		# 標題卡期間主角可能被劇情或物理移動：拍之前再放回同一個位置、重新對準鏡頭，修前修後才對得上。
		player.global_position = Vector2(player.global_position.x, player.global_position.y) if int(shot[1]) < 0 else player.global_position
		if int(shot[1]) >= 0:
			var col_again := mini(int(shot[1]), layout.width - 2)
			var y_again: float = float(shot[3]) * layout.tile_size - 2.0 if shot.size() > 3 and int(shot[3]) >= 0 else layout.surface_heights[col_again] - 2.0
			player.global_position = Vector2(col_again * layout.tile_size + 8.0, y_again)
			player.velocity = Vector2.ZERO
			snap_camera()
			await settle(3)
		get_tree().paused = true
		await settle(4)
		capture(shot[2])
		var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
		_check_hue(area, shot[2], image)
		var to_screen := get_viewport().get_canvas_transform()
		var feet_y := (to_screen * player.global_position).y / get_viewport().get_visible_rect().size.y
		# 死黑量的是剖面與遠景：近前景的剪影本來就是畫面上最暗的東西，量的時候先藏起來（只影響這一張量測用的畫面）。
		var near := level.find_child("NearForeground", true, false) as CanvasItem
		if near != null:
			near.visible = false
			await settle(2)
			image = preload("res://tools/viewport_capture.gd").image(get_viewport())
			near.visible = true
		_check_black(shot[2], image, feet_y)
		get_tree().paused = false
		print("COLOR_SCRIPT %s zone=%s player=%s camera=%s" % [shot[2], level._lighting.zone_id_at(player.global_position.x), player.global_position, get_viewport().get_camera_2d().get_screen_center_position()])
		level.queue_free()
		await settle(4)
	var chapters := {}
	for area: String in _area_hue:
		var chapter := area.get_slice("_", 0)
		chapters[chapter] = chapters.get(chapter, Vector2.ZERO) + (_area_hue[area] as Vector2).normalized()
	var means := {}
	for chapter: String in chapters:
		var sum: Vector2 = chapters[chapter]
		means[chapter] = fposmod(rad_to_deg(sum.angle()), 360.0)
		var span := ColorScript.chapter_hue(chapter)
		var mean := fposmod(rad_to_deg(sum.angle()), 360.0)
		print("CHAPTER_HUE %s mean=%.0f range=%s" % [chapter, mean, span])
		if span.x >= 0.0 and not ColorScript.hue_in(mean, span):
			failures += 1
			push_error("[ColorScriptScenario] %s 的平均色相 %.0f 不在色彩腳本的範圍 %s" % [chapter, mean, span])
	# 相鄰兩章的色相差距（BG-77）：同一次拍到的相鄰章節才比。
	for chapter: String in means:
		var next := "ch%d" % (int(chapter.trim_prefix("ch")) + 1)
		if means.has(next) and ColorScript.neighbor_gap > 0.0:
			var gap := ColorScript.hue_distance(means[chapter], means[next])
			print("CHAPTER_GAP %s-%s %.0f (min %.0f)" % [chapter, next, gap, ColorScript.neighbor_gap])
			if gap < ColorScript.neighbor_gap:
				failures += 1
				push_error("[ColorScriptScenario] %s 和 %s 的平均色相只差 %.0f 度（至少 %.0f）" % [chapter, next, gap, ColorScript.neighbor_gap])
	await finish()


## 這一張的平均色相：有自己範圍的區域單獨檢查，其餘加進章節的平均。
func _check_hue(area: String, file_name: String, image: Image) -> void:
	var hue := mean_hue(image)
	var own := ColorScript.area_hue(StringName(area))
	print("SHOT_HUE %s hue=%.0f" % [file_name, hue])
	if own.x >= 0.0:
		if not ColorScript.hue_in(hue, own):
			failures += 1
			push_error("[ColorScriptScenario] %s 的平均色相 %.0f 不在它自己的範圍 %s" % [file_name, hue, own])
		return
	_area_hue[area] = _area_hue.get(area, Vector2.ZERO) + Vector2.from_angle(deg_to_rad(hue))


## 圖的平均色相（度）：縮小後每個像素依飽和度 × 亮度加權（灰與黑不算）。
static func mean_hue(image: Image) -> float:
	var small := image.duplicate() as Image
	small.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var sum := Vector2.ZERO
	for y in small.get_height():
		for x in small.get_width():
			var color := small.get_pixel(x, y)
			sum += Vector2.from_angle(color.h * TAU) * color.s * color.v
	return fposmod(rad_to_deg(sum.angle()), 360.0)


## 拍哪些：命令列的 --shots 優先，否則 SHOTS；回傳 [區域, 欄, 檔名]。
static func _shots() -> Array:
	var result := []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			for item in arg.trim_prefix("--shots=").split(",", false):
				var parts := item.split(":")
				var label := "-".join(parts.slice(0, 3)) if parts.size() > 1 else parts[0]
				result.append([parts[0], int(parts[1]) if parts.size() > 1 else -1, label,
					int(parts[2]) if parts.size() > 2 else -1])
			return result
	for shot: Array in SHOTS:
		result.append([shot[0], shot[1], shot[0]])
	return result


## 畫面下方的死黑：有地面剖面的區域才檢查。
func _check_black(file_name: String, image: Image, feet_y: float) -> void:
	if level.data.load_layout_value("ground_section") == null:
		return
	var share := black_share(image, feet_y)
	print("BOTTOM_BLACK %s share=%.2f limit=%.2f" % [file_name, share, MAX_BLACK])
	if share > MAX_BLACK:
		failures += 1
		push_error("[ColorScriptScenario] %s 畫面下方 %d%% 有 %.0f%% 接近純黑（上限 %.0f%%）" % [file_name, int(BOTTOM_SHARE * 100.0), share * 100.0, MAX_BLACK * 100.0])


## 主角腳下（feet_y 是畫面高度的比例）往下到畫面底的那一段裡，接近純黑的像素比例（縮小後算）：量的是「走道下方」，
## 不是天際線的建築剪影（站在上層通道時畫面下方有一大段是遠景）。這一段至少取畫面底部 MIN_BELOW。
static func black_share(image: Image, feet_y := 1.0 - BOTTOM_SHARE) -> float:
	var small := image.duplicate() as Image
	small.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var total := 0
	var dark := 0
	var top := clampf(feet_y + FEET_CLEAR, 0.0, 1.0 - MIN_BELOW)
	for y in range(int(small.get_height() * top), small.get_height()):
		for x in small.get_width():
			total += 1
			if small.get_pixel(x, y).v < BLACK_LEVEL:
				dark += 1
	return float(dark) / maxf(1.0, total)
