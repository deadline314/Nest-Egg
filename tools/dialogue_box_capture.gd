extends Node
## 通訊對話框的原生截圖（NE-274）。
##
## 用法（原生）：
##   godot --path . res://tools/dialogue_box_capture.tscn -- --out=<絕對資料夾> [--tag=<標籤>] [--level=ch1_street]
##       [--text-scale=1.0] [--reduce-motion] [--self-check（可無頭）]
## 超過正式設定上限的倍率是局部文字壓測，不改全域上限；1.5 必須真的取得 17 字級。
## 在真實關卡裡依序送出幾句通訊，每句拍三張：剛滑入（字還在出現）、整句出現、快要換句之前。
## 涵蓋：短句、兩行的長句、不同講者的顏色、正式的系統廣播（沒有人臉的頭像）、沒有頭像的講者。
## 另外量：對話框有沒有超出畫面、字有沒有被裁掉、內文與底色的對比（至少 4.5:1）。
## 輸出 <標籤>-<編號>-<講者>-<階段>.png 與 <標籤>-index.json。

const LINES := [
	{"speaker": "rin", "text": "聽得到。"},
	{"speaker": "old_k", "text": "倉庫的電是從隔壁偷接的，燈會閃。看到快壞的燈就繞過去，別站在下面。"},
	{"speaker": "mei", "text": "姊，你那邊訊號好差。"},
	{"speaker": "system", "text": "本區進入節電時段。請住戶留在室內。"},
	{"speaker": "", "name": "不明訊號", "color": "#9aa7b4", "text": "……有人在聽嗎。"},
]

