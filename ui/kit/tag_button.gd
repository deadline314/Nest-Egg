class_name TagButton
extends UiButton
## 拼貼版面的主要項目（NE-403、NE-412）：每個項目是一樣這個世界裡的實物，依 style 不同：
## tag＝貨運吊牌（切角、打孔、穿繩、撕線）、ticket＝米白的當票（票根打孔線、條碼、圓戳章，主要動作用）、
## folder＝檔案夾標籤、sticker＝維修貼紙（警示斜紋）、seal＝洋紅的封條膠帶（撕開的兩端，只給離開與危險）。
## tilt_text：整個按鈕連字一起斜（6 度以內，主選單用，按鈕要自己擺位置、不能放在容器裡）；
## 否則只有外框斜、字保持水平（放在容器裡的分頁吊牌用）。
## 選到（焦點或滑鼠）時轉正、放大、浮到最上面；確認時壓下再彈回；選到後待機時很慢地呼吸。
## 開啟畫面時由呼叫端 intro() 依序彈入（帶一點過衝），吊牌可以 swing() 晃一下再停。所有動畫 300 毫秒內完成、不擋輸入，
## 連續操作以最後一次為準；「減少動態」時直接到位。點擊範圍跟著畫面上看到的形狀。
## 靜止時不重畫；呼吸只在選到、看得到、沒有減少動態時才跑，離開畫面就停。

const SELECT_TIME := 0.14
const PRESS_DOWN := 0.06
const PRESS_UP := 0.1
const INTRO_TIME := 0.18
const INTRO_SLIDE := 26.0
const SWING_TIME := 0.28
const SWING_DEGREES := 5.0
const BREATH_PERIOD := 2.8
const BREATH_SCALE := 0.016
## 選到時放大多少、文字往前多少（像素）。
const ACTIVE_SCALE := 0.05
const ACTIVE_SHIFT := 6.0
## 連字一起斜的選項（主選單）選到時放大多少。
const ACTIVE_GROW := 0.12
const PRESS_SCALE := 0.05
const TEXT_MARGIN := 18.0
const NOTCH := 7.0
const HOLE_INSET := 7.0
## 當票紙與印在上面的字（深藍灰配米白，對比遠高於最低標準）。
const PAPER := Color("e9e2ce")
const INK := Color("17202b")
const SEAL := Color("b51f62")
## 選到時亮一點，但白字對比仍在 4.5 以上（純洋紅只有約 3.4）。
const SEAL_ACTIVE := Color("c7246c")
const STUB := 22.0

## 待機時的傾斜（度，6 度以內；正值順時針）。
var tilt_degrees := 3.0:
	set(value):
		tilt_degrees = clampf(value, -6.0, 6.0)
		_apply_pose()
var accent := Palette.CYAN
## 外形：tag、ticket、folder、sticker、seal。
var style: StringName = &"tag":
	set(value):
		style = value
		_apply_style()
## 整個按鈕連字一起斜（主選單）；false 時只有外框斜（分頁）。
var tilt_text := false:
	set(value):
		tilt_text = value
		_apply_pose()
## 後面錯位的大外文字（主要動作用，例如 DEPLOY）。
var ghost_text := ""
## 吊牌從多高的橫桿垂下來（本地座標的 y，負值在按鈕上方）；NAN 代表沒有橫桿。
var rod_y := NAN
## 吊牌往下多垂幾像素（繩長不同）：外形與文字一起往下，按鈕的高度要多留這麼多。
var hang_drop := 0.0:
	set(value):
		hang_drop = value
		_margin.content_margin_top = 5.0 + value
		_redraw()
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
var _swing := 0.0
var _frame: _Frame
var _margin := StyleBoxEmpty.new()
var _active_tween: Tween
var _press_tween: Tween
var _breath_tween: Tween
var _intro_tween: Tween
var _swing_tween: Tween


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
	resized.connect(_apply_pose)


## 選到的程度（0 = 傾斜待機，1 = 轉正往前）。測試與截圖用。
func active_amount() -> float:
	return _active


