class_name LevelBackground
extends Node2D
## 沉港市夜景：多層 Parallax2D 視差背景，全部程式產生（固定亂數種子，畫面穩定、不需貼圖）。
##   天空漸層 → 遠方「天穹」巨塔（紅色信標）→ 探照燈 → 遠景樓群（細密窗光）
##   → 飛行車流 → 中景樓群（霓虹招牌、全像廣告）→ 近景剪影
## 所有層都只繪製一次（BG-66）：會動的東西（信標、探照燈、車流）各自畫在子節點上，每影格只改子節點的位置、角度或亮度，不重畫。
## 背景不受場景光源影響（light_mask = 0）。

const PATTERN_WIDTH := 1280.0
const BACKGROUND_Z := -100
const HORIZON := 300.0
## 層與層之間霧色的高度（邏輯像素）：從該層底邊往上淡出。
const HAZE_HEIGHT := 230.0
## 霧色：被城市燈光染亮的水氣，比樓群的剪影亮，近的樓才會從遠的樓前面浮出來。會再乘上光影區段的背景色調。
const HAZE_COLOR := Color(1.1, 0.6, 1.5)


## 環境主題的背景貼圖層（由遠到近）；空陣列時使用程式繪製的天際線。要在加入場景樹之前指定。
var backdrop: Array[BackdropLayer] = []
## 環境主題的照片天空；null 或貼圖缺失時只用程式天空。要在加入場景樹之前指定。
var sky: BackdropLayer

## 各層前面的霧色（BG-65）；低畫質時整批隱藏。
var _hazes: Array[CanvasItem] = []
## 遠景的窗光層與它原本的顏色（BG-79：白天的室外窗燈跟著場景燈一起變弱）。
var _window_glows: Array[Sprite2D] = []
var _window_colors: PackedColorArray = PackedColorArray()
var _window_level := 1.0
static var _haze_texture: GradientTexture2D


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
	Settings.display_changed.connect(_refresh_haze)
	_refresh_haze()


## 霧色是體積效果：低畫質不畫（漂移照常）。
func _refresh_haze() -> void:
	for haze in _hazes:
		haze.visible = LightQuality.volumetrics()


func haze_count() -> int:
	return _hazes.size()


## 由上往下變濃的霧色貼圖（所有層共用一張）：最濃在該層的底邊（地平線附近），往上淡出。
static func _haze() -> GradientTexture2D:
	if _haze_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0))
		gradient.set_color(1, Color(1, 1, 1, 1))
		gradient.add_point(0.55, Color(1, 1, 1, 0.45))
		_haze_texture = GradientTexture2D.new()
		_haze_texture.gradient = gradient
		_haze_texture.fill_from = Vector2(0.5, 0.0)
		_haze_texture.fill_to = Vector2(0.5, 1.0)
		_haze_texture.width = 4
		_haze_texture.height = 64
	return _haze_texture


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
	parallax.autoscroll = Vector2(sky.drift_speed(), 0.0)  # 雲自己慢慢飄，鏡頭不動時天空也在動
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
	parallax.autoscroll = Vector2(layer.drift_speed(), 0.0)
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
		_window_glows.append(glow_sprite)
		_window_colors.append(glow_sprite.self_modulate)
	# 這一層前面的霧色：越遠的層越濃，層與層之間才有空氣感（大氣透視）。顏色跟著整個背景的光影區段色調。
	var strength := layer.haze_strength()
	if strength > 0.0:
		var haze := Sprite2D.new()
		haze.name = "Haze"
		haze.texture = _haze()
		haze.centered = false
		haze.scale = Vector2(PATTERN_WIDTH * 0.5 / float(haze.texture.get_width()), HAZE_HEIGHT / float(haze.texture.get_height()))
		haze.position = Vector2(0.0, layer.bottom_y - HAZE_HEIGHT)
		haze.modulate = Color(HAZE_COLOR, strength)
		haze.light_mask = 0
		parallax.add_child(haze)
		_hazes.append(haze)
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


## 遠方的天穹集團巨塔（劇情地標）：頂端紅色信標閃爍、垂直光帶。塔身只畫一次；信標是三個小節點，每影格只改大小與亮度。
class _Arcology:
	extends Node2D

	const BASE_X := 430.0
	const BEACONS: Array[Vector2] = [Vector2(BASE_X, -152), Vector2(BASE_X - 22, -64), Vector2(BASE_X + 22, -64)]
	## 信標畫成這個半徑、這個亮度；閃爍時縮放到 2～3 像素、亮度 1～2 倍（與原本每影格重畫的結果相同）。
	const BEACON_RADIUS := 3.0
	const BEACON_PEAK := 2.0

	var _time := 0.0
	var _beacons: Array[Node2D] = []

	func _ready() -> void:
		for point in BEACONS:
			var beacon := _Dot.new()
			beacon.radius = BEACON_RADIUS
			beacon.color = Color(LightKit.glow(Palette.DANGER, BEACON_PEAK), 0.9)
			beacon.position = point
			beacon.light_mask = 0
			add_child(beacon)
			_beacons.append(beacon)
		_pulse()

	func _process(delta: float) -> void:
		_time += delta
		_pulse()

	func _pulse() -> void:
		var blink := 0.5 + 0.5 * sin(_time * 3.0)
		var size := (2.0 + blink) / BEACON_RADIUS
		var level := (1.0 + blink) / BEACON_PEAK
		for beacon in _beacons:
			beacon.scale = Vector2(size, size)
			beacon.modulate = Color(level, level, level, 1.0)

	func _draw() -> void:
		var horizon := LevelBackground.HORIZON
		var tower := PackedVector2Array([Vector2(BASE_X - 70, horizon), Vector2(BASE_X - 26, -60), Vector2(BASE_X - 10, -150),
				Vector2(BASE_X + 10, -150), Vector2(BASE_X + 26, -60), Vector2(BASE_X + 70, horizon)])
		draw_colored_polygon(tower, Color("100c22"))
		for i in 5:
			var x := BASE_X - 18.0 + i * 9.0
			draw_line(Vector2(x, -40), Vector2(x * 0.98 + BASE_X * 0.02, horizon), Color(Palette.MAGENTA, 0.08), 2.0)
		# 頂部光環
		draw_arc(Vector2(BASE_X, -110), 34.0, PI, TAU, 24, Color(Palette.CYAN, 0.18), 2.0)


