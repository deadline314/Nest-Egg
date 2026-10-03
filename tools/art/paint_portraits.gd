extends Node
## 開發工具：把骨架角色渲染成背包用的像素立繪（96×128，分四層 PNG：後髮、身體、頭、頭（閉眼））。
## 流程：以 4 倍解析度渲染待機姿勢 → 縮小 → 透明度二值化 → 限色 → 描邊；閉眼層由頭層把眼睛換成膚色並加一條睫毛。
## 用法（需要可渲染的環境）：godot --path . res://tools/art/paint_portraits.tscn [-- --only=rin] [--preview=/絕對路徑]
## 會覆蓋 art/items/portraits/ 底下的同名 PNG；已換成手繪像素圖的角色請用 --only 指定要重畫的。
## 手繪替換：依 ItemIcons.PORTRAIT_LAYERS 畫四張同尺寸、位置對齊的 PNG 即可。

const CHARACTERS: Array[String] = ["rin", "mei"]
const OUTLINE := Color("07080d")
const SUPERSAMPLE := 4
## 取景：角色放大倍數（骨架單位 → 立繪像素）與腳底位置，依各角色身高與頭身比個別設定；沒列出的角色用 DEFAULT_FRAMING。
## 7.5 頭身的凜身高約 70 世界像素：放大 2.7 倍、腳放在畫面下方外面，剛好取到頭頂到大腿中段（頭與馬尾完整，臉約 30 像素寬）。
const FRAMING := {
	"rin": {"zoom": 2.7, "feet": Vector2(54, 193)},
	"mei": {"zoom": 4.0, "feet": Vector2(44, 214)},
}
const DEFAULT_FRAMING := {"zoom": 2.7, "feet": Vector2(54, 193)}
const SETTLE_FRAMES := 90
## 空手站姿：手臂朝前下方自然垂放。
const IDLE_AIM := Vector2(1.0, 0.45)
const COLOR_LEVELS := 7
## 各層包含的零件（character.json 的 parts.name）；不在 HEAD 與 HAIR 裡的都算身體。
const HEAD_PARTS: Array[String] = ["head", "hair_front"]
const HAIR_PARTS: Array[String] = ["hair_back_1", "hair_back_2"]
var _only: PackedStringArray = []
var _preview_dir := ""
var _written := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--preview="):
			_preview_dir = arg.trim_prefix("--preview=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ItemIcons.PORTRAIT_DIR))
	if not _preview_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_preview_dir)
	for id in CHARACTERS:
		if _only.is_empty() or _only.has(id):
			await _paint_character(id)
	print("paint_portraits: wrote %d files" % _written)
	get_tree().quit()


