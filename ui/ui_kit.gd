class_name UiKit
extends RefCounted
## UI 共用工具：主題、字型、常用控制項。所有畫面共用同一份主題，確保風格一致且只建立一次。
## Tooltip 原則：一句話講重點（做什麼／怎麼用），不寫廢話。

## 介面字型樣式（NE-215）：smooth＝思源黑體（Noto Sans TC，只含專案用到的字加常用符號的子集，SIL OFL），
## pixel＝Cubic 11 像素字。設定畫面的「平滑字型」可切換；新增樣式只在這裡加一筆。
const FONT_STYLES := {
	"smooth": {"path": "res://art/fonts/NotoSansTC-Regular-subset.ttf", "pixel": false},
	"pixel": {"path": "res://art/fonts/Cubic_11.ttf", "pixel": true},
}
const DEFAULT_FONT_STYLE := "smooth"
## 舊名稱：像素字檔（測試與工具引用）。
const FONT_PATH := "res://art/fonts/Cubic_11.ttf"
## 系統備援字型（專案字體載入失敗，或遇到字體沒有的字時使用）。
const FONT_NAMES: Array[String] = [
	"Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "PingFang TC", "Heiti TC",
	"Source Han Sans TC", "Noto Sans CJK JP", "sans-serif",
]
## 字級只用整數倍（像素字體只有整數倍才銳利）。新增畫面只從這三個挑。
const FS_BODY := 11
const FS_TITLE := 22
const FS_DISPLAY := 33
const BASE_FONT_SIZE := FS_BODY

static var _theme: Theme
## 工具與測試用：不為空時強制用這個樣式（不讀也不寫設定檔，截圖比較字型時不會把使用者的設定改掉）。
static var style_override := ""
## 公開的字型是一層 FontVariation：切換樣式時只換它的 base_font，所有已經拿著它的控制項、繪圖節點立刻跟著換。
static var _font: FontVariation


static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = _load_font(font_style())
	return _font


## 目前的字型樣式（設定裡沒有或寫錯時用預設）。
static func font_style() -> String:
	if not style_override.is_empty() and FONT_STYLES.has(style_override):
		return style_override
	var style: String = Settings.get_ui_font()
	return style if FONT_STYLES.has(style) else DEFAULT_FONT_STYLE


## 套用設定裡的字型樣式（設定畫面切換時呼叫）。
static func apply_font_style() -> void:
	font()
	_font.base_font = _load_font(font_style())


## 先用專案字體；載入失敗時記錄並退回系統字型。系統字型同時掛為專案字體的備援，缺字不顯示方塊。
static func _load_font(style: String) -> Font:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(FONT_NAMES)
	system_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var entry: Dictionary = FONT_STYLES.get(style, FONT_STYLES[DEFAULT_FONT_STYLE])
	var project_font := _load_project_font(str(entry["path"]), bool(entry["pixel"]))
	if project_font == null:
		push_warning("UiKit: 專案字體載入失敗（%s），改用系統字型。" % entry["path"])
		return system_font
	project_font.fallbacks = [system_font]
	return project_font


static func _load_project_font(path: String, pixel: bool) -> FontFile:
	var loaded: Variant = load(path) if ResourceLoader.exists(path) else null
	var font_file := loaded as FontFile
	if font_file == null:
		# 尚未匯入（例如新 clone 沒開過編輯器）時，直接讀檔案。
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		font_file = FontFile.new()
		font_file.data = bytes
	# 像素字只有關掉抗鋸齒與次像素定位才銳利；平滑字用灰階抗鋸齒與輕度微調。
	font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE if pixel else TextServer.FONT_ANTIALIASING_GRAY
	font_file.hinting = TextServer.HINTING_NONE if pixel else TextServer.HINTING_LIGHT
	font_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED if pixel else TextServer.SUBPIXEL_POSITIONING_AUTO
	font_file.allow_system_fallback = true
	return font_file


## 任何字級對應到最近的設計字級（<=16 內文、<=27 標題、其餘大標）。
static func snap_size(size: int) -> int:
	if size <= 16:
		return FS_BODY
	if size <= 27:
		return FS_TITLE
	return FS_DISPLAY


static func theme() -> Theme:
	if _theme == null:
		_theme = UiTheme.build(font(), BASE_FONT_SIZE)
	return _theme


## 頁籤外框：選取中亮青色底與邊、下沿與面板相連，未選取暗色。
static func tab_style(selected: bool) -> StyleBox:
	return UiTheme.tab_box(selected)


static func label(text: String, size := BASE_FONT_SIZE, color := Palette.UI_TEXT,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", snap_size(size))
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 建立按鈕；tooltip 請寫一句重點。選取與確認的音效、動畫由 UiButton 負責。
static func button(text: String, on_pressed: Callable, tooltip := "") -> Button:
	var b := UiButton.new()
	b.text = text
	b.tooltip_text = tooltip
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## 全螢幕置中面板（死亡／暫停／過關畫面共用）。回傳內容 VBox。
static func centered_panel(parent: Control, min_width := 360.0, dim := 0.6) -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	return box


## 讓控制項填滿父節點。在 _ready 內對自己用請用這個：set_anchors_preset 會依「目前尺寸」重算偏移，
## 新節點尺寸是 0，掛在 Control 底下就變成 0 大小（遮罩消失、畫面疊在一起）。
static func fill_parent(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func full_rect_root(theme_owner: Node) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme()
	theme_owner.add_child(root)
	return root


## 遊戲中隱藏系統游標（改用準星），選單與暫停時顯示。
static func set_cursor_visible(visible: bool) -> void:
	GameplayLock.set_base_mouse_mode(Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_HIDDEN)


static func format_time(seconds: float) -> String:
	var total := maxf(0.0, seconds)
	return "%02d:%05.2f" % [int(total / 60.0), fmod(total, 60.0)]


## 讓「父節點不是 Control」的畫面（例如直接掛在 Main 底下）永遠填滿視窗。
static func fit_to_viewport(control: Control) -> void:
	var viewport := control.get_viewport()
	if viewport == null:
		return
	var resize := func() -> void:
		if is_instance_valid(control):
			control.position = Vector2.ZERO
			control.size = viewport.get_visible_rect().size
	resize.call()
	viewport.size_changed.connect(resize)
	# 畫面移除時解除連線，避免殘留回呼。
	control.tree_exiting.connect(func() -> void:
		if viewport.size_changed.is_connected(resize):
			viewport.size_changed.disconnect(resize), CONNECT_ONE_SHOT)