## 現在畫面上的傾斜（弧度，含晃動）。
func current_tilt() -> float:
	return deg_to_rad(tilt_degrees) * (1.0 - _active) + deg_to_rad(_swing)


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


## 吊牌被掛上去時晃一下再停（有阻尼，SWING_TIME 內停住）。「減少動態」時不晃。
func swing(delay: float, strength := 1.0) -> void:
	if _swing_tween != null:
		_swing_tween.kill()
	_set_swing(0.0)
	if Settings.get_reduce_ui_motion() or not is_inside_tree():
		return
	var peak := SWING_DEGREES * strength
	_swing_tween = create_tween()
	_swing_tween.tween_method(func(t: float) -> void: _set_swing(peak * exp(-5.0 * t) * sin(t * TAU * 1.6)), 0.0, 1.0, SWING_TIME).set_delay(delay)
	_swing_tween.tween_callback(_set_swing.bind(0.0))


## 畫面上的外形（本地座標），繪製與點擊判斷共用。
func shape_points() -> PackedVector2Array:
	var body := _body_rect()
	var points := _style_polygon(body)
	if tilt_text:
		return points
	var center := body.get_center()
	var scale_factor := 1.0 + ACTIVE_SCALE * _active - PRESS_SCALE * _press + _breath
	var transform := Transform2D(current_tilt(), center) * Transform2D(0.0, Vector2(scale_factor, scale_factor), 0.0, Vector2.ZERO) * Transform2D(0.0, -center)
	for i in points.size():
		points[i] = transform * points[i]
	return points


func _body_rect() -> Rect2:
	var body := Rect2(Vector2(2.0, 2.0 + hang_drop), size - Vector2(4.0, 4.0 + hang_drop))
	if not tilt_text:
		body.position.x += -INTRO_SLIDE * (1.0 - _intro) + ACTIVE_SHIFT * 0.5 * _active
	return body


func _style_polygon(body: Rect2) -> PackedVector2Array:
	match style:
		&"ticket":
			return CollageShapes.tag_polygon(body, 10.0)
		&"folder":
			# 檔案夾：右上角多一片標籤。
			var tab := minf(46.0, body.size.x * 0.4)
			return PackedVector2Array([Vector2(body.position.x, body.position.y + 6.0), Vector2(body.end.x - tab - 6.0, body.position.y + 6.0),
				Vector2(body.end.x - tab, body.position.y), Vector2(body.end.x - 4.0, body.position.y), Vector2(body.end.x, body.position.y + 4.0),
				Vector2(body.end.x, body.end.y), Vector2(body.position.x + 3.0, body.end.y), Vector2(body.position.x, body.end.y - 3.0)])
		&"sticker":
			return _rounded(body, 6.0)
		&"seal":
			# 封條膠帶：兩端是撕開的鋸齒。
			var points := PackedVector2Array()
			var teeth := 4
			for i in teeth + 1:
				points.append(Vector2(body.position.x + (3.0 if i % 2 == 0 else 0.0), body.position.y + body.size.y * float(i) / teeth))
			for i in teeth + 1:
				points.append(Vector2(body.end.x - (3.0 if i % 2 == 0 else 0.0), body.end.y - body.size.y * float(i) / teeth))
			return points
		_:
			return CollageShapes.tag_polygon(body, NOTCH)


static func _rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [rect.position + Vector2(radius, radius), Vector2(rect.end.x - radius, rect.position.y + radius), rect.end - Vector2(radius, radius), Vector2(rect.position.x + radius, rect.end.y - radius)]
	for c in 4:
		for k in 4:
			var angle := PI + PI * 0.5 * (c + float(k) / 3.0)
			points.append(corners[c] + Vector2.from_angle(angle) * radius)
	return points


func _has_point(point: Vector2) -> bool:
	return CollageShapes.contains(shape_points(), point)


func _draw() -> void:
	pass  # 外形由 _Frame 畫在文字後面；不畫 UiButton 的方形閃光。


