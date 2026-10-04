class_name SteamVent
extends Node2D
## 地面排氣孔：平時緩慢冒出上升的蒸汽，每隔幾秒噴一陣更猛的蒸汽柱（噴發前孔口先抖一下），被燈光照到時特別有氛圍。

const INTERVAL := 0.12
## 噴發：間隔秒數範圍、持續秒數、噴發時的頻率倍數、噴發前的預兆秒數。
const BURST_EVERY := Vector2(3.5, 6.5)
const BURST_TIME := 0.7
const BURST_RATE := 3.0
const BURST_WARNING := 0.25

var _timer := 0.0
var _burst_in := randf_range(BURST_EVERY.x, BURST_EVERY.y)
var _burst_left := 0.0


func _ready() -> void:
	LightKit.mark_emissive(self)


func _process(delta: float) -> void:
	_burst_in -= delta
	if _burst_in <= 0.0 and _burst_left <= 0.0:
		_burst_left = BURST_TIME
		_burst_in = randf_range(BURST_EVERY.x, BURST_EVERY.y)
	_burst_left = maxf(0.0, _burst_left - delta)
	var bursting := _burst_left > 0.0
	_timer -= delta
	if _timer <= 0.0:
		_timer = INTERVAL * randf_range(0.6, 1.4) / (BURST_RATE if bursting else 1.0)
		var at := global_position + Vector2(randf_range(-6, 6), -2)
		if bursting:
			Fx.steam_jet(at)
		else:
			Fx.steam(at)
	if _burst_in < BURST_WARNING or bursting:
		queue_redraw()


func _draw() -> void:
	# 噴發前後孔口的隔柵抖動。
	var shake := 0.0
	if _burst_in < BURST_WARNING or _burst_left > 0.0:
		shake = sin(Time.get_ticks_msec() * 0.06) * 0.8
	draw_rect(Rect2(-10 + shake, -3, 20, 3), Palette.TERRAIN_EDGE)
	for i in 4:
		draw_line(Vector2(-8 + i * 5 + shake, -3), Vector2(-8 + i * 5 + shake, 0), Color("05070c"), 1.0)