## 一個只畫一次的圓點（信標用）。
class _Dot:
	extends Node2D

	var radius := 1.0
	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)


## 探照燈：兩道光束在雲層間緩慢掃動。每道光束畫一次（朝正上方），每影格只轉節點。
class _Searchlights:
	extends Node2D

	const LENGTH := 520.0
	const HALF_WIDTH := 26.0

	var _time := 0.0
	var _beams: Array[Node2D] = []

	func _ready() -> void:
		for i in 2:
			var beam := _Beam.new()
			beam.position = Vector2(160.0 + i * 420.0, LevelBackground.HORIZON)
			beam.light_mask = 0
			add_child(beam)
			_beams.append(beam)
		_sweep()

	func _process(delta: float) -> void:
		_time += delta
		_sweep()

	func _sweep() -> void:
		for i in _beams.size():
			_beams[i].rotation = sin(_time * (0.25 + i * 0.1) + i * 2.0) * 0.55

	class _Beam:
		extends Node2D

		func _draw() -> void:
			var tip := Vector2(0.0, -LENGTH)
			draw_polygon(PackedVector2Array([Vector2.ZERO, tip + Vector2(HALF_WIDTH, 0.0), tip - Vector2(HALF_WIDTH, 0.0)]),
					PackedColorArray([Color(0.7, 0.8, 1.0, 0.1), Color(0.7, 0.8, 1.0, 0.0), Color(0.7, 0.8, 1.0, 0.0)]))


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


## 飛行車流：三條航道上的光點，車頭白光、車尾紅光。每條航道的車畫一次（畫兩段好接起來），每影格只平移那一條。
class _Traffic:
	extends Node2D

	## 每條航道：高度、速度（像素／秒，負值往左）、車數。
	const LANES := [[150.0, 70.0, 9], [185.0, -95.0, 7], [215.0, 120.0, 6]]
	const SPACING := 160.0

	var _time := 0.0
	var _lanes: Array[Node2D] = []

	func _ready() -> void:
		for lane: Array in LANES:
			var node := _Lane.new()
			node.cars = int(lane[2])
			node.heading = signf(float(lane[1]))
			node.position.y = float(lane[0])
			node.light_mask = 0
			add_child(node)
			_lanes.append(node)
		_advance()

	func _process(delta: float) -> void:
		_time += delta
		_advance()

	func _advance() -> void:
		for i in _lanes.size():
			_lanes[i].position.x = fposmod(_time * float((LANES[i] as Array)[1]), LevelBackground.PATTERN_WIDTH) - LevelBackground.PATTERN_WIDTH

	class _Lane:
		extends Node2D

		var cars := 0
		var heading := 1.0

		func _draw() -> void:
			# 同一排車畫兩段（一段在原位、一段往右一個循環寬度），節點在 [-寬度, 0) 之間平移時永遠接得起來。
			for copy in 2:
				for i in cars:
					var x := fposmod(i * SPACING, LevelBackground.PATTERN_WIDTH) + copy * LevelBackground.PATTERN_WIDTH
					draw_line(Vector2(x, 0.0), Vector2(x - heading * 10.0, 0.0), Color(Palette.DANGER, 0.6), 1.5)
					draw_circle(Vector2(x, 0.0), 1.2, LightKit.glow(Palette.WHITE, 1.5))


## 遠景窗光的亮度（0～1，光影設定的 lamp_power）：白天的室外多半不開燈。只有值變了才更新。
func set_window_level(level: float) -> void:
	level = clampf(level, 0.0, 1.0)
	if is_equal_approx(level, _window_level):
		return
	_window_level = level
	for i in _window_glows.size():
		if is_instance_valid(_window_glows[i]):
			var base := _window_colors[i]
			_window_glows[i].self_modulate = Color(base.r * level, base.g * level, base.b * level, base.a)


## 遠景層之間的霧色跟著光影區段的霧色（BG-79）：原本固定是洋紅，白天、清晨與青綠色調的區域也被染成紫。
## 亮度維持原本的霧（HAZE_COLOR 的感知亮度），只換色相。只有顏色變了才更新。
func set_haze_color(color: Color) -> void:
	var target := ColorScript.match_luminance(Color(color, 1.0), HAZE_COLOR.get_luminance())
	for haze in _hazes:
		if is_instance_valid(haze) and not Color(haze.modulate, 1.0).is_equal_approx(Color(target, 1.0)):
			haze.modulate = Color(target, haze.modulate.a)
