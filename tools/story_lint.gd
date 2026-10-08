extends Node
## 開發工具：列出所有劇本與道具文字的品質檢查結果（規則見 design/04-story/WRITING.md、StoryLint）。
## 用法：godot --headless res://tools/story_lint.tscn
## 任何錯誤、警告或結構問題皆以非零代碼結束；-- --out=路徑 輸出完整來源清單。


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var issues: Array[Dictionary] = Story.lint()
	issues.append_array(StoryItems.lint())
	var source_root := "res://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source-root="):
			source_root = arg.trim_prefix("--source-root=")
	if not DirAccess.dir_exists_absolute(source_root.path_join("data")):
		push_error("Cannot read player text source: %s" % source_root)
		get_tree().quit(1)
		return
	var catalog := PlayerTextAudit.catalog(source_root)
	var validation := Story.validate()
	issues.append_array(PlayerTextAudit.lint(catalog))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			if file == null:
				push_error("Cannot write audit report: %s" % arg)
				get_tree().quit(1)
				return
			file.store_string(JSON.stringify({"entries": catalog, "issues": issues, "validation": validation}, "\t"))
	var errors := StoryLint.errors_of(issues)
	var warnings := StoryLint.warnings_of(issues)
	for issue in errors + warnings:
		print(StoryLint.format(issue))
	for problem in validation:
		print("[劇本] %s" % problem)
	print("玩家文字來源：%d 條" % catalog.size())
	print("劇本檢查：%d 個錯誤，%d 個警告" % [errors.size(), warnings.size()])
	get_tree().quit(1 if not issues.is_empty() or not validation.is_empty() else 0)
