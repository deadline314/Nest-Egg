class_name UiButton
extends Button
## 共用按鈕：切角外框（來自主題）+ 選取時向右滑出的小三角 + 確認時閃一下。
## 選取與確認的音效由這個類別負責，呼叫端不需要另外接。

const MARKER_SLIDE := 5.0
const MARKER_TIME := 0.12
const FLASH_TIME := 0.16

## 小按鈕與分頁的左右留白不夠放三角，關掉後焦點改由外框表示（見 FlatStyle）。
var show_marker := true
var _marker: float = 0.0
var _flash: float = 0.0
var _marker_tween: Tween
var _flash_tween: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(180, 0)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_selected)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_update_marker)
	focus_exited.connect(_update_marker)


func _on_pressed() -> void:
	Sfx.play(&"ui_confirm", -6.0, 0.0)
	if Settings.get_reduce_flashes() or Settings.get_reduce_ui_motion():
		return
	_tween_property(&"_flash", 1.0, 0.0, FLASH_TIME, true)


func _on_selected() -> void:
	Sfx.play(&"ui_move", -14.0, 0.0)
	_update_marker()


func _on_hover() -> void:
	if not disabled and not has_focus():
		Sfx.play(&"ui_move", -18.0, 0.0)
	_update_marker()


func _update_marker() -> void:
	var active := (has_focus() or is_hovered()) and not disabled
	_tween_property(&"_marker", _marker, 1.0 if active else 0.0, MARKER_TIME, false)


func _tween_property(prop: StringName, from: float, to: float, time: float, is_flash: bool) -> void:
	if not is_inside_tree():
		set(prop, to)
		return
	var old: Tween = _flash_tween if is_flash else _marker_tween
	if old != null and old.is_valid():
		old.kill()
	if Settings.get_reduce_ui_motion():
		set(prop, to)
		queue_redraw()
		return
	set(prop, from)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		set(prop, v)
		queue_redraw(), from, to, time)
	if is_flash:
		_flash_tween = tween
	else:
		_marker_tween = tween


func _draw() -> void:
	if disabled:
		return
	if show_marker and _marker > 0.01:
		var x := 4.0 + _marker * MARKER_SLIDE
		var cy := size.y * 0.5
		var color := Color(Palette.CYAN, _marker)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, cy - 3.0), Vector2(x + 3.0, cy), Vector2(x, cy + 3.0)]), color)
	if _flash > 0.01:
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(1, 1, 1, 0.35 * _flash))
