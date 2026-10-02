extends Node
## 開發工具：以程式繪製所有角色零件與武器的暫代圖，輸出成 PNG（含 *_glow.png 自發光層）。
## 用法（需要可渲染的環境）：godot --path . res://tools/art/paint_assets.tscn [-- --only=rin,rifle,portrait_mei] [--guides]
## 會覆蓋 art/ 底下的同名 PNG；已換成正式美術的角色請用 --only 指定要重畫的項目。
## --guides：另外輸出對位參考圖到 art/guides/humanoid/（紅十字＝支點、藍圈＝接下一個零件的關節、灰框＝畫布）。

const HumanoidPainterScript := preload("res://tools/art/humanoid_painter.gd")
const WeaponPainterScript := preload("res://tools/art/weapon_painter.gd")
const PortraitPainterScript := preload("res://tools/art/portrait_painter.gd")
const PORTRAITS: Array[String] = ["rin", "mei", "old_k", "warden", "system"]
const PORTRAIT_DIR := "res://art/portraits"
const CHARACTERS: Array[String] = ["rin", "trooper", "grenadier", "enforcer", "warden"]
## 以 2 倍解析度繪製再縮小，取得平滑邊緣。
const SUPERSAMPLE := 2

const GUIDE_DIR := "res://art/guides/humanoid"
const GUIDE_SOURCE := "rin"
const GUIDE_SCALE := 4

var _only: PackedStringArray = []
var _guides := false
var _written := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg == "--guides":
			_guides = true
	_run.call_deferred()


func _run() -> void:
	for id in CHARACTERS:
		if _only.is_empty() or _only.has(id):
			await _paint_character(id)
	var weapons := RigLibrary.weapons()
	var defs: Dictionary = weapons.get("weapons", {})
	for weapon_id: String in defs.keys():
		if _only.is_empty() or _only.has(weapon_id):
			await _paint_weapon(weapon_id, defs[weapon_id])
	for id in PORTRAITS:
		if _only.is_empty() or _only.has("portrait_" + id):
			var painter: Object = PortraitPainterScript.new()
			await _render(PortraitPainterScript.SIZE, func(canvas: CanvasItem) -> void: painter.paint(canvas, id), PORTRAIT_DIR.path_join(id + ".png"))
	if _guides:
		await _paint_guides()
	print("paint_assets: wrote %d files" % _written)
	get_tree().quit()


func _paint_character(id: String) -> void:
	var skin := RigLibrary.character(id)
	if skin.is_empty():
		push_error("找不到角色定義：%s" % id)
		return
	var painter: Object = HumanoidPainterScript.new(skin.get("painter_style", {}))
	var dir := RigLibrary.character_dir(id)
	var textures: Dictionary = skin.get("textures", {})
	for tex_name: String in textures.keys():
		var def: Dictionary = textures[tex_name]
		var size := RigLibrary.vec2(def.get("size"), Vector2(16, 16))
		var pivot := RigLibrary.vec2(def.get("pivot"))
		var draw := func(canvas: CanvasItem, emissive: bool) -> void: painter.paint(canvas, tex_name, size, pivot, emissive)
		await _render(size, draw.bind(false), dir.path_join(str(def.get("file"))))
		if def.has("glow"):
			await _render(size, draw.bind(true), dir.path_join(str(def.get("glow"))))


func _paint_weapon(id: String, def: Dictionary) -> void:
	var size := RigLibrary.vec2(def.get("size"), Vector2(64, 24))
	var dir := RigLibrary.WEAPONS_PATH.get_base_dir()
	await _render(size, func(canvas: CanvasItem) -> void: WeaponPainterScript.paint(canvas, def, false), dir.path_join(str(def.get("file"))))
	if def.has("glow"):
		await _render(size, func(canvas: CanvasItem) -> void: WeaponPainterScript.paint(canvas, def, true), dir.path_join(str(def.get("glow"))))


## 對位參考圖：以主角的零件為底（半透明），標出畫布、支點與子關節，放大 GUIDE_SCALE 倍方便檢視。
func _paint_guides() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GUIDE_DIR))
	var skeleton := RigLibrary.load_json("res://art/rigs/humanoid.json")
	var children: Dictionary = {}  # bone -> [rest offset...]
	for bone: Dictionary in skeleton.get("bones", []):
		var parent := str(bone.get("parent", ""))
		if not children.has(parent):
			children[parent] = []
		children[parent].append(RigLibrary.vec2(bone.get("pos")))
	var guide_skins: Array[String] = [GUIDE_SOURCE, "enforcer"]
	var done: Dictionary = {}
	for skin_id in guide_skins:
		var skin := RigLibrary.character(skin_id)
		var scale_factor := 1.0 / float(skin.get("texture_scale", 0.25))
		var dir := RigLibrary.character_dir(skin_id)
		for part: Dictionary in skin.get("parts", []):
			var tex_name := str(part["texture"])
			if done.has(tex_name):
				continue
			done[tex_name] = true
			var def: Dictionary = skin["textures"][tex_name]
			var size := RigLibrary.vec2(def.get("size"))
			var pivot := RigLibrary.vec2(def.get("pivot"))
			var joints: Array = []
			if not tex_name.begins_with("armor") and tex_name != "riot_shield":
				for offset: Vector2 in children.get(str(part["bone"]), []):
					joints.append(pivot + offset * scale_factor)
			var image := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(def["file"])))
			var tex := ImageTexture.create_from_image(image) if image != null else null
			var draw := func(canvas: CanvasItem) -> void:
				canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.2, 1.0))
				if tex != null:
					canvas.draw_texture(tex, Vector2.ZERO, Color(1, 1, 1, 0.45))
				canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.65, 0.75), false, 0.5)
				for joint: Vector2 in joints:
					canvas.draw_arc(joint, 2.5, 0.0, TAU, 16, Color(0.3, 0.6, 1.0), 0.6)
				canvas.draw_line(pivot - Vector2(4, 0), pivot + Vector2(4, 0), Color(1, 0.2, 0.2), 0.6)
				canvas.draw_line(pivot - Vector2(0, 4), pivot + Vector2(0, 4), Color(1, 0.2, 0.2), 0.6)
			await _render(size * GUIDE_SCALE, func(canvas: CanvasItem) -> void:
				canvas.scale *= GUIDE_SCALE
				draw.call(canvas), GUIDE_DIR.path_join(tex_name + "_guide.png"), false)


func _render(size: Vector2, draw: Callable, path: String, supersample := true) -> void:
	var factor := SUPERSAMPLE if supersample else 1
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size * factor)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := _Canvas.new()
	canvas.draw_callable = draw
	canvas.scale = Vector2.ONE * factor
	viewport.add_child(canvas)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.resize(int(size.x), int(size.y), Image.INTERPOLATE_LANCZOS)
	var err := image.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("寫入失敗 %s：%s" % [path, error_string(err)])
	else:
		_written += 1
	viewport.queue_free()


class _Canvas:
	extends Node2D
	var draw_callable: Callable

	func _draw() -> void:
		if draw_callable.is_valid():
			draw_callable.call(self)
