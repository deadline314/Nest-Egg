class_name CreditsTag
extends Control
## 信用點讀數：黃色晶片圖示 + 數字。增加時數字往上跳動並閃白，花費時閃紅。

const SIZE := Vector2(110, 16)
const COUNT_TIME := 0.45
const FLASH_TIME := 0.25

var _value := 0
var _shown := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "信用點：撿取與擊敗敵人取得，在背包改裝武器"
	set_process(false)


func value() -> int:
	return _value


## delta 為這次的變化量（0 代表只是設定初值）。
func set_credits(value: int, delta: int) -> void:
	_value = value
	if delta > 0 and not Settings.get_reduce_flashes():
		_flash = 1.0
		_flash_color = Color.WHITE
		set_process(true)
	elif delta < 0:
		_shown = float(value)
		_flash = 1.0
		_flash_color = Palette.DANGER
		set_process(true)
	elif delta == 0:
		_shown = float(value)
	queue_redraw()
	if delta > 0:
		set_process(true)


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
