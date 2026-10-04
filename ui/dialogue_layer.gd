class_name DialogueLayer
extends CanvasLayer
## 對話介面（由 Story 服務持有）：
##   過場：暫停遊戲、上下黑邊、頭像＋講者名＋逐字顯示；點擊／Enter／射擊／互動鍵推進（第一下先顯示完整句子），Esc 跳過整段。
##   通訊：畫面左上角的小面板，不暫停，逐字顯示後依字數停留再自動換下一句；台詞帶 delay 時先收起面板沉默那麼久。

signal cinematic_finished(scene_id: StringName)
signal radio_finished(scene_id: StringName)

const CHARS_PER_SECOND := 42.0
const RADIO_CHARS_PER_SECOND := 60.0
const RADIO_HOLD_BASE := 1.6
const RADIO_HOLD_PER_CHAR := 0.055
const BAR_HEIGHT := 34.0
const PORTRAIT_SIZE := 56.0
const RADIO_PORTRAIT_SIZE := 32.0
const RADIO_HOME := Vector2(170, 46)
const RADIO_SLIDE := 28.0

var _cinematic_root: Control
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _portrait: TextureRect
var _name: Label
var _text: Label
var _continue: Label
var _cinematic_id: StringName = &""
var _cinematic_lines: Array[Dictionary] = []
var _cinematic_index := 0
var _was_paused := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE

var _radio_root: PanelContainer
var _radio_portrait: TextureRect
var _radio_name: Label
var _radio_bar: ColorRect
var _radio_slide: Tween
var _radio_text: Label
var _radio_queue: Array[Dictionary] = []  # { id, line, last }
var _radio_hold := 0.0
## 這一句顯示前還要沉默幾秒（台詞的 delay）；沉默期間通訊框是收起來的。
var _radio_wait := 0.0
var _radio_active := false
var _time := 0.0


func _ready() -> void:
	layer = UiLayers.DIALOGUE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_cinematic()
	_build_radio()


# ---------------------------------------------------------------------------
# 過場
# ---------------------------------------------------------------------------

func start_cinematic(id: StringName, lines: Array[Dictionary]) -> void:
	if lines.is_empty():
		cinematic_finished.emit(id)
		return
	_cinematic_id = id
	_cinematic_lines = lines
	_cinematic_index = 0
	_was_paused = get_tree().paused
	get_tree().paused = true
	Fx.reset_time()
	_previous_mouse_mode = Input.mouse_mode
	UiKit.set_cursor_visible(true)
	_cinematic_root.visible = true
	_radio_root.visible = false
	_show_line()


func is_cinematic_active() -> bool:
	return _cinematic_id != &""


## 推進：句子還在逐字顯示時先顯示完整句子，否則換下一句。
func advance() -> void:
	if not is_cinematic_active():
		return
	if _text.visible_ratio < 1.0:
		_text.visible_ratio = 1.0
		return
	_cinematic_index += 1
	if _cinematic_index >= _cinematic_lines.size():
		finish_cinematic()
	else:
		_show_line()
		Sfx.play(&"ui_move", -12.0, 0.0)


func finish_cinematic() -> void:
	if not is_cinematic_active():
		return
	var id := _cinematic_id
	_cinematic_id = &""
	_cinematic_root.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse_mode
	cinematic_finished.emit(id)


func _show_line() -> void:
	var line := _cinematic_lines[_cinematic_index]
	_name.text = line["name"]
	_name.add_theme_color_override(&"font_color", line["color"])
	_text.text = line["text"]
	_text.visible_ratio = 0.0
	_portrait.texture = _portrait_texture(line["portrait"])


