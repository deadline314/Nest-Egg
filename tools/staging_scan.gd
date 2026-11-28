extends Node
## 過場的鏡頭與走位自動掃描（總檢第 21 項，NE-495）：從過場資料的靜態模型（CutsceneChecker.settled_states）掃所有有舞台的過場，
## 逐段記下可以算出來的問題，輸出 JSON 給總檢表使用。看得出來但算不出來的（姿勢、道具、前景遮擋、畫風、接縫的觀感）留給截圖目看。
## 用法：godot --headless --path . res://tools/staging_scan.tscn -- --out=<絕對路徑.json>
##
## 項目（編號同總檢清單）：
## 1 面對面：說話時講者與最近的聽者互相面對；兩人在畫面內、離左右邊緣至少畫面寬 8%（正要走進或走出的那一步不算）。
## 2 鏡頭：講者沒換卻來回（A→B→A）、位移不到 8 像素的小抖動。
## 3 進出場：畫面沒被蓋住時演員在畫面內憑空出現、消失，或在畫面內換位置卻沒有走（瞬移）。
## 5 構圖：每個停下來的步驟記錄演員外框佔畫面面積的比例；主體中心不在畫面寬 25%～75%。建立鏡頭（舞台第一個停頓是旁白或標題）標成例外。
## 6 節奏：自動前進的台詞與旁白，停留時間比讀完所需短（讀不完）或超過兩倍；連續 3 句以上鏡頭與演員完全不動。
## 8 接縫：開頭是硬切（第一個舞台 fade 為 0）、結尾沒有淡出（只記錄，觀感目看）。
## 9 比例：舞台的美術遠近不同，縮放本來就不同，所以比兩種「換算回世界尺寸」的數字（鏡頭倍率不算）：
##   同一個舞台在不同過場裡，同一個外觀的縮放相差超過 5%；同一段裡站在同一條地面線上的兩個角色的身高比，和這兩個角色在其他過場的身高比相差超過 5%
##   （腳底高度不同＝刻意的前後景深，例如隔著玻璃的室內，不比）。

const EDGE := 0.08
const NUDGE := 8.0
const CENTER_LOW := 0.25
const CENTER_HIGH := 0.75
const SCALE_TOLERANCE := 0.05
const CHANGE_STEPS: PackedStringArray = ["camera", "scene", "actor", "move", "pose", "face", "remove", "fx", "prop", "prop_move", "prop_hold", "prop_release", "prop_visible", "reach", "world_action", "transition", "fade"]
const SAFE := Rect2(0.0, CutsceneChecker.LETTERBOX_BAR, 640.0, 360.0 - CutsceneChecker.LETTERBOX_BAR * 2.0)

var _out := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	var records: Array[Dictionary] = []
	var stage_scale: Dictionary = {}
	var pair_ratios: Dictionary = {}
	for id: String in Story._scenes:
		var scene: Variant = Story._scenes[id]
		if not scene is Dictionary or not (scene as Dictionary).get("steps") is Array or not _staged(scene):
			continue
		var record := _scan(id, scene)
		# 9 比例（同一個舞台）：和最早用這個舞台的過場比。
		for key: String in record["scales"]:
			var scale: float = record["scales"][key]
			if stage_scale.has(key):
				var first: Array = stage_scale[key]
				if absf(scale - float(first[1])) / float(first[1]) > SCALE_TOLERANCE:
					record["issues"].append({"item": 9, "step": 0, "note": "舞台與外觀 %s 的縮放 %.2f，%s 是 %.2f" % [key, scale, first[0], first[1]]})
			else:
				stage_scale[key] = [id, scale]
		for pair: String in record["ratios"]:
			var list: Array = pair_ratios.get(pair, [])
			list.append([id, record["ratios"][pair]])
			pair_ratios[pair] = list
		records.append(record)
	# 9 比例（兩個角色的身高比）：和這一對角色最常見的身高比相差超過 5%。
	for pair: String in pair_ratios:
		var list: Array = pair_ratios[pair]
		if list.size() < 2:
			continue
		var values: Array = list.map(func(entry: Array) -> float: return float(entry[1]))
		values.sort()
		var typical: float = values[values.size() / 2]
		for entry: Array in list:
			if absf(float(entry[1]) - typical) / typical > SCALE_TOLERANCE:
				for record in records:
					if record["id"] == entry[0]:
						record["issues"].append({"item": 9, "step": 0, "note": "%s 的身高比 %.2f，其他過場通常是 %.2f" % [pair, entry[1], typical]})
	var file := FileAccess.open(_out, FileAccess.WRITE) if not _out.is_empty() else null
	if file != null:
		file.store_string(JSON.stringify(records, " "))
		file.close()
	var counts := {}
	for record in records:
		var items := {}
		for issue: Dictionary in record["issues"]:
			items[int(issue["item"])] = true
		for item: int in items:
			counts[item] = int(counts.get(item, 0)) + 1
	print("STAGING_SCAN scenes=%d per_item=%s out=%s" % [records.size(), counts, _out])
	get_tree().quit()


