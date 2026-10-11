extends Node
## ST-22 安全區截圖：在真關卡裡播序章開場、第一章的診間醒來與回家過場，到指定台詞時截圖，確認演員的頭在 21:9 遮幅內。
## 只推進台詞、不改劇情；每段播完就結束。用法：
## godot --path . res://tools/cinematic_safe_area_capture.tscn -- --out=<絕對路徑資料夾>

const LEVEL := "res://data/levels/ch1_pawnshop_dawn.tres"
## 場景 id → 要截圖的台詞（含這句的畫面）。
const SHOTS := {
	&"ch1_p01_door": ["把門帶上喔，雨都跑進來了。"],
	&"ch1_c14_home": ["你已經回來了啊，我本來想留一壺。", "你什麼時候回來的？"],
	# 診間醒來最後接托盤的選擇，所以排在最後。
	&"ch1_c09_wake": ["歡迎回來。你死了十一分鐘。", "你的聲音跟電話亭很像。", "初次建檔免信用點費，之後復原照登記費扣，記憶也會磨損。"],
}

var _out := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 中文台詞 → 目前劇本語言的同一句（直接讀劇本檔的 ja／en 欄位）。
func _translations() -> Dictionary:
	var result := {}
	if Story.language == StoryLocale.SOURCE_LANGUAGE:
		return result
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/ch1_kasa.json"))
	var stack: Array = [data]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if node is Dictionary:
			if node.get("text") is String and node.has(Story.language):
				result[node["text"]] = node[Story.language]
			stack.append_array((node as Dictionary).values())
		elif node is Array:
			stack.append_array(node)
	return result


func _run() -> void:
	Story.auto_skip = false
	GameState.start_new_run(GameState.difficulties[1])
	for flag in [&"ch1_supper_done", &"ch1_handoff_done"]:
		GameState.set_flag(flag)
	var level := Level.new()
	level.configure(load(LEVEL))
	get_tree().root.add_child(level)
	await _frames(60)
	Story.reset_active_presentation(&"route")
	var translated := _translations()
	for id: StringName in SHOTS:
		# 選了日文或英文（--story-language）時，要找的台詞換成同一句的譯文（ST-2）。
		var wanted: Array = SHOTS[id].map(func(zh: String) -> String: return translated.get(zh, zh))
		var taken := 0
		if not Story.play(id, false):
			print("FAIL could not start %s" % id)
			continue
		for i in 300:
			if Story.is_cinematic_active() and Story._current_cinematic == id:
				break
			await _frames(1)
		for i in 6000:
			if not Story.is_cinematic_active() or taken >= wanted.size():
				break
			var player: CutscenePlayer = Story._player
			if player == null:
				await _frames(3)
				continue
			var text: String = player._dialogue._text.text
			var complete := player._dialogue.is_complete()
			if taken < wanted.size() and text == wanted[taken] and complete:
				await _frames(50)  # 鏡頭移動完
				var name := "ST-22-%s-%d%s" % [String(id).trim_prefix("ch1_"), taken + 1, "" if Story.language == "zh" else "-" + Story.language]
				if DisplayServer.get_name() == "headless":
					print("reached %s" % name)
				else:
					var image := preload("res://tools/viewport_capture.gd").image(get_viewport())
					print("saved %s (%s)" % [name, error_string(image.save_png(_out.path_join(name + ".png")))])
				taken += 1
			if complete and (taken >= wanted.size() or text != wanted[taken]):
				player._advance_requested = true
			await _frames(3)
		print("%s shots %d/%d" % [id, taken, wanted.size()])
		if taken >= wanted.size() and Story.is_cinematic_active():
			Story.reset_active_presentation(&"route")
			await _frames(10)
	get_tree().quit()
