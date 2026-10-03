extends Node
## 開發工具：以程式繪製彈種圖示（滿／空／低三種狀態），輸出到 art/ammo/。只用 CPU，可用 --headless 執行。
## 用法：godot --headless --path . res://tools/art/paint_ammo.tscn [-- --only=rifle,shell]

const OUT_DIR := "res://art/ammo"

var _only: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var written := 0
	for spec in AmmoIconPainter.CATALOG:
		var id := str(spec["id"])
		if not _only.is_empty() and not _only.has(id):
			continue
		var images := AmmoIconPainter.paint(spec)
		for state: String in ["full", "empty", "low"]:
			var canvas: EnvCanvas = images[state]
			var file := "%s.png" % id if state == "full" else "%s_%s.png" % [id, state]
			var err := canvas.image.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file)))
			if err != OK:
				push_error("寫入失敗 %s：%s" % [file, error_string(err)])
			else:
				written += 1
	print("paint_ammo: wrote %d files" % written)
	get_tree().quit()
