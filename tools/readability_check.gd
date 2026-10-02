extends Node
## 開發工具：實際渲染第一章每個區段，量測暗場的可讀性（玩家輪廓與地面邊緣的對比），低於門檻就以非零代碼結束。
## 用法（需要可渲染的環境）：godot --path . res://tools/readability_check.tscn
## 量測方式：對每個區段截圖（隱藏 HUD），比較「玩家身體範圍」的亮部（第 90 百分位亮度，看輪廓與亮處）與
##   「周圍一圈」的平均亮度、「地面頂面亮邊」與「正下方 6 像素」的平均亮度。對比 = (內 − 外) / (外 + 0.02)。

const LEVEL_PATH := "res://data/levels/level_01.tres"
## 各區段取中段的一欄；設施入口後段是停電走廊，另外量測。
const SPOTS: Array[Array] = [["屋頂巷弄", 30], ["霓虹市集", 115], ["貨運站", 200], ["設施入口", 252], ["停電走廊", 275], ["頭目機庫", 330]]
const MIN_PLAYER_CONTRAST := 0.6
const MIN_EDGE_CONTRAST := 1.0
const PLAYER_BOX := Rect2(-9, -44, 18, 40)
const RING := 20.0

var _failed := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	Story.auto_skip = true
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	for i in 20:
		await get_tree().process_frame
	var player := level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	for id: String in Story.scene_ids():
		if id.begins_with("radio_"):
			Story._seen[StringName(id)] = true
	var layout: LevelLayout = level._layout
	print("%-8s  %-8s  %-8s" % ["區段", "玩家對比", "邊緣對比"])
	for spot: Array in SPOTS:
		var tile: int = spot[1]
		var y := layout.surface_heights[tile] - 2.0
		# 室內區段最上面的「地面」是天花板，改用檢查點的高度。
		if spot[0] == "設施入口" or spot[0] == "停電走廊" or spot[0] == "頭目機庫":
			y = layout.checkpoints[3].y - 2.0
		player.global_position = Vector2(tile * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		for node in get_tree().get_nodes_in_group(&"enemies"):
			node.queue_free()
		for i in 60:
			await get_tree().process_frame
		await get_tree().create_timer(1.2).timeout
		var image := get_viewport().get_texture().get_image()
		var scale := float(image.get_width()) / get_viewport().get_visible_rect().size.x
		var to_screen := get_viewport().get_canvas_transform()
		var feet := player.global_position
		var player_contrast := _contrast(image, scale, to_screen, Rect2(feet + PLAYER_BOX.position, PLAYER_BOX.size), RING)
		# 地面頂面亮邊：腳下 1~3 像素 vs 再往下 6~12 像素。
		var edge_rect := Rect2(feet + Vector2(-24, 0), Vector2(48, 3))
		var below_rect := Rect2(feet + Vector2(-24, 8), Vector2(48, 6))
		var edge_contrast := (_mean_luma(image, scale, to_screen, edge_rect) - _mean_luma(image, scale, to_screen, below_rect)) \
				/ (_mean_luma(image, scale, to_screen, below_rect) + 0.02)
		var ok := player_contrast >= MIN_PLAYER_CONTRAST and edge_contrast >= MIN_EDGE_CONTRAST
		_failed = _failed or not ok
		print("%-8s  %-8.2f  %-8.2f  %s" % [spot[0], player_contrast, edge_contrast, "OK" if ok else "太暗（門檻 %.1f / %.1f）" % [MIN_PLAYER_CONTRAST, MIN_EDGE_CONTRAST]])
	get_tree().quit(1 if _failed else 0)


## 方框內平均亮度與外圈（向外擴 ring 像素）平均亮度的對比。
func _contrast(image: Image, scale: float, to_screen: Transform2D, box: Rect2, ring: float) -> float:
	var inner := _percentile_luma(image, scale, to_screen, box, 0.9)
	var outer_box := box.grow(ring)
	var outer_total := _luma_sum(image, scale, to_screen, outer_box) - _luma_sum(image, scale, to_screen, box)
	var outer_count := _pixel_count(scale, outer_box) - _pixel_count(scale, box)
	var outer := outer_total / maxf(1.0, outer_count)
	return (inner - outer) / (outer + 0.02)


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
