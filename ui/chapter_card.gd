class_name ChapterCard
extends CanvasLayer
## 章節卡：淡入、停留、淡出後自行釋放。
## block = true 是章末的專屬畫面（全片少數保留章節卡的時刻）：全黑底、章節序號小字、章名大字（標題字體）、
## 朱色「完」印、下一步的提示；暫停遊戲，確認或取消鍵可提早收尾。畫完內容淡出但保持黑底，交給結算畫面接手。
## block = false 是舊的疊在畫面上的標題（只剩工具使用；遊戲進場改用 LocationMarker）。

signal finished

const FADE := 0.6
## 章末畫面的節奏（秒）：黑底、序號、章名、蓋印、提示依序出現。
const END_SHADE := 0.6
const END_NUMBER_AT := 0.45
const END_NAME_AT := 0.7
const END_NAME_TIME := 0.8
const END_SEAL_AT := 1.45
const END_SEAL_TIME := 0.16
const END_TEASER_AT := 1.75
const END_OUT := 0.8
const END_SKIP_OUT := 0.3
## 開始後多久可以按鍵提早收尾（避免帶著上一個畫面的按鍵直接跳過）。
const END_SKIP_AFTER := 0.8
const END_NAME_SIZE := 56
const END_NAME_RISE := 4.0
const END_NUMBER_SPACING := 6
const END_TEASER_WIDTH := 420.0
const SEAL_COLOR := Color("c73a2e")
const SEAL_TILT := -7.0
const SEAL_PRESS := 1.25

var title := ""
var subtitle := ""
var hold := 2.2
var block := false
## 章末畫面用：章節序號（「第一章」）、章名（「傘」）、印上的字（「完」）。章名空白時整段 title 當章名、不蓋印。
var chapter_number := ""
var chapter_name := ""
var seal_text := ""

var _root: Control
var _lock_token := 0
var _tween: Tween
var _presentation_suspended := false
var _title_label: Label
var _subtitle_label: Label
var _title_extent := Vector2.ZERO
var _subtitle_extent := Vector2.ZERO
var _content: Control
var _elapsed := 0.0
var _closing := false


## 從章節資訊拆出章末畫面要的三段：title「第一章　傘」、end_title「第一章　傘　完」→ 序號、章名、印。
## 拆不出來（例如英文標題）時回傳空的序號與印，章名用 end_title 整段。
static func split_end_title(chapter_title: String, end_title: String) -> PackedStringArray:
	var parts := chapter_title.split("　", false)
	if parts.size() == 2 and end_title.begins_with(chapter_title):
		var rest := end_title.trim_prefix(chapter_title).strip_edges().trim_prefix("　").strip_edges()
		if rest.length() <= 2:
			return PackedStringArray([parts[0], parts[1], rest])
	return PackedStringArray(["", end_title, ""])


func _ready() -> void:
	layer = UiLayers.CHAPTER_CARD
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	if block:
		_lock_token = GameplayLock.acquire(self)
		_build_end()
	else:
		_build_overlay()
	_update_presentation()


func _build_overlay() -> void:
	_root.modulate.a = 0.0
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.position = Vector2(-220, -40)
	box.custom_minimum_size = Vector2(440, 80)
	_root.add_child(box)
	_title_label = UiKit.label(title, 22, LightKit.glow(Palette.MAGENTA, 1.4), HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle_label = UiKit.label(subtitle, 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title_label)
	box.add_child(_subtitle_label)
	_title_label.resized.connect(_refresh_title_extent)
	_title_label.theme_changed.connect(_refresh_title_extent)
	_subtitle_label.resized.connect(_refresh_subtitle_extent)
	_subtitle_label.theme_changed.connect(_refresh_subtitle_extent)
	_refresh_title_extent()
	_refresh_subtitle_extent()
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	_tween = create_tween()
	# 疊在畫面上的標題遇到暫停（暫停選單、背包）就凍結並藏起來。
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_tween.tween_property(_root, "modulate:a", 1.0, FADE)
	_tween.tween_interval(hold)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE)
	_tween.tween_callback(_done)


