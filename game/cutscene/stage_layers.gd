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
	"dial": ["pos", "radius", "color", "pointer"],
}

static var _soft_texture: GradientTexture2D


## 建立一層。def 缺欄位或種類不明時回傳 null，並記錄 where（例如「場景 shop_night 第 3 層」）。
static func create(def: Dictionary, where: String) -> Node2D:
	var state_issue := prop_state_problem(def)
	if not state_issue.is_empty():
		push_error("[Stage] %s: %s" % [where, state_issue])
		return null
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
		"dial":
			node = _Dial.new(def)
	node.modulate.a = float(def.get("alpha", 1.0))
	if not def.get("visible", true):
		node.hide()
		node.set_meta(&"visible_process_mode", node.process_mode)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	if bool(def.get("additive", false)):
		node.material = LightKit.additive_emissive_material()
	node.set_meta(&"kind", kind)
	node.set_meta(&"parallax", float(def.get("parallax", 1.0)))
	node.set_meta(&"depth", str(def.get("depth", "back")))
	if def.has("id"):
		node.set_meta(&"prop_id", str(def["id"]))
	if def.has("parent_prop"):
		node.set_meta(&"parent_prop", str(def["parent_prop"]))
		node.set_meta(&"anchor", vec2_of(def["anchor"]))
	return node


## Finite material states only. Authors cannot address Nodes or execute handlers.
static func prop_state_problem(def: Dictionary) -> String:
	var effect_issue := _effect_problem(def)
	if not effect_issue.is_empty():
		return effect_issue
	if def.has("visible") and not def["visible"] is bool:
		return "layer visible must be boolean"
	var geometry_issue := StageSpriteGeometry.problem(def)
	if not geometry_issue.is_empty():
		return geometry_issue
	if def.has("initial_state"):
		var state: Variant = def["initial_state"]
		var states: Variant = def.get("states", {})
		if def.get("kind") != "sprite" or not state is String or (state != "default" and (not states is Dictionary or not states.has(state))):
			return "sprite initial_state must name a registered texture state"
	if not def.has("states"):
		return ""
	if def.get("kind") != "sprite" or not def.get("id") is String or not String(def["id"]).is_valid_identifier():
		return "sprite states require a named sprite layer"
	var states: Variant = def["states"]
	if not states is Dictionary or states.is_empty() or states.size() > 8:
		return "sprite states require 1..8 named textures"
	for key: Variant in states:
		var entry: Variant = states[key]
		if not key is String or key == "default" or key.length() > 64 or not key.is_valid_identifier() or not entry is Dictionary or entry.size() != 1 or not entry.get("path") is String:
			return "sprite state must contain only a named texture path"
		var path: String = entry["path"]
		if not path.begins_with("res://art/") or ".." in path or RigLibrary.texture_size(path) == Vector2.ZERO:
			return "sprite state texture is missing: " + path.left(256)
	return ""


static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _effect_problem(def: Dictionary) -> String:
	if def.get("kind") == "dial":
		if not _finite(def.get("radius")) or float(def["radius"]) < 1.0 or float(def["radius"]) > 64.0:
			return "dial radius must be finite and within 1..64"
		for key: String in ["color", "pointer"]:
			if not def.get(key) is String or not Color.html_is_valid(def[key]):
				return "dial %s must be a color" % key
		if def.has("angle") and (not _finite(def["angle"]) or absf(float(def["angle"])) > TAU * 8.0):
			return "dial angle must be finite and within eight turns"
	if def.get("kind") != "rain":
		return ""
	if def.has("area"):
		var area: Variant = def["area"]
		if not area is Array or area.size() != 4:
			return "rain area requires four finite coordinates"
		for value: Variant in area:
			if not _finite(value) or absf(float(value)) > 8192.0:
				return "rain area must be finite and bounded"
		if float(area[2]) <= 0.0 or float(area[3]) <= 0.0:
			return "rain area must have positive width and height"
	for key: String in ["speed", "length"]:
		if not def.has(key):
			continue
		var limits: Variant = def[key]
		if not limits is Array or limits.size() != 2 or not _finite(limits[0]) or not _finite(limits[1]):
			return "rain %s requires two finite limits" % key
		var maximum := 2048.0 if key == "speed" else 128.0
		if float(limits[0]) < 0.0 or float(limits[1]) < float(limits[0]) or float(limits[1]) > maximum:
			return "rain %s limits are invalid" % key
	if def.has("wind") and (not _finite(def["wind"]) or absf(float(def["wind"])) > 10.0):
		return "rain wind must be finite and within ±10"
	return ""


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
	return sprite_scale_for_width(def, float(texture.get_width()))


