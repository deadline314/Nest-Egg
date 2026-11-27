class_name TagButton
extends UiButton
## 拼貼版面的主要項目（NE-403）：外框是一張微微傾斜的貨運吊牌（切角、打孔、穿繩、撕線），文字永遠水平。
## 選到（焦點或滑鼠）時吊牌轉正、放大一點、文字往前一步；確認時壓下再彈回；選到後待機時很慢地呼吸。
## 開啟畫面時由呼叫端 intro() 依序彈入（帶一點過衝）。所有動畫 300 毫秒內完成、不擋輸入，
## 連續操作以最後一次為準；「減少動態」時直接到位。點擊範圍跟著畫面上看到的吊牌形狀。
## 靜止時不重畫；呼吸只在選到、看得到、沒有減少動態時才跑，離開畫面就停。

const SELECT_TIME := 0.14
const PRESS_DOWN := 0.06
const PRESS_UP := 0.1
const INTRO_TIME := 0.18
const INTRO_SLIDE := 26.0
const BREATH_PERIOD := 2.8
const BREATH_SCALE := 0.016
## 選到時放大多少、文字往前多少（像素）。
const ACTIVE_SCALE := 0.05
const ACTIVE_SHIFT := 6.0
const PRESS_SCALE := 0.05
const TEXT_MARGIN := 18.0
const NOTCH := 7.0
const HOLE_INSET := 7.0

## 待機時的傾斜（度，2～6 度；正值順時針）。
var tilt_degrees := 3.0:
	set(value):
		tilt_degrees = value
		_redraw()
var accent := Palette.CYAN
## 文字左右的留白（左邊要讓出打孔）；分頁這種窄的吊牌用小一點的值。
var text_margin := TEXT_MARGIN:
	set(value):
		text_margin = value
		_margin.content_margin_left = text_margin + ACTIVE_SHIFT * _active
var text_margin_right := 10.0:
	set(value):
		text_margin_right = value
		_margin.content_margin_right = value
## 不靠焦點也維持轉正（例如目前所在的分頁吊牌）。
var pinned := false:
	set(value):
		if value != pinned:
			pinned = value
			_refresh_active()

var _active := 0.0
var _press := 0.0
var _breath := 0.0
var _intro := 1.0
var _frame: _Frame
var _margin := StyleBoxEmpty.new()
var _active_tween: Tween
var _press_tween: Tween
var _breath_tween: Tween
var _intro_tween: Tween


func _init() -> void:
	super()
	show_marker = false
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	_margin.content_margin_left = TEXT_MARGIN
	_margin.content_margin_right = 10.0
	_margin.content_margin_top = 5.0
	_margin.content_margin_bottom = 5.0
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		add_theme_stylebox_override(state, _margin)
	_frame = _Frame.new()
	_frame.button = self
	_frame.show_behind_parent = true
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	focus_entered.connect(_refresh_active)
	focus_exited.connect(_refresh_active)
	mouse_entered.connect(_refresh_active)
	mouse_exited.connect(_refresh_active)
	button_down.connect(_press_feedback)
	visibility_changed.connect(_refresh_breath)
	resized.connect(_redraw)


## 選到的程度（0 = 傾斜待機，1 = 轉正往前）。測試與截圖用。
func active_amount() -> float:
	return _active


## 現在畫面上吊牌的傾斜（弧度）。
func current_tilt() -> float:
	return deg_to_rad(tilt_degrees) * (1.0 - _active)


## 依序彈入：delay 秒後從左邊滑進來並帶一點過衝。「減少動態」時直接到位。
func intro(delay: float) -> void:
	if _intro_tween != null:
		_intro_tween.kill()
	if Settings.get_reduce_ui_motion() or not is_inside_tree():
		_set_intro(1.0)
		return
	_set_intro(0.0)
	_intro_tween = create_tween()
	_intro_tween.tween_method(_set_intro, 0.0, 1.0, INTRO_TIME).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 畫面上吊牌的外形（本地座標），繪製與點擊判斷共用。
