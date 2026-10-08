class_name ShockRing
extends Sprite2D
## 衝擊波：一個方形，用 shader 在環上折射畫面並加一圈亮邊（art/shaders/shock_ring.gdshader）。由 Fx 的環池循環使用。
## play(位置, 半徑, 力道, 顏色, 時間) 之後自己擴張、淡出、隱藏。

const SHADER := preload("res://art/shaders/shock_ring.gdshader")

static var _surface: ImageTexture

var _tween: Tween
var _mat: ShaderMaterial


func _ready() -> void:
	# PlaceholderTexture2D produces partial UVs in Forward+; keep one real surface for every pooled ring.
	if _surface == null:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_surface = ImageTexture.create_from_image(image)
	texture = _surface
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	light_mask = 0
	visible = false
	z_index = 7


func play(at: Vector2, radius: float, strength: float, color: Color, time := 0.5) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	global_position = at
	scale = Vector2.ONE * radius
	visible = true
	_mat.set_shader_parameter("tint", color)
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("progress", 0.0)
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("progress", v), 0.0, 1.0, time)
	_tween.tween_callback(func() -> void: visible = false)
