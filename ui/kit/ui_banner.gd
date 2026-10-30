class_name UiBanner
extends PanelContainer
## 橫幅：從側邊滑入、停留、滑出。取得物品、檢查點、警告共用。
## 再次呼叫 show_text 會直接接手目前的橫幅，不會堆疊。

enum Kind { INFO, ITEM, WARNING }

const SLIDE := 28.0
const SLIDE_TIME := 0.18

## >= 0 時，橫幅水平置中於這個 x 座標（HUD 把它設在畫面中央）。
var center_x := -1.0

var _label: Label
var _tween: Tween
var _home_x: float = 0.0
var _travel := SLIDE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label.custom_minimum_size = Vector2(120, 0)
	add_child(_label)
	modulate.a = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	PromptLayout.add_obstacle(self, prompt_obstacle_rect)


## Reserve the complete horizontal animation envelope, including its first fade-in frame.
func prompt_obstacle_rect() -> Rect2:
	var moving := _tween != null and _tween.is_valid() and _tween.is_running()
	if not is_visible_in_tree() or (modulate.a <= 0.01 and not moving):
		return Rect2()
	var rect := Rect2(Vector2.ZERO, size)
	if moving:
		rect.position.x = _home_x - _travel - position.x
		rect.size.x += _travel * 2.0
	return (get_viewport().get_canvas_transform().affine_inverse() * get_global_transform_with_canvas()) * rect


func show_text(text: String, kind: Kind = Kind.INFO, hold: float = 2.0) -> void:
	var accent := _accent(kind)
	var box := ChamferBox.make(Color(0.03, 0.06, 0.09, 0.92), accent, 4)
	box.bracket = accent
	box.scanlines = 0.1
	box.margins(14, 4, 14, 4)
	add_theme_stylebox_override(&"panel", box)
	_label.text = text
	_label.add_theme_color_override(&"font_color", Palette.UI_TEXT if kind == Kind.INFO else accent)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		return
	reset_size()
	if center_x >= 0.0:
		position.x = roundf(center_x - size.x * 0.5)
	_home_x = position.x
	_travel = 0.0 if Settings.get_reduce_ui_motion() else SLIDE
	position.x = _home_x - _travel
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:x", _home_x, SLIDE_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_TIME)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(self, "position:x", _home_x + _travel, SLIDE_TIME).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, SLIDE_TIME)
	PromptLayout.invalidate()


## Exact ownership guard: a delayed withdrawal cannot hide a newer message.
func dismiss_text(expected_text: String) -> bool:
	if expected_text.is_empty() or _label.text != expected_text:
		return false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_label.text = ""
	position.x = _home_x
	modulate.a = 0.0
	PromptLayout.invalidate()
	return true


func is_showing() -> bool:
	return modulate.a > 0.01


static func _accent(kind: Kind) -> Color:
	match kind:
		Kind.ITEM:
			return Palette.NEON_YELLOW
		Kind.WARNING:
			return Palette.MAGENTA
	return Palette.CYAN
