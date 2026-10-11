class_name DetailPanel
extends MarginContainer
## 詳情面板：名稱與類型在最上面一整行，下面是圖示與數值、說明與動作按鈕。換項目時圖示彈出、內容淡入。
## 寬度約為畫面三分之一（右側留給立繪，NE-244），所以圖示底板較小、數值與說明都會折行。
## 只認 InventoryEntry，所有分頁共用。
## 版面用容器排列（不用錨點）：錨點全滿的子控制項在父層尚未排版時若最小尺寸較大，會把多出的尺寸記成偏移而撐破面板。

signal action_pressed
signal action_hovered(hint: String)

const POP_FROM := 0.9
const POP_TIME := 0.16
const FADE_FROM := 0.35
const BODY_MIN_WIDTH := 180.0
const PLATE := Vector2(92, 76)
## 數值欄折行的最小寬度（避免容器先把它擠成一字寬）。
const STATS_MIN_WIDTH := 72.0

var _plate: IconPlate
var _title: Label
var _tag: Label
var _ammo_icon: TextureRect
var _stats: VBoxContainer
var _body: Label
var _empty: Label
var _content: VBoxContainer
var _action: Button
var _tween: Tween
var _action_hint := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 12)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 8)
	add_child(_content)
	var column := _content

	var header := VBoxContainer.new()
	header.add_theme_constant_override(&"separation", 1)
	column.add_child(header)
	_title = UiKit.label("", 16)
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_title)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override(&"separation", 6)
	header.add_child(tag_row)
	_tag = UiKit.label("", 10, Palette.UI_MUTED)
	tag_row.add_child(_tag)
	_ammo_icon = TextureRect.new()
	_ammo_icon.custom_minimum_size = AmmoIcons.CELL * 1.5
	_ammo_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ammo_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ammo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_child(_ammo_icon)

	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	column.add_child(top)
	_plate = IconPlate.new()
	_plate.plate_size = PLATE
	top.add_child(_plate)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override(&"separation", 1)
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_stats)

	column.add_child(HSeparator.new())
	_body = UiKit.label("", 11, Palette.UI_TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 折行的標籤必須有最小寬度，否則容器排版時會先把它擠成一字寬、算出超高的最小高度。
	_body.custom_minimum_size = Vector2(BODY_MIN_WIDTH, 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	_action = UiKit.button("", _on_action, "")
	_action.custom_minimum_size = Vector2(150, 0)
	_action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_action.focus_mode = Control.FOCUS_NONE
	_action.mouse_entered.connect(func() -> void: action_hovered.emit(_action_hint))
	column.add_child(_action)

	_empty = UiKit.label("", 11, Palette.UI_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(BODY_MIN_WIDTH, 0)
	add_child(_empty)
	_content.visible = false


func _draw() -> void:
	PixelUi.frame(self, Rect2(Vector2.ZERO, size), UiTheme.PANEL_BODY, UiTheme.PANEL_EDGE, 6, 1)


## 顯示一個項目；animate = true 時圖示彈出、內容淡入。entry 為 null 時顯示 empty_text。
func show_entry(entry: InventoryEntry, empty_text := "", animate := true) -> void:
	_empty.text = empty_text
	_empty.visible = entry == null
	_content.visible = entry != null
	if entry == null:
		return
	_plate.show_icon(entry.detail_icon if entry.detail_icon != null else entry.icon, 1 if entry.detail_icon != null else entry.detail_icon_scale, entry.accent, entry.dimmed, entry.detail_icon != null)
	_title.text = entry.title
	_title.tooltip_text = entry.title
	_title.add_theme_color_override(&"font_color", entry.accent)
	_tag.text = entry.detail_tag
	_ammo_icon.texture = entry.ammo_icon
	_ammo_icon.visible = entry.ammo_icon != null
	for child in _stats.get_children():
		child.queue_free()
	for line in entry.detail_stats:
		var stat := UiKit.label(line, 11, Palette.UI_TEXT)
		stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stat.custom_minimum_size = Vector2(STATS_MIN_WIDTH, 0)
		_stats.add_child(stat)
	_body.text = entry.detail_body
	_action.visible = not entry.action_label.is_empty()
	_action.text = entry.action_label
	_action.disabled = not entry.action_enabled
	_action_hint = entry.action_hint
	_action.tooltip_text = entry.action_hint
	if animate:
		_pop_in()


func _pop_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if Settings.get_reduce_ui_motion():
		_plate.scale = Vector2.ONE
		_content.modulate.a = 1.0
		return
	_plate.pivot_offset = PLATE * 0.5
	_plate.scale = Vector2.ONE * POP_FROM
	_content.modulate.a = FADE_FROM
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_plate, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_content, "modulate:a", 1.0, POP_TIME)


func _on_action() -> void:
	action_pressed.emit()
