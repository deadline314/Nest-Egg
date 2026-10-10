class_name FocusHintBar
extends PanelContainer
## 聚焦說明列：鍵盤或手把移動焦點時，把該控制項的 tooltip 顯示在畫面底部，說明不再只靠滑鼠 Hover。
## 只回應 scope 底下的控制項；滑鼠移動時收起（滑鼠已有原生 tooltip），焦點離開或 scope 隱藏時跟著消失。
## 用法：`FocusHintBar.attach(root)`；版面底部有東西時改用 `BOTTOM_RIGHT`、`BELOW`（貼在指定面板下方）
## 或 `INLINE`（放進指定的排版容器，例如按鈕列旁邊，由容器決定位置）。
## 整個視窗只連一次焦點訊號，按鈕動態增減也不用逐一接線。

enum Placement { BOTTOM_CENTER, BOTTOM_RIGHT, BELOW, INLINE }

const MARGIN := 6.0

var placement := Placement.BOTTOM_CENTER
var _scope: Control
var _anchor: Control
var _label: Label
var _focused: WeakRef


static func attach(scope: Control, where := Placement.BOTTOM_CENTER, anchor: Control = null) -> FocusHintBar:
	var bar := FocusHintBar.new()
	bar._scope = scope
	bar.placement = where
	bar._anchor = anchor
	if (where == Placement.BELOW or where == Placement.INLINE) and anchor == null:
		push_error("[FocusHintBar] %s：BELOW／INLINE 需要指定面板或容器，改放底部置中" % scope.name)
		bar.placement = Placement.BOTTOM_CENTER
	if bar.placement == Placement.INLINE:
		# 放在按鈕旁時不加框，避免看起來像另一顆按鈕。
		bar.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		bar._label.theme_type_variation = &""
		bar._label.add_theme_color_override(&"font_color", Palette.UI_MUTED)
		anchor.add_child(bar)
	else:
		scope.add_child(bar)
	return bar


func _init() -> void:
	name = &"FocusHintBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"TooltipPanel"
	_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label.theme_type_variation = &"TooltipLabel"
	add_child(_label)
	hide()


func _ready() -> void:
	if _scope == null:
		_scope = get_parent() as Control
	if _scope == null:
		push_error("[FocusHintBar] %s：沒有可守護的 Control，說明列停用" % get_path())
		set_process_input(false)
		return
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_scope.visibility_changed.connect(_refresh)
	if is_instance_valid(_anchor) and placement == Placement.BELOW:
		# 面板滑入或改版面時跟著移動；只在面板實際移動時觸發，不每影格計算。
		_anchor.item_rect_changed.connect(func() -> void:
			if visible:
				_place())


## 目前顯示的說明（測試與除錯用；沒顯示時是空字串）。
func text() -> String:
	return _label.text if visible else ""


func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseMotion:
		hide()


func _on_focus_changed(control: Control) -> void:
	_focused = weakref(control) if control != null else null
	_refresh()


func _refresh() -> void:
	var control: Control = _focused.get_ref() as Control if _focused != null else null
	var tip := ""
	if is_instance_valid(control) and control.is_visible_in_tree() and _scope.is_visible_in_tree() and _scope.is_ancestor_of(control):
		tip = control.tooltip_text.strip_edges()
	_label.text = tip
	visible = not tip.is_empty()
	if visible:
		# 文字長短不同：依內容重算大小後再放到指定位置，並夾在畫面內。
		reset_size()
		if placement != Placement.INLINE:
			_place()


func _place() -> void:
	var area := get_parent_area_size()
	var target := Vector2((area.x - size.x) * 0.5, area.y - size.y - MARGIN)
	if placement == Placement.BOTTOM_RIGHT:
		target.x = area.x - size.x - MARGIN
	elif placement == Placement.BELOW and is_instance_valid(_anchor):
		var rect := _anchor.get_global_rect()
		var origin := (get_parent() as Control).get_global_rect().position if get_parent() is Control else Vector2.ZERO
		target = Vector2(rect.position.x, rect.end.y + MARGIN) - origin
	position = Vector2(clampf(target.x, 0.0, maxf(0.0, area.x - size.x)), clampf(target.y, 0.0, maxf(0.0, area.y - size.y)))
