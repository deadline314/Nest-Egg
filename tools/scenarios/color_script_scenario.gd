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


var _area_hue := {}


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
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
		get_tree().paused = true
		await settle(4)
		capture(shot[2])
		_check_hue(area, shot[2])
		get_tree().paused = false
		print("COLOR_SCRIPT %s zone=%s ambient=%s" % [area, level._lighting.zone_id_at(player.global_position.x), level._lighting.current.ambient_color])
		level.queue_free()
		await settle(4)
	var chapters := {}
	for area: String in _area_hue:
		var chapter := area.get_slice("_", 0)
		chapters[chapter] = chapters.get(chapter, Vector2.ZERO) + (_area_hue[area] as Vector2).normalized()
	for chapter: String in chapters:
		var sum: Vector2 = chapters[chapter]
		var span := ColorScript.chapter_hue(chapter)
		var mean := fposmod(rad_to_deg(sum.angle()), 360.0)
		print("CHAPTER_HUE %s mean=%.0f range=%s" % [chapter, mean, span])
		if span.x >= 0.0 and not ColorScript.hue_in(mean, span):
			failures += 1
			push_error("[ColorScriptScenario] %s 的平均色相 %.0f 不在色彩腳本的範圍 %s" % [chapter, mean, span])
	await finish()


## 這一張的平均色相：有自己範圍的區域單獨檢查，其餘加進章節的平均。
func _check_hue(area: String, file_name: String) -> void:
	var hue := mean_hue(preload("res://tools/viewport_capture.gd").image(get_viewport()))
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
				result.append([parts[0], int(parts[1]) if parts.size() > 1 else -1, "%s-%s" % [parts[0], parts[1]] if parts.size() > 1 else parts[0],
					int(parts[2]) if parts.size() > 2 else -1])
			return result
	for shot: Array in SHOTS:
		result.append([shot[0], shot[1], shot[0]])
	return result
