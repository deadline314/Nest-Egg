class_name LevelBackground
extends Node2D
## 沉港市夜景：多層 Parallax2D 視差背景，全部程式產生（固定亂數種子，畫面穩定、不需貼圖）。
##   天空漸層 → 遠方「天穹」巨塔（紅色信標）→ 探照燈 → 遠景樓群（細密窗光）
##   → 飛行車流 → 中景樓群（霓虹招牌、全像廣告）→ 近景剪影
## 靜態層只繪製一次；只有會動的層（信標、探照燈、車流）每影格重繪。
## 背景不受場景光源影響（light_mask = 0）。

const PATTERN_WIDTH := 1280.0
const BACKGROUND_Z := -100
const HORIZON := 300.0


## 環境主題的背景貼圖層（由遠到近）；空陣列時使用程式繪製的天際線。要在加入場景樹之前指定。
var backdrop: Array[BackdropLayer] = []
## 環境主題的照片天空；null 或貼圖缺失時只用程式天空。要在加入場景樹之前指定。
var sky: BackdropLayer


func _ready() -> void:
	z_as_relative = false
	z_index = BACKGROUND_Z
	_add_layer(0.0, _Sky.new(), false)
	_add_photo_sky()
	_add_layer(0.03, _Arcology.new(), false)
	_add_layer(0.05, _Searchlights.new(), false)
	if backdrop.is_empty():
		_add_layer(0.1, _Skyline.new(11, Palette.CITY_FAR, 150.0, 260.0, 26.0, 0.55, 0.0), true)
		_add_layer(0.16, _Traffic.new(), true)
		_add_layer(0.24, _Skyline.new(23, Palette.CITY_MID, 80.0, 200.0, 40.0, 0.35, 0.5), true)
		_add_layer(0.38, _Skyline.new(37, Palette.CITY_NEAR, 40.0, 120.0, 60.0, 0.15, 0.25), true)
		return
	for i in backdrop.size():
		_add_textured_layer(backdrop[i])
		# 車流夾在遠景與中景之間。
		if i == 0:
			_add_layer(0.16, _Traffic.new(), true)


## 照片天空：整圈全景切成的長條（左右無縫），慢速視差，上緣透明漸層接上程式天空。
func _add_photo_sky() -> void:
	if sky == null:
		return
	var texture := RigLibrary.optional_texture(sky.texture)
	if texture == null:
		push_warning("[LevelBackground] 找不到天空貼圖，改用程式天空：%s" % sky.texture)
		return
	var factor := sky.pixel_scale(texture)
	var parallax := Parallax2D.new()
	parallax.scroll_scale = Vector2(sky.scroll_scale, sky.scroll_scale * 0.4)
	parallax.repeat_size = Vector2(float(texture.get_width()) * factor, 0.0)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * factor
	sprite.modulate = sky.tint
	sprite.light_mask = 0
	sprite.position = Vector2(0.0, sky.bottom_y - float(texture.get_height()) * factor)
	parallax.add_child(sprite)
	add_child(parallax)


## 貼圖背景層：左右無縫平鋪的圖（寬 640 邏輯像素）+ 自發光窗光。
func _add_textured_layer(layer: BackdropLayer) -> void:
	var texture := RigLibrary.texture(layer.texture, Vector2i(int(PATTERN_WIDTH * 0.5), 400))
	var parallax := Parallax2D.new()
	parallax.scroll_scale = Vector2(layer.scroll_scale, layer.scroll_scale * 0.4)
	parallax.repeat_size = Vector2(PATTERN_WIDTH * 0.5, 0.0)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	var factor := layer.pixel_scale(texture)
	sprite.scale = Vector2.ONE * factor
	sprite.modulate = layer.tint
	sprite.light_mask = 0
	sprite.position = Vector2(0.0, layer.bottom_y - float(texture.get_height()) * factor)
	parallax.add_child(sprite)
	var glow := RigLibrary.optional_texture(layer.glow_path())
	if glow != null:
		var glow_sprite := Sprite2D.new()
		glow_sprite.texture = glow
		glow_sprite.centered = false
		glow_sprite.scale = sprite.scale
		glow_sprite.position = sprite.position
		glow_sprite.light_mask = 0
		glow_sprite.material = LightKit.window_life_material()  # 窗光緩慢閃爍、屋頂信標明滅
		glow_sprite.self_modulate = LightKit.glow(layer.tint, layer.glow_intensity)
		parallax.add_child(glow_sprite)
	add_child(parallax)


func _add_layer(scale_factor: float, drawer: Node2D, repeat: bool) -> void:
	var parallax := Parallax2D.new()
	parallax.scroll_scale = Vector2(scale_factor, scale_factor * 0.4)
	if repeat:
		parallax.repeat_size = Vector2(PATTERN_WIDTH, 0)
	drawer.light_mask = 0
	parallax.add_child(drawer)
	add_child(parallax)


## 天空：上方深藍紫、地平線被城市光染成洋紅。固定在畫面上。
class _Sky:
	extends Node2D

	func _draw() -> void:
		var rect := PackedVector2Array([Vector2(-400, -300), Vector2(1100, -300), Vector2(1100, LevelBackground.HORIZON + 200), Vector2(-400, LevelBackground.HORIZON + 200)])
		draw_polygon(rect, PackedColorArray([Palette.SKY_TOP, Palette.SKY_TOP, Palette.SKY_HORIZON, Palette.SKY_HORIZON]))
		# 低垂雲層
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 14:
			draw_circle(Vector2(rng.randf_range(-300, 1000), rng.randf_range(-40, 90)), rng.randf_range(60, 140), Color(0.2, 0.12, 0.3, 0.12))


