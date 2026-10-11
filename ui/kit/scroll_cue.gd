class_name ScrollCue
extends Control
## 捲動提示：可捲動區塊下方還有內容時，底緣淡出並在右下角顯示 ▼；已往下捲時右上角顯示 ▲。
## 只畫淡出與小箭頭，不在內文上疊文字；需要文字說明時，畫面接 overflow_changed 放在自己的操作列。
## 只在捲軸範圍、位置或尺寸改變時更新（訊號驅動），不每影格計算。
## 用法：`ScrollCue.attach(scroll)`。內文沒有可聚焦的控制項時（例如任務細節），
## 由畫面把右搖桿或 PageUp／PageDown 轉給 `ScrollCue.step(scroll, 方向)` 捲動。

signal overflow_changed(below: bool, above: bool)

const FADE_HEIGHT := 22.0
const FADE_BANDS := 6
## 一次捲動可見高度的比例；留一段重疊，玩家不會漏讀換頁處的那一行。
const STEP_RATIO := 0.7
const BOTTOM_TEXT := "▼"
const TOP_TEXT := "▲"

var more_below := false
var more_above := false

var _scroll: ScrollContainer
var _bar: VScrollBar
var _below: Label
var _above: Label
var _inset := 2.0


static func attach(scroll: ScrollContainer) -> ScrollCue:
	if scroll == null:
		push_error("[ScrollCue] 沒有指定捲動區塊，捲動提示停用")
		return null
	var cue := ScrollCue.new()
	cue._scroll = scroll
	# 內部子節點不算捲動內容，ScrollContainer 不會把它當成要排版的清單。
	scroll.add_child(cue, false, Node.INTERNAL_MODE_BACK)
	return cue


## 找出捲動區上已掛的提示（提示是內部子節點，一般的 get_children／find_children 看不到）。
static func of(scroll: ScrollContainer) -> ScrollCue:
	if scroll == null:
		return null
	for i in scroll.get_child_count(true):
		var cue := scroll.get_child(i, true) as ScrollCue
		if cue != null:
			return cue
	return null


## 捲動一頁的 STEP_RATIO；回傳是否真的移動（已在頂／底時為 false，呼叫端可讓焦點照常移動）。
static func step(scroll: ScrollContainer, direction: int) -> bool:
	if scroll == null or direction == 0:
		return false
	var bar := scroll.get_v_scroll_bar()
	var before := scroll.scroll_vertical
	var limit := maxi(0, int(bar.max_value - bar.page))
	scroll.scroll_vertical = clampi(before + signi(direction) * int(maxf(scroll.size.y * STEP_RATIO, 16.0)), 0, limit)
	return scroll.scroll_vertical != before


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = &"ScrollCue"


func _ready() -> void:
	if _scroll == null:
		_scroll = get_parent() as ScrollContainer
	if _scroll == null:
		push_error("[ScrollCue] %s：父節點不是 ScrollContainer，捲動提示停用" % get_path())
		return
	_below = _cue_label(BOTTOM_TEXT)
	_above = _cue_label(TOP_TEXT)
	_bar = _scroll.get_v_scroll_bar()
	_bar.changed.connect(_sync)
	_bar.value_changed.connect(_sync.unbind(1))
	_bar.visibility_changed.connect(_sync)
	_scroll.resized.connect(_sync)
	_sync()


func _cue_label(text: String) -> Label:
	var label := UiKit.label(text, UiKit.FS_BODY, Palette.CYAN)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override(&"outline_size", 3)
	label.add_theme_color_override(&"font_outline_color", Palette.UI_PANEL_DEEP)
	add_child(label)
	label.hide()
	return label


func _sync() -> void:
	if _bar == null:
		return
	var below := _bar.value + _bar.page < _bar.max_value - 1.0
	var above := _bar.value > 1.0
	# 捲動區不替內部子節點排版，位置與大小在這裡直接跟著捲動區。
	position = Vector2.ZERO
	size = _scroll.size
	# 捲軸佔掉右側寬度時，提示文字往左讓開，不壓在把手上。
	var inset := _bar.size.x + 4.0 if _bar.visible else 2.0
	var below_size := _below.get_minimum_size()
	_below.position = Vector2(size.x - inset - below_size.x, size.y - below_size.y)
	_below.size = below_size
	var above_size := _above.get_minimum_size()
	_above.position = Vector2(size.x - inset - above_size.x, 0)
	_above.size = above_size
	_inset = inset
	var changed := below != more_below or above != more_above
	more_below = below
	more_above = above
	_below.visible = below
	_above.visible = above
	queue_redraw()
	if changed:
		overflow_changed.emit(below, above)


func _draw() -> void:
	if not more_below:
		return
	# 底緣淡出：幾條遞增不透明度的色帶，告訴玩家文字被切在這裡、還能往下讀。
	var band := FADE_HEIGHT / FADE_BANDS
	for i in FADE_BANDS:
		var alpha := float(i + 1) / FADE_BANDS * 0.85
		draw_rect(Rect2(0, size.y - FADE_HEIGHT + band * i, size.x - _inset, band + 0.5), Color(Palette.UI_PANEL_DEEP, alpha))
