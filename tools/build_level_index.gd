extends Node
## godot --headless --path . res://tools/build_level_index.tscn -- [--check]

const LevelIndex := preload("res://core/navigation/level_resource_index.gd")


func _ready() -> void:
	var generated := LevelIndex.authored_manifest()
	var expected := 0
	for filename in ResourceLoader.list_directory(LevelIndex.DIRECTORY):
		expected += int(filename.ends_with(".tres"))
	if expected == 0 or generated["levels"].size() != expected:
		push_error("[LevelCatalog] 無法從全部關卡產生索引。")
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args().has("--check"):
		var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(LevelIndex.MANIFEST))
		if not current is Dictionary or current.get("version") != LevelIndex.FORMAT or current.get("levels") != generated["levels"]:
			push_error("[LevelCatalog] 關卡索引已過期，請執行 build_level_index.tscn 更新。")
			get_tree().quit(2)
			return
	else:
		var file := FileAccess.open(LevelIndex.MANIFEST, FileAccess.WRITE)
		if file == null:
			push_error("[LevelCatalog] 無法寫入 %s（%s）。" % [LevelIndex.MANIFEST, FileAccess.get_open_error()])
			get_tree().quit(2)
			return
		file.store_string(JSON.stringify(generated, "\t") + "\n")
		file.close()
	print("[LevelCatalog] 關卡索引已驗證：%d 區域。" % expected)
	get_tree().quit()
