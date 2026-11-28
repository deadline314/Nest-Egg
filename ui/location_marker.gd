class_name LocationMarker
extends CanvasLayer
## 地點標示：進入一個地點時，右下角像雙語路牌的一小塊標示淡入、停留、淡出後自行釋放。
## 一條霓虹細軌由上往下畫出來，地名（標題字體）接著淡入，下面一行是另一種語言的地名；
## 後面只有往左淡掉的暗色襯底，沒有方框。回訪時只顯示地名、較小、停留較短。
## 右下角是可走地面以下的地層，角色、敵人、子彈與世界提示都在地面之上；左上角是任務目標、左下角是武器列。
## 不擋輸入；暫停、背包、通訊與任何蓋住遊戲的畫面（死亡畫面、提示…）出現時凍結並藏起來；「減少動態」時不滑動、不畫軌，只淡入淡出。

signal finished

## 第一次到訪：細軌畫出、地名淡入、第二行淡入、停留、淡出（秒）。
const RAIL_TIME := 0.28
const NAME_DELAY := 0.12
const NAME_TIME := 0.5
const SUB_DELAY := 0.22
const HOLD_FIRST := 2.8
const HOLD_REVISIT := 1.4
const FADE_OUT := 0.9
## 地名淡入時從右邊滑進來的距離（畫面像素）。
const SLIDE := 6.0
## 版面（畫面像素）：右緣和右下角的操作說明對齊（hud.gd 的操作說明右緣離畫面 12、上緣離底邊 34），
## 標示下緣固定在操作說明上方 10 像素，兩者看起來是上下兩塊、不是疊在一起。
const MARGIN_RIGHT := 12.0
const CONTROLS_TOP := 34.0
const CONTROLS_GAP := 10.0
const MARGIN_BOTTOM := CONTROLS_TOP + CONTROLS_GAP
## 玩家或敵人進到標示的範圍時，標示淡到這個程度（判讀優先）；淡出、恢復的速度（每秒）。
const AVOID_ALPHA := 0.12
const AVOID_SPEED := 5.0
## 判斷角色有沒有進到標示範圍時，角色身體的大約範圍（世界座標，腳底為原點）。
const BODY_RECT := Rect2(-12, -56, 24, 56)
const RAIL_GAP := 7.0
const RAIL_WIDTH := 2.0
## 暗色襯底：從文字左緣再往左延伸多遠才完全透明、最深處的不透明度（HDR 線性混色，要夠高才看得出來）。
const WASH_REACH := 96.0
const WASH_ALPHA := 0.62
const WASH_COLOR := Color("060b12")
const SCAN_STEP := 3.0
const SCAN_ALPHA := 0.025
const NAME_COLOR := Color("eef6f8")
## 第二行（外文地名）：比地名弱一階，對比仍至少 4.5:1（見 TYPOGRAPHY.md 的對比標準）。
const SUB_COLOR := Color("7fd3e3")
## 地名裡的括號註記（例如「當舖（天亮）」的「天亮」）另外用小字排在地名右邊。
const NOTE_PATTERN := "^(.+?)\\s*[（(]([^）)]+)[）)]\\s*$"

## 主要地名（遊戲語言）、第二行（另一種語言的地名，可空白）。
var place_name := ""
var secondary := ""
var revisit := false

var _root: Control
var _art: _Art
var _slider: Control
var _column: VBoxContainer
var _name_row: HBoxContainer
var _name_label: Label
var _note_label: Label
var _sub_label: Label
var _tween: Tween
var _rail := 0.0
var _text_alpha := 0.0
var _sub_alpha := 0.0
var _envelope := 1.0
var _slide := 0.0
var _suspended := false
var _avoid := 1.0
static var _note_regex: RegEx


## 依區域資料建立標示；名稱空白時回傳 null（不顯示）。
static func for_level(level_data: LevelData, language: String, is_revisit: bool) -> LocationMarker:
	if level_data == null:
		return null
	var main := level_data.display_name_for(language).strip_edges()
	if main.is_empty():
		return null
	var marker := LocationMarker.new()
	marker.place_name = main
	marker.revisit = is_revisit
	var other_language := "zh" if language == "en" else "en"
	var other := level_data.display_name_for(other_language).strip_edges()
	if other != main:
		other = split_note(other)[0]
		marker.secondary = other.to_upper() if other_language == "en" else other
	return marker


