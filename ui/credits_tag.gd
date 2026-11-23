class_name CreditsTag
extends Control
## 信用點讀數：黃色晶片圖示與餘額；動態提示受顯示設定控制。

const SIZE := Vector2(110, 16)
const COUNT_TIME := 0.45
const FLASH_TIME := 0.25
const DEFAULT_HELP := "撿拾或擊敗敵人取得信用點，用來改裝武器。"
const HELP: Dictionary[String, String] = {
	"ja": "拾うか敵を倒してクレジットを獲得し、武器を改造できます。",
	"en": "Collect or earn credits from enemies to upgrade weapons.",
}


var _value := 0
var _shown := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = DEFAULT_HELP
	set_process(false)


func _ready() -> void:
	Settings.display_changed.connect(_sync_display)


func _get_tooltip(_at_position: Vector2) -> String:
	if tooltip_text != DEFAULT_HELP:
		return tooltip_text
	return StoryLocale.optional_text(HELP, Story.language, DEFAULT_HELP)


func value() -> int:
	return _value


## delta 為這次的變化量（0 代表只是設定初值）。
func set_credits(value: int, delta: int) -> void:
	_value = value
	if delta <= 0:
		_shown = float(value)
	if delta != 0:
		_flash = 1.0
		_flash_color = Color.WHITE if delta > 0 else Palette.DANGER
	_sync_display()


func _sync_display() -> void:
	var reduced_motion := Settings.get_reduce_ui_motion()
	if reduced_motion:
		_shown = float(_value)
	if reduced_motion or Settings.get_reduce_flashes():
		_flash = 0.0
	set_process(_flash > 0.0 or _shown < float(_value))
	queue_redraw()


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	if _shown < float(_value):
		_shown = minf(float(_value), _shown + maxf(1.0, float(_value) - _shown) * delta / COUNT_TIME * 2.0)
	if _flash <= 0.0 and is_equal_approx(_shown, float(_value)):
		_shown = float(_value)
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var font := UiKit.font()
	var text := "%d" % roundi(_shown)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY).x
	var color := Palette.NEON_YELLOW.lerp(_flash_color, _flash)
	draw_string(font, Vector2(SIZE.x - text_width, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FS_BODY, color)
	# 晶片圖示：切角的小方塊，中間一個點。
	var origin := Vector2(SIZE.x - text_width - 16.0, 2.0)
	var box := ChamferBox.make(Color(Palette.NEON_YELLOW, 0.25), Palette.NEON_YELLOW, 2)
	box.draw(get_canvas_item(), Rect2(origin, Vector2(11, 11)))
	draw_rect(Rect2(origin + Vector2(4, 4), Vector2(3, 3)), Palette.NEON_YELLOW)