func _apply_style() -> void:
	match style:
		&"ticket":
			for state in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color", &"font_hover_pressed_color"]:
				add_theme_color_override(state, INK)
		&"seal":
			for state in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color", &"font_hover_pressed_color"]:
				add_theme_color_override(state, Color.WHITE)
	_redraw()


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
	_margin.content_margin_left = text_margin + (0.0 if tilt_text else ACTIVE_SHIFT * value)
	_apply_pose()


func _set_press(value: float) -> void:
	_press = value
	_apply_pose()


func _set_breath(value: float) -> void:
	_breath = value
	_apply_pose()


func _set_intro(value: float) -> void:
	_intro = value
	modulate.a = clampf(value * 1.6, 0.0, 1.0)
	_apply_pose()


func _set_swing(value: float) -> void:
	_swing = value
	_apply_pose()


## 連字一起斜的按鈕：轉動、縮放與上下層由按鈕本身處理（以中心為軸）；只有外框斜的由外框自己畫。
func _apply_pose() -> void:
	if tilt_text:
		pivot_offset = size * 0.5
		rotation = current_tilt()
		var scale_factor := 1.0 + ACTIVE_GROW * _active - PRESS_SCALE * _press + _breath
		scale = Vector2(scale_factor, scale_factor)
		position.x = _home.x - INTRO_SLIDE * (1.0 - _intro)
		# 選到的浮到最上面（只改畫的先後，焦點順序不變）。
		z_index = 2 if _active > 0.5 else 0
	_redraw()


## 連字一起斜的按鈕自己擺位置：home 是待機時的左上角。
var _home := Vector2.ZERO


func place(home: Vector2) -> void:
	_home = home
	position = home
	_apply_pose()


func _redraw() -> void:
	if _frame != null:
		_frame.queue_redraw()


