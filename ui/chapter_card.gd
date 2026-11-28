class_name ChapterCard
extends CanvasLayer
## 章末畫面（全片少數保留章節卡的時刻，NE-421／NE-422）：全黑底上依序出現章節序號、大字章名、朱色「完」印、下一步的提示。
## 暫停遊戲；開始一小段時間後可按確認或取消提早收尾。內容淡出後黑底留著，交給結算畫面接手（關卡釋放時一起釋放）。
## 進場不再顯示章節卡；地名改由 LocationMarker 標示。

signal finished

## 節奏（秒）：黑底、序號、章名、蓋印、提示依序出現。
const SHADE_TIME := 0.6
const NUMBER_AT := 0.45
const NAME_AT := 0.7
const NAME_TIME := 0.8
const SEAL_AT := 1.45
const SEAL_TIME := 0.16
const TEASER_AT := 1.75
const OUT_TIME := 0.8
const SKIP_OUT := 0.3
## 開始後多久可以按鍵提早收尾（避免帶著上一個畫面的按鍵直接跳過）。
const SKIP_AFTER := 0.8
const NAME_RISE := 4.0
## 章名最寬佔畫面寬度的比例；太長的章名（多半是英文）縮小字級到放得下，但不小於時刻標題。
const NAME_MAX_WIDTH := 0.8
## 四層之間的間距（畫面像素）：序號與章名、章名與細線、細線與提示。
const GAP_NUMBER := 6
const GAP_RULE := 12
const GAP_TEASER := 6
const TEASER_WIDTH := 460.0
## 印：所有語言都蓋同一個「完」（當票上的朱印，是這個世界的東西）；大小是章名字級的比例。
const SEAL_TEXT := "完"
const SEAL_COLOR := Color("c73a2e")
const SEAL_TILT := -7.0
const SEAL_PRESS := 1.25
const SEAL_SCALE := 0.4
## 章名縮小時（太長的英文章名），印不跟著縮到比這個比例（相對於時刻大標原本的字級）更小。
const SEAL_MIN_SCALE := 0.3

## 章末標題整段（拆不出序號與章名時當章名用）、下一步提示、內容全部出現後停留幾秒。
var title := ""
var subtitle := ""
var hold := 2.8
## 章節序號（「第一章」「CHAPTER 1」）、章名（「傘」「Kasa」）、印上的字。
var chapter_number := ""
var chapter_name := ""
var seal_text := SEAL_TEXT

var _root: Control
var _content: Control
var _name_label: Label
var _lock_token := 0
var _tween: Tween
var _elapsed := 0.0
var _closing := false


## 從章節標題拆出序號與章名：「第一章　傘」→ 第一章／傘；「Chapter 1: Kasa」→ CHAPTER 1／Kasa。
## 拆不出來時序號空白、章名用 end_title 整段；所有語言都蓋「完」印。
static func split_end_title(chapter_title: String, end_title: String) -> PackedStringArray:
	var parts := chapter_title.split("　", false)
	if parts.size() == 2:
		return PackedStringArray([parts[0], parts[1], SEAL_TEXT])
	var colon := chapter_title.find(":")
	if colon > 0 and colon < chapter_title.length() - 1:
		return PackedStringArray([chapter_title.left(colon).strip_edges().to_upper(), chapter_title.substr(colon + 1).strip_edges(), SEAL_TEXT])
	return PackedStringArray(["", end_title if not end_title.is_empty() else chapter_title, SEAL_TEXT])


func _ready() -> void:
	layer = UiLayers.CHAPTER_CARD
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(UiLayers.PRESENTATION_GROUP)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_lock_token = GameplayLock.acquire(self)
	_build()