## 遠方的天穹集團巨塔（劇情地標）：頂端紅色信標閃爍、垂直光帶。
class _Arcology:
	extends Node2D

	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var base_x := 430.0
		var horizon := LevelBackground.HORIZON
		var tower := PackedVector2Array([Vector2(base_x - 70, horizon), Vector2(base_x - 26, -60), Vector2(base_x - 10, -150),
				Vector2(base_x + 10, -150), Vector2(base_x + 26, -60), Vector2(base_x + 70, horizon)])
		draw_colored_polygon(tower, Color("100c22"))
		for i in 5:
			var x := base_x - 18.0 + i * 9.0
			draw_line(Vector2(x, -40), Vector2(x * 0.98 + base_x * 0.02, horizon), Color(Palette.MAGENTA, 0.08), 2.0)
		# 頂部光環與信標
		draw_arc(Vector2(base_x, -110), 34.0, PI, TAU, 24, Color(Palette.CYAN, 0.18), 2.0)
		var blink := 0.5 + 0.5 * sin(_time * 3.0)
		for point: Vector2 in [Vector2(base_x, -152), Vector2(base_x - 22, -64), Vector2(base_x + 22, -64)]:
			draw_circle(point, 2.0 + blink, Color(LightKit.glow(Palette.DANGER, 1.0 + blink), 0.9))


## 探照燈：兩道光束在雲層間緩慢掃動。
class _Searchlights:
	extends Node2D

	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for i in 2:
			var origin := Vector2(160.0 + i * 420.0, LevelBackground.HORIZON)
			var angle := -PI * 0.5 + sin(_time * (0.25 + i * 0.1) + i * 2.0) * 0.55
			var direction := Vector2.RIGHT.rotated(angle)
			var side := direction.orthogonal() * 26.0
			var tip := origin + direction * 520.0
			var beam := PackedVector2Array([origin, tip + side, tip - side])
			draw_polygon(beam, PackedColorArray([Color(0.7, 0.8, 1.0, 0.1), Color(0.7, 0.8, 1.0, 0.0), Color(0.7, 0.8, 1.0, 0.0)]))


## 樓群：固定種子產生；窗光密度與霓虹招牌比例依層調整。只繪製一次。
class _Skyline:
	extends Node2D

	var _seed: int
	var _color: Color
	var _min_height: float
	var _max_height: float
	var _min_width: float
	var _window_density: float
	var _neon_chance: float

	func _init(p_seed: int, color: Color, min_height: float, max_height: float, min_width: float, window_density: float, neon_chance: float) -> void:
		_seed = p_seed
		_color = color
		_min_height = min_height
		_max_height = max_height
		_min_width = min_width
		_window_density = window_density
		_neon_chance = neon_chance

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		var x := 0.0
		var ground := LevelBackground.HORIZON + 120.0
		while x < LevelBackground.PATTERN_WIDTH:
			var w := rng.randf_range(_min_width, _min_width * 2.2)
			var h := rng.randf_range(_min_height, _max_height)
			var top := ground - h
			draw_rect(Rect2(x, top, w - 3.0, h + 200.0), _color)
			# 屋頂天線與信標
			if rng.randf() < 0.35:
				var ax := x + rng.randf_range(4.0, w - 8.0)
				draw_line(Vector2(ax, top), Vector2(ax, top - rng.randf_range(10.0, 30.0)), _color.lightened(0.1), 1.0)
				draw_circle(Vector2(ax, top - 30.0), 1.2, Color(Palette.DANGER, 0.8))
			# 窗光
			var wy := top + 6.0
			while wy < ground - 4.0:
				var wx := x + 4.0
				while wx < x + w - 8.0:
					if rng.randf() < _window_density:
						var lit: Color = [Color("ffd27a"), Color("7fe8ff"), Color("ff8fd0")][rng.randi() % 3]
						draw_rect(Rect2(wx, wy, 2.0, 2.0), Color(lit, rng.randf_range(0.25, 0.7)))
					wx += 5.0
				wy += 6.0
			# 霓虹招牌（直式色條）
			if rng.randf() < _neon_chance:
				var neon: Color = Palette.NEON_COLORS[rng.randi() % Palette.NEON_COLORS.size()]
				var nx := x + rng.randf_range(2.0, maxf(3.0, w - 10.0))
				var ny := top + rng.randf_range(8.0, maxf(10.0, h * 0.5))
				draw_rect(Rect2(nx, ny, 5.0, rng.randf_range(16.0, 34.0)), LightKit.glow(neon, 1.4))
			x += w


## 飛行車流：三條航道上的光點，車頭白光、車尾紅光。
class _Traffic:
	extends Node2D

	const LANES := [[150.0, 70.0, 9], [185.0, -95.0, 7], [215.0, 120.0, 6]]
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for lane: Array in LANES:
			var y: float = lane[0]
			var speed: float = lane[1]
			for i in int(lane[2]):
				var x := fposmod(i * 160.0 + _time * speed, LevelBackground.PATTERN_WIDTH)
				var dir := signf(speed)
				draw_line(Vector2(x, y), Vector2(x - dir * 10.0, y), Color(Palette.DANGER, 0.6), 1.5)
				draw_circle(Vector2(x, y), 1.2, LightKit.glow(Palette.WHITE, 1.5))
