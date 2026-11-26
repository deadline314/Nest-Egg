class_name CutsceneDialogue
extends Control
## 過場的對話框：底部切角面板 + 側邊滑入的頭像框 + 逐字顯示。
## 說話風格：normal、whisper（低語，小聲慢速）、shout（吼叫，抖動）、noise（雜訊，色散與抖動）。
## 標點會讓逐字顯示停頓，念起來比較像人在說話。

const BOX_RECT := Rect2(28, 268, 584, 76)
## 寬銀幕黑邊開著時，對話框底下留給下黑邊的空間：框頂 = 安全範圍下緣 − SAFE_BOTTOM_GAP（過場構圖檢查也用這個值）。
const SAFE_BOTTOM_GAP := 84.0
const SIDE_MARGIN := BOX_RECT.position.x
const BOTTOM_MARGIN := SAFE_BOTTOM_GAP - BOX_RECT.size.y
const PORTRAIT_SIZE := 60.0
const PORTRAIT_INSET := Vector2(10.0, 8.0)
const PORTRAIT_SLIDE := 6.0
const STYLES: PackedStringArray = ["normal", "whisper", "shout", "noise"]
const SPEED := {"normal": 38.0, "whisper": 22.0, "shout": 52.0, "noise": 30.0}
const LONG_PAUSE := "。！？"
const SHORT_PAUSE := "，、；：…"
const LONG_PAUSE_TIME := 0.2
const SHORT_PAUSE_TIME := 0.08
const BLIP_EVERY := 3