## 「當舖（天亮）」→ ["當舖", "天亮"]；沒有括號註記時第二項是空字串。
static func split_note(text: String) -> PackedStringArray:
	if _note_regex == null:
		_note_regex = RegEx.create_from_string(NOTE_PATTERN)
	var found := _note_regex.search(text)
	if found == null:
		return PackedStringArray([text, ""])
	return PackedStringArray([found.get_string(1), found.get_string(2)])


func _ready() -> void:
	layer = UiLayers.LOCATION_MARKER
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(UiLayers.PRESENTATION_GROUP)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_art = _Art.new()
	_art.marker = self
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art)
	# 滑入只移動這一層（容器會重設子節點位置，不能直接移文字）。
	_slider = Control.new()
	_slider.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_slider)
	_column = VBoxContainer.new()
	_column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_column.offset_right = -(MARGIN_RIGHT + RAIL_WIDTH + RAIL_GAP)
	_column.offset_bottom = -MARGIN_BOTTOM
	_column.offset_left = _column.offset_right
	_column.offset_top = _column.offset_bottom
	_column.add_theme_constant_override(&"separation", 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slider.add_child(_column)
	_name_row = HBoxContainer.new()
	_name_row.alignment = BoxContainer.ALIGNMENT_END
	_name_row.add_theme_constant_override(&"separation", 6)
	_name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_name_row)
	var parts := split_note(place_name)
	# 地名用畫面標題的字體；回訪的短版用段落標題的字級。
	_name_label = UiKit.styled(parts[0], &"title", NAME_COLOR)
	if revisit:
		UiKit.set_text_role(_name_label, &"heading")
	_name_row.add_child(_name_label)
	_note_label = UiKit.styled(parts[1], &"caption", SUB_COLOR)
	_note_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_note_label.visible = not parts[1].is_empty()
	_name_row.add_child(_note_label)
	_sub_label = UiKit.styled(secondary, &"label", SUB_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_sub_label.visible = not revisit and not secondary.is_empty()
	_column.add_child(_sub_label)
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)
	_set_rail(0.0)
	_set_text(0.0)
	_set_sub(0.0)
	_start()
	_update_presentation()


