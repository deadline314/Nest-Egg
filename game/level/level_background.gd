class_name LevelBackground
extends Node2D
## 多層視差背景（程式產生廢墟設施剪影），使用 Godot 4 的 Parallax2D。
## 每層以固定亂數種子產生，畫面穩定且不需貼圖；不受場景光源影響（light_mask = 0）。

const PATTERN_WIDTH := 1280.0
const BACKGROUND_Z := -100


func _ready() -> void:
	z_as_relative = false
	z_index = BACKGROUND_Z
	_add_layer(0.0, _SkyLayer.new())
	_add_layer(0.15, _SilhouetteLayer.new(11, Palette.BG_MID, 140.0, 260.0, 40.0, 0.0))
	_add_layer(0.35, _SilhouetteLayer.new(23, Palette.BG_NEAR, 70.0, 180.0, 30.0, 0.6))


func _add_layer(scale_factor: float, drawer: Node2D) -> void:
	var parallax := Parallax2D.new()
	parallax.scroll_scale = Vector2(scale_factor, scale_factor * 0.5)
	if scale_factor > 0.0:
		parallax.repeat_size = Vector2(PATTERN_WIDTH, 0)
	drawer.light_mask = 0
	parallax.add_child(drawer)
	add_child(parallax)


class _SkyLayer:
	extends Node2D

	func _draw() -> void:
		var steps := 12
		for i in steps:
			var t := float(i) / steps
			draw_rect(Rect2(-200, -200 + i * 50.0, 1100, 52), Palette.BG_FAR.lerp(Color("142333"), t))
		# 遠方的青色光柱（培育設施的核心）
		draw_rect(Rect2(420, -200, 18, 700), Color(Palette.CYAN, 0.05))
		draw_rect(Rect2(426, -200, 6, 700), Color(Palette.CYAN, 0.08))


class _SilhouetteLayer:
	extends Node2D

	var _seed: int
	var _color: Color
	var _min_height: float
	var _max_height: float
	var _min_width: float
	var _window_chance: float

	func _init(p_seed: int, p_color: Color, min_height: float, max_height: float, min_width: float, window_chance: float) -> void:
		_seed = p_seed
		_color = p_color
		_min_height = min_height
		_max_height = max_height
		_min_width = min_width
		_window_chance = window_chance

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		var x := 0.0
		var ground := 380.0
		while x < LevelBackground.PATTERN_WIDTH:
			var w := rng.randf_range(_min_width, _min_width * 2.5)
			var h := rng.randf_range(_min_height, _max_height)
			draw_rect(Rect2(x, ground - h, w - 4.0, h + 200.0), _color)
			# 斷裂的管線與塔頂
			if rng.randf() < 0.4:
				draw_line(Vector2(x + w * 0.5, ground - h), Vector2(x + w * 0.5, ground - h - rng.randf_range(10, 40)), _color, 3.0)
			if rng.randf() < _window_chance:
				var wy := ground - h + 10.0
				while wy < ground - 10.0:
					if rng.randf() < 0.3:
						draw_rect(Rect2(x + 6, wy, 4, 3), Color(Palette.CYAN, 0.25))
					wy += 14.0
			x += w
