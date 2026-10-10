class_name StageLayers
extends RefCounted
## 過場場景的圖層工廠：依資料字典建立一層 Node2D。所有座標是 640×360 的舞台座標。
## 新增場景只要在 data/cutscene/stages/*.json 組合這些圖層，不用改程式；要新圖層種類才加在這裡。
##
## 通用欄位：kind（種類）、parallax（1 = 跟舞台一起動，0 = 固定在畫面，預設 1）、depth（back／front，預設 back）、
## alpha（整層透明度）、additive（加亮混合）。

const SOFT_TEXTURE_SIZE := 128
const FALLBACK_COLOR := Color("ff00ff")

## 合法的圖層種類與必填欄位（檢查工具用）。
const KINDS: Dictionary = {
	"gradient": ["top", "bottom"],
	"skyline": ["color"],
	"rect": ["rect", "color"],
	"poly": ["points", "color"],
	"glow": ["pos", "radius", "color"],
	"sprite": ["path", "pos"],
	"rain": [],
	"motes": [],
	"grain": [],
	"text": ["text", "pos"],
	"stripes": ["rect", "color"],
	"counter": ["pos", "from", "to"],
}

static var _soft_texture: GradientTexture2D


## 建立一層。def 缺欄位或種類不明時回傳 null，並記錄 where（例如「場景 shop_night 第 3 層」）。
static func create(def: Dictionary, where: String) -> Node2D:
	var kind := str(def.get("kind", ""))
	if not KINDS.has(kind):
		push_error("[Stage] %s：未知的圖層種類「%s」" % [where, kind])
		return null
	for key in KINDS[kind]:
		if not def.has(key):
			push_error("[Stage] %s：%s 圖層缺少欄位「%s」" % [where, kind, key])
			return null
	var node: Node2D
	match kind:
		"gradient":
			node = _Gradient.new(def)
		"skyline":
			node = _Skyline.new(def)
		"rect":
			node = _Rect.new(def)
		"poly":
			node = _Poly.new(def)
		"glow":
			node = _Glow.new(def)
		"sprite":
			node = _Sprite.new(def)
		"rain":
			node = _Rain.new(def)
		"motes":
			node = _Motes.new(def)
		"grain":
			node = _Grain.new(def)
		"text":
			node = _Text.new(def)
		"stripes":
			node = _Stripes.new(def)
		"counter":
			node = _Counter.new(def)
	node.modulate.a = float(def.get("alpha", 1.0))
	if bool(def.get("additive", false)):
		node.material = LightKit.additive_emissive_material()
	node.set_meta(&"kind", kind)
	node.set_meta(&"parallax", float(def.get("parallax", 1.0)))
	node.set_meta(&"depth", str(def.get("depth", "back")))
	return node


static func color_of(value: Variant, fallback := FALLBACK_COLOR) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
	if typeof(value) == TYPE_STRING and Color.html_is_valid(str(value)):
		return Color(str(value))
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return fallback


static func vec2_of(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func rect_of(value: Variant, fallback := Rect2()) -> Rect2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback


## Import resolution changes must preserve stage geometry, including furniture.
static func sprite_scale(def: Dictionary, texture: Texture2D) -> float:
	var ratio := float(def.get("source_width", texture.get_width())) / float(maxi(1, texture.get_width()))
	return float(def.get("scale", 1.0)) * ratio


## 發光色（亮度可超過 1，經 HDR 泛光）。
static func lit(value: Variant, intensity: float) -> Color:
	return LightKit.glow(color_of(value), intensity)


static func soft_texture() -> Texture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		gradient.offsets = PackedFloat32Array([0.0, 1.0])
		_soft_texture = GradientTexture2D.new()
		_soft_texture.gradient = gradient
		_soft_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_texture.fill_from = Vector2(0.5, 0.5)
		_soft_texture.fill_to = Vector2(1.0, 0.5)
		_soft_texture.width = SOFT_TEXTURE_SIZE
		_soft_texture.height = SOFT_TEXTURE_SIZE
	return _soft_texture


## 垂直漸層（可超出畫面，鏡頭平移與放大時不露邊）。
class _Gradient:
	extends Node2D
	var _top: Color
	var _bottom: Color
	var _rect: Rect2

	func _init(def: Dictionary) -> void:
		_top = StageLayers.color_of(def["top"])
		_bottom = StageLayers.color_of(def["bottom"])
		_rect = StageLayers.rect_of(def.get("rect"), Rect2(-320, -180, 1280, 720))

	func _draw() -> void:
		var r := _rect
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
				PackedColorArray([_top, _top, _bottom, _bottom]))


