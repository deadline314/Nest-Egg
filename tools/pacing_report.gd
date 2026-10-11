extends Node
## 第一章節奏報告：用法 godot --headless --path . res://tools/pacing_report.tscn
## 依資料估計每個區域與整章的遊玩時間、遭遇數、無遭遇的連續段（假設都在 core/pacing_estimate.gd 的常數）。

func _ready() -> void:
	var areas: Array = []
	var prologue: Dictionary = {}
	var design: Dictionary = (load("res://data/levels/ch1_design.json") as JSON).data["areas"]
	print("%-14s %5s %6s %6s %6s %6s %6s %6s %6s %5s %6s" % ["區域", "寬", "走路", "戰鬥", "對話", "氣泡", "拾取", "機關", "商店", "遭遇", "最長無遭遇"])
	for id in ["prologue", "pawnshop", "rooftop", "street", "booth_alley", "warehouse", "vault", "handoff", "lounge", "stall", "pawnshop_dawn"]:
		var data := load("res://data/levels/ch1_%s.tres" % id) as LevelData
		var ranges: Array[Vector2] = []
		for e: Dictionary in (design.get(id, {}) as Dictionary).get("encounters", []):
			ranges.append(Vector2(float(e["x0"]), float(e["x1"])))
		var entry := PacingEstimate.area(data, LevelBuilder.parse(data), func(scene: StringName) -> int: return Story.scene_lines(scene).size(), ranges)
		if id == "prologue":
			prologue = entry
		elif id != "pawnshop_dawn":
			areas.append(entry)
		print("%-14s %5d %6.0f %6.0f %6.0f %6.0f %6.0f %6.0f %6.0f %5d %6.0f" % [id, entry["width_tiles"], entry["walk"], entry["combat"], entry["talk"], entry["bubbles"], entry["pickups"], entry["puzzles"], entry["shop"], entry["encounters"], entry["max_quiet"]])
	var cutscenes := 0.0
	for id in ["ch1_c09_wake", "ch1_c14_home"]:
		cutscenes += _budget(id)
	var opening := PacingEstimate.along_path(prologue, PacingEstimate.PROLOGUE_PATH, Story.pacing_info)
	print("序章：第一次玩約 %.1f 分鐘（目標 %.0f–%.0f）；鎖操作的電影與對話佔 %.1f%%（上限 %.0f%%）" % [
		opening["first_time_minutes"], PacingEstimate.PROLOGUE_MINUTES.x, PacingEstimate.PROLOGUE_MINUTES.y,
		float(opening["locked_share"]) * 100.0, PacingEstimate.PROLOGUE_MAX_LOCKED_SHARE * 100.0])
	var chapter := PacingEstimate.chapter(areas, cutscenes)
	print("技巧純熟 %.1f 分鐘；第一次玩約 %.1f 分鐘（目標 %.0f–%.0f）；遭遇 %d 場、每分鐘 %.2f（目標 %.1f–%.1f）；過場佔 %.1f%%" % [
		float(chapter["seconds"]) / 60.0, chapter["first_time_minutes"], PacingEstimate.TARGET_MINUTES.x, PacingEstimate.TARGET_MINUTES.y,
		chapter["encounters"], chapter["encounters_per_minute"], PacingEstimate.TARGET_ENCOUNTERS_PER_MINUTE.x, PacingEstimate.TARGET_ENCOUNTERS_PER_MINUTE.y, float(chapter["cutscene_share"]) * 100.0])
	get_tree().quit()


func _budget(id: StringName) -> float:
	var scene: Variant = (Story.audit_data()["scenes"] as Dictionary).get(id)
	if not scene is Dictionary:
		push_error("[pacing_report] 找不到過場 %s，以 0 秒計" % id)
		return 0.0
	return float((scene as Dictionary).get("budget", 0.0))
