class_name KeyLightScenario
extends ScenarioBase
## 主光（BG-67）：第三章向陽區同一格鏡頭拍「遮得少」與「遮得多」、主光關掉的對照、低中高三個畫質，
## 以及主角站在光源正下方的近拍。近拍另外量主角頭部的過曝：同一格把主角藏起來再拍一次，兩張不同的像素就是主角，
## 數其中每個色版都超過 0.92 的比例，主光開與關各量一次。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=key_light

const LEVEL := "res://data/levels/ch3_glass_edge.tres"
## 整體鏡頭的欄、站在光源正下方的欄。
const VIEW_COL := 14
const UNDER_COL := 17
const CLIP := 0.92
const ZOOM_SIZE := Vector2(90, 80)
const ZOOM_HEIGHT := 480


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)  # 光柱不閃動，同一格的開／關對照才只差在主光
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right")
	var key := level.find_child("KeyLight", true, false) as KeyLight
	if key == null:
		failures += 1
		push_error("[KeyLightScenario] %s 沒有主光" % LEVEL)
		await finish()
		return
	print("KEY_LIGHT max_rate=%.4f per second, range %.2f..%.2f, period %.0f s" % [key.data.max_rate(), key.data.occlusion_min, key.data.occlusion_max, key.data.period])
	await wait(TITLE_CARD_TIME)

	_place(VIEW_COL)
	for state: Array in [["open", 0.1], ["covered", 0.9]]:
		KeyLight.forced_occlusion = float(state[1])
		await settle(20)
		capture("BG-67-%s" % state[0])
		await settle(2)
	KeyLight.forced_occlusion = 0.5
	key.visible = false
	await settle(10)
	capture("BG-67-off")
	await settle(2)
	key.visible = true

	for tier: int in [LightQuality.Tier.LOW, LightQuality.Tier.MEDIUM, LightQuality.Tier.HIGH]:
		Settings.set_light_quality(tier)
		await settle(10)
		capture("BG-67-quality-%s" % ["low", "medium", "high"][tier])
		await settle(2)

	# 主角站在光源正下方、遮得最少（最亮）：主光開與關各拍主角在與不在。主角的範圍用「主光關」那一對算
	# （背景暗、分得清楚），同一個範圍拿來數兩張的全白像素，比較才公平。
	_place(UNDER_COL)
	KeyLight.forced_occlusion = 0.0
	await settle(30)
	var shots := {}
	for on: bool in [true, false]:
		key.visible = on
		await settle(8)
		shots[on] = await _pair()
	var mask := _head_mask(shots[false][0], shots[false][1])
	for on: bool in [true, false]:
		var image: Image = shots[on][0]
		var clipped := 0
		for point: Vector2i in mask:
			var p := image.get_pixelv(point)
			if p.r > CLIP and p.g > CLIP and p.b > CLIP:
				clipped += 1
		var tag := "on" if on else "off"
		print("KEY_LIGHT_EXPOSURE under-%s head_pixels=%d clipped=%d ratio=%.4f" % [tag, mask.size(), clipped, float(clipped) / maxf(1.0, mask.size())])
		_save_closeup(image, "BG-67-under-%s" % tag)
	if mask.size() < 50:
		failures += 1
		push_error("[KeyLightScenario] 找不到主角的頭（%d 像素）" % mask.size())
	key.visible = true
	KeyLight.forced_occlusion = -1.0
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	await finish()


func _place(col: int) -> void:
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(col * layout.tile_size + 8.0, layout.surface_heights[col] - 2.0)
	player.velocity = Vector2.ZERO
	player.facing = 1
	snap_camera()


## 同一格主角在與不在各拍一張。
func _pair() -> Array:
	snap_camera()
	await settle(3)
	var viewport := get_viewport()
	var shown := preload("res://tools/viewport_capture.gd").image(viewport)
	player.visible = false
	await settle(3)
	var hidden := preload("res://tools/viewport_capture.gd").image(viewport)
	player.visible = true
	await settle(2)
	return [shown, hidden]


func _zoom_rect(size: Vector2i) -> Rect2i:
	var viewport := get_viewport()
	var to_screen := viewport.get_final_transform() * viewport.get_canvas_transform()
	var center := player.global_position + Vector2(0, -30)
	var a := Vector2i(to_screen * (center - ZOOM_SIZE * 0.5))
	var b := Vector2i(to_screen * (center + ZOOM_SIZE * 0.5))
	return Rect2i(a, b - a).intersection(Rect2i(Vector2i.ZERO, size))


## 兩張差異大的像素是主角；頭部是主角範圍最上面的 30%。
func _head_mask(shown: Image, hidden: Image) -> Array[Vector2i]:
	var rect := _zoom_rect(shown.get_size())
	var body: Array[Vector2i] = []
	var top := rect.end.y
	var bottom := rect.position.y
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := shown.get_pixel(x, y)
			var q := hidden.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.12:
				body.append(Vector2i(x, y))
				top = mini(top, y)
				bottom = maxi(bottom, y)
	var limit := top + int((bottom - top) * 0.3)
	var head: Array[Vector2i] = []
	for point in body:
		if point.y <= limit:
			head.append(point)
	return head


func _save_closeup(image: Image, file_name: String) -> void:
	image.save_png(out_dir.path_join(file_name + "_full.png"))
	var rect := _zoom_rect(image.get_size())
	var crop := image.get_region(rect)
	crop.resize(int(ZOOM_HEIGHT * float(rect.size.x) / rect.size.y), ZOOM_HEIGHT, Image.INTERPOLATE_NEAREST)
	crop.save_png(out_dir.path_join(file_name + ".png"))
