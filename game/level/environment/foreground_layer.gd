class_name ForegroundLayer
extends Parallax2D
## 前景剪影：比可玩區域更靠近鏡頭的暗色管線、鋼樑與欄杆，加上快速飄過的雨簾。
## 只畫在畫面邊緣（頂端與地面以下），壓住邊角、增加縱深，不遮住可玩區域與敵人。
## 剪影是免費素材流程生成的貼圖條（art/environment/backdrop/fg_top／fg_bottom，近乎全黑、邊緣一圈冷色輪廓光），
## 左右鏡像拼成可重複的一段；上緣的纜線會擺動，LED 小燈會明滅（自發光層）。貼圖缺失時退回程式繪製的剪影並記錄路徑。
## 靜態部分只繪製一次；雨簾每影格重繪。品質低（沒有體積效果）時整層隱藏。

const REPEAT_WIDTH := 1500.0
const SCROLL_SCALE := 1.45
const SILHOUETTE := Color(0.012, 0.016, 0.03, 0.97)
const RIM := Color(0.2, 0.4, 0.5, 0.25)
## 世界座標：頂端管線的高度範圍，與地面（街道上緣）之下的欄杆範圍。
const TOP_Y := 0.0
const PIPE_THICKNESS := 14.0
const TOP_TEXTURE := "res://art/environment/backdrop/fg_top.webp"
const BOTTOM_TEXTURE := "res://art/environment/backdrop/fg_bottom.webp"
## 貼圖條在遊戲裡的高度（邏輯像素）：寬度固定為半段（REPEAT_WIDTH / 2），高度依貼圖比例。
const SWAY_AMPLITUDE := 2.2

## 街道地面上緣的世界 y 座標，由關卡設定（欄杆畫在它下方，不蓋住角色腳下）。
var ground_y := 320.0
## 這一關有沒有下雨；沒有就不畫雨簾。
var rain := true
## 每一欄頭上有沒有屋頂（1＝有）與格子大小，由關卡設定：鏡頭在屋頂下時不畫雨簾。
var covered_columns := PackedByteArray()
var tile_size := 16

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


func _process(_delta: float) -> void:
	_curtain.visible = rain and not _camera_under_roof()


func _camera_under_roof() -> bool:
	var camera := get_viewport().get_camera_2d()
	if camera == null or covered_columns.is_empty():
		return false
	var column := clampi(int(camera.get_screen_center_position().x / tile_size), 0, covered_columns.size() - 1)
	return covered_columns[column] == 1


## 靜態剪影：頂端的橫管與吊纜、地面下的欄杆柱。
class _Static:
	extends Node2D

	var ground_y := 320.0
	var _textured := false

	func _ready() -> void:
		LightKit.mark_emissive(self)
		_textured = _add_strip(TOP_TEXTURE, TOP_Y - 4.0, true)
		_textured = _add_strip(BOTTOM_TEXTURE, ground_y + 14.0, false) and _textured
		if not _textured:
			queue_redraw()

	## 一條貼圖：左右各半段（第二段鏡像）排滿 REPEAT_WIDTH；回傳是否成功。有 LED 的「_glow」另疊一層（信標會明滅）。
	func _add_strip(path: String, y: float, hanging: bool) -> bool:
		var tex := RigLibrary.optional_texture(path)
		if tex == null:
			push_error("[Foreground] 找不到前景貼圖，改用程式繪製的剪影：%s" % path)
			return false
		var glow := RigLibrary.optional_texture(path.get_basename() + "_glow." + path.get_extension())
		var half := REPEAT_WIDTH * 0.5
		var scale_k := half / float(tex.get_width())
		for i in 2:
			var sprite := _strip_sprite(tex, Vector2(half * i, y), scale_k, i == 1)
			sprite.material = PropNode.sway_material(SWAY_AMPLITUDE, true, true) if hanging else LightKit.emissive_material()
			add_child(sprite)
			if glow != null:
				var lights := _strip_sprite(glow, Vector2(half * i, y), scale_k, i == 1)
				lights.material = LightKit.window_life_material()
				lights.self_modulate = LightKit.glow(Color.WHITE, 1.4)
				add_child(lights)
		return true

	func _strip_sprite(tex: Texture2D, at: Vector2, scale_k: float, mirrored: bool) -> Sprite2D:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = false
		sprite.position = at
		sprite.scale = Vector2(scale_k, scale_k)
		sprite.flip_h = mirrored
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		return sprite

	func _draw() -> void:
		if _textured:
			return
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