## 同上，但只知道貼圖寬度（資料檢查用，不必把貼圖留在記憶體裡）。
static func sprite_scale_for_width(def: Dictionary, width: float) -> float:
	var ratio := float(def.get("source_width", width)) / maxf(1.0, width)
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
	var _state_textures: Dictionary[String, Texture2D] = {}
	var _state_glows: Dictionary[String, Texture2D] = {}
	var _state := "default"
	var _world_width := 0.0
	var _glow_sprite: Sprite2D
	var _glow_enabled := true
	var _source_width := 0.0
	var _source_region := Rect2()
	var _source_pivot := Vector2.ZERO
	var _has_geometry := false
	var _anchored := false
	var _anchor_source := Vector2.ZERO
	var _anchored_children: Array[WeakRef] = []

	## 有同名 `_glow.png` 時疊上自發光層（加亮混合），道具的窗光、霓虹在演出裡也會亮。
	func _init(def: Dictionary) -> void:
		var path := str(def["path"])
		var tex := RigLibrary.optional_texture(path)
		if tex == null:
			push_error("[Stage] 找不到圖片：%s" % path)
			tex = RigLibrary.texture(path, Vector2i(32, 32))
		texture = tex
		_source_width = float(def.get("source_width", tex.get_width()))
		_source_region = StageLayers.rect_of(def.get("region"), Rect2(Vector2.ZERO, Vector2(tex.get_size()) * (_source_width / float(tex.get_width()))))
		_source_pivot = StageLayers.vec2_of(def.get("pivot"))
		_has_geometry = def.has("region") or def.has("pivot")
		region_enabled = def.has("region")
		_world_width = float(def.get("source_width", tex.get_width())) * float(def.get("scale", 1.0))
		_state_textures["default"] = tex
		_glow_enabled = bool(def.get("glow", true))
		var state_paths: Dictionary = {"default": path}
		for key: String in def.get("states", {}):
			var state_path: String = def["states"][key]["path"]
			_state_textures[key] = RigLibrary.optional_texture(state_path)
			state_paths[key] = state_path
		for key: String in state_paths:
			var state_path: String = state_paths[key]
			_state_glows[key] = RigLibrary.optional_texture(state_path.get_basename() + "_glow." + state_path.get_extension())
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
		var has_glow := false
		for glow: Texture2D in _state_glows.values():
			has_glow = has_glow or glow != null
		if has_glow and _glow_enabled:
			var glow_sprite := Sprite2D.new()
			_glow_sprite = glow_sprite
			glow_sprite.texture = _state_glows["default"]
			glow_sprite.centered = centered
			glow_sprite.texture_filter = filter
			glow_sprite.material = LightKit.window_life_material() if bool(def.get("life", false)) else LightKit.additive_emissive_material()
			glow_sprite.self_modulate = LightKit.glow(Color.WHITE, float(def.get("glow_intensity", 1.2)))
			add_child(glow_sprite)
		_apply_geometry()
		if def.get("initial_state", "default") != "default":
			set_prop_state(def["initial_state"])

	func set_prop_state(state: String) -> bool:
		if not supports_prop_state(state):
			return false
		texture = _state_textures[state]
		scale = Vector2.ONE * (_world_width / float(texture.get_width()))
		if _glow_sprite != null:
			_glow_sprite.texture = _state_glows.get(state)
		_apply_geometry()
		_sync_parent_geometry()
		_sync_anchored_children()
		_state = state
		return true

	func prop_state() -> String:
		return _state

	func supports_prop_state(state: String) -> bool:
		return _state_textures.has(state) and _state_textures[state] != null

	func source_point(point: Vector2) -> Vector2:
		return StageSpriteGeometry.source_point(self, point, _source_width, _source_region)

	func _apply_geometry() -> void:
		if not _has_geometry:
			return
		StageSpriteGeometry.apply(self, _source_width, _source_region, _source_pivot)
		if _glow_sprite != null:
			_glow_sprite.region_enabled = region_enabled
			StageSpriteGeometry.apply(_glow_sprite, _source_width, _source_region, _source_pivot)
			if _glow_sprite.texture != null:
				_glow_sprite.scale = Vector2.ONE * (float(texture.get_width()) / float(_glow_sprite.texture.get_width()))

	func nominal_scale() -> float:
		return _world_width / float(texture.get_width()) if texture != null and texture.get_width() > 0 else 0.0

	func anchored() -> bool:
		return _anchored

	func anchor_to(parent: StageLayers._Sprite, point: Vector2) -> String:
		if _anchored or get_parent() == null or not is_instance_valid(parent) or parent == self:
			return "sprite anchor requires a distinct parent and an unbound stage child"
		if not parent.source_point(point).is_finite() or parent.nominal_scale() <= 0.0:
			return "anchor point is outside its parent sprite"
		parent._compact_anchor_children()
		if parent._anchored_children.size() >= 8:
			return "parent sprite exceeds eight anchored children"
		var ancestor := parent
		var depth := 0
		while ancestor != null:
			if ancestor == self or depth >= 8:
				return "sprite anchor is cyclic or exceeds eight levels"
			ancestor = ancestor.get_parent() as StageLayers._Sprite
			depth += 1
		_anchor_source = point
		_anchored = true
		reparent(parent, false)
		parent._anchored_children.append(weakref(self))
		_sync_parent_geometry()
		return ""

	func _sync_parent_geometry() -> void:
		if not _anchored:
			return
		var parent := get_parent() as StageLayers._Sprite
		if parent != null and parent.nominal_scale() > 0.0:
			position = parent.source_point(_anchor_source)
			scale = Vector2.ONE * (nominal_scale() / parent.nominal_scale())

	func _sync_anchored_children() -> void:
		_compact_anchor_children()
		for reference: WeakRef in _anchored_children:
			var child := reference.get_ref() as StageLayers._Sprite
			if is_instance_valid(child):
				child._sync_parent_geometry()

	func _compact_anchor_children() -> void:
		var index := _anchored_children.size() - 1
		while index >= 0:
			var child := _anchored_children[index].get_ref() as StageLayers._Sprite
			if not is_instance_valid(child) or child.get_parent() != self:
				_anchored_children.remove_at(index)
			index -= 1