## 天際線：一排高低不同的建築，帶細密的窗光。
class _Skyline:
	extends Node2D
	var _def: Dictionary

	func _init(def: Dictionary) -> void:
		_def = def

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_def.get("seed", 1))
		var color := StageLayers.color_of(_def["color"])
		var base_y := float(_def.get("base_y", 280.0))
		var min_h := float(_def.get("min_h", 60.0))
		var max_h := float(_def.get("max_h", 160.0))
		var step := float(_def.get("step_w", 36.0))
		var from_x := float(_def.get("from_x", -160.0))
		var to_x := float(_def.get("to_x", 800.0))
		var density := float(_def.get("window_density", 0.25))
		var window_colors: Array = _def.get("window_colors", ["#ffd070", "#6fe0ff", "#ff7ab0"])
		var x := from_x
		while x < to_x:
			var w := rng.randf_range(step * 0.7, step * 1.3)
			var h := rng.randf_range(min_h, max_h)
			draw_rect(Rect2(x, base_y - h, w, h + 400.0), color)
			if density > 0.0:
				var wy := base_y - h + 6.0
				while wy < base_y - 4.0:
					var wx := x + 4.0
					while wx < x + w - 5.0:
						if rng.randf() < density:
							var wc := StageLayers.color_of(window_colors[rng.randi() % window_colors.size()])
							draw_rect(Rect2(wx, wy, 3, 3), StageLayers.lit(wc, 1.3))
						wx += 7.0
					wy += 8.0
			x += w + rng.randf_range(0.0, 3.0)


class _Rect:
	extends Node2D
	var _rect: Rect2
	var _color: Color

	func _init(def: Dictionary) -> void:
		_rect = StageLayers.rect_of(def["rect"])
		_color = StageLayers.lit(def["color"], float(def.get("intensity", 1.0)))

	func _draw() -> void:
		draw_rect(_rect, _color)


class _Poly:
	extends Node2D
	var _points := PackedVector2Array()
	var _color: Color

	func _init(def: Dictionary) -> void:
		for p: Variant in def["points"]:
			_points.append(StageLayers.vec2_of(p))
		_color = StageLayers.lit(def["color"], float(def.get("intensity", 1.0)))

	func _draw() -> void:
		if _points.size() >= 3:
			draw_colored_polygon(_points, _color)


## 柔光團（燈、霓虹、窗光、投影機光束）。flicker > 0 時閃爍；pulse > 0 時以該頻率（次／秒）明暗起伏（警報、呼吸燈），
## pulse_depth 是最暗時降到多少（0 ~ 1，預設 0.7）。
class _Glow:
	extends Sprite2D
	var _base: Color
	var _flicker := 0.0
	var _pulse := 0.0
	var _pulse_depth := 0.7
	var _phase := 0.0
	var _t := 0.0

	func _init(def: Dictionary) -> void:
		texture = StageLayers.soft_texture()
		position = StageLayers.vec2_of(def["pos"])
		var radius := float(def["radius"])
		scale = Vector2.ONE * (radius * 2.0 / float(StageLayers.SOFT_TEXTURE_SIZE))
		if def.has("stretch"):
			scale *= StageLayers.vec2_of(def["stretch"], Vector2.ONE)
		_base = StageLayers.lit(def["color"], float(def.get("intensity", 1.0)))
		self_modulate = _base
		_flicker = float(def.get("flicker", 0.0))
		_pulse = float(def.get("pulse", 0.0))
		_pulse_depth = clampf(float(def.get("pulse_depth", 0.7)), 0.0, 1.0)
		_phase = float(def.get("phase", 0.0))
		material = LightKit.additive_emissive_material()
		set_process(_flicker > 0.0 or _pulse > 0.0)

	func _process(delta: float) -> void:
		_t += delta
		var k := 1.0 - _flicker * (0.5 + 0.5 * sin(_t * 31.0) * sin(_t * 7.3))
		if _pulse > 0.0:
			k *= 1.0 - _pulse_depth * (0.5 + 0.5 * sin((_t * _pulse + _phase) * TAU))
		self_modulate = Color(_base.r * k, _base.g * k, _base.b * k, _base.a)


