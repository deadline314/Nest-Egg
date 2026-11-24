class_name UiKit
extends RefCounted
## UI 共用工具：主題、字型、常用控制項。所有畫面共用同一份主題，確保風格一致且只建立一次。
## Tooltip 原則：一句話講重點（做什麼／怎麼用），不寫廢話。

## 平滑樣式依遊戲語言使用繁中或日文內文字型；像素樣式沿用 Cubic 11。
const FONT_STYLES := {
	"smooth": {"path": "res://art/fonts/NestEggSansTC-Regular.ttf", "pixel": false},
	"pixel": {"path": "res://art/fonts/Cubic_11.ttf", "pixel": true},
}
const DEFAULT_FONT_STYLE := "smooth"
const JAPANESE_BODY_PATH := "res://art/fonts/NestEggSansJP-Regular.ttf"
const BODY_FALLBACK_PATH := "res://art/fonts/NotoSansTC-Regular-subset.ttf"
const SPECIAL_FONT_PATHS := {
	&"display": "res://art/fonts/IBMPlexSansCondensed-SemiBold.ttf",
	&"readout": "res://art/fonts/IBMPlexMono-Medium.ttf",
}
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
## 版面角色字級：只有明確呼叫 caption()／heading() 的控制項會用到，snap_size() 的三個設計字級不變。
## 說明小字（地點、計數、按鍵提示）用 9、段落標題用 14；像素字體只有 11 才銳利，兩者都改用內文字級。
const FS_CAPTION := 9
const FS_HEADING := 14
const ROLE_META := &"ui_text_role"
const ROLE_SIZES := {&"caption": FS_CAPTION, &"heading": FS_HEADING}
const TEXT_GROUP := &"ui_scalable_text"
const TEXT_SIZE_META := &"ui_base_font_size"

static var _theme: Theme
## 工具與測試用：不為空時強制用這個樣式（不讀也不寫設定檔，截圖比較字型時不會把使用者的設定改掉）。
static var style_override := ""
## 公開的字型是一層 FontVariation：切換樣式時只換它的 base_font，所有已經拿著它的控制項、繪圖節點立刻跟著換。
static var _font: FontVariation
static var _special_fonts: Dictionary[StringName, FontVariation] = {}
static var _font_language := "zh"
static var _system_fallback: SystemFont


static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = _load_font(font_style())
	return _font


## 標題與數字沿用同一個可切換的字型物件，既有標籤不必重建。
static func special_font(role: StringName) -> Font:
	if not SPECIAL_FONT_PATHS.has(role):
		return font()
	if not _special_fonts.has(role):
		var variant := FontVariation.new()
		variant.base_font = _special_base(role)
		_special_fonts[role] = variant
	return _special_fonts[role]


static func set_font_language(language: String) -> void:
	var selected := "ja" if language == "ja" else "zh"
	if _font_language == selected:
		return
	_font_language = selected
	if _font != null and font_style() == DEFAULT_FONT_STYLE:
		apply_font_style()


## 目前的字型樣式（設定裡沒有或寫錯時用預設）。
static func font_style() -> String:
	if not style_override.is_empty() and FONT_STYLES.has(style_override):
		return style_override
	var style: String = Settings.get_ui_font()
	return style if FONT_STYLES.has(style) else DEFAULT_FONT_STYLE


## 套用設定裡的字型樣式（設定畫面切換時呼叫）。
static func apply_font_style() -> void:
	font()
	# Labels may reshape synchronously while their cached glyphs still use the old RID.
	# Keep that font alive until the text-size refresh has finished.
	var previous_bases: Array[Font] = [_font.base_font]
	_font.base_font = _load_font(font_style())
	for role in _special_fonts:
		previous_bases.append(_special_fonts[role].base_font)
		_special_fonts[role].base_font = _special_base(role)
	# 說明小字依字體樣式換字級（像素字體改用內文字級才銳利）。
	apply_text_scale()


static func _system_font() -> SystemFont:
	if _system_fallback == null:
		_system_fallback = SystemFont.new()
		_system_fallback.font_names = PackedStringArray(FONT_NAMES)
		_system_fallback.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _system_fallback