func _staged(scene: Dictionary) -> bool:
	for step: Variant in scene["steps"]:
		if step is Dictionary and str(step.get("do", "")) == "scene":
			return true
	return false


func _scan(id: String, scene: Dictionary) -> Dictionary:
	var steps: Array = scene["steps"]
	var issues: Array[Dictionary] = []
	var shares: Array[Dictionary] = []
	var speaker_of := _speaker_map(steps)
	var states := CutsceneChecker.settled_states(scene)
	var state_at := {}
	for state in states:
		state_at[int(state["index"])] = state
	var moves := _move_indices(steps)
	# 逐步追蹤：畫面有沒有被蓋住、演員位置、鏡頭、靜止的連續台詞、舞台第一個停頓。
	var covered := true
	var feet: Dictionary = {}
	var cam := Vector2(320, 180)
	var zoom := 1.0
	var cams: Array[Dictionary] = []
	var still_run := 0
	var stage_first_settled := true
	var last_speaker := ""
	var scales := {}
	var heights := {}
	var stage_id := ""
	var says := 0
	var opening := "hard"
	var first_stage := true
	var ends_faded := false
	for i in steps.size():
		var index := i + 1
		var step: Variant = steps[i]
		if not step is Dictionary:
			continue
		var kind := str(step.get("do", ""))
		if state_at.has(index):
			cam = state_at[index]["cam"]
			zoom = state_at[index]["zoom"]
		match kind:
			"scene":
				stage_id = str(step.get("id", ""))
				var fade_in := float(step.get("fade", 0.5 if covered else 0.0))
				# 第一個舞台一定揭開開場的黑幕（fade 0 是硬切）；之後的舞台只有 fade 大於 0 才揭開。
				if fade_in > 0.0 or first_stage:
					covered = false
				if first_stage:
					opening = "fade %.1f" % fade_in if fade_in > 0.0 else "hard"
					first_stage = false
				feet.clear()
				stage_first_settled = true
				cams.append({"index": index, "pos": _cam_after(scene, index), "speaker": last_speaker})
			"camera":
				cams.append({"index": index, "pos": _cam_after(scene, index), "speaker": last_speaker})
			"fade":
				covered = float(step.get("to", 0.0)) >= 0.5
				ends_faded = covered
			"transition":
				covered = str(step.get("mode", "cover")) == "cover"
				ends_faded = covered
			"actor":
				var actor_id := str(step.get("id", ""))
				var pos := StageLayers.vec2_of(step.get("pos"))
				var view := _view(scene, index)
				var rig := str(step.get("kind", ""))
				if not rig.is_empty() and FileAccess.file_exists(RigLibrary.CHARACTER_PATH % rig):
					scales["%s|%s" % [stage_id, rig]] = float(step.get("scale", 2.0))
					heights[rig] = [RigLibrary.standing_height(rig) * float(step.get("scale", 2.0)), pos.y]
				if not covered and not stage_first_settled:
					if not feet.has(actor_id) and view.has_point(pos):
						issues.append({"item": 3, "step": index, "note": "「%s」在畫面內憑空出現" % actor_id})
					elif feet.has(actor_id) and pos.distance_to(feet[actor_id]) > NUDGE and view.has_point(pos) and view.has_point(feet[actor_id]):
						issues.append({"item": 3, "step": index, "note": "「%s」在畫面內瞬移 %.0f 像素" % [actor_id, pos.distance_to(feet[actor_id])]})
				feet[actor_id] = pos
			"move":
				if feet.has(str(step.get("id", ""))):
					feet[str(step["id"])] = StageLayers.vec2_of(step.get("to"))
			"remove":
				var gone := str(step.get("id", ""))
				if feet.has(gone) and not covered and _view(scene, index).has_point(feet[gone]) and not _moved_near(moves, gone, index, 2):
					issues.append({"item": 3, "step": index, "note": "「%s」在畫面內突然消失" % gone})
				feet.erase(gone)
		# 6 連續不動的台詞。
		if kind in ["say", "narrate"]:
			still_run += 1
			if still_run == 3:
				issues.append({"item": 6, "step": index, "note": "連續 3 句以上鏡頭與演員完全不動"})
		elif kind in CHANGE_STEPS:
			still_run = 0
		if kind == "say":
			says += 1
			_check_say_pacing(step, index, issues)
			last_speaker = str(step.get("speaker", ""))
		elif kind == "narrate":
			_check_narrate_pacing(step, index, issues)
		if state_at.has(index):
			var state: Dictionary = state_at[index]
			var establishing := stage_first_settled and kind in ["narrate", "title"]
			shares.append(_composition(state, index, establishing, issues))
			if kind == "say":
				_check_faces(state, index, speaker_of, moves, issues)
			stage_first_settled = false
		if kind in ["say", "narrate", "choice", "title", "wait"]:
			ends_faded = false
	_check_camera(cams, issues)
	var ratios := {}
	var rigs := heights.keys()
	rigs.sort()
	for a in rigs.size():
		for b in range(a + 1, rigs.size()):
			var first: Array = heights[rigs[a]]
			var second: Array = heights[rigs[b]]
			if float(second[0]) > 0.0 and absf(float(first[1]) - float(second[1])) <= 4.0:
				ratios["%s/%s" % [rigs[a], rigs[b]]] = snappedf(float(first[0]) / float(second[0]), 0.001)
	return {"id": id, "chapter": id.get_slice("_", 0), "says": says, "issues": issues, "shares": shares, "scales": scales, "ratios": ratios,
			"opening": opening, "ends_faded": ends_faded, "silence_music": bool(scene.get("silence_music", false))}