class _Sprite:
	extends Sprite2D

	## 有同名 `_glow.png` 時疊上自發光層（加亮混合），道具的窗光、霓虹在演出裡也會亮。
	func _init(def: Dictionary) -> void:
		var path := str(def["path"])
		var tex := RigLibrary.optional_texture(path)
		if tex == null:
			push_error("[Stage] 找不到圖片：%s" % path)
			tex = RigLibrary.texture(path, Vector2i(32, 32))
		texture = tex
		position = StageLayers.vec2_of(def["pos"])
		scale = Vector2.ONE * StageLayers.sprite_scale(def, tex)
		centered = bool(def.get("centered", false))
		if def.has("modulate"):
			modulate = StageLayers.color_of(def["modulate"])
		# 像素圖用最近點取樣；免費素材加工的照片背景要設 "filter": "linear"，否則放大會有鋸齒。
		var filter := CanvasItem.TEXTURE_FILTER_LINEAR if str(def.get("filter", "nearest")) == "linear" else CanvasItem.TEXTURE_FILTER_NEAREST
		texture_filter = filter
		# "life": true 時本層顯示窗光閃爍與信標明滅（窗光層與本層同一份著色器）。
		if bool(def.get("life", false)):
			material = LightKit.window_life_material()
		var glow_texture := RigLibrary.optional_texture(path.get_basename() + "_glow." + path.get_extension())
		if glow_texture != null and bool(def.get("glow", true)):
			var glow_sprite := Sprite2D.new()
			glow_sprite.texture = glow_texture
			glow_sprite.centered = centered
			glow_sprite.texture_filter = filter
			glow_sprite.material = LightKit.window_life_material() if bool(def.get("life", false)) else LightKit.additive_emissive_material()
			glow_sprite.self_modulate = LightKit.glow(Color.WHITE, float(def.get("glow_intensity", 1.2)))
			add_child(glow_sprite)


## 雨：固定數量的斜線，用同一批座標循環使用，不配置新物件。
class _Rain:
	extends Node2D
	var _drops := PackedVector2Array()
	var _speeds := PackedFloat32Array()
	var _lengths := PackedFloat32Array()
	var _color: Color
	var _wind: float
	var _area := Rect2(-80, -40, 800, 440)

	func _init(def: Dictionary) -> void:
		var count := clampi(int(def.get("count", 140)), 0, 600)
		_color = StageLayers.color_of(def.get("color", "#9db8f2"))
		_color.a = float(def.get("opacity", 0.38))
		_wind = float(def.get("wind", -0.18))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(def.get("seed", 5))
		for i in count:
			_drops.append(Vector2(rng.randf_range(_area.position.x, _area.end.x), rng.randf_range(_area.position.y, _area.end.y)))
			_speeds.append(rng.randf_range(420.0, 640.0))
			_lengths.append(rng.randf_range(6.0, 12.0))

	func _process(delta: float) -> void:
		for i in _drops.size():
			var d := _drops[i]
			d.y += _speeds[i] * delta
			d.x += _speeds[i] * delta * _wind
			if d.y > _area.end.y:
				d.y = _area.position.y
				d.x = fposmod(d.x - _area.position.x, _area.size.x) + _area.position.x
			_drops[i] = d
		queue_redraw()

	func _draw() -> void:
		for i in _drops.size():
			var d := _drops[i]
			draw_line(d, d + Vector2(_wind, 1.0).normalized() * _lengths[i], _color, 1.0)


## 塵粒：在光裡緩慢漂浮的小亮點（灰塵、數據碎片、餘燼）。固定數量、同一批座標循環使用，不配置新物件。
## 欄位：count（預設 40）、color、opacity、area [x, y, w, h]（預設整個畫面）、drift [vx, vy]（每秒，預設緩慢上飄）、size（像素，預設 1.5）。
class _Motes:
	extends Node2D
	var _points := PackedVector2Array()
	var _seeds := PackedFloat32Array()
	var _color: Color
	var _area: Rect2
	var _drift: Vector2
	var _size: float
	var _t := 0.0

	func _init(def: Dictionary) -> void:
		var count := clampi(int(def.get("count", 40)), 0, 300)
		_color = StageLayers.color_of(def.get("color", "#ffd9a0"))
		_color.a = float(def.get("opacity", 0.5))
		_area = StageLayers.rect_of(def.get("area"), Rect2(0, 0, 640, 360))
		_drift = StageLayers.vec2_of(def.get("drift"), Vector2(2.0, -5.0))
		_size = float(def.get("size", 1.5))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(def.get("seed", 9))
		for i in count:
			_points.append(Vector2(rng.randf_range(0.0, _area.size.x), rng.randf_range(0.0, _area.size.y)))
			_seeds.append(rng.randf_range(0.0, TAU))
		material = LightKit.additive_emissive_material()

	func _process(delta: float) -> void:
		_t += delta
		for i in _points.size():
			var p := _points[i]
			p += _drift * delta * (0.6 + 0.4 * sin(_seeds[i]))
			p.x = fposmod(p.x, _area.size.x)
			p.y = fposmod(p.y, _area.size.y)
			_points[i] = p
		queue_redraw()

	func _draw() -> void:
		for i in _points.size():
			var wobble := Vector2(sin(_t * 0.7 + _seeds[i]) * 2.0, cos(_t * 0.5 + _seeds[i]) * 1.5)
			var twinkle := 0.55 + 0.45 * sin(_t * 1.3 + _seeds[i] * 3.0)
			draw_circle(_area.position + _points[i] + wobble, _size, Color(_color.r, _color.g, _color.b, _color.a * twinkle))


