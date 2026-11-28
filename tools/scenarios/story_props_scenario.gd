class_name StoryPropsScenario
extends ScenarioBase
## 可讀物件的小擺設（BG-80）：把共用小物件包的擺設加進該區的地圖（只改記憶體裡的地圖 JSON，不寫檔），
## 走和正式擺設同一套放置、支撐檢查、接地陰影與色調；主角站到可讀物件前等互動提示出現，
## 拍一張遊戲比例、一張放大。擺不上去（找不到、支撐無效）算失敗。PLACEMENTS 就是交給地圖線寫進產生器的項目。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=story_props [--areas=a,b]

const ZOOM := 3.0
const PLACEMENTS := {
	"ch3_clinic": {"station": "ch3_clinic_cups", "props": [
		{"id": "common__numbered_thermos_cups", "x": 99, "dx": 5.5, "dy": -23, "ground": true, "support": "prop", "support_id": "nursing_ward__bedside_locker", "support_x": 99, "support_dy": 10}]},
	"ch3_office_hall": {"station": "ch3_office_vent", "props": [
		{"id": "common__ac_service_hatch", "x": 24, "y": 12, "support": "wall"}]},
	"ch1_stall": {"station": "ch1_stall_cat_bowl", "props": [
		{"id": "common__chipped_bowl", "x": 41, "y": 12}]},
	"ch4_pawnshop": {"station": "ch4_counter_note", "props": [
		{"id": "common__register_note", "x": 52, "dx": 63, "dy": -20, "ground": true, "support": "prop", "support_id": "pawnshop_front__counter_register", "support_x": 52, "support_dy": 16}]},
	"ch4_revival_lounge": {"station": "ch4_lost_box", "props": [
		{"id": "common__lost_and_found_box", "x": 50, "ground": true}]},
	"ch2_ledger_front": {"station": "ch2_unsent_notices", "props": [
		{"id": "common__unsent_dunning_letters", "x": 60, "dx": 2, "ground": true}]},
	"ch3_pump": {"station": "ch3_pump_locker", "props": [
		{"id": "common__taped_duty_roster", "x": 74, "y": 35, "dx": 2, "dy": -40, "support": "prop", "support_id": "sluice_hall__maintenance_locker", "support_x": 74, "support_dy": 17}]},
}


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	Settings.set_reduce_flashes(true)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	var areas: Array = PLACEMENTS.keys()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--areas="):
			areas = Array(arg.trim_prefix("--areas=").split(",", false))
	for area: String in areas:
		await _shoot(area)
	print("STORY_PROPS areas=%d failures=%d" % [areas.size(), failures])
	await finish()


func _shoot(area: String) -> void:
	var spec: Dictionary = PLACEMENTS[area]
	var data := load("res://data/levels/%s.tres" % area) as LevelData
	# 地圖 JSON 是快取的資源：在記憶體裡換成加過擺設的內容（JSON.data 取出來是複本，要寫回去），Level 讀到的就是加過的清單；拍完還原。
	var json := load(data.layout_path) as JSON
	var original: Dictionary = json.data
	var doc: Dictionary = original.duplicate(true)
	var added: Array = (spec["props"] as Array).duplicate(true)
	(doc["props"] as Array).append_array(added)
	json.data = doc
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	await clear_enemies()
	var layout: LevelLayout = level._layout
	var dirs := data.environment.prop_dirs()
	var entries := data.load_props()
	var focus := Vector2.ZERO
	for entry: Dictionary in added:
		var prop := PropLibrary.find_in(StringName(str(entry["id"])), dirs)
		if prop == null:
			failures += 1
			push_error("[StoryPropsScenario] %s 找不到擺設 %s" % [area, entry["id"]])
			continue
		var placed := PropPlacement.resolve(entry, prop, layout)
		var issue := "prop_floating" if placed.is_empty() else ScenerySupport.check_prop(entry, prop, placed["rect"], layout, level._scenery_walls, entries, dirs)
		if not issue.is_empty():
			failures += 1
			push_error("[StoryPropsScenario] %s 的 %s 擺不上去（%s）" % [area, entry["id"], issue])
			continue
		var rect: Rect2 = placed["rect"]
		focus = rect.get_center()
		print("STORY_PROPS %s %s rect=%s" % [area, entry["id"], rect])
	var spawned := {}
	for node in level.find_children("*", "", true, false):
		if node is PropNode:
			spawned[str((node as PropNode).data.id)] = true
	for entry: Dictionary in added:
		if not spawned.has(str(entry["id"])):
			failures += 1
			push_error("[StoryPropsScenario] %s 的 %s 沒有出現在關卡裡" % [area, entry["id"]])
	# 主角站在可讀物件（NpcData 站點）左邊 22 像素：還在互動範圍裡、又不會擋到擺設。
	var station := Vector2.ZERO
	for spawn in layout.spawns:
		if spawn["resource"] is NpcData and str((spawn["resource"] as NpcData).id) == str(spec["station"]):
			station = spawn["position"]
	if station == Vector2.ZERO:
		failures += 1
		push_error("[StoryPropsScenario] %s 找不到可讀物件 %s" % [area, spec["station"]])
	print("STORY_PROPS %s station %s at %s (col %d, row %d)" % [area, spec["station"], station, int(station.x / layout.tile_size), int(station.y / layout.tile_size)])
	player.global_position = station + Vector2(-22.0, -2.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	while UiLayers.presentation_busy(get_tree()):
		await get_tree().process_frame
	# 不暫停：暫停時世界提示會藏起來。敵人已清掉、主角沒有輸入，站著不動。
	await wait(1.0)
	# 停掉鏡頭的跟隨（Camera2D 自己的更新照跑），兩張都把畫面中心放在擺設與提示之間：先遊戲倍率，再拉近。關卡隨後釋放，不必還原。
	var camera := level.camera
	camera.set_physics_process(false)
	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	camera.global_position = (focus if focus != Vector2.ZERO else station).lerp(station + Vector2(0, -40), 0.4)
	camera.reset_smoothing()
	await settle(6)
	capture("%s-game" % area)
	level.hud.visible = false
	# 遊戲倍率那張照鏡頭的邊界（和實際遊玩一樣）；拉近那張放掉邊界，才能對準擺設。
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	camera.zoom *= ZOOM
	await settle(6)
	capture("%s-zoom" % area)
	level.queue_free()
	await settle(4)
	json.data = original
