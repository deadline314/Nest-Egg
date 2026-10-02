extends Node
## 開發工具：產生背包用的像素圖示 PNG（消耗品與劇情道具 32×32、武器 64×24；逐像素處理，不需要 GPU，可用 --headless 執行）。
## 用法：godot --headless --path . res://tools/art/paint_icons.tscn [-- --only=wataru_photo,rifle] [--preview=/絕對路徑]
## 會覆蓋 art/items/ 底下的同名 PNG；已換成正式美術的項目請用 --only 指定要重畫的。
## --preview：另外輸出每張圖示放大 8 倍的預覽圖，方便檢查。

const ICON_DIR := "res://art/items/icons"
const WEAPON_DIR := "res://art/items/weapons"
const PREVIEW_SCALE := 8

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICON_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WEAPON_DIR))
	if not _preview_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_preview_dir)
	for id in ItemIconPainter.ids():
		if _only.is_empty() or _only.has(id):
			_write(ItemIconPainter.paint(id), ICON_DIR, id)
	var weapons: Dictionary = RigLibrary.weapons().get("weapons", {})
	for visual_id: String in weapons.keys():
		if _only.is_empty() or _only.has(visual_id):
			_write(WeaponIconPainter.paint(visual_id), WEAPON_DIR, visual_id)
	print("paint_icons: wrote %d files" % _written)
	get_tree().quit()


func _write(canvas: PixelCanvas, dir: String, id: String) -> void:
	if canvas == null:
		return
	var path := dir.path_join(id + ".png")
	var err := canvas.save_png(path)
	if err != OK:
		push_error("寫入失敗 %s：%s" % [path, error_string(err)])
		return
	_written += 1
	if not _preview_dir.is_empty():
		canvas.upscaled(PREVIEW_SCALE).save_png(_preview_dir.path_join(id + "_x%d.png" % PREVIEW_SCALE))
