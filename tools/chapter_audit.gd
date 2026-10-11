extends Node
## 章節逐區稽核報表（NE-233～235）：godot --headless --path . res://tools/chapter_audit.tscn [-- --chapter=ch2_heron] [--json=<輸出路徑>]
## 不指定章節就跑 data/release/campaign.json 列出、且有自己區域的每一章（見 core/chapter_audit.gd）。


func _ready() -> void:
	get_tree().quit.call_deferred()  # 報表中途出錯也會結束，錯誤留在輸出裡。
	var only := ""
	var json_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chapter="):
			only = arg.trim_prefix("--chapter=")
		elif arg.begins_with("--json="):
			json_path = arg.trim_prefix("--json=")
	var results: Array[Dictionary] = []
	for chapter: Dictionary in CampaignLedger.build()["chapters"]:
		if only.is_empty() or chapter["id"] == only:
			var result := ChapterAudit.audit(StringName(chapter["id"]))
			results.append(result)
			print(ChapterAudit.report(result))
	if not json_path.is_empty():
		var file := FileAccess.open(json_path, FileAccess.WRITE)
		if file == null:
			push_error("[ChapterAudit] 無法寫入 %s（%s）" % [json_path, error_string(FileAccess.get_open_error())])
			return
		file.store_string(JSON.stringify(results, "  "))