var _out := ""
var _tag := "dialogue"
var _level := "ch1_street"
var _text_scale := 1.0
var _reduce := false
var _failures := 0
var _self_check := false
var _local_font_override := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=").replace("\\", "/")
		elif argument.begins_with("--tag="):
			_tag = argument.trim_prefix("--tag=")
		elif argument.begins_with("--level="):
			_level = argument.trim_prefix("--level=")
		elif argument.begins_with("--text-scale="):
			_text_scale = float(argument.trim_prefix("--text-scale="))
		elif argument == "--reduce-motion":
			_reduce = true
		elif argument == "--self-check":
			_self_check = true
	if not _out.is_absolute_path() or not is_finite(_text_scale) or _text_scale < 1.0 or _text_scale > 1.5 or (DisplayServer.get_name() == "headless" and not _self_check):
		push_error("[DialogueBoxCapture] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	if _self_check:
		_run_self_check.call_deferred()
	else:
		_run.call_deferred()


## 正式設定保持原上限；只有這張卡片的文字使用要求字級。
func _apply_capture_fonts(labels: Array[Label]) -> void:
	_local_font_override = _text_scale > Settings.get_ui_text_scale() + 0.001
	if _local_font_override:
		for label in labels:
			label.add_theme_font_size_override(&"font_size", roundi(UiKit.FS_BODY * _text_scale))


func _font_state(labels: Array[Label]) -> Dictionary:
	var actual: Array[int] = []
	var expected := roundi(UiKit.FS_BODY * _text_scale)
	for label in labels:
		actual.append(label.get_theme_font_size(&"font_size"))
	return {"requested_scale": _text_scale, "effective_setting_scale": Settings.get_ui_text_scale(),
		"local_font_override": _local_font_override, "expected_font_size": expected,
		"base_font_size": UiKit.FS_BODY, "actual_renderer_ratios": actual.map(func(value: int) -> float: return float(value) / UiKit.FS_BODY),
		"actual_font_sizes": actual, "font_sizes_match": actual.all(func(value: int) -> bool: return value == expected)}


## 同一字級判定先拒絕舊的 1.5→1.2 路徑，再驗局部覆寫；不需要關卡或 GPU。
func _run_self_check() -> void:
	Settings.use_storage("user://dialogue-box-capture.cfg")
	Settings.set_ui_text_scale(_text_scale)
	var label := UiKit.label("倉庫的電", UiKit.FS_BODY)
	add_child(label)
	var labels: Array[Label] = [label]
	var original := _font_state(labels)
	_apply_capture_fonts(labels)
	var candidate := _font_state(labels)
	var accepted := bool(candidate["font_sizes_match"]) and (not bool(original["font_sizes_match"]) if _text_scale > 1.2 else bool(original["font_sizes_match"]))
	_write_report({"self_check": true, "original_without_override": original, "candidate": candidate, "passed": accepted})
	print("DIALOGUE_FONT_SELF_CHECK ", JSON.stringify({"original": original, "candidate": candidate, "passed": accepted}))
	Settings.use_storage(Settings.DEFAULT_PATH)
	get_tree().quit(0 if accepted and _failures == 0 else 1)


func _run() -> void:
	Settings.use_storage("user://dialogue-box-capture.cfg")
	Settings.erase_section(Settings.DISPLAY_SECTION)
	Settings.set_ui_text_scale(_text_scale)
	Settings.set_reduce_ui_motion(_reduce)
	Story.auto_skip = false
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	add_child(LightKit.create_environment())
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load("res://data/levels/%s.tres" % _level) as LevelData)
	add_child(level)
	await _frames(90)
	level.player.health.setup(999, 0.0)
	# 拍攝固定既有角色姿勢與鏡頭，避免待機骨架讓避讓位置發生次像素變化。
	# 通訊卡、逐字、停留與所有 UI 照常更新；不是凍結介面來通過減少動態。
	level.player.process_mode = Node.PROCESS_MODE_DISABLED
	for actor: Node in get_tree().get_nodes_in_group(NpcActor.GROUP):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	level.camera.position_smoothing_enabled = false
	level.camera.process_mode = Node.PROCESS_MODE_DISABLED
	level.camera.force_update_scroll()
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	var layer: DialogueLayer = Story._layer
	layer.cancel_radio()
	_apply_capture_fonts([layer._radio_name, layer._radio_text, layer._radio_continue])
	await _frames(30)
	var report := {"tag": _tag, "text_scale": _text_scale, "reduce_motion": _reduce,
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"display": DisplayServer.get_name(), "scope": "Arranged five-speaker capture; local font stress above public 1.2 limit, not human play",
		"fixture": "Player/NPC poses and camera held; radio UI and reading clocks process normally; enemies removed as in original capture",
		"lines": [], "captures": [], "decoration_checks": []}
	var long_height := 0.0
	for index in LINES.size():
		var spec: Dictionary = LINES[index]
		var info := Story.speaker(str(spec["speaker"])) if not str(spec["speaker"]).is_empty() else {}
		var line := {
			"speaker": str(spec["speaker"]),
			"name": str(spec.get("name", info.get("name", ""))),
			"color": Color(str(spec.get("color", info.get("color", "#ffffff")))),
			"portrait": str(info.get("portrait", "")),
			"text": str(spec["text"]),
		}
		var lines: Array[Dictionary] = [line]
		layer.enqueue_radio(StringName("capture_%d" % index), lines)
		var who := str(spec["speaker"]) if not str(spec["speaker"]).is_empty() else "unknown"
		await _frames(7)
		var early := await _shot("%s-%d-%s-in" % [_tag, index + 1, who], layer, who, false)
		report["captures"].append(early)
		var limit := 600
		while layer._radio_text.visible_ratio < 1.0 and limit > 0:
			await get_tree().process_frame
			limit -= 1
		await _frames(12)
		var full := await _shot("%s-%d-%s-full" % [_tag, index + 1, who], layer, who)
		report["lines"].append(full)
		report["captures"].append(full)
		if not layer._radio_active or layer._radio_text.visible_ratio < 1.0 or full["name"] != line["name"]:
			_fail("未取得同一講者的整句畫面：" + who)
		if not is_equal_approx(float(early["rect"][3]), float(full["rect"][3])):
			_fail("逐字顯示期間面板改高：" + who)
		if who == "old_k":
			long_height = float(full["rect"][3])
		if who == "mei" and (long_height <= float(full["rect"][3]) or int(full["lines"]) != 1):
			_fail("長句之後的短句沒有縮回一行")
		if _reduce:
			var before := _decoration_state(layer)
			await _frames(12)
			var still := await _shot("%s-%d-%s-still" % [_tag, index + 1, who], layer, who)
			var after := _decoration_state(layer)
			# 避讓位置的浮點值保留作診斷；裝飾判定用實際畫素位置與完整畫素，不以整份字典相等冒充動畫檢查。
			var stable: bool = before["clock"] == after["clock"] and before["pixel_rects"] == after["pixel_rects"] \
					and before["pixel_hashes"] == after["pixel_hashes"] and before["card_processing"] and after["card_processing"]
			report["decoration_checks"].append({"speaker": who, "first_file": full["file"], "second_file": still["file"], "first": before, "second": after, "unchanged": stable})
			if not stable:
				_fail("減少動態時裝飾仍在變動：" + who)
		limit = 900
		while layer._radio_active and layer._radio_hold > 0.35 and limit > 0:
			await get_tree().process_frame
			limit -= 1
		var late := await _shot("%s-%d-%s-late" % [_tag, index + 1, who], layer, who)
		report["captures"].append(late)
		if not layer._radio_active or layer._radio_hold <= 0.0 or layer._radio_hold > 0.35:
			_fail("未取得換句前的實際停留畫面：" + who)
		limit = 600
		while layer._radio_active and limit > 0:
			await get_tree().process_frame
			limit -= 1
		await _frames(30)
		report["long_to_short"] = {"long_height": long_height, "short_height": float(full["rect"][3])} if who == "mei" else report.get("long_to_short", {})
	report["failures"] = _failures
	_write_report(report)
	print("DIALOGUE_BOX_CAPTURE failures ", _failures)
	Settings.use_storage(Settings.DEFAULT_PATH)
	get_tree().quit(1 if _failures > 0 else 0)