func _start() -> void:
	var still := Settings.get_reduce_ui_motion()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_tween.set_parallel(true)
	if still:
		_set_rail(1.0)
		_tween.tween_method(_set_text, 0.0, 1.0, NAME_TIME)
		if _sub_label.visible:
			_tween.tween_method(_set_sub, 0.0, 1.0, NAME_TIME)
	else:
		_tween.tween_method(_set_rail, 0.0, 1.0, RAIL_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_method(_set_text, 0.0, 1.0, NAME_TIME).set_delay(NAME_DELAY).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		if _sub_label.visible:
			_tween.tween_method(_set_sub, 0.0, 1.0, NAME_TIME).set_delay(NAME_DELAY + SUB_DELAY)
	_tween.chain().tween_interval(HOLD_REVISIT if revisit else HOLD_FIRST)
	_tween.chain().tween_method(_set_envelope, 1.0, 0.0, FADE_OUT).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_callback(_done)


func _set_rail(value: float) -> void:
	_rail = value
	if is_instance_valid(_art):
		_art.queue_redraw()


func _set_text(value: float) -> void:
	_text_alpha = value
	_slide = 0.0 if Settings.get_reduce_ui_motion() else (1.0 - value) * SLIDE
	if is_instance_valid(_name_row):
		_name_row.modulate.a = value
	if is_instance_valid(_slider):
		_slider.position.x = _slide
	if is_instance_valid(_art):
		_art.queue_redraw()


func _set_sub(value: float) -> void:
	_sub_alpha = value
	if is_instance_valid(_sub_label):
		_sub_label.modulate.a = value


func _set_envelope(value: float) -> void:
	_envelope = value
	_apply_alpha()


func _apply_alpha() -> void:
	if is_instance_valid(_root):
		_root.modulate.a = _envelope * _avoid


## 從出現到釋放要多久（秒，不含暫停的時間）。
func lifetime() -> float:
	var appear := NAME_DELAY + NAME_TIME + (SUB_DELAY if not revisit and not secondary.is_empty() else 0.0)
	return maxf(appear, RAIL_TIME) + (HOLD_REVISIT if revisit else HOLD_FIRST) + FADE_OUT


## 目前可見的程度（工具與測試用）：地名淡入的程度乘上整體淡出。
func presentation_alpha() -> float:
	if not is_instance_valid(_root) or not _root.visible:
		return 0.0
	return _text_alpha * _envelope


func is_showing() -> bool:
	return presentation_alpha() > 0.01


## 整塊標示在畫面上的範圍（畫面像素）：細軌到文字右緣，加上襯底。
func screen_rect() -> Rect2:
	if not is_instance_valid(_column):
		return Rect2()
	var text_rect := _column.get_rect()
	return Rect2(text_rect.position, Vector2(rail_x() + RAIL_WIDTH - text_rect.position.x, text_rect.size.y)).grow_individual(6, 2, 0, 2)


## 細軌的 x（畫面像素）：跟著畫面寬度靠右。
func rail_x() -> float:
	return (_root.size.x if is_instance_valid(_root) else 640.0) - MARGIN_RIGHT - RAIL_WIDTH


func prompt_obstacle_rect() -> Rect2:
	if not is_instance_valid(_root) or not _root.visible or presentation_alpha() <= 0.01:
		return Rect2()
	var canvas := get_viewport().get_canvas_transform()
	if not is_finite(canvas.determinant()) or is_zero_approx(canvas.determinant()):
		return Rect2()
	return canvas.affine_inverse() * screen_rect()


func _process(delta: float) -> void:
	_update_presentation()
	if not _root.visible:
		return
	var target := AVOID_ALPHA if crowded() else 1.0
	if not is_equal_approx(_avoid, target):
		_avoid = move_toward(_avoid, target, delta * AVOID_SPEED)
		_apply_alpha()


## 玩家或敵人在標示的範圍裡（畫面座標）：標示要讓開。只在標示存在的幾秒內檢查。
func crowded() -> bool:
	var area := screen_rect()
	if not area.has_area():
		return false
	var canvas := get_viewport().get_canvas_transform()
	for group: StringName in [&"player", &"enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var body := node as Node2D
			if body != null and body.is_visible_in_tree() and area.intersects(canvas * Rect2(body.global_position + BODY_RECT.position, BODY_RECT.size)):
				return true
	return false


func _update_presentation() -> void:
	var suspended := UiLayers.gameplay_covered(get_tree())
	_root.visible = not suspended
	if suspended == _suspended:
		return
	_suspended = suspended
	if _tween != null and _tween.is_valid():
		if suspended:
			_tween.pause()
		else:
			_tween.play()


func _done() -> void:
	finished.emit()
	queue_free()


## 細軌與往左淡掉的暗色襯底；只在動畫進行時重畫。
class _Art extends Control:
	var marker: LocationMarker
	static var _wash: GradientTexture2D

	func _draw() -> void:
		if marker == null:
			return
		var area := marker.screen_rect()
		if not area.has_area():
			return
		var rail_x := marker.rail_x()
		var top := area.position.y
		var full := area.size.y
		var text := marker._text_alpha
		# 襯底：細軌那一側最深，往左越過文字一段距離才完全透明；只跟著地名淡入。
		if text > 0.0:
			var left := area.position.x - LocationMarker.WASH_REACH
			var wash := Rect2(Vector2(left, top), Vector2(rail_x - left, full))
			draw_texture_rect(_wash_texture(), wash, false, Color(LocationMarker.WASH_COLOR, LocationMarker.WASH_ALPHA * text))
			var y := top + 1.0
			while y < top + full:
				# 掃描線用同一張漸層，跟襯底一起往左淡掉，不留硬邊。
				draw_texture_rect(_wash_texture(), Rect2(Vector2(left, y), Vector2(wash.size.x - 2.0, 1.0)), false, Color(Palette.CYAN, LocationMarker.SCAN_ALPHA * text))
				y += LocationMarker.SCAN_STEP
		# 細軌：由上往下畫出來；頂端一小段往左的短橫，像路牌的掛架。
		var rail_len := full * marker._rail
		if rail_len > 0.5:
			var rail_color := LightKit.glow(Palette.CYAN, 1.15)
			draw_rect(Rect2(Vector2(rail_x, top), Vector2(LocationMarker.RAIL_WIDTH, rail_len)), rail_color)
			var tick := 5.0 * marker._rail
			draw_rect(Rect2(Vector2(rail_x + LocationMarker.RAIL_WIDTH - tick, top), Vector2(tick, 1.0)), rail_color)

	## 左透明、右不透明的白色橫向漸層（畫時再染成襯底或掃描線的顏色），所有標示共用一張。
	static func _wash_texture() -> GradientTexture2D:
		if _wash == null:
			var gradient := Gradient.new()
			gradient.set_color(0, Color(1, 1, 1, 0.0))
			gradient.set_color(1, Color.WHITE)
			gradient.add_point(0.45, Color(1, 1, 1, 0.8))
			_wash = GradientTexture2D.new()
			_wash.gradient = gradient
			_wash.width = 128
			_wash.height = 1
		return _wash