## 章末畫面：全黑底上，序號、章名、印、提示依序出現。
func _build_end() -> void:
	var still := Settings.get_reduce_ui_motion()
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.modulate.a = 0.0
	_root.add_child(shade)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(column)
	var name_text := chapter_name if not chapter_name.is_empty() else title
	var number := UiKit.caption(chapter_number, Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	var spaced := FontVariation.new()
	spaced.base_font = UiKit.special_font(&"title")
	spaced.spacing_glyph = END_NUMBER_SPACING
	number.add_theme_font_override(&"font", spaced)
	number.visible = not chapter_number.is_empty()
	column.add_child(number)
	# 章名與印同一列：印壓在章名右下角，不佔版面寬度。
	var name_row := CenterContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_row)
	var name_label := UiKit.label(name_text, UiKit.FS_DISPLAY, Palette.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.set_meta(UiKit.TEXT_SIZE_META, END_NAME_SIZE)
	name_label.add_theme_font_size_override(&"font_size", UiKit.scaled_size(END_NAME_SIZE))
	name_label.add_theme_font_override(&"font", UiKit.special_font(&"title"))
	name_row.add_child(name_label)
	var seal := _Seal.new()
	seal.text = seal_text
	seal.visible = not seal_text.is_empty()
	seal.modulate.a = 0.0
	name_label.add_child(seal)
	var rule := _Rule.new()
	rule.custom_minimum_size = Vector2(0, 14)
	rule.modulate.a = 0.0
	column.add_child(rule)
	var teaser := UiKit.label(subtitle, UiKit.FS_BODY, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	teaser.custom_minimum_size.x = END_TEASER_WIDTH
	teaser.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	teaser.visible = not subtitle.is_empty()
	teaser.modulate.a = 0.0
	column.add_child(teaser)
	number.modulate.a = 0.0
	name_label.modulate.a = 0.0

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(shade, "modulate:a", 1.0, END_SHADE)
	_tween.tween_property(number, "modulate:a", 1.0, 0.5).set_delay(END_NUMBER_AT)
	_tween.tween_property(name_label, "modulate:a", 1.0, END_NAME_TIME).set_delay(END_NAME_AT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if not still:
		_tween.tween_method(func(rise: float) -> void: _content.position.y = rise, END_NAME_RISE, 0.0, END_NAME_TIME).set_delay(END_NAME_AT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if seal.visible:
		# 蓋印：從稍大壓到原大小、同時出現；「減少動態」時只淡入。
		_tween.tween_property(seal, "modulate:a", 1.0, END_SEAL_TIME).set_delay(END_SEAL_AT)
		if not still:
			_tween.tween_method(seal.set_press, SEAL_PRESS, 1.0, END_SEAL_TIME).set_delay(END_SEAL_AT).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(rule, "modulate:a", 1.0, 0.6).set_delay(END_TEASER_AT)
	_tween.tween_property(teaser, "modulate:a", 1.0, 0.6).set_delay(END_TEASER_AT)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(_content, "modulate:a", 0.0, END_OUT)
	_tween.chain().tween_callback(_done)


func _refresh_title_extent() -> void:
	_title_extent = _readable_label_extent(_title_label)


func _refresh_subtitle_extent() -> void:
	_subtitle_extent = _readable_label_extent(_subtitle_label)


func _readable_label_extent(label: Label) -> Vector2:
	if not is_instance_valid(label):
		return Vector2.ZERO
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0 or label.text.is_empty():
		return Vector2.ZERO
	var width := 0.0
	var lines := label.text.split("\n")
	for line: String in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return Vector2(width, font.get_height(font_size) * maxi(1, lines.size()))


func _label_world_rect(label: Label, extent: Vector2) -> Rect2:
	if not is_instance_valid(label) or extent.x <= 0.0 or extent.y <= 0.0 or not label.is_visible_in_tree():
		return Rect2()
	var local := Rect2(Vector2((label.size.x - extent.x) * 0.5, 0.0), extent)
	var canvas := get_viewport().get_canvas_transform()
	if not is_finite(canvas.determinant()) or is_zero_approx(canvas.determinant()):
		return Rect2()
	return canvas.affine_inverse() * (label.get_global_transform() * local)


func prompt_obstacle_rect() -> Rect2:
	if not is_instance_valid(_root) or not _root.is_visible_in_tree() or not _root.visible \
				or _root.modulate.a <= 0.01:
		return Rect2()
	var title_rect := _label_world_rect(_title_label, _title_extent)
	var subtitle_rect := _label_world_rect(_subtitle_label, _subtitle_extent)
	if not title_rect.has_area():
		return subtitle_rect
	if not subtitle_rect.has_area():
		return title_rect
	return title_rect.merge(subtitle_rect)


## 目前可見的程度（工具與測試用）：章末畫面看內容，疊加標題看整體。
func presentation_alpha() -> float:
	if not is_instance_valid(_root) or not _root.visible:
		return 0.0
	if is_instance_valid(_content):
		var shown := 0.0
		for node in _content.find_children("*", "Label", true, false):
			var label := node as Label
			if label.visible and not label.text.is_empty():
				shown = maxf(shown, label.modulate.a)
		return shown * _content.modulate.a
	return _root.modulate.a


func _process(delta: float) -> void:
	_elapsed += delta
	_update_presentation()


func _update_presentation() -> void:
	var suspended := not block and (get_tree().paused or DialogueLayer.radio_visible())
	_root.visible = not suspended
	if suspended == _presentation_suspended:
		return
	_presentation_suspended = suspended
	if _tween != null and _tween.is_valid():
		if suspended:
			_tween.pause()
		else:
			_tween.play()


func _input(event: InputEvent) -> void:
	if _lock_token == 0:
		return
	get_viewport().set_input_as_handled()
	# 章末畫面可以按確認或取消提早收尾（只收尾，不跳過黑底）。
	if block and not _closing and _elapsed >= END_SKIP_AFTER and is_instance_valid(_content) \
			and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel")):
		_closing = true
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween.tween_property(_content, "modulate:a", 0.0, END_SKIP_OUT)
		_tween.tween_callback(_done)


func _done() -> void:
	GameplayLock.release(_lock_token)
	_lock_token = 0
	finished.emit()
	if block:
		# 黑底留著給下一個畫面（結算）接手，避免關卡閃出一格；關卡釋放時一起釋放。
		set_process(false)
		set_process_input(false)
		return
	queue_free()


## 朱色方印：圓角方塊、內縮一圈細框、字反白；蓋下去時從稍大壓到原大小。
class _Seal extends Control:
	var text := ""
	var _press := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parent := get_parent() as Control
		parent.resized.connect(_place)
		_place()

	func set_press(value: float) -> void:
		_press = value
		scale = Vector2(value, value)

	func _place() -> void:
		var parent := get_parent() as Control
		var side := roundf(parent.size.y * 0.42)
		size = Vector2(side, side)
		pivot_offset = size * 0.5
		position = Vector2(parent.size.x - side * 0.15, parent.size.y - side * 0.95)
		rotation = deg_to_rad(ChapterCard.SEAL_TILT)
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var body := ChamferBox.make(ChapterCard.SEAL_COLOR, ChapterCard.SEAL_COLOR, 3)
		body.bevel = false
		draw_style_box(body, rect)
		var inner := rect.grow(-2.5)
		draw_rect(inner, Color(1, 0.93, 0.88, 0.75), false, 1.0)
		var font := UiKit.special_font(&"title")
		var font_size := int(size.y * 0.62)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := Vector2((size.x - text_size.x) * 0.5, (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size))
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.95, 0.9))


## 章名與提示之間的細線：中段亮、往兩端淡掉，中央一顆小菱形。
class _Rule extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var mid := size * 0.5
		var half := 70.0
		var steps := 14
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var alpha := 0.55 * (1.0 - t0)
			draw_line(Vector2(mid.x + half * t0, mid.y), Vector2(mid.x + half * t1, mid.y), Color(Palette.CYAN_DIM, alpha), 1.0)
			draw_line(Vector2(mid.x - half * t0, mid.y), Vector2(mid.x - half * t1, mid.y), Color(Palette.CYAN_DIM, alpha), 1.0)
		var d := 2.5
		draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -d), mid + Vector2(d, 0), mid + Vector2(0, d), mid + Vector2(-d, 0)]), Palette.CYAN_DIM)
