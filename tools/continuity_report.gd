extends Node
## 連續性報告：用法 godot --headless --path . res://tools/continuity_report.tscn
## 印出旗標表（誰寫、誰讀）、旗標問題與沒有任何引用的場景，見 core/continuity_audit.gd 與 skill continuity-qa。


func _ready() -> void:
	var view := Story.audit_data()
	var table := ContinuityAudit.flag_table(view["scenes"], view["death"], ContinuityAudit.read_text_files())
	var names: Array = table.keys()
	names.sort()
	print("== 旗標表（%d 個）==" % names.size())
	for flag: String in names:
		print("%s\n  寫：%s\n  讀：%s" % [flag, "、".join(table[flag]["writes"]), "、".join(table[flag]["reads"])])
	var result := ContinuityAudit.flag_problems(table)
	print("== 錯誤 ==")
	for message in result["errors"] as PackedStringArray:
		print(message)
	print("== 警告 ==")
	for message in result["warnings"] as PackedStringArray:
		print(message)
	var files := ContinuityAudit.read_text_files(ContinuityAudit.SCAN_ROOTS, ["res://data/story/"])
	print("== 沒有任何引用的場景 ==")
	for id in ContinuityAudit.orphan_scenes(ContinuityAudit.scene_references(view["scenes"], view["respawn"], view["death"], files)):
		print(id)
	# 不可達內容：從兩個起點（新遊戲、舊的雨夜關卡）模擬旗標圖，劇情旗標只能由場景設定
	var datas: Dictionary = {}
	var layouts: Dictionary = {}
	for path in SceneAudit.level_paths():
		var data := load(path) as LevelData
		datas[path] = data
		layouts[path] = LevelBuilder.parse(data)
	var always: Array = []
	for tables: Dictionary in [view["respawn"], view["death"]]:
		for chapter: String in tables:
			for entry: Variant in tables[chapter]:
				if typeof(entry) == TYPE_DICTIONARY:
					always.append(str((entry as Dictionary).get("scene", "")))
	var model := ContinuityAudit.level_model(datas, layouts, view["scenes"], always, [])
	var reach := ContinuityAudit.unreachable_problems(model, ["res://data/levels/ch1_pawnshop.tres", "res://data/levels/level_01.tres"])
	print("== 不可達內容 ==")
	for message in reach["errors"] as PackedStringArray:
		print("錯誤：" + message)
	for message in reach["warnings"] as PackedStringArray:
		print("警告：" + message)
	var failed := not (result["errors"] as PackedStringArray).is_empty() or not (reach["errors"] as PackedStringArray).is_empty()
	get_tree().quit(1 if failed else 0)
