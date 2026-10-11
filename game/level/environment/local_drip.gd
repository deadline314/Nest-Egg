class_name LocalDrip
extends Node2D
## 滴水：一顆水滴從出水口落到承接面，越落越快，碰到水面時濺開一圈小水花，然後等下一滴。
## 自己累計時間（暫停時停住、離開畫面不更新），沒有粒子、沒有每影格配置；由擺設（PropNode）擁有。

## 水滴落下與水花散開各花多久（秒）。
const FALL_TIME := 0.38
const SPLASH_TIME := 0.32
## 水花往兩側散開多遠、往上跳多高（世界像素）。
const SPLASH_REACH := 3.5
const SPLASH_HOP := 2.0
const DROP_COLOR := Color(0.66, 0.9, 1.0, 0.9)

var clock := 0.0
var on_screen := false

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _period := 1.6
var _idle_drawn := false


## data 的 drip_from／drip_to 是貼圖的 0～1 座標；flip 為真時左右鏡像，和擺設本體一致。
func setup(data: PropData, flip: bool) -> void:
	_from = data.drip_from * data.size
	_to = data.drip_to * data.size
	if flip:
		_from.x = data.size.x - _from.x
		_to.x = data.size.x - _to.x
	_period = data.drip_period
	clock = randf() * _period
	LightKit.mark_emissive(self)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(Vector2.ZERO, data.size)
	notifier.screen_entered.connect(func() -> void: on_screen = true)
	notifier.screen_exited.connect(func() -> void: on_screen = false)
	add_child(notifier)


## 目前這一滴進行到哪裡：&"fall"、&"splash" 或 &"wait"（測試與量測用）。
func stage() -> StringName:
	if clock < FALL_TIME:
		return &"fall"
	return &"splash" if clock < FALL_TIME + SPLASH_TIME else &"wait"


## 水滴目前的位置（擺設的本地座標）；不在落下階段時回傳承接面的位置。
func drop_position() -> Vector2:
	if clock >= FALL_TIME:
		return _to
	var t := clock / FALL_TIME
	return _from.lerp(_to, t * t)


func _process(delta: float) -> void:
	if not on_screen:
		return
	clock = fmod(clock + delta, _period)
	# 等下一滴的期間畫面是空的，只需要清一次。
	var waiting := stage() == &"wait"
	if not waiting or not _idle_drawn:
		_idle_drawn = waiting
		queue_redraw()


func _draw() -> void:
	match stage():
		&"fall":
			var t := clock / FALL_TIME
			var at := drop_position()
			draw_rect(Rect2(at.x - 0.5, at.y - 1.5 - t, 1.0, 2.0 + t), DROP_COLOR)
		&"splash":
			var t := (clock - FALL_TIME) / SPLASH_TIME
			var color := Color(DROP_COLOR, DROP_COLOR.a * (1.0 - t))
			var reach := 1.0 + SPLASH_REACH * t
			var hop := SPLASH_HOP * sin(t * PI)
			draw_rect(Rect2(_to.x - reach - 0.5, _to.y - hop - 0.5, 1.0, 1.0), color)
			draw_rect(Rect2(_to.x + reach - 0.5, _to.y - hop - 0.5, 1.0, 1.0), color)
			draw_rect(Rect2(_to.x - reach, _to.y, reach * 2.0, 0.6), Color(color, color.a * 0.5))