## 講者 id → 演員 id（演員的 speaker 欄位，或同名）。
func _speaker_map(steps: Array) -> Dictionary:
	var result := {}
	for step: Variant in steps:
		if step is Dictionary and str(step.get("do", "")) == "actor":
			result[str(step.get("speaker", step.get("id", "")))] = str(step.get("id", ""))
	return result


func _move_indices(steps: Array) -> Dictionary:
	var result := {}
	for i in steps.size():
		var step: Variant = steps[i]
		if step is Dictionary and str(step.get("do", "")) in ["move", "actor", "remove"]:
			var list: Array = result.get(str(step.get("id", "")), [])
			if str(step.get("do", "")) == "move":
				list.append(i + 1)
			result[str(step.get("id", ""))] = list
	return result


func _moved_near(moves: Dictionary, actor_id: String, index: int, reach: int) -> bool:
	for at: int in moves.get(actor_id, []):
		if absi(at - index) <= reach:
			return true
	return false


## 鏡頭在 index 這一步之後看到的舞台範圍（從最近一個停頓狀態推；沒有就用預設）。
func _view(scene: Dictionary, index: int) -> Rect2:
	var state := _state_before(scene, index)
	var cam: Vector2 = state.get("cam", Vector2(320, 180))
	var zoom: float = state.get("zoom", 1.0)
	return TextBoxPlacement.view_rect(cam, zoom, Vector2(640, 360))


func _cam_after(scene: Dictionary, index: int) -> Array:
	var state := _state_after(scene, index)
	return [state.get("cam", Vector2(320, 180)), state.get("zoom", 1.0)]


func _state_before(scene: Dictionary, index: int) -> Dictionary:
	var best := {}
	for state in CutsceneChecker.settled_states(scene):
		if int(state["index"]) <= index:
			best = state
	return best if not best.is_empty() else _state_after(scene, index)


func _state_after(scene: Dictionary, index: int) -> Dictionary:
	for state in CutsceneChecker.settled_states(scene):
		if int(state["index"]) >= index:
			return state
	return {}


func _screen_x(feet: Vector2, cam: Vector2, zoom: float) -> float:
	return 320.0 + (feet.x - cam.x) * zoom