## 旋鈕：指針跟著節點角度轉動，供手部接觸追實際控制方向。
class _Dial:
	extends Node2D
	var _radius := 5.0
	var _color := Color("34393a")
	var _pointer := Color("cfccc3")

	func _init(def: Dictionary) -> void:
		position = StageLayers.vec2_of(def["pos"])
		rotation = float(def.get("angle", 0.0))
		_radius = float(def["radius"])
		_color = StageLayers.color_of(def["color"])
		_pointer = StageLayers.color_of(def["pointer"])

	func _draw() -> void:
		draw_circle(Vector2.ZERO, _radius + 1.0, Color("1b211d"))
		draw_circle(Vector2.ZERO, _radius, _color)
		draw_line(Vector2(0, 0.5), Vector2(0, -_radius * 0.65), _pointer, 1.2, true)


## 雨／局部水流：固定斜線循環使用；隱藏時由舞台停用更新。
class _Rain:
	extends Node2D
	var _drops := PackedVector2Array()
	var _speeds := PackedFloat32Array()
	var _lengths := PackedFloat32Array()
	var _color: Color
	var _wind: float
	var _area := Rect2(-80, -40, 800, 440)
	var _local_flow := false

	func _init(def: Dictionary) -> void:
		var count := clampi(int(def.get("count", 140)), 0, 600)
		_color = StageLayers.color_of(def.get("color", "#9db8f2"))
		_color.a = float(def.get("opacity", 0.38))
		_wind = float(def.get("wind", -0.18))
		_local_flow = def.has("area")
		_area = StageLayers.rect_of(def.get("area"), _area)
		var speed: Array = def.get("speed", [420.0, 640.0])
		var length: Array = def.get("length", [6.0, 12.0])
		var rng := RandomNumberGenerator.new()
		rng.seed = int(def.get("seed", 5))
		for i in count:
			_drops.append(Vector2(rng.randf_range(_area.position.x, _area.end.x), rng.randf_range(_area.position.y, _area.end.y)))
			_speeds.append(rng.randf_range(float(speed[0]), float(speed[1])))
			_lengths.append(rng.randf_range(float(length[0]), float(length[1])))

	func _process(delta: float) -> void:
		for i in _drops.size():
			var d := _drops[i]
			d.y += _speeds[i] * delta
			d.x += _speeds[i] * delta * _wind
			if d.y > _area.end.y:
				d.y = fposmod(d.y - _area.position.y, _area.size.y) + _area.position.y if _local_flow else _area.position.y
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