func _input(event: InputEvent) -> void:
	if not is_cinematic_active():
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		finish_cinematic()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"shoot") or event.is_action_pressed(&"jump") \
			or event.is_action_pressed(&"interact") \
			or (event is InputEventMouseButton and event.is_pressed() and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		# 過場期間吞掉其他輸入，避免穿透到遊戲。
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 通訊
# ---------------------------------------------------------------------------

func enqueue_radio(id: StringName, lines: Array[Dictionary]) -> void:
	if lines.is_empty():
		radio_finished.emit(id)
		return
	for i in lines.size():
		_radio_queue.append({"id": id, "line": lines[i], "last": i == lines.size() - 1})
	if not _radio_active:
		_next_radio()


func _next_radio() -> void:
	if _radio_queue.is_empty():
		_radio_active = false
		var tween := create_tween()
		tween.tween_property(_radio_root, "modulate:a", 0.0, 0.25)
		tween.tween_callback(_radio_root.set.bind("visible", false))
		return
	_radio_active = true
	var entry: Dictionary = _radio_queue.front()
	var line: Dictionary = entry["line"]
	_radio_name.text = line["name"]
	_radio_name.add_theme_color_override(&"font_color", line["color"])
	_radio_bar.color = line["color"]
	_radio_text.text = line["text"]
	_radio_text.visible_ratio = 0.0
	_radio_portrait.texture = _portrait_texture(line["portrait"])
	_radio_hold = RADIO_HOLD_BASE + str(line["text"]).length() * RADIO_HOLD_PER_CHAR
	_radio_wait = float(line.get("delay", 0.0))
	var was_hidden := not _radio_root.visible or _radio_root.modulate.a < 0.5
	_radio_root.visible = not is_cinematic_active() and _radio_wait <= 0.0
	if _radio_wait <= 0.0:
		_reveal_radio(was_hidden)


func _process(delta: float) -> void:
	_time += delta
	if is_cinematic_active():
		if _text.visible_ratio < 1.0:
			_text.visible_ratio = minf(1.0, _text.visible_ratio + delta * CHARS_PER_SECOND / maxf(1.0, _text.text.length()))
		_continue.visible = _text.visible_ratio >= 1.0 and int(_time * 3.0) % 2 == 0
		return
	if not _radio_active or get_tree().paused:
		return
	if _radio_wait > 0.0:
		_radio_wait -= delta
		if _radio_wait <= 0.0:
			_radio_root.visible = true
			_reveal_radio(true)
		return
	_radio_root.visible = true
	if _radio_text.visible_ratio < 1.0:
		_radio_text.visible_ratio = minf(1.0, _radio_text.visible_ratio + delta * RADIO_CHARS_PER_SECOND / maxf(1.0, _radio_text.text.length()))
		return
	_radio_hold -= delta
	if _radio_hold <= 0.0:
		var entry: Dictionary = _radio_queue.pop_front()
		if entry["last"]:
			radio_finished.emit(entry["id"])
		_next_radio()


# ---------------------------------------------------------------------------
# 建立介面
# ---------------------------------------------------------------------------

func _build_cinematic() -> void:
	_cinematic_root = Control.new()
	_cinematic_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cinematic_root.theme = UiKit.theme()
	_cinematic_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_cinematic_root.visible = false
	add_child(_cinematic_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cinematic_root.add_child(dim)
	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_place(_top_bar, Control.PRESET_TOP_WIDE, Rect2(0, 0, 0, BAR_HEIGHT))
	_cinematic_root.add_child(_top_bar)
	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_place(_bottom_bar, Control.PRESET_BOTTOM_WIDE, Rect2(0, -BAR_HEIGHT - 66.0, 0, BAR_HEIGHT + 66.0))
	_cinematic_root.add_child(_bottom_bar)
	var skip := UiKit.label("Esc 跳過", 9, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(skip, Control.PRESET_TOP_RIGHT, Rect2(-90, 10, 80, 14))
	_cinematic_root.add_child(skip)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_place(_portrait, Control.PRESET_BOTTOM_LEFT, Rect2(24, -PORTRAIT_SIZE - 26.0, PORTRAIT_SIZE, PORTRAIT_SIZE))
	_cinematic_root.add_child(_portrait)
	_name = UiKit.label("", 12, Palette.CYAN)
	_place(_name, Control.PRESET_BOTTOM_LEFT, Rect2(92, -88, 300, 16))
	_cinematic_root.add_child(_name)
	_text = UiKit.label("", 12, Palette.UI_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(500, 0)
	_place(_text, Control.PRESET_BOTTOM_LEFT, Rect2(92, -70, 500, 50))
	_cinematic_root.add_child(_text)
	_continue = UiKit.label("▼", 10, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_continue, Control.PRESET_BOTTOM_RIGHT, Rect2(-40, -26, 20, 14))
	_cinematic_root.add_child(_continue)


func _build_radio() -> void:
	_radio_root = PanelContainer.new()
	_radio_root.theme = UiKit.theme()
	_radio_root.position = RADIO_HOME
	_radio_root.custom_minimum_size = Vector2(300, 0)
	_radio_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_root.visible = false
	var box := ChamferBox.make(Color(0.02, 0.04, 0.07, 0.9), Palette.CYAN_DIM, 4)
	box.bracket = Palette.CYAN
	box.scanlines = 0.1
	box.margins(8, 6, 10, 6)
	_radio_root.add_theme_stylebox_override(&"panel", box)
	add_child(_radio_root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_radio_root.add_child(row)
	# 講者顏色條 + 頭像框（從側邊滑入時一起移動）。
	_radio_bar = ColorRect.new()
	_radio_bar.custom_minimum_size = Vector2(2, 0)
	_radio_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_radio_bar)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_box := ChamferBox.make(Color(0.03, 0.06, 0.09, 0.96), Palette.CYAN, 3, 2)
	frame_box.margins(2, 2, 2, 2)
	frame.add_theme_stylebox_override(&"panel", frame_box)
	row.add_child(frame)
	_radio_portrait = TextureRect.new()
	_radio_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_radio_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_radio_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_radio_portrait.custom_minimum_size = Vector2(RADIO_PORTRAIT_SIZE, RADIO_PORTRAIT_SIZE)
	frame.add_child(_radio_portrait)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	row.add_child(column)
	_radio_name = UiKit.label("", UiKit.FS_BODY, Palette.CYAN)
	column.add_child(_radio_name)
	_radio_text = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	_radio_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_radio_text.custom_minimum_size = Vector2(240, 0)
	column.add_child(_radio_text)


## 顯示這一句通訊：面板原本隱藏時滑入，否則直接換字；兩者都有提示音。
func _reveal_radio(slide: bool) -> void:
	if slide:
		_slide_radio_in()
	else:
		_radio_root.modulate.a = 1.0
	Sfx.play(&"telegraph", -18.0, 0.0)


## 通訊面板從左側滑入（已經在顯示時不重播）。
func _slide_radio_in() -> void:
	if _radio_slide != null and _radio_slide.is_valid():
		_radio_slide.kill()
	_radio_root.position = RADIO_HOME + Vector2(-RADIO_SLIDE, 0)
	_radio_root.modulate.a = 0.0
	_radio_slide = create_tween().set_parallel(true)
	_radio_slide.tween_property(_radio_root, "position", RADIO_HOME, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_radio_slide.tween_property(_radio_root, "modulate:a", 1.0, 0.15)


## 以錨點為基準放置控制項（rect 的座標相對於錨點，例如底部錨點時 y 為負值）。
func _place(control: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x if rect.size.x > 0.0 else 0.0
	control.offset_bottom = rect.position.y + rect.size.y


func _portrait_texture(path: String) -> Texture2D:
	return RigLibrary.optional_texture(path) if not path.is_empty() else null