func _visible_bodies(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: Dictionary in state["actors"]:
		if float(actor["tall"]) <= 0.0:
			continue
		var x := _screen_x(actor["feet"], state["cam"], state["zoom"])
		if x >= 0.0 and x <= 640.0:
			result.append(actor)
	return result


## 1 面對面與邊緣。
func _check_faces(state: Dictionary, index: int, speaker_of: Dictionary, moves: Dictionary, issues: Array[Dictionary]) -> void:
	var bodies := _visible_bodies(state)
	var speaker_id := str(speaker_of.get(str(state["step"].get("speaker", "")), state["step"].get("speaker", "")))
	var speaker: Dictionary = {}
	for actor: Dictionary in state["actors"]:
		if actor["id"] == speaker_id:
			speaker = actor
	if speaker.is_empty() or float(speaker["tall"]) <= 0.0:
		return
	var sx := _screen_x(speaker["feet"], state["cam"], state["zoom"])
	if sx < 0.0 or sx > 640.0:
		if not bodies.is_empty():
			issues.append({"item": 1, "step": index, "note": "講者「%s」在畫面外，畫面裡是別人" % speaker_id})
		return
	var listener: Dictionary = {}
	for actor: Dictionary in bodies:
		if actor["id"] != speaker_id and (listener.is_empty() or absf(actor["feet"].x - speaker["feet"].x) < absf(listener["feet"].x - speaker["feet"].x)):
			listener = actor
	for actor: Dictionary in [speaker, listener]:
		if actor.is_empty() or _moved_near(moves, actor["id"], index, 1):
			continue
		var x := _screen_x(actor["feet"], state["cam"], state["zoom"])
		if x < 640.0 * EDGE or x > 640.0 * (1.0 - EDGE):
			issues.append({"item": 1, "step": index, "note": "「%s」貼著畫面邊緣（x=%.0f）" % [actor["id"], x]})
	if listener.is_empty():
		return
	var dx: float = listener["feet"].x - speaker["feet"].x
	if absf(dx) < 4.0:
		return
	var toward := 1 if dx > 0.0 else -1
	if int(speaker["facing"]) != toward:
		issues.append({"item": 1, "step": index, "note": "講者「%s」背對聽者「%s」" % [speaker_id, listener["id"]]})
	if int(listener["facing"]) != -toward:
		issues.append({"item": 1, "step": index, "note": "聽者「%s」背對講者「%s」" % [listener["id"], speaker_id]})


## 5 構圖：演員外框佔安全範圍面積的比例與主體中心。
func _composition(state: Dictionary, index: int, establishing: bool, issues: Array[Dictionary]) -> Dictionary:
	var area := 0.0
	var union := Rect2()
	for actor: Dictionary in _visible_bodies(state):
		var height: float = float(actor["tall"]) * float(state["zoom"])
		var x := _screen_x(actor["feet"], state["cam"], state["zoom"])
		var y: float = 180.0 + (actor["feet"].y - state["cam"].y) * state["zoom"]
		var body := Rect2(x - height * 0.21, y - height, height * 0.42, height).intersection(SAFE)
		area += body.get_area()
		union = body if not union.has_area() else union.merge(body)
	var share := area / SAFE.get_area()
	var kind := str(state["kind"])
	if union.has_area() and kind in ["say", "choice"]:
		var center := union.get_center().x / 640.0
		if center < CENTER_LOW or center > CENTER_HIGH:
			issues.append({"item": 5, "step": index, "note": "主體中心在畫面寬 %.0f%%" % (center * 100.0)})
	return {"step": index, "kind": kind, "share": snappedf(share, 0.0001), "establishing": establishing, "actors": _visible_bodies(state).size()}


## 6 自動前進的台詞：停留時間對照讀完所需。
func _check_say_pacing(step: Dictionary, index: int, issues: Array[Dictionary]) -> void:
	var auto := float(step.get("auto", 0.0))
	if auto <= 0.0:
		return
	var need := CutsceneChecker.SAY_BASE + CutsceneChecker.SAY_PER_CHAR * str(step.get("text", "")).length()
	if auto < need:
		issues.append({"item": 6, "step": index, "kind": "short", "note": "自動台詞停 %.1f 秒，讀完要 %.1f 秒" % [auto, need]})
	elif auto > need * 2.0:
		issues.append({"item": 6, "step": index, "kind": "long", "note": "自動台詞停 %.1f 秒，超過讀完所需 %.1f 秒的兩倍" % [auto, need]})


func _check_narrate_pacing(step: Dictionary, index: int, issues: Array[Dictionary]) -> void:
	var text := "".join(PackedStringArray((step.get("lines", []) as Array).map(func(l: Variant) -> String: return str(l))))
	var shown := maxf(0.4, text.length() * 0.05) + float(step.get("time", 2.2))
	var need := CutsceneChecker.SAY_BASE + CutsceneChecker.SAY_PER_CHAR * text.length()
	if shown < need:
		issues.append({"item": 6, "step": index, "kind": "short", "note": "旁白顯示 %.1f 秒，讀完要 %.1f 秒" % [shown, need]})
	elif shown > need * 2.0:
		issues.append({"item": 6, "step": index, "kind": "long", "note": "旁白顯示 %.1f 秒，超過讀完所需 %.1f 秒的兩倍" % [shown, need]})


## 2 鏡頭：講者沒換卻來回、或幾乎沒動的小抖動。
func _check_camera(cams: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for i in range(1, cams.size()):
		var a: Array = cams[i - 1]["pos"]
		var b: Array = cams[i]["pos"]
		var moved: float = (b[0] as Vector2).distance_to(a[0])
		var zoomed: float = absf(float(b[1]) - float(a[1])) / maxf(0.01, float(a[1]))
		if moved > 0.5 and moved < NUDGE and zoomed < 0.03:
			issues.append({"item": 2, "step": cams[i]["index"], "note": "鏡頭只動了 %.1f 像素" % moved})
		if i >= 2:
			var c: Array = cams[i - 2]["pos"]
			if (b[0] as Vector2).distance_to(c[0]) < 4.0 and moved > NUDGE and cams[i]["speaker"] == cams[i - 1]["speaker"]:
				issues.append({"item": 2, "step": cams[i]["index"], "note": "講者沒換，鏡頭來回（回到兩步前的位置）"})