## 新字型缺字時先找同包的備援，最後才用系統字型。
static func _load_font(style: String) -> Font:
	var entry: Dictionary = FONT_STYLES.get(style, FONT_STYLES[DEFAULT_FONT_STYLE])
	var pixel: bool = entry["pixel"]
	var path: String = JAPANESE_BODY_PATH if not pixel and _font_language == "ja" else entry["path"]
	var face := _load_project_font(path, pixel)
	var system_font := _system_font()
	if pixel:
		if face != null:
			face.fallbacks = [system_font]
			return face
		push_warning("UiKit: 像素字型載入失敗（%s），使用系統字型。" % path)
		return system_font
	var fallback := _load_project_font(BODY_FALLBACK_PATH, false)
	if fallback != null:
		fallback.fallbacks = [system_font]
	if face == null:
		push_warning("UiKit: 內文字型載入失敗（%s），使用備援字型。" % path)
		return fallback if fallback != null else system_font
	face.fallbacks = [fallback] if fallback != null else [system_font]
	return face


static func _special_base(role: StringName) -> Font:
	var body := (font() as FontVariation).base_font
	if font_style() == "pixel":
		return body
	var path: String = SPECIAL_FONT_PATHS[role]
	var face := _load_project_font(path, false)
	if face == null:
		push_warning("UiKit: 字型載入失敗（%s），使用內文字型。" % path)
		return body
	face.fallbacks = [body]
	return face


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
		_theme = UiTheme.build(font(), scaled_size(BASE_FONT_SIZE))
	return _theme


static func scaled_size(base: int) -> int:
	return maxi(1, roundi(float(base) * Settings.get_ui_text_scale()))


## 版面角色目前的實際字級（依字體樣式與文字大小設定）；未知角色用內文字級。
static func role_size(role: StringName) -> int:
	if FONT_STYLES.get(font_style(), {}).get("pixel", false):
		return scaled_size(FS_BODY)
	return scaled_size(int(ROLE_SIZES.get(role, FS_BODY)))


static func caption_size() -> int:
	return role_size(&"caption")


## 僅在設定改變時更新；群組不持有節點，關閉頁面不留下參照。
static func apply_text_scale() -> void:
	if _theme != null:
		_theme.default_font_size = scaled_size(BASE_FONT_SIZE)
		_theme.set_font_size(&"font_size", &"TooltipLabel", scaled_size(BASE_FONT_SIZE))
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group(TEXT_GROUP):
		if node is Control and node.has_meta(ROLE_META):
			(node as Control).add_theme_font_size_override(&"font_size", role_size(node.get_meta(ROLE_META)))
		elif node is Label and node.has_meta(TEXT_SIZE_META):
			(node as Label).add_theme_font_size_override(&"font_size", scaled_size(int(node.get_meta(TEXT_SIZE_META))))
		elif node is CanvasItem:
			(node as CanvasItem).queue_redraw()


## 頁籤外框：選取中亮青色底與邊、下沿與面板相連，未選取暗色。
static func tab_style(selected: bool) -> StyleBox:
	return UiTheme.tab_box(selected)


static func cinematic_skip_hint(language: String, action: StringName = &"ui_cancel", exits := false) -> String:
	var copy := {"zh": "離開", "ja": "終了", "en": "Leave"} if exits else {"zh": "跳過", "ja": "スキップ", "en": "Skip"}
	return InputBindings.format("{%s} %s" % [action, copy.get(language, copy["zh"])])


static func label(text: String, size := BASE_FONT_SIZE, color := Palette.UI_TEXT,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.set_meta(TEXT_SIZE_META, snap_size(size))
	l.add_theme_font_size_override(&"font_size", scaled_size(snap_size(size)))
	l.tree_entered.connect(func() -> void:
		l.add_to_group(TEXT_GROUP)
		l.add_theme_font_size_override(&"font_size", scaled_size(int(l.get_meta(TEXT_SIZE_META)))))
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 說明小字標籤：地點、計數、分類標題與按鍵提示這類次要資訊，讓內文與標題拉開層級。
static func caption(text: String, color := Palette.UI_MUTED, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _role_label(text, &"caption", color, align)


## 段落標題標籤：一頁只給主角（例如選中任務的名稱、目前區域）。
static func heading(text: String, color := Palette.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _role_label(text, &"heading", color, align)


static func _role_label(text: String, role: StringName, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override(&"font_color", color)
	set_text_role(l, role)
	return l


## 讓既有控制項（例如小按鈕）使用版面角色字級，並跟著文字大小與字體樣式更新。
static func set_text_role(control: Control, role: StringName) -> void:
	control.set_meta(ROLE_META, role)
	control.add_theme_font_size_override(&"font_size", role_size(role))
	control.tree_entered.connect(func() -> void:
		control.add_to_group(TEXT_GROUP)
		control.add_theme_font_size_override(&"font_size", role_size(role)))


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
	# 此分支由 viewport 明確指定尺寸，避免全幅錨點再覆寫同一尺寸。
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
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
