class_name RadioCard
extends PanelContainer
## 通訊對話框的外觀（NE-274）。純外觀：不排隊、不計時、不碰劇情；對話層把講者顏色、頭像、名字與內文塞進來就好。
##
## 組成（由左到右）：講者顏色的直條、方形頭像格、名牌＋訊號格、內文；底部一條細線表示這一句還會停多久。
## - 講者的顏色用在直條、頭像框、面板的四個角標、名牌的邊與訊號格，同一個人永遠同一個顏色（不只靠顏色：還有名字與頭像）。
## - 「這是通訊」用訊號格表示（講話時跳動、講完降到底），不再寫「通訊」兩個字。
## - 頭像格固定是方形，內文變兩行時不跟著拉長；沒有頭像的講者顯示「只有聲音」的波形，不留空框。
## - 面板一出現就是這一句需要的高度（逐字顯示時不會中途長高），長句之後接短句會縮回去。
## - 設定的「減少介面動態」打開時，訊號格、掃描線與滑入都不動。
##
## 對話層只要認得這幾個節點：accent（直條，設它的 color 就是設講者顏色）、portrait、name_label、column（內文加在這裡）。

const PORTRAIT_SIZE := 40.0
const ACCENT_WIDTH := 3.0
const GAP := 7.0
const BODY := Color("0d1820")
const EDGE := Color("36505f")
const CELL := Color("081017")
const METER_BARS := 5

var accent: ColorRect
var portrait: TextureRect
var name_label: Label
var column: VBoxContainer
## 回傳這一句還剩多少停留時間（0～1）；小於 0 表示現在不顯示（字還在出現、或這一句要等玩家確認）。
var hold_source := Callable()

