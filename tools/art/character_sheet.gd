extends Node
## 開發工具：為角色輸出「對位檢查圖」——把一個角色的每張零件圖並排，疊上支點（紅十字）、
## 接下一個零件的關節（藍圈）與畫布邊界（灰框），一眼看出零件有沒有錯位、斷開或超出畫布。
## 用法（需要可渲染的環境）：
##   godot --path . res://tools/art/character_sheet.tscn [-- --only=old_k,mei] [--out=/絕對路徑資料夾]
## 預設輸出到 art/guides/characters/<角色>_guide.png；沒有指定 --only 時輸出所有角色。

const OUT_DIR := "res://art/guides/characters"
const CHARACTERS_DIR := "res://art/characters"
const SKELETON_PATH := "res://art/rigs/humanoid.json"
const ZOOM := 2.0
const COLUMNS := 6
const MARGIN := 10.0
const LABEL_HEIGHT := 14.0
const BACKGROUND := Color(0.1, 0.12, 0.18, 1.0)

var _only: PackedStringArray = []
var _out_dir := ""
var _written := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	var directory := _out_dir if not _out_dir.is_empty() else ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var ids := Array(DirAccess.get_directories_at(CHARACTERS_DIR))
	ids.sort()
	for id: String in ids:
		if _only.is_empty() or _only.has(id):
			await _paint_sheet(id, directory)
	print("character_sheet: wrote %d files" % _written)
	get_tree().quit()


## 骨頭 → 它的子骨頭靜止位置（單位：世界像素），子關節 = 支點 + 偏移 / texture_scale。
func _child_offsets() -> Dictionary:
	var children: Dictionary = {}
	var skeleton := RigLibrary.load_json(SKELETON_PATH)
	for bone: Dictionary in skeleton.get("bones", []):
		var parent := str(bone.get("parent", ""))
		if not children.has(parent):
			children[parent] = []
		children[parent].append(RigLibrary.vec2(bone.get("pos")))
	return children


func _paint_sheet(id: String, directory: String) -> void:
	var skin := RigLibrary.character(id)
	if skin.is_empty():
		return
	var scale_factor := 1.0 / float(skin.get("texture_scale", 0.25))
	var children := _child_offsets()
	# 每個貼圖用過它的第一根骨頭決定子關節（前後手腳共用同一張圖）。
	var bone_of: Dictionary = {}
	for part: Dictionary in skin.get("parts", []):
		if not bone_of.has(part["texture"]):
			bone_of[part["texture"]] = str(part["bone"])
	var textures: Dictionary = skin.get("textures", {})
	var names: Array = textures.keys()
	names.sort()
	var cells: Array[Dictionary] = []
	var cell_size := Vector2.ZERO
	for tex_name: String in names:
		var def: Dictionary = textures[tex_name]
		var size := RigLibrary.vec2(def.get("size"))
		var pivot := RigLibrary.vec2(def.get("pivot"))
		var joints: Array[Vector2] = []
		var is_armor := tex_name.begins_with("armor") or tex_name == "riot_shield"
		if not is_armor:
			for offset: Vector2 in children.get(bone_of.get(tex_name, ""), []):
				joints.append(pivot + offset * scale_factor)
		var image := Image.load_from_file(ProjectSettings.globalize_path(RigLibrary.character_dir(id).path_join(str(def.get("file")))))
		var tex: Texture2D = ImageTexture.create_from_image(image) if image != null else null
		cells.append({"name": tex_name, "size": size, "pivot": pivot, "joints": joints, "texture": tex})
		cell_size = Vector2(maxf(cell_size.x, size.x * ZOOM), maxf(cell_size.y, size.y * ZOOM))
	cell_size += Vector2(MARGIN * 2.0, MARGIN * 2.0 + LABEL_HEIGHT)
	var rows := ceili(float(cells.size()) / COLUMNS)
	var sheet_size := Vector2(cell_size.x * COLUMNS, cell_size.y * rows)
	var draw := func(canvas: CanvasItem) -> void:
		canvas.draw_rect(Rect2(Vector2.ZERO, sheet_size), BACKGROUND)
		for i in cells.size():
			var cell: Dictionary = cells[i]
			var origin := Vector2((i % COLUMNS) * cell_size.x + MARGIN, (i / COLUMNS) * cell_size.y + MARGIN + LABEL_HEIGHT)
			var size: Vector2 = cell["size"]
			canvas.draw_rect(Rect2(origin, size * ZOOM), Color(0.16, 0.19, 0.27, 1.0))
			var tex: Texture2D = cell["texture"]
			if tex != null:
				canvas.draw_texture_rect(tex, Rect2(origin, size * ZOOM), false)
			canvas.draw_rect(Rect2(origin, size * ZOOM), Color(0.6, 0.65, 0.75), false, 1.0)
			for joint: Vector2 in cell["joints"]:
				canvas.draw_arc(origin + joint * ZOOM, 2.5 * ZOOM, 0.0, TAU, 16, Color(0.3, 0.6, 1.0), 1.5)
			var pivot_at: Vector2 = origin + (cell["pivot"] as Vector2) * ZOOM
			canvas.draw_line(pivot_at - Vector2(8, 0), pivot_at + Vector2(8, 0), Color(1, 0.2, 0.2), 1.5)
			canvas.draw_line(pivot_at - Vector2(0, 8), pivot_at + Vector2(0, 8), Color(1, 0.2, 0.2), 1.5)
			canvas.draw_string(ThemeDB.fallback_font, origin + Vector2(0, -3), "%s %dx%d" % [cell["name"], size.x, size.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 0.95))
	await _render(sheet_size, draw, directory.path_join("%s_guide.png" % id))


func _render(size: Vector2, draw: Callable, path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := _Canvas.new()
	canvas.draw_callable = draw
	viewport.add_child(canvas)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var err := viewport.get_texture().get_image().save_png(path)
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