func shape_points() -> PackedVector2Array:
	var body := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	var scale_factor := 1.0 + ACTIVE_SCALE * _active - PRESS_SCALE * _press + _breath
	var center := body.get_center()
	body = Rect2(center - body.size * 0.5 * scale_factor, body.size * scale_factor)
	body.position.x += -INTRO_SLIDE * (1.0 - _intro) + ACTIVE_SHIFT * 0.5 * _active
	var points := CollageShapes.tag_polygon(body, NOTCH)
	return CollageShapes.rotated(points, center, current_tilt())


func _has_point(point: Vector2) -> bool:
	return CollageShapes.contains(shape_points(), point)


func _draw() -> void:
	pass  # 外框由 _Frame 畫在文字後面；不畫 UiButton 的方形閃光。


func _refresh_active() -> void:
	var target := 1.0 if (pinned or has_focus() or is_hovered()) and not disabled else 0.0
	if _active_tween != null:
		_active_tween.kill()
	if Settings.get_reduce_ui_motion() or not is_inside_tree():
		_set_active(target)
	else:
		_active_tween = create_tween()
		_active_tween.tween_method(_set_active, _active, target, SELECT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_refresh_breath()


func _press_feedback() -> void:
	if _press_tween != null:
		_press_tween.kill()
	if Settings.get_reduce_ui_motion() or not is_inside_tree():
		_set_press(0.0)
		return
	_press_tween = create_tween()
	_press_tween.tween_method(_set_press, _press, 1.0, PRESS_DOWN)
	_press_tween.tween_method(_set_press, 1.0, 0.0, PRESS_UP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_breath() -> void:
	var breathing := has_focus() and is_visible_in_tree() and not Settings.get_reduce_ui_motion()
	if breathing and _breath_tween != null and _breath_tween.is_valid():
		return
	if _breath_tween != null:
		_breath_tween.kill()
		_breath_tween = null
	if not breathing:
		_set_breath(0.0)
		return
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_method(func(t: float) -> void: _set_breath(sin(t) * BREATH_SCALE), 0.0, TAU, BREATH_PERIOD)


func _set_active(value: float) -> void:
	_active = value
	_margin.content_margin_left = text_margin + ACTIVE_SHIFT * value
	_redraw()


func _set_press(value: float) -> void:
	_press = value
	_redraw()


func _set_breath(value: float) -> void:
	_breath = value
	_redraw()


func _set_intro(value: float) -> void:
	_intro = value
	modulate.a = clampf(value * 1.6, 0.0, 1.0)
	_redraw()


func _redraw() -> void:
	if _frame != null:
		_frame.queue_redraw()


## 吊牌外框：畫在按鈕的文字後面（show_behind_parent）。
class _Frame:
	extends Control

	var button: TagButton

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var active := button._active
		var points := button.shape_points()
		var fill := Palette.UI_PANEL_DEEP.lerp(Palette.UI_PANEL_SEL, active)
		var border := Color(button.accent, lerpf(0.35, 1.0, active))
		if button.disabled:
			border.a = 0.18
		CollageShapes.draw_shape(self, points, fill, border, 1.0)
		# 打孔與穿出去的繩子（在切角那一端）、靠右一條撕線（像當票的存根）。
		var tilt := button.current_tilt()
		var hole := (points[6] + points[7]) * 0.5 + (points[1] - points[0]).normalized() * TagButton.HOLE_INSET
		CollageShapes.draw_hole(self, hole, 2.2, Color(button.accent, lerpf(0.4, 0.9, active)), Color(Palette.UI_MUTED, 0.5), tilt)
		var along := (points[1] - points[0]).normalized()
		var down := (points[5] - points[0]).normalized()
		var stub := points[1] - along * 16.0
		var height := (points[5] - points[0]).length()
		var y := 3.0
		while y < height - 3.0:
			draw_line(stub + down * y, stub + down * minf(y + 2.0, height - 3.0), Color(button.accent, 0.25 + 0.3 * active), 1.0)
			y += 4.0