var _box: ChamferBox
var _cell_box: ChamferBox
var _plate_box: ChamferBox
var _cell: Control
var _plate: PanelContainer
var _overlay: Control
var _meter: Control
var _text: Label
var _speaker := Color(0, 0, 0, 0)
var _time := 0.0
var _hold := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = ChamferBox.make(BODY, EDGE, 5, 2)
	_box.margins(7, 6, 10, 7)
	_box.scanlines = 0.05
	add_theme_stylebox_override(&"panel", _box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	accent = ColorRect.new()
	accent.custom_minimum_size = Vector2(ACCENT_WIDTH, 0)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(accent)
	_build_cell(row)
	column = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.child_entered_tree.connect(_adopt)
	row.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	_plate = PanelContainer.new()
	var plate := _plate
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_box = ChamferBox.make(Color("14252f"), EDGE, 2, 1)
	_plate_box.margins(5, 0, 6, 0)
	_plate_box.bevel = false
	plate.add_theme_stylebox_override(&"panel", _plate_box)
	header.add_child(plate)
	name_label = UiKit.label("", UiKit.FS_BODY, Palette.CYAN)
	plate.add_child(name_label)
	_meter = Control.new()
	_meter.custom_minimum_size = Vector2(METER_BARS * 3 - 1, 9)
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.draw.connect(_draw_meter)
	header.add_child(_meter)
	minimum_size_changed.connect(_fit.call_deferred)


## 內文以外、左右兩邊固定占掉的寬度（對話層用它算內文可以多寬）。
func side_width() -> float:
	return _box.get_content_margin(SIDE_LEFT) + _box.get_content_margin(SIDE_RIGHT) + ACCENT_WIDTH + PORTRAIT_SIZE + GAP * 2.0


func _build_cell(row: HBoxContainer) -> void:
	_cell = PanelContainer.new()
	_cell.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell.clip_contents = true
	_cell_box = ChamferBox.make(CELL, Palette.CYAN, 3, 2)
	_cell_box.margins(2, 2, 2, 2)
	_cell.add_theme_stylebox_override(&"panel", _cell_box)
	row.add_child(_cell)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell.add_child(portrait)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_cell.add_child(_overlay)


## 對話層把內文標籤加進 column：記住它，訊號格看它出字的進度。
func _adopt(node: Node) -> void:
	if node is Label and node != name_label and _text == null:
		_text = node as Label
		# 先照整句排版再逐字顯示：兩行的句子一開始就是兩行高，不會字出到第二行時整個面板跳一下。
		_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if accent.color != _speaker:
		_tint(accent.color)
	# 頭像隱藏時（沒有圖）頭像格照樣留著，改畫「只有聲音」。
	if not Settings.get_reduce_ui_motion():
		_time += delta
	var hold := float(hold_source.call()) if hold_source.is_valid() else -1.0
	if not is_equal_approx(hold, _hold):
		_hold = hold
		queue_redraw()
	_meter.queue_redraw()
	_overlay.queue_redraw()


## 講者換人：直條以外用到講者顏色的地方一起換。
func _tint(color: Color) -> void:
	_speaker = color
	_cell_box.border = color
	_box.bracket = Color(color, 0.9)
	_plate_box.border = EDGE.lerp(color, 0.55)
	_plate_box.fill = Color("14252f").lerp(color, 0.08)
	# 面板樣式改了顏色不會自己重畫。
	_cell.queue_redraw()
	_plate.queue_redraw()
	queue_redraw()


## 內文從兩行變回一行時，把面板縮回去（獨立擺放的面板不會自己縮）。
func _fit() -> void:
	size.y = get_combined_minimum_size().y


## 講者正在講話（字還在出現）：訊號格跳動的那段時間。
func radio_speaking() -> bool:
	return _text != null and _text.visible_ratio < 1.0


## 底部的停留線：這一句還會停多久。
func _draw() -> void:
	if _hold < 0.0 or column == null:
		return
	var left := column.position.x
	var right := size.x - _box.get_content_margin(SIDE_RIGHT)
	var y := size.y - 4.0
	draw_rect(Rect2(left, y, right - left, 1.0), Color(_speaker, 0.14))
	draw_rect(Rect2(left, y, roundf((right - left) * clampf(_hold, 0.0, 1.0)), 1.0), Color(_speaker, 0.7))


## 訊號格：講話時每一格依時間起伏，講完降到最低一格；減少動態時講話固定成階梯、不跳。
func _draw_meter() -> void:
	var speaking := radio_speaking()
	var height := _meter.size.y
	for index in METER_BARS:
		var level := 0.2
		if speaking:
			level = 0.35 + 0.65 * absf(sin(_time * (7.0 + index * 1.7) + index * 1.3)) if not Settings.get_reduce_ui_motion() \
					else 0.4 + 0.15 * float(index % 3)
		var bar := maxf(1.0, roundf(height * level))
		_meter.draw_rect(Rect2(index * 3.0, height - bar, 2.0, bar), Color(_speaker, 1.0 if speaking else 0.45))


## 頭像格上面的掃描線；沒有頭像時畫「只有聲音」的波形。
func _draw_overlay() -> void:
	var area := _overlay.size
	if portrait.texture == null or not portrait.visible:
		var mid := area.y * 0.5
		var count := int(area.x / 4.0) - 1
		for index in count:
			var phase := float(index) / maxf(1.0, count - 1.0)
			var envelope := sin(phase * PI)
			var wave := absf(sin(_time * 5.0 + index * 0.9)) if radio_speaking() and not Settings.get_reduce_ui_motion() else 0.45
			var half := maxf(1.0, roundf((area.y * 0.34) * envelope * (0.35 + 0.65 * wave)))
			_overlay.draw_rect(Rect2(3.0 + index * 4.0, mid - half, 2.0, half * 2.0), Color(_speaker, 0.85))
	for y in range(0, int(area.y), 2):
		_overlay.draw_rect(Rect2(0, y, area.x, 1.0), Color(0, 0, 0, 0.16))
	if not Settings.get_reduce_ui_motion():
		# 一條慢慢往下掃的亮帶，像畫面在更新。
		var sweep := fposmod(_time * 14.0, area.y + 12.0) - 6.0
		_overlay.draw_rect(Rect2(0, sweep, area.x, 3.0), Color(_speaker, 0.10))