## 顆粒雜訊（老舊畫面、記憶、過曝）：每隔一小段時間重新撒點。
class _Grain:
	extends Node2D
	## 特殊舞台的顆粒上限：再多就會蓋過人物與字幕。
	const MAX_GRAIN := 200
	var _amount: int
	var _color: Color
	var _t := 0.0
	var _seed := 0

	func _init(def: Dictionary) -> void:
		_amount = clampi(int(def.get("amount", 160)), 0, MAX_GRAIN)
		_color = StageLayers.color_of(def.get("color", "#ffffff"))
		_color.a = float(def.get("opacity", 0.18))
		# 減少閃光時不畫會跳動的顆粒。
		visible = not Settings.get_reduce_flashes()

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 0.07:
			_t = 0.0
			_seed += 1
			queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		for i in _amount:
			draw_rect(Rect2(rng.randf_range(-40.0, 680.0), rng.randf_range(-20.0, 380.0), 1.0, 1.0), _color)


class _Text:
	extends Node2D
	var _text: String
	var _color: Color
	var _size: int

	func _init(def: Dictionary) -> void:
		_text = str(def["text"])
		position = StageLayers.vec2_of(def["pos"])
		_color = StageLayers.lit(def.get("color", "#35e0ff"), float(def.get("intensity", 1.5)))
		_size = UiKit.snap_size(int(def.get("size", UiKit.FS_BODY)))

	func _draw() -> void:
		draw_string(UiKit.font(), Vector2.ZERO, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size, _color)


## 斜線警示條紋。
class _Stripes:
	extends Node2D
	var _rect: Rect2
	var _color: Color
	var _gap: float

	func _init(def: Dictionary) -> void:
		_rect = StageLayers.rect_of(def["rect"])
		_color = StageLayers.lit(def["color"], float(def.get("intensity", 1.0)))
		_gap = maxf(4.0, float(def.get("gap", 10.0)))

	func _draw() -> void:
		var x := _rect.position.x - _rect.size.y
		while x < _rect.end.x:
			draw_line(Vector2(x, _rect.end.y), Vector2(x + _rect.size.y, _rect.position.y), _color, 3.0)
			x += _gap


## 數字計數器（電梯樓層）：舞台建立後經過 delay 秒開始，在 time 秒內從 from 數到 to。
class _Counter:
	extends Node2D
	var _from: int
	var _to: int
	var _time: float
	var _delay: float
	var _color: Color
	var _size: int
	var _suffix: String
	var _t := 0.0
	var _last := -999

	func _init(def: Dictionary) -> void:
		position = StageLayers.vec2_of(def["pos"])
		_from = int(def["from"])
		_to = int(def["to"])
		_time = maxf(0.1, float(def.get("time", 6.0)))
		_delay = float(def.get("delay", 0.0))
		_color = StageLayers.lit(def.get("color", "#35e0ff"), float(def.get("intensity", 1.6)))
		_size = UiKit.snap_size(int(def.get("size", UiKit.FS_TITLE)))
		_suffix = str(def.get("suffix", ""))

	func _process(delta: float) -> void:
		_t += delta
		var value := current()
		if value != _last:
			_last = value
			queue_redraw()

	func current() -> int:
		var k := clampf((_t - _delay) / _time, 0.0, 1.0)
		return roundi(lerpf(float(_from), float(_to), k))

	func _draw() -> void:
		draw_string(UiKit.font(), Vector2.ZERO, "%d%s" % [current(), _suffix], HORIZONTAL_ALIGNMENT_LEFT, -1, _size, _color)
