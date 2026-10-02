class_name ForegroundLayer
extends Parallax2D
## 前景剪影：比可玩區域更靠近鏡頭的暗色管線、鋼樑與欄杆，加上快速飄過的雨簾。
## 只畫在畫面邊緣（頂端與地面以下），壓住邊角、增加縱深，不遮住可玩區域與敵人。
## 靜態部分只繪製一次；雨簾每影格重繪。品質低（沒有體積效果）時整層隱藏。

const REPEAT_WIDTH := 1500.0
const SCROLL_SCALE := 1.45
const SILHOUETTE := Color(0.012, 0.016, 0.03, 0.97)
const RIM := Color(0.2, 0.4, 0.5, 0.25)
## 世界座標：頂端管線的高度範圍，與地面（街道上緣）之下的欄杆範圍。
const TOP_Y := 0.0
const PIPE_THICKNESS := 14.0

## 街道地面上緣的世界 y 座標，由關卡設定（欄杆畫在它下方，不蓋住角色腳下）。
var ground_y := 320.0

var _static: _Static
var _curtain: _Curtain


func _ready() -> void:
	scroll_scale = Vector2(SCROLL_SCALE, 1.0)
	repeat_size = Vector2(REPEAT_WIDTH, 0)
	z_index = 15
	_static = _Static.new()
	_static.ground_y = ground_y
	add_child(_static)
	_curtain = _Curtain.new()
	add_child(_curtain)
	Settings.display_changed.connect(_refresh_visibility)
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = LightQuality.volumetrics()


## 靜態剪影：頂端的橫管與吊纜、地面下的欄杆柱。
class _Static:
	extends Node2D

	var ground_y := 320.0

	func _ready() -> void:
		LightKit.mark_emissive(self)

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		# 頂端：兩條粗細不同的橫管，每隔一段有固定座。
		for row in 2:
			var y := TOP_Y - 4.0 + row * 13.0
			var thickness := PIPE_THICKNESS - row * 5.0
			draw_rect(Rect2(0, y, REPEAT_WIDTH, thickness), SILHOUETTE)
			draw_line(Vector2(0, y + thickness), Vector2(REPEAT_WIDTH, y + thickness), RIM, 1.0)
			var x := rng.randf_range(40.0, 160.0)
			while x < REPEAT_WIDTH:
				draw_rect(Rect2(x - 4.0, y - 2.0, 8.0, thickness + 5.0), SILHOUETTE)
				x += rng.randf_range(140.0, 260.0)
		# 吊纜：從橫管垂下的弧線。
		for i in 7:
			var x := rng.randf_range(20.0, REPEAT_WIDTH - 20.0)
			var drop := rng.randf_range(18.0, 46.0)
			var points := PackedVector2Array()
			for k in 9:
				var t := float(k) / 8.0
				points.append(Vector2(x + sin(t * PI) * rng.randf_range(-6.0, 6.0), TOP_Y + 10.0 + drop * t))
			draw_polyline(points, SILHOUETTE, 2.0)
		# 地面之下：欄杆柱與橫桿，只在街道上緣以下。
		var post := 30.0
		while post < REPEAT_WIDTH:
			var height := rng.randf_range(18.0, 36.0)
			draw_rect(Rect2(post, ground_y + 14.0, 5.0, height + 60.0), SILHOUETTE)
			draw_line(Vector2(post, ground_y + 14.0), Vector2(post + 5.0, ground_y + 14.0), RIM, 1.0)
			post += rng.randf_range(90.0, 190.0)
		draw_rect(Rect2(0, ground_y + 30.0, REPEAT_WIDTH, 3.0), SILHOUETTE)


## 雨簾：比雨更近、更長、更快、極淡的斜線，只在畫面上方三分之二。
class _Curtain:
	extends Node2D

	const STREAKS := 16
	const SPEED := 1300.0
	const LENGTH := 90.0

	var _time := 0.0

	func _ready() -> void:
		LightKit.mark_emissive(self)

	func _process(delta: float) -> void:
		_time += delta
		if get_parent().visible:
			queue_redraw()

	func _draw() -> void:
		var tile_w := REPEAT_WIDTH
		for i in STREAKS:
			var x := fposmod(float(i) * 97.0 + float(i * i) * 13.0, tile_w)
			var y := fposmod(float(i) * 61.0 + _time * SPEED * (0.8 + float(i % 3) * 0.15), 420.0) - 40.0
			draw_line(Vector2(x, y), Vector2(x - 12.0, y + LENGTH), Color(Palette.RAIN, 0.07), 2.0)
