extends Node
## 通訊對話框的原生截圖（NE-274）。
##
## 用法（原生）：
##   godot --path . res://tools/dialogue_box_capture.tscn -- --out=<絕對資料夾> [--tag=<標籤>] [--level=ch1_street]
##       [--text-scale=1.0] [--reduce-motion]
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
	if not _out.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("[DialogueBoxCapture] 需要原生視窗與 --out=<絕對資料夾>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


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
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	var layer: DialogueLayer = Story._layer
	layer.cancel_radio()
	await _frames(30)
	var report := {"tag": _tag, "text_scale": _text_scale, "reduce_motion": _reduce, "lines": []}
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
		await _shot("%s-%d-%s-in" % [_tag, index + 1, who])
		var limit := 600
		while layer._radio_text.visible_ratio < 1.0 and limit > 0:
			await get_tree().process_frame
			limit -= 1
		await _frames(12)
		await _shot("%s-%d-%s-full" % [_tag, index + 1, who])
		report["lines"].append(_measure(layer, who))
		limit = 900
		while layer._radio_active and layer._radio_hold > 0.35 and limit > 0:
			await get_tree().process_frame
			limit -= 1
		await _shot("%s-%d-%s-late" % [_tag, index + 1, who])
		limit = 600
		while layer._radio_active and limit > 0:
			await get_tree().process_frame
			limit -= 1
		await _frames(30)
	var writer := FileAccess.open(_out.path_join(_tag + "-index.json"), FileAccess.WRITE)
	if writer != null:
		writer.store_string(JSON.stringify(report, "\t"))
		writer.close()
	print("DIALOGUE_BOX_CAPTURE failures ", _failures)
	Settings.use_storage(Settings.DEFAULT_PATH)
	get_tree().quit(1 if _failures > 0 else 0)


## 對話框的位置、大小、字有沒有被裁、內文與底色的對比。
func _measure(layer: DialogueLayer, who: String) -> Dictionary:
	var root := layer._radio_root
	var rect := root.get_global_rect()
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var text := layer._radio_text
	var inside := screen.encloses(rect)
	var clipped := not rect.grow(1.0).encloses(text.get_global_rect()) or text.get_line_count() > text.get_visible_line_count()
	var image: Image = preload("res://tools/viewport_capture.gd").image(get_viewport())
	var scale := float(image.get_width()) / screen.size.x
	# 底色取內文框右下角往內一點、沒有字的地方。
	var probe := (text.get_global_rect().end - Vector2(3.0, 2.0)) * scale
	var ground := image.get_pixelv(Vector2i(probe))
	var ink := text.get_theme_color(&"font_color")
	var ratio := _contrast(ink, ground)
	var record := {"speaker": who, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "inside_screen": inside,
		"text_clipped": clipped, "lines": text.get_line_count(), "contrast": snappedf(ratio, 0.01)}
	if not inside or clipped or ratio < 4.5:
		push_error("[DialogueBoxCapture] %s：超出畫面=%s、字被裁=%s、對比=%.2f" % [who, not inside, clipped, ratio])
		_failures += 1
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


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = preload("res://tools/viewport_capture.gd").image(get_viewport())
	image.save_png(_out.path_join(file_name + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