## 外形：畫在按鈕的文字後面（show_behind_parent）。投影、形狀、各 style 的細節。
class _Frame:
	extends Control

	var button: TagButton

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var active := button._active
		var points := button.shape_points()
		if not is_nan(button.rod_y):
			# 從橫桿垂下來的繩子（到打孔處）。
			var hole := (points[6] + points[7]) * 0.5 + (points[1] - points[0]).normalized() * TagButton.HOLE_INSET
			draw_line(Vector2(hole.x, button.rod_y), hole, Color(Palette.UI_MUTED, 0.7), 1.0)
		if button.tilt_text:
			var shadow := points.duplicate()
			var offset := Vector2(3.0, 4.0) * (1.0 + active)
			for i in shadow.size():
				shadow[i] += offset
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
		match button.style:
			&"ticket":
				_ticket(points, active)
			&"folder":
				CollageShapes.draw_shape(self, points, Color("1c3340").lerp(Color("25546a"), active), Color(button.accent, lerpf(0.4, 1.0, active)), 1.0)
			&"sticker":
				_sticker(points, active)
			&"seal":
				_seal(points, active)
			_:
				_tag(points, active)

	func _tag(points: PackedVector2Array, active: float) -> void:
		var fill := Palette.UI_PANEL_DEEP.lerp(Palette.UI_PANEL_SEL, active)
		var border := Color(button.accent, lerpf(0.35, 1.0, active))
		if button.disabled:
			border.a = 0.18
		CollageShapes.draw_shape(self, points, fill, border, 1.0)
		var tilt := button.current_tilt()
		var hole := (points[6] + points[7]) * 0.5 + (points[1] - points[0]).normalized() * TagButton.HOLE_INSET
		CollageShapes.draw_hole(self, hole, 2.2, Color(button.accent, lerpf(0.4, 0.9, active)), Color(Palette.UI_MUTED, 0.5) if is_nan(button.rod_y) else Color(0, 0, 0, 0), tilt)
		var along := (points[1] - points[0]).normalized()
		var down := (points[5] - points[0]).normalized()
		var stub := points[1] - along * 16.0
		var height := (points[5] - points[0]).length()
		var y := 3.0
		while y < height - 3.0:
			draw_line(stub + down * y, stub + down * minf(y + 2.0, height - 3.0), Color(button.accent, 0.25 + 0.3 * active), 1.0)
			y += 4.0

	func _ticket(points: PackedVector2Array, active: float) -> void:
		var body := button._body_rect()
		var font := UiKit.font()
		if not button.ghost_text.is_empty():
			# 後面錯位的大外文字：從當票右下方伸出來，左半被當票壓住。
			draw_string(font, Vector2(body.end.x - body.size.x * 0.3, body.end.y + 8.0), button.ghost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.scaled_size(30), Color(Palette.CYAN, 0.28))
		CollageShapes.draw_shape(self, points, TagButton.PAPER.lerp(Color("fbf6e8"), active), Color(TagButton.INK, 0.5), 1.0)
		# 票根：左邊一段，打孔線與打孔。
		var stub_x := body.position.x + TagButton.STUB
		var y := body.position.y + 3.0
		while y < body.end.y - 3.0:
			draw_line(Vector2(stub_x, y), Vector2(stub_x, minf(y + 2.5, body.end.y - 3.0)), Color(TagButton.INK, 0.45), 1.0)
			y += 5.0
		CollageShapes.draw_hole(self, Vector2(body.position.x + 12.0, body.get_center().y), 3.0, Color(TagButton.INK, 0.6), Color(0, 0, 0, 0), 0.0)
		# 右下角的條碼與半色調。
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(button.text)
		var x := body.end.x - 48.0
		while x < body.end.x - 8.0:
			var width := 1.0 if rng.randf() < 0.6 else 2.0
			draw_rect(Rect2(x, body.end.y - 14.0, width, 9.0), Color(TagButton.INK, 0.75))
			x += width + rng.randf_range(1.0, 2.5)
		CollageShapes.draw_halftone(self, Rect2(stub_x + 4.0, body.end.y - 12.0, 40.0, 10.0), Color(TagButton.INK, 0.12), 4.0, 1.4)
		# 右上角蓋出邊的圓戳章。
		var stamp := Vector2(body.end.x - 14.0, body.position.y + 4.0)
		draw_arc(stamp, 11.0, 0.0, TAU, 20, Color(Palette.CYAN, 0.85), 1.5)
		draw_arc(stamp, 7.5, 0.0, TAU, 16, Color(Palette.CYAN, 0.6), 1.0)

	func _sticker(points: PackedVector2Array, active: float) -> void:
		var body := button._body_rect()
		CollageShapes.draw_shape(self, points, Color("26313d").lerp(Color("2f4a58"), active), Color(button.accent, lerpf(0.35, 0.95, active)), 1.0)
		# 左端警示斜紋（青與深色），兩顆鉚釘。
		var band := Rect2(body.position.x + 4.0, body.position.y + 4.0, 12.0, body.size.y - 8.0)
		var x := band.position.x - band.size.y
		while x < band.end.x:
			var stripe := PackedVector2Array([Vector2(x, band.end.y), Vector2(x + 3.0, band.end.y), Vector2(x + 3.0 + band.size.y, band.position.y), Vector2(x + band.size.y, band.position.y)])
			var clipped := Geometry2D.intersect_polygons(stripe, PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]))
			for piece in clipped:
				draw_colored_polygon(piece, Color(button.accent, 0.7))
			x += 6.0
		draw_circle(Vector2(body.end.x - 6.0, body.position.y + 6.0), 1.5, Color(Palette.UI_MUTED, 0.8))
		draw_circle(Vector2(body.end.x - 6.0, body.end.y - 6.0), 1.5, Color(Palette.UI_MUTED, 0.8))

	func _seal(points: PackedVector2Array, active: float) -> void:
		var body := button._body_rect()
		CollageShapes.draw_shape(self, points, TagButton.SEAL.lerp(TagButton.SEAL_ACTIVE, active), Color(0, 0, 0, 0), 1.0)
		# 膠帶上的淡斜紋。
		var x := body.position.x
		while x < body.end.x:
			draw_line(Vector2(x, body.end.y - 1.0), Vector2(x + body.size.y * 0.6, body.position.y + 1.0), Color(1, 1, 1, 0.12), 2.0)
			x += 9.0
