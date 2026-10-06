extends Node
## 場景合理性報告：用法 godot --headless --path . res://tools/scene_report.tscn [-- --level=ch1_street]
## 對 data/levels/ 的每一張關卡印出 SceneAudit 找到的問題（錯誤與警告），有錯誤時結束碼為 1。規則見 core/scene_audit.gd 與 skill scene-staging。


func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			only = arg.trim_prefix("--level=")
	var datas: Dictionary = {}
	var layouts: Dictionary = {}
	for path in SceneAudit.level_paths():
		var data := load(path) as LevelData
		if data == null:
			printerr("[scene_report] 讀不到 %s" % path)
			continue
		datas[path] = data
		layouts[path] = LevelBuilder.parse(data)
	var error_count := 0
	var warn_count := 0
	for path: String in datas:
		var data := datas[path] as LevelData
		if not only.is_empty() and not path.contains(only):
			continue
		var split := SceneAudit.split(SceneAudit.audit(data, layouts[path]))
		print("== %s（%d 錯誤、%d 警告）==" % [path.get_file(), split["errors"].size(), split["warnings"].size()])
		for issue: Dictionary in split["errors"] + split["warnings"]:
			print("  " + SceneAudit.describe(issue))
		error_count += split["errors"].size()
		warn_count += split["warnings"].size()
	var links := SceneAudit.split(SceneAudit.audit_links(datas, layouts))
	print("== 出入口連結（%d 錯誤、%d 警告）==" % [links["errors"].size(), links["warnings"].size()])
	for issue: Dictionary in links["errors"] + links["warnings"]:
		print("  " + SceneAudit.describe(issue))
	error_count += links["errors"].size()
	warn_count += links["warnings"].size()
	var stage_issues := SceneAudit.split(SceneAudit.audit_stages(Story.audit_data()["scenes"], StageLibrary.definition))
	print("== 過場舞台（%d 錯誤、%d 警告）==" % [stage_issues["errors"].size(), stage_issues["warnings"].size()])
	for issue: Dictionary in stage_issues["errors"] + stage_issues["warnings"]:
		print("  " + SceneAudit.describe(issue))
	error_count += stage_issues["errors"].size()
	warn_count += stage_issues["warnings"].size()
	print("總計：%d 錯誤、%d 警告" % [error_count, warn_count])
	get_tree().quit(1 if error_count > 0 else 0)