func _paint_character(id: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = ItemIcons.PORTRAIT_SIZE * SUPERSAMPLE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var framing: Dictionary = FRAMING.get(id, DEFAULT_FRAMING)
	var holder := Node2D.new()
	holder.position = (framing["feet"] as Vector2) * SUPERSAMPLE
	holder.scale = Vector2.ONE * float(framing["zoom"]) * SUPERSAMPLE
	viewport.add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	if not rig.setup(id):
		push_error("[paint_portraits] 無法建立角色：%s" % id)
		viewport.queue_free()
		return
	# 待機姿勢：跑幾格讓頭髮與衣襬的彈簧靜止下來。
	var input := RigInput.new()
	input.two_handed = false
	input.aim_dir = IDLE_AIM.normalized()
	for i in SETTLE_FRAMES:
		rig.animate(1.0 / 60.0, input)
		await get_tree().process_frame
	var sprites := _parts_by_name(rig)
	var layers: Dictionary[StringName, Image] = {}
	layers[&"hair_back"] = await _render_layer(viewport, sprites, HAIR_PARTS, false)
	layers[&"body"] = await _render_layer(viewport, sprites, HEAD_PARTS + HAIR_PARTS, true)
	layers[&"head"] = await _render_layer(viewport, sprites, HEAD_PARTS, false)
	layers[&"head_blink"] = _blink_version(layers[&"head"], rig, sprites)
	for layer: StringName in ItemIcons.PORTRAIT_LAYERS:
		_write(layers[layer], id, layer)
	viewport.queue_free()


## 只顯示 visible_names（invert = true 時改成「除了這些以外都顯示」）後渲染，回傳像素化的圖。
func _render_layer(viewport: SubViewport, sprites: Dictionary[String, Sprite2D], names: Array[String], invert: bool) -> Image:
	for part_name in sprites:
		sprites[part_name].visible = (part_name not in names) if invert else (part_name in names)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var source := viewport.get_texture().get_image()
	source.convert(Image.FORMAT_RGBA8)
	var canvas := PixelCanvas.from_image_exact(source, ItemIcons.PORTRAIT_SIZE, COLOR_LEVELS)
	canvas.outline(OUTLINE)
	return canvas.image


## 骨架下所有零件圖（依零件名稱）。
func _parts_by_name(rig: CharacterRig) -> Dictionary[String, Sprite2D]:
	var result: Dictionary[String, Sprite2D] = {}
	var stack: Array[Node] = [rig]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Sprite2D and node.get_parent() is Bone2D:
			result[node.name] = node
		stack.append_array(node.get_children())
	return result


## 閉眼版：把頭層中的眼睛範圍抹成膚色，並畫上閉眼的眼線。眼睛位置來自角色定義（character.json 的 portrait.blink），
## 由頭部貼圖座標換算到立繪座標；沒有設定時閉眼層沿用睜眼圖（不會眨眼）。
func _blink_version(head: Image, rig: CharacterRig, sprites: Dictionary[String, Sprite2D]) -> Image:
	var blink := head.duplicate() as Image
	var setup: Variant = RigLibrary.character(rig.skin_id).get("portrait", {})
	var config: Variant = (setup as Dictionary).get("blink", null) if typeof(setup) == TYPE_DICTIONARY else null
	if typeof(config) != TYPE_DICTIONARY or not sprites.has(str(config.get("part", ""))):
		push_warning("[paint_portraits] %s 沒有眨眼設定（portrait.blink），閉眼層沿用睜眼圖。" % rig.skin_id)
		return blink
	var sprite: Sprite2D = sprites[str(config["part"])]
	var eye := _canvas_points(sprite, config.get("eye", []))
	var lid := _canvas_points(sprite, config.get("lid", []))
	if eye.size() < 3 or lid.size() < 2:
		push_warning("[paint_portraits] %s 的眨眼設定格式錯誤，閉眼層沿用睜眼圖。" % rig.skin_id)
		return blink
	var skin := _skin_color(head, eye)
	for y in blink.get_height():
		for x in blink.get_width():
			if blink.get_pixel(x, y).a > 0.0 and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), eye):
				blink.set_pixel(x, y, skin)
	for i in lid.size() - 1:
		_line(blink, Vector2i(lid[i]), Vector2i(lid[i + 1]), OUTLINE)
	return blink


## 貼圖座標（x,y 平鋪陣列）→ 立繪像素座標。
func _canvas_points(sprite: Sprite2D, flat: Variant) -> PackedVector2Array:
	var points := PackedVector2Array()
	if typeof(flat) != TYPE_ARRAY:
		return points
	var values: Array = flat
	for i in range(0, values.size() - 1, 2):
		var local := Vector2(float(values[i]), float(values[i + 1])) + sprite.offset
		points.append(sprite.get_global_transform() * local / float(SUPERSAMPLE))
	return points


## 眼睛範圍中心附近最常見的偏膚色顏色（色相涵蓋橘膚色與粉膚色）。
func _skin_color(image: Image, area: PackedVector2Array) -> Color:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in area:
		low = low.min(p)
		high = high.max(p)
	var counts: Dictionary[Color, int] = {}
	for y in range(int(low.y) - 3, int(high.y) + 4):
		for x in range(int(low.x) - 3, int(high.x) + 4):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.s > 0.08 and c.s < 0.45 and c.v > 0.6 and (c.h < 0.12 or c.h > 0.88):
				counts[c] = counts.get(c, 0) + 1
	var best := Color("f2d4c6")
	var best_count := 0
	for c in counts:
		if counts[c] > best_count:
			best = c
			best_count = counts[c]
	return best


func _line(image: Image, from: Vector2i, to: Vector2i, color: Color) -> void:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for i in steps + 1:
		var p := Vector2(from).lerp(Vector2(to), float(i) / maxf(1.0, steps))
		var x := roundi(p.x)
		var y := roundi(p.y)
		if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
			image.set_pixel(x, y, color)


func _write(image: Image, character: String, layer: StringName) -> void:
	var path := ItemIcons.PORTRAIT_DIR.path_join("%s_%s.png" % [character, layer])
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("寫入失敗 %s：%s" % [path, error_string(err)])
		return
	_written += 1
	if not _preview_dir.is_empty():
		var big := image.duplicate() as Image
		big.resize(image.get_width() * 4, image.get_height() * 4, Image.INTERPOLATE_NEAREST)
		big.save_png(_preview_dir.path_join("%s_%s_x4.png" % [character, layer]))
