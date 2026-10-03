extends Node
## 開發工具：列出所有劇本與道具文字的品質檢查結果（規則見 design/04-story/WRITING.md、StoryLint）。
## 用法：godot --headless res://tools/story_lint.tscn
## 有「錯誤」時以非零代碼結束；警告只列出來，請人工檢視。


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var issues: Array[Dictionary] = Story.lint()
	issues.append_array(StoryItems.lint())
	var errors := StoryLint.errors_of(issues)
	var warnings := StoryLint.warnings_of(issues)
	for issue in errors + warnings:
		print(StoryLint.format(issue))
	for problem in Story.validate():
		print("[劇本] %s" % problem)
	print("劇本檢查：%d 個錯誤，%d 個警告" % [errors.size(), warnings.size()])
	get_tree().quit(1 if not errors.is_empty() else 0)
