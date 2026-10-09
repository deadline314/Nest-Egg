class_name StatusPage
extends InventoryPage
## 角色狀態：凜的高解析立繪（骨架即時繪製，待機動畫）與生命、護盾、殘機、難度、遊玩時間、擊破數。
## 切到此頁時數字由 0 跳動到目前的值。

const PORTRAIT_SIZE := Vector2(192, 256)
const ROW_WIDTH := 330.0

## 狀態列定義：id、名稱、一句說明。順序即顯示順序。
const ROWS: Array[Dictionary] = [
	{"id": &"health", "label": "生命", "hint": "生命歸零就會倒下；醫療針可以回復"},
	{"id": &"guard", "label": "護盾", "hint": "格擋會消耗護盾能量，用盡會破防一小段時間"},
	{"id": &"lives", "label": "殘機", "hint": "殘機用盡會從關卡開頭重來"},
	{"id": &"difficulty", "label": "難度", "hint": "這一輪的難度，開始新遊戲時選擇"},
	{"id": &"time", "label": "遊玩時間", "hint": "這一輪累計的遊玩時間，暫停與背包不計"},
	{"id": &"kills", "label": "擊破數", "hint": "這一輪擊破的敵人數量（含終結技）"},
]

var _portrait: HdPortrait
var _values: Dictionary[StringName, CountUpLabel] = {}
var _health_bar: _Segments
var _guard_bar: _Segments


func tab_title() -> String:
	return "角色狀態"


func tab_tooltip() -> String:
	return "查看凜的狀態與這一輪的紀錄"


func _ready() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 24)
	add_child(row)

	var left := Control.new()
	left.custom_minimum_size = Vector2(PORTRAIT_SIZE.x + 12, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	_portrait = HdPortrait.new()
	_portrait.position = Vector2(6, 6)
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	_portrait.size = PORTRAIT_SIZE
	left.add_child(_portrait)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 6)
	row.add_child(right)
	var name_label := UiKit.label("凜", 18, Palette.MAGENTA)
	right.add_child(name_label)
	right.add_child(UiKit.label("傭兵・代號「七號」", 10, Palette.UI_MUTED))
	right.add_child(HSeparator.new())
	for def in ROWS:
		right.add_child(_make_row(def))


func _make_row(def: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(ROW_WIDTH, 30)
	row.add_theme_constant_override(&"separation", 10)
	row.tooltip_text = str(def["hint"])
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var title := UiKit.label(str(def["label"]), 12, Palette.UI_MUTED)
	title.custom_minimum_size = Vector2(70, 0)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var bar_slot := Control.new()
	bar_slot.custom_minimum_size = Vector2(120, 0)
	bar_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_slot)
	match def["id"]:
		&"health":
			_health_bar = _add_bar(bar_slot)
		&"guard":
			_guard_bar = _add_bar(bar_slot)
	var value := CountUpLabel.new()
	value.set_meta(UiKit.TEXT_SIZE_META, 13)
	value.add_theme_font_size_override(&"font_size", UiKit.scaled_size(13))
	value.add_theme_color_override(&"font_color", Palette.CYAN)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(value)
	_values[def["id"]] = value
	row.mouse_entered.connect(func() -> void: hint_changed.emit(str(def["hint"])))
	return row


func _add_bar(slot: Control) -> _Segments:
	var bar := _Segments.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bar)
	return bar


func page_shown(_animate: bool) -> void:
	_update(true)
	hint_changed.emit(current_hint())


func refresh() -> void:
	if _portrait != null:
		_update(false)


func current_hint() -> String:
	return "凜目前的狀態；這一輪的紀錄會一直累計到重新開始"


func _update(from_zero: bool) -> void:
	if context == null or not context.is_valid():
		return
	var player := context.player
	var max_health := player.health.max_health
	var health := player.health.current
	_health_bar.setup(max_health, health, Palette.DANGER if health * 3 <= max_health else Palette.CYAN)
	_values[&"health"].count_to(health, func(v: float) -> String: return "%d / %d" % [roundi(v), max_health], from_zero)
	var guard_ratio := clampf(player.guard / maxf(1.0, player.tuning.guard_max), 0.0, 1.0)
	_guard_bar.setup(10, roundi(guard_ratio * 10.0), Palette.WARNING if player.is_guard_broken() else Palette.CYAN)
	_values[&"guard"].count_to(guard_ratio * 100.0, func(v: float) -> String:
		return "破防" if player.is_guard_broken() else "%d%%" % roundi(v), from_zero)
	var lives := GameState.lives_left
	var limited := GameState.difficulty.has_limited_lives()
	_values[&"lives"].count_to(maxf(0.0, lives), func(v: float) -> String:
		return ("× %d" % roundi(v)) if limited else "無限", from_zero)
	_values[&"difficulty"].count_to(0.0, func(_v: float) -> String: return GameState.difficulty.display_name, false)
	_values[&"time"].count_to(GameState.run_time, func(v: float) -> String: return UiKit.format_time(v), from_zero)
	_values[&"kills"].count_to(GameState.kills, func(v: float) -> String:
		return "%d　（終結 %d）" % [roundi(v), GameState.finishers], from_zero)


## 像素分格的量表（生命、護盾共用）。
class _Segments:
	extends Control

	var _total := 0
	var _filled := 0
	var _color := Palette.CYAN

	func setup(total: int, filled: int, color: Color) -> void:
		_total = total
		_filled = filled
		_color = color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var cell := Vector2(floorf((size.x - _total) / maxf(1.0, _total)), 10)
		PixelUi.segments(self, Vector2(0, (size.y - cell.y) * 0.5).floor(), _total, _filled, _color, cell, 1.0)