var _panel: PanelContainer
var _frame: Control
var _portrait: TextureRect
var _name: Label
var _text: Label
var _ghost_a: Label
var _ghost_b: Label
var _continue: Label
var _style := "normal"
var _shown := 0.0
var _pause := 0.0
var _total := 0
var _last_blip := 0
var _speaker_key := ""
var _time := 0.0
var _slide_tween: Tween
var _box_rect := BOX_RECT
var _safe_rect := Rect2()
var _frame_slide := 0.0:
	set(value):
		_frame_slide = value
		_layout_portrait()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = BOX_RECT.position
	_panel.size = BOX_RECT.size
	_panel.custom_minimum_size = BOX_RECT.size
	var box := DialogueMaterial.panel("dialogue")
	box.margins(PORTRAIT_SIZE + 22.0, 8, 14, 18)
	_panel.add_theme_stylebox_override(&"panel", box)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	_panel.add_child(column)
	_name = UiKit.label("", UiKit.FS_BODY, Palette.CYAN)
	column.add_child(_name)
	_text = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_text)
	# 色散用的兩份文字（只在 noise 風格顯示）。
	_ghost_a = _make_ghost(Color(Palette.CYAN, 0.55))
	_ghost_b = _make_ghost(Color(Palette.MAGENTA, 0.55))
	_text.resized.connect(_sync_ghost_width)

	_frame = Control.new()
	_frame.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_layout_portrait()
	var frame_back := Panel.new()
	frame_back.size = _frame.size
	frame_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_back.add_theme_stylebox_override(&"panel", DialogueMaterial.portrait_backing())
	_frame.add_child(frame_back)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.position = Vector2(4, 4)
	_portrait.size = _frame.size - Vector2(8, 8)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_portrait)

	_continue = UiKit.label("▼", UiKit.FS_BODY, Palette.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	_continue.position = Vector2(BOX_RECT.end.x - 28.0, BOX_RECT.end.y - 18.0)
	_continue.size = Vector2(20, 14)
	add_child(_continue)
	_panel.minimum_size_changed.connect(_fit_box.call_deferred)


func _make_ghost(color: Color) -> Label:
	var l := UiKit.label("", UiKit.FS_BODY, color)
	l.autowrap_mode = _text.autowrap_mode
	l.visible_characters_behavior = _text.visible_characters_behavior
	l.visible = false
	l.size = Vector2(_text.size.x, 40)
	add_child(l)
	return l


## 顯示一句。speaker 是 Story.speaker() 的結果（name、color、portrait）。
func show_line(speaker: Dictionary, text: String, style := "normal") -> void:
	_style = style if STYLES.has(style) else "normal"
	var key := str(speaker.get("name", "")) + str(speaker.get("portrait", ""))
	var changed := key != _speaker_key
	_speaker_key = key
	visible = true
	_name.text = str(speaker.get("name", ""))
	_name.add_theme_color_override(&"font_color", Color(str(speaker.get("color", "#35e0ff"))))
	_portrait.texture = RigLibrary.optional_texture(str(speaker.get("portrait", "")))
	_frame.visible = _portrait.texture != null
	_text.language = Story.language
	_text.text = text
	_text.add_theme_color_override(&"font_color", _text_color())
	for ghost in [_ghost_a, _ghost_b]:
		ghost.language = _text.language
		ghost.text = text
		ghost.visible = _style == "noise"
	_total = text.length()
	_shown = 0.0
	_pause = 0.0
	_last_blip = 0
	_text.visible_characters = 0
	_ghost_a.visible_characters = 0
	_ghost_b.visible_characters = 0
	if changed and _frame.visible:
		_slide_frame()


func hide_box() -> void:
	visible = false
	_speaker_key = ""


func is_complete() -> bool:
	return _shown >= float(_total)


## 一次顯示完整句子。
func complete() -> void:
	_shown = float(_total)
	_apply_visible()


func _slide_frame() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if Settings.get_reduce_ui_motion():
		_frame_slide = 0.0
		_frame.modulate.a = 1.0
		return
	_frame_slide = -PORTRAIT_SLIDE
	_frame.modulate.a = 0.0
	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.tween_property(self, "_frame_slide", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(_frame, "modulate:a", 1.0, 0.14)


func _text_color() -> Color:
	match _style:
		"whisper":
			return Palette.UI_MUTED
		"shout":
			return Color("ffb0a8")
	return Palette.UI_TEXT


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if not is_complete():
		if _pause > 0.0:
			_pause -= delta
		else:
			var before := int(_shown)
			_shown = minf(float(_total), _shown + delta * float(SPEED[_style]))
			var after := int(_shown)
			if after > before:
				_after_reveal(before, after)
		_apply_visible()
	_continue.visible = is_complete() and (Settings.get_reduce_ui_motion() or int(_time * 3.0) % 2 == 0)
	_apply_style_motion()


func _after_reveal(from_index: int, to_index: int) -> void:
	var raw := _text.text
	for i in range(from_index, mini(to_index, raw.length())):
		var ch := raw[i]
		if LONG_PAUSE.contains(ch):
			_pause = maxf(_pause, LONG_PAUSE_TIME)
		elif SHORT_PAUSE.contains(ch):
			_pause = maxf(_pause, SHORT_PAUSE_TIME)
	if to_index - _last_blip >= BLIP_EVERY:
		_last_blip = to_index
		Sfx.play(&"ui_move", -26.0, 0.12)


func _apply_visible() -> void:
	var count := int(_shown)
	_text.visible_characters = count
	_ghost_a.visible_characters = count
	_ghost_b.visible_characters = count


## 吼叫抖動、雜訊色散；其他風格固定不動。文字在容器裡不能直接動，所以抖動整個面板。
func _apply_style_motion() -> void:
	_panel.position = _box_rect.position
	var reduce_motion := Settings.get_reduce_ui_motion()
	if _style == "shout" and not reduce_motion:
		_panel.position += Vector2(sin(_time * 80.0) * 0.8, cos(_time * 70.0) * 0.6)
	elif _style == "noise":
		var origin := _text.global_position - global_position
		var jitter := float(int(_time * 20.0) % 3) - 1.0
		_ghost_a.position = origin if reduce_motion else origin + Vector2(1.5 + jitter, 0.0)
		_ghost_b.position = origin if reduce_motion else origin + Vector2(-1.5 - jitter, 0.5)


func layout_safe_rect(rect: Rect2) -> void:
	_safe_rect = rect
	if Settings.get_reduce_ui_motion():
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		_frame_slide = 0.0
		_frame.modulate.a = 1.0
	_fit_box()


func _fit_box() -> void:
	if not _safe_rect.has_area():
		return
	var width := maxf(0.0, _safe_rect.size.x - SIDE_MARGIN * 2.0)
	_panel.custom_minimum_size.x = width
	_panel.size = Vector2(width, _panel.get_combined_minimum_size().y)
	_box_rect = Rect2(Vector2(_safe_rect.position.x + SIDE_MARGIN,
			_safe_rect.end.y - BOTTOM_MARGIN - _panel.size.y), _panel.size)
	_layout_portrait()
	_continue.position = _box_rect.end - Vector2(28, 18)
	_apply_style_motion()


func _sync_ghost_width() -> void:
	_ghost_a.size.x = _text.size.x
	_ghost_b.size.x = _text.size.x


func _layout_portrait() -> void:
	if is_instance_valid(_frame):
		_frame.position = _box_rect.position + PORTRAIT_INSET + Vector2(_frame_slide, 0.0)
