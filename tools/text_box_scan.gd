extends Node
## 過場文字框的掃描（NE-492）：所有章節的過場，每一句台詞與每個選擇框，修前（固定位置）與修後（避開演員、鏡頭讓位）各蓋住幾步。
## 用法：godot --headless --path . res://tools/text_box_scan.tscn


func _ready() -> void:
	var legacy_total := 0
	var now_total := 0
	var per_chapter := {}
	var remaining := PackedStringArray()
	for id: String in Story._scenes:
		var scene: Variant = Story._scenes[id]
		if not scene is Dictionary or not (scene as Dictionary).get("steps") is Array:
			continue
		var staged := false
		for step: Variant in scene["steps"]:
			if step is Dictionary and str(step.get("do", "")) == "scene":
				staged = true
				break
		if not staged:
			continue
		var chapter := id.get_slice("_", 0)
		var legacy := CutsceneChecker.text_box_problems(id, scene, true)
		var now := CutsceneChecker.text_box_problems(id, scene)
		var counts: Array = per_chapter.get(chapter, [0, 0, 0])
		counts[0] += 1
		counts[1] += legacy.size()
		counts[2] += now.size()
		per_chapter[chapter] = counts
		legacy_total += legacy.size()
		now_total += now.size()
		remaining.append_array(now)
	for chapter: String in per_chapter:
		print("TEXT_BOX_SCAN %s scenes=%d legacy=%d now=%d" % [chapter, per_chapter[chapter][0], per_chapter[chapter][1], per_chapter[chapter][2]])
	print("TEXT_BOX_SCAN total legacy=%d now=%d" % [legacy_total, now_total])
	for line in remaining:
		print("TEXT_BOX_SCAN remaining ", line)
		var sid := line.get_slice(" ", 0)
		for state in CutsceneChecker.settled_states(Story._scenes[sid]):
			if state["kind"] == "choice":
				print("TEXT_BOX_SCAN   cam=%s zoom=%.2f actors=%s" % [state["cam"], state["zoom"], state["actors"]])
	get_tree().quit(0 if now_total == 0 else 1)