func _build() -> void:
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
	column.add_theme_constant_override(&"separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(column)
	var number := UiKit.styled(chapter_number, &"kicker", Palette.CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	number.visible = not chapter_number.is_empty()
	column.add_child(number)
	column.add_child(_spacer(GAP_NUMBER))
	# 章名與印同一列：印壓在章名右下角，不佔版面寬度。
	var name_row := CenterContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_row)
	_name_label = UiKit.styled(chapter_name if not chapter_name.is_empty() else title, &"hero", Palette.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	name_row.add_child(_name_label)
	_fit_name()
	var seal := _Seal.new()
	seal.text = seal_text
	seal.visible = not seal_text.is_empty()
	seal.modulate.a = 0.0
	_name_label.add_child(seal)
	column.add_child(_spacer(GAP_RULE))
	var rule := _Rule.new()
	rule.custom_minimum_size = Vector2(0, 6)
	rule.modulate.a = 0.0
	column.add_child(rule)
	column.add_child(_spacer(GAP_TEASER))
	var teaser := UiKit.styled(subtitle, &"heading", Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	teaser.custom_minimum_size.x = TEASER_WIDTH
	teaser.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	teaser.visible = not subtitle.is_empty()
	teaser.modulate.a = 0.0
	column.add_child(teaser)
	number.modulate.a = 0.0
	_name_label.modulate.a = 0.0

	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(shade, "modulate:a", 1.0, SHADE_TIME)
	_tween.tween_property(number, "modulate:a", 1.0, 0.5).set_delay(NUMBER_AT)
	_tween.tween_property(_name_label, "modulate:a", 1.0, NAME_TIME).set_delay(NAME_AT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if not still:
		_tween.tween_method(func(rise: float) -> void: _content.position.y = rise, NAME_RISE, 0.0, NAME_TIME).set_delay(NAME_AT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if seal.visible:
		# 蓋印：從稍大壓到原大小、同時出現；「減少動態」時只淡入。
		_tween.tween_property(seal, "modulate:a", 1.0, SEAL_TIME).set_delay(SEAL_AT)
		if not still:
			_tween.tween_method(seal.set_press, SEAL_PRESS, 1.0, SEAL_TIME).set_delay(SEAL_AT).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(rule, "modulate:a", 1.0, 0.6).set_delay(TEASER_AT)
	_tween.tween_property(teaser, "modulate:a", 1.0, 0.6).set_delay(TEASER_AT)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(_content, "modulate:a", 0.0, OUT_TIME)
	_tween.chain().tween_callback(_done)


static func _spacer(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## 章名太寬時縮小字級到放得下（不小於時刻標題的字級）。
func _fit_name() -> void:
	var font := _name_label.get_theme_font(&"font")
	var size := UiKit.role_size(&"hero")
	var limit := get_viewport().get_visible_rect().size.x * NAME_MAX_WIDTH
	var width := font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if width > limit:
		size = maxi(UiKit.role_size(&"display"), floori(size * limit / width))
		_name_label.add_theme_font_size_override(&"font_size", size)


## 章名目前的字級（工具與測試用）。
func name_font_size() -> int:
	return _name_label.get_theme_font_size(&"font_size") if is_instance_valid(_name_label) else 0


## 目前可見的程度（工具與測試用）：看得到的文字中最清楚的那一層乘上整體淡出。
func presentation_alpha() -> float:
	if not is_instance_valid(_root) or not _root.visible or not is_instance_valid(_content):
		return 0.0
	var shown := 0.0
	for node in _content.find_children("*", "Label", true, false):
		var label := node as Label
		if label.visible and not label.text.is_empty():
			shown = maxf(shown, label.modulate.a)
	return shown * _content.modulate.a


func _process(delta: float) -> void:
	_elapsed += delta


func _input(event: InputEvent) -> void:
	if _lock_token == 0:
		return
	get_viewport().set_input_as_handled()
	# 可以按確認或取消提早收尾（只收尾，不跳過黑底）。
	if not _closing and _elapsed >= SKIP_AFTER and is_instance_valid(_content) \
			and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel")):
		_closing = true
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween.tween_property(_content, "modulate:a", 0.0, SKIP_OUT)
		_tween.tween_callback(_done)


func _done() -> void:
	GameplayLock.release(_lock_token)
	_lock_token = 0
	finished.emit()
	# 黑底留著給下一個畫面（結算）接手，避免關卡閃出一格；關卡釋放時一起釋放。
	set_process(false)
	set_process_input(false)


## 朱色方印：圓角方塊、內縮一圈細框、字反白；蓋下去時從稍大壓到原大小。
class _Seal extends Control:
	var text := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parent := get_parent() as Control
		parent.resized.connect(_place)
		_place()

	func set_press(value: float) -> void:
		scale = Vector2(value, value)

	func _place() -> void:
		var parent := get_parent() as Label
		var side := roundf(maxf(parent.get_theme_font_size(&"font_size") * ChapterCard.SEAL_SCALE, UiKit.role_size(&"hero") * ChapterCard.SEAL_MIN_SCALE))
		size = Vector2(side, side)
		pivot_offset = size * 0.5
		position = Vector2(parent.size.x - side * 0.2, parent.size.y - side * 1.15)
		rotation = deg_to_rad(ChapterCard.SEAL_TILT)
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var body := ChamferBox.make(ChapterCard.SEAL_COLOR, ChapterCard.SEAL_COLOR, 3)
		body.bevel = false
		draw_style_box(body, rect)
		draw_rect(rect.grow(-2.5), Color(1, 0.93, 0.88, 0.75), false, 1.0)
		var font := Typography.font(&"title")
		var font_size := int(size.y * 0.62)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := Vector2((size.x - text_size.x) * 0.5, (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size))
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.95, 0.9))


## 章名與提示之間的細線：中段亮、往兩端淡掉，中央一顆小菱形。
class _Rule extends Control:
	const HALF := 110.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var mid := size * 0.5
		var steps := 16
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var alpha := 0.55 * (1.0 - t0)
			draw_line(Vector2(mid.x + HALF * t0, mid.y), Vector2(mid.x + HALF * t1, mid.y), Color(Palette.CYAN_DIM, alpha), 1.0)
			draw_line(Vector2(mid.x - HALF * t0, mid.y), Vector2(mid.x - HALF * t1, mid.y), Color(Palette.CYAN_DIM, alpha), 1.0)
		var d := 2.5
		draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -d), mid + Vector2(d, 0), mid + Vector2(0, d), mid + Vector2(-d, 0)]), Palette.CYAN_DIM)
