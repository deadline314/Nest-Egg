class_name UiBanner
extends PanelContainer
## 橫幅：從側邊滑入、停留、滑出。取得物品、檢查點、警告共用。
## 再次呼叫 show_text 會直接接手目前的橫幅，不會堆疊。

enum Kind { INFO, ITEM, WARNING }

const SLIDE := 28.0
const SLIDE_TIME := 0.18

var _label: Label
var _tween: Tween
var _home_x: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiKit.label("", UiKit.FS_BODY, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_label.custom_minimum_size = Vector2(120, 0)
	add_child(_label)
	modulate.a = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS


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
	_home_x = position.x
	position.x = _home_x - SLIDE
	modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:x", _home_x, SLIDE_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_TIME)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(self, "position:x", _home_x + SLIDE, SLIDE_TIME).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, SLIDE_TIME)


func is_showing() -> bool:
	return modulate.a > 0.01


static func _accent(kind: Kind) -> Color:
	match kind:
		Kind.ITEM:
			return Palette.NEON_YELLOW
		Kind.WARNING:
			return Palette.MAGENTA
	return Palette.CYAN
