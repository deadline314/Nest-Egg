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
	get_tree().quit(1 if not (result["errors"] as PackedStringArray).is_empty() else 0)
