class_name PickupFeed
extends VBoxContainer
## 拾取紀錄：撿到東西時在右上角信用點下方疊一行，幾秒後淡出；同一句在顯示中再出現就刷新並計次，不洗版。
## 取代畫面中央的「取得」橫幅，戰鬥時不擋住角色與敵人；通訊出現時先讓位（計時暫停），通訊結束再回來。
## 列數固定、物件池重用，閒置時不跑 _process。

const MAX_ROWS := 4
const HOLD := 2.6
const FADE := 0.45
const FADE_IN := 0.12

var _rows: Array[_Row] = []
var _serial := 0


class _Row extends PanelContainer:
	var label: Label
	var base_text := ""
	var repeats := 1
	var left := 0.0
	var age := 0.0
	## 加入順序；同一影格加入多行時用它分辨誰最舊。
	var serial := 0


func _init() -> void:
	name = &"PickupFeed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 2)
	for i in MAX_ROWS:
		var row := _Row.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 每行只和文字一樣寬，靠右對齊信用點。
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		var style := ChamferBox.make(Color(Palette.UI_PANEL, 0.8), Color(Palette.NEON_YELLOW, 0.55), 2, 1)
		style.bevel = false
		style.margins(6, 1, 6, 1)
		row.add_theme_stylebox_override(&"panel", style)
		row.label = UiKit.label("", UiKit.FS_BODY, Palette.NEON_YELLOW)
		row.add_child(row.label)
		row.hide()
		add_child(row)
		_rows.append(row)
	set_process(false)


func _ready() -> void:
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)


## A fresh row reserves its whole allotted slot before its first fade-in/layout.
## Empty, radio-covered and expired feeds release the space immediately.
func prompt_obstacle_rect() -> Rect2:
	if not is_visible_in_tree() or DialogueLayer.radio_visible():
		return Rect2()
	var occupied := false
	for row in _rows:
		if row.visible:
			occupied = true
			break
	if not occupied:
		return Rect2()
	return (get_viewport().get_canvas_transform().affine_inverse() * get_global_transform_with_canvas()) * Rect2(Vector2.ZERO, size.max(get_minimum_size()))


## 加一行；顯示中已有同一句就刷新時間並顯示次數。
func push(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	for row in _rows:
		if row.visible and row.base_text == text:
			row.repeats += 1
			row.label.text = "%s ×%d" % [text, row.repeats]
			row.left = HOLD
			_serial += 1
			row.serial = _serial
			move_child(row, get_child_count() - 1)
			set_process(true)
			PromptLayout.invalidate()
			return
	var row := _free_row()
	row.base_text = text
	row.repeats = 1
	row.label.text = text
	row.left = HOLD
	row.age = 0.0
	_serial += 1
	row.serial = _serial
	row.modulate.a = 1.0 if Settings.get_reduce_ui_motion() else 0.0
	row.show()
	move_child(row, get_child_count() - 1)
	set_process(true)
	PromptLayout.invalidate()


## 目前顯示中的文字（由舊到新；測試與除錯用）。
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in get_children():
		var row := child as _Row
		if row != null and row.visible:
			out.append(row.label.text)
	return out


func _free_row() -> _Row:
	var oldest: _Row = null
	for row in _rows:
		if not row.visible:
			return row
		if oldest == null or row.serial < oldest.serial:
			oldest = row
	return oldest


func _process(delta: float) -> void:
	# 通訊佔用畫面上方時先收起，計時也暫停，通訊結束後照原本剩下的時間顯示。
	visible = not DialogueLayer.radio_visible()
	if not visible:
		return
	var still_showing := false
	var reduce := Settings.get_reduce_ui_motion()
	for row in _rows:
		if not row.visible:
			continue
		row.age += delta
		row.left -= delta
		if row.left <= 0.0:
			row.hide()
			continue
		still_showing = true
		# 新的一行短暫淡入（減少動態時直接出現），最後幾分之一秒淡出。
		var fade_in := 1.0 if reduce else clampf(row.age / FADE_IN, 0.0, 1.0)
		row.modulate.a = minf(fade_in, clampf(row.left / FADE, 0.0, 1.0))
	if not still_showing:
		set_process(false)