## 對話框的位置、大小、字有沒有被裁、內文與底色的對比。
func _measure(layer: DialogueLayer, who: String, image: Image, readable: bool) -> Dictionary:
	var root := layer._radio_root
	var rect := root.get_global_rect()
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var text := layer._radio_text
	var inside := screen.encloses(rect)
	var clipped := not rect.grow(1.0).encloses(text.get_global_rect()) or text.get_line_count() > text.get_visible_line_count()
	# 底色取內文框右下角往內一點、沒有字的地方。
	var to_image := get_viewport().get_final_transform() * text.get_global_transform_with_canvas()
	var probe := to_image * (text.size - Vector2(3.0, 2.0))
	if not Rect2(Vector2.ZERO, Vector2(image.get_size())).has_point(probe):
		_fail("內文底色取樣超出真正影像：" + who)
		return {"speaker": who, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "lines": 0, "name": "", "file": ""}
	var ground := image.get_pixelv(Vector2i(probe))
	var ink := text.get_theme_color(&"font_color")
	var ratio := _contrast(ink, ground)
	var card := root as RadioCard
	var record := {"speaker": who, "name": layer._radio_name.text, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "inside_screen": inside,
		"text_clipped": clipped, "lines": text.get_line_count(), "contrast": snappedf(ratio, 0.01), "contrast_checked": readable,
		"font_state": _font_state([layer._radio_name, text, layer._radio_continue]), "cell_size": [card._cell.size.x, card._cell.size.y],
		"portrait_visible": card.portrait.visible, "voice_waveform": not card.portrait.visible and card._cell.visible,
		"speaker_color": card.accent.color.to_html(), "name_color": card.name_label.get_theme_color(&"font_color").to_html(),
		"visible_ratio": text.visible_ratio, "hold_ratio": layer.radio_hold_ratio(), "hold_seconds": layer._radio_hold,
		"paused": get_tree().paused, "opacity": root.modulate.a, "image_size": [image.get_width(), image.get_height()],
		"contrast_probe": [probe.x, probe.y], "ink": [ink.r, ink.g, ink.b], "ground": [ground.r, ground.g, ground.b]}
	if not inside or clipped or (readable and ratio < 4.5):
		push_error("[DialogueBoxCapture] %s：超出畫面=%s、字被裁=%s、對比=%.2f" % [who, not inside, clipped, ratio])
		_failures += 1
	if not bool(record["font_state"]["font_sizes_match"]) or not card._cell.size.is_equal_approx(Vector2.ONE * RadioCard.PORTRAIT_SIZE):
		_fail("真實字級或方形頭像尺寸不符：" + who)
	if get_tree().paused or card.accent.color != card.name_label.get_theme_color(&"font_color") or (who == "unknown" and not bool(record["voice_waveform"])):
		_fail("通訊暫停、講者顏色或無頭像波形不符：" + who)
	print("DIALOGUE_BOX:", JSON.stringify(record))
	return record


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(color: Color) -> float:
	var parts: Array[float] = []
	for channel: float in [color.r, color.g, color.b]:
		parts.append(channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4))
	return 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]


func _shot(file_name: String, layer: DialogueLayer, who: String, readable := true) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image: Image = preload("res://tools/viewport_capture.gd").image(get_viewport())
	if image.save_png(_out.path_join(file_name + ".png")) != OK:
		_fail("儲存圖片失敗：" + file_name)
	var record := _measure(layer, who, image, readable)
	record["file"] = file_name + ".png"
	return record


## 僅比較頭像裝飾與訊號格，不把功能性的停留倒數或內文當作裝飾。
func _decoration_state(layer: DialogueLayer) -> Dictionary:
	var card := layer._radio_root as RadioCard
	var image: Image = preload("res://tools/viewport_capture.gd").image(get_viewport())
	var hashes: Array[String] = []
	var regions: Array[Array] = []
	for control: Control in [card._overlay, card._meter]:
		var transform := get_viewport().get_final_transform() * control.get_global_transform_with_canvas()
		var rect := transform * Rect2(Vector2.ZERO, control.size)
		var pixels := Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.end.ceil() - rect.position.floor()))
		if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(pixels):
			_fail("裝飾取樣超出影像")
			continue
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(image.get_region(pixels).get_data())
		hashes.append(hash.finish().hex_encode())
		regions.append([pixels.position.x, pixels.position.y, pixels.size.x, pixels.size.y])
	return {"clock": card._time, "pixel_hashes": hashes, "pixel_rects": regions,
		"card_processing": card.is_processing(), "position": [card.position.x, card.position.y]}


func _fail(message: String) -> void:
	_failures += 1
	push_error("[DialogueBoxCapture] " + message)


func _write_report(report: Dictionary) -> void:
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer == null:
		_fail("無法寫入驗證報告")
		return
	writer.store_string(JSON.stringify(report, "\t"))
	writer.close()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
