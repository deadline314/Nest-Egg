extends Node
## 跨章經濟對帳報表（NE-231）：godot --headless --path . res://tools/campaign_ledger.tscn [-- --json=<輸出路徑>]
## 印出每章主路／探索收入、主線／支線報酬、付款、必要補給、不刷錢計畫與成長價格（見 core/campaign_ledger.gd）。


func _ready() -> void:
	get_tree().quit.call_deferred()  # 報表中途出錯也會結束，錯誤留在輸出裡。
	var ledger := CampaignLedger.build()
	print(CampaignLedger.report(ledger))
	for chapter: Dictionary in ledger["chapters"]:
		var story := _story(chapter["id"])
		for issue in CampaignLedger.reward_mismatches(story):
			print("獎勵不一致：%s" % issue)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--json="):
			_write_json(arg.trim_prefix("--json="), ledger)


func _story(id: String) -> Dictionary:
	for path in Story.CHAPTER_PATHS:
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary and json.data.get("chapter") is Dictionary and json.data["chapter"].get("id") == id:
			return json.data
	return {}


func _write_json(path: String, ledger: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[CampaignLedger] 無法寫入 %s（%s）" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(ledger, "  "))
