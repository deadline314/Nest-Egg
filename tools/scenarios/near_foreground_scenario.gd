class_name NearForegroundScenario
extends ScenarioBase
## 近前景（BG-68）：第三章向陽區與第一章街道各拍幾格，每格同一個畫面拍「有」與「沒有」近前景（只切換近前景的顯示）；
## 街道另外拍一場戰鬥：主角對著兩個敵人開火，看近前景有沒有擋到角色、敵人、子彈。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=near_foreground

const AREAS := {
	"ch3_glass_edge": [8, 14, 30, 48],
	"ch1_street": [24, 96, 160],
	"ch1_booth_alley": [26],
	"ch1_rooftop": [42],
}
const GRUNT := "res://data/enemies/grunt.tres"


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	for area: String in AREAS:
		await _open(area)
		var near := level.find_child("NearForeground", true, false) as CanvasItem
		if near == null:
			failures += 1
			push_error("[NearForegroundScenario] %s 沒有近前景" % area)
			continue
		var mid := 0
		for node in get_tree().get_nodes_in_group(PropNode.GROUP):
			if node.has_meta(Midground.META):
				mid += 1
				print("MIDGROUND %s %s col=%d" % [area, (node as PropNode).data.id, int((node as Node2D).position.x / 16.0)])
		var haze := level.find_child("FacadeHaze", true, false) as FacadeHaze
		print("NEAR_FOREGROUND %s pieces=%d midground=%d haze_bands=%d" % [area, near.get_child_count(), mid, haze.band_count() if haze != null else 0])
		for col: int in AREAS[area]:
			_place(col)
			await wait(1.2)
			await _pair(near, "BG-68-%s-%d" % [area, col])
		if area == "ch1_street":
			await _fight(near)
		level.queue_free()
		await settle(4)
	await finish()


func _open(area: String) -> void:
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
	AimInput.set_virtual_gamepad(player, true)
	await wait(TITLE_CARD_TIME)


func _place(col: int) -> void:
	var layout: LevelLayout = level._layout
	var y := layout.surface_heights[col] - 2.0
	player.global_position = Vector2(col * layout.tile_size + 8.0, y)
	player.velocity = Vector2.ZERO
	player.facing = 1
	snap_camera()


## 同一格畫面：有近前景、沒有近前景。拍的時候整棵樹暫停，兩張只差在近前景（子彈、特效、動作都停在同一格）。
func _pair(near: CanvasItem, file_name: String) -> void:
	get_tree().paused = true
	await settle(2)
	capture(file_name)
	await settle(2)
	near.visible = false
	await settle(2)
	capture(file_name + "-without")
	near.visible = true
	await settle(2)
	await _check_midground(file_name)
	get_tree().paused = false


## 中景物件的平均明度要低於同一格主角的平均明度（BG-71）：各自藏起來再拍一張，兩張不同的像素就是它。
func _check_midground(file_name: String) -> void:
	var mids: Array[CanvasItem] = []
	# BG-74：中景與手擺的非互動、不發光擺設都要比主角暗，每一件分開量（一張白色長椅不會被其他擺設平均掉）。
	for node in get_tree().get_nodes_in_group(PropNode.GROUP):
		var prop_node := node as PropNode
		if prop_node.is_visible_in_tree() and (prop_node.has_meta(Midground.META) or Midground.tones_hand_prop(prop_node.data)):
			mids.append(prop_node)
	if mids.is_empty():
		return
	var shown := preload("res://tools/viewport_capture.gd").image(get_viewport())
	for node in mids:
		node.visible = false
	await settle(2)
	var without_mid := preload("res://tools/viewport_capture.gd").image(get_viewport())
	for node in mids:
		node.visible = true
	player.visible = false
	await settle(2)
	var without_player := preload("res://tools/viewport_capture.gd").image(get_viewport())
	player.visible = true
	await settle(2)
	var to_screen := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
	var hero := _mean_changed(shown, without_player, [to_screen * Rect2(player.global_position - Vector2(16, 60), Vector2(32, 60))] as Array[Rect2])
	if hero.y < 40.0:
		return
	for node in mids:
		var prop := node as PropNode
		var mid := _mean_changed(shown, without_mid, [to_screen * Rect2(prop.global_position, prop.data.size)] as Array[Rect2])
		if mid.y < 40.0:
			continue
		var kind := "midground" if prop.has_meta(Midground.META) else "hand"
		print("PROP_LUMA %s %s %s=%.3f player=%.3f (%d px)" % [file_name, prop.data.id, kind, mid.x, hero.x, int(mid.y)])
		if mid.x >= hero.x:
			failures += 1
			push_error("[NearForegroundScenario] %s 的擺設 %s（%s）比主角亮：%.3f >= %.3f" % [file_name, prop.data.id, kind, mid.x, hero.x])


## 只在 rects（畫面座標）裡、兩張不同的像素，在第一張裡的平均亮度與像素數
## （藏起主角會連她自己的燈一起關掉、藏起擺設會連接地陰影一起拿掉，範圍外的變化不算）。
static func _mean_changed(a: Image, b: Image, rects: Array[Rect2]) -> Vector2:
	var total := 0.0
	var count := 0
	var bounds := Rect2i(Vector2i.ZERO, a.get_size())
	for rect in rects:
		var area := Rect2i(rect.abs()).intersection(bounds)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var p := a.get_pixel(x, y)
				var q := b.get_pixel(x, y)
				if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.08:
					total += p.get_luminance()
					count += 1
	return Vector2(total / maxf(1.0, float(count)), float(count))


## 戰鬥：兩個敵人站在主角前方，主角朝右連射，拍三格。
func _fight(near: CanvasItem) -> void:
	var col := int(AREAS["ch1_street"][1])
	_place(col)
	var layout: LevelLayout = level._layout
	for offset: int in [7, 11]:
		var enemy := level._create_enemy(load(GRUNT) as EnemyData)
		enemy.position = Vector2((col + offset) * layout.tile_size + 8.0, layout.surface_heights[col + offset] - 2.0)
		level._entities.add_child(enemy)
	await wait(1.0)
	Input.action_press(&"aim_right")
	Input.action_press(&"shoot")
	for i in 3:
		await settle(4)
		await _pair(near, "BG-68-fight-%d" % i)
	Input.action_release(&"shoot")
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
