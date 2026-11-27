class_name NearForeground
extends Node2D
## 近前景（BG-68）：畫在角色前面、不透明的深色剪影。走道外緣一排從地面往下長的欄杆、矮籬、花台，
## 畫面上緣垂下來的纜線、燈籠串、枝葉。剪影用既有素材的形狀（貼圖只取 alpha），朝主光的一側有一圈邊緣光。
## 資料：地圖 JSON 頂層的 "near_foreground"（每一排：anchor、pieces、rise 或 above、spacing、from、to），零件在 LIBRARY_PATH。
## bottom 的 rise：地面以上露出多高；top 的 above：從下面走道往上多高的地方垂下來（站在走道上時就在畫面上緣附近）。
##
## 判讀優先：走道那排最多只露出小腿高（CALF_RISE），戰鬥範圍（敵人出生點附近）更矮；垂掛物的底邊離下面最高的走道
## 至少 HEAD_CLEAR，戰鬥範圍不放。放不下就略過那一件，不會擋到角色、武器、子彈與提示。規則集中在 plan()，
## 遊戲與自動檢查用同一份。比走道捲動得略快（DRIFT，最多 MAX_DRIFT 像素）；垂掛物被風吹、被經過的角色帶動，
## 「減少動態」或低畫質時靜止；三個畫質都畫（它是構圖不是特效）。靜止時只有鏡頭移動才更新位置。

const LIBRARY_PATH := "res://data/environment/near_foreground.json"
const SHADER := preload("res://game/level/environment/near_silhouette.gdshader")
## 走道那排在地面以上最多露出多高（小腿以下）；戰鬥範圍再矮。
const CALF_RISE := 16.0
const COMBAT_RISE := 9.0
## 垂掛物的底邊至少要比下面最高的走道高多少（高個子敵人的頭頂與舉槍）。
const HEAD_CLEAR := 84.0
## 垂掛物預設從走道往上多高的地方垂下來。
const DEFAULT_ABOVE := 175.0
## 敵人出生點左右多遠算戰鬥範圍。
const COMBAT_REACH := 160.0
## 比走道捲動得快多少（鏡頭每移動 1 像素多移 DRIFT），位移上限。
const DRIFT := 0.06
const MAX_DRIFT := 24.0
## 走道那排的地面要平：零件下方地面高低差超過這個就不放。
const FLAT_TOLERANCE := 2.0
## 邊緣光的寬度（遊戲像素）。
const RIM_WIDTH := 1.6

static var _library: Dictionary = {}
static var _library_loaded := false

var _sprites: Array[Sprite2D] = []
var _base_x := PackedFloat32Array()
var _half_width := PackedFloat32Array()
var _kicks: Array[SwayKick] = []
var _materials: Array[ShaderMaterial] = []
var _swaying: Array[float] = []
var _last_camera_x := INF


## 讀零件庫（快取）。檔案壞掉時記錄並回傳空的（整個近前景不畫，關卡照常）。
static func library() -> Dictionary:
	if not _library_loaded:
		_library_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY_PATH)) if FileAccess.file_exists(LIBRARY_PATH) else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("[NearForeground] 讀不到近前景零件庫：%s" % LIBRARY_PATH)
		else:
			for id: String in (parsed as Dictionary):
				if not id.begins_with("_"):
					_library[id] = parsed[id]
	return _library


## 依資料排出每一件的位置（不建立節點）：回傳 [{id, anchor, rect, texture, region, flip_v, sway}]。
## rows 是地圖的 near_foreground；surface_y(x) 回傳 x 處最高可走地面的 y；enemy_x 是敵人出生點；where 用在錯誤訊息。
## 不合規則的擺放直接略過（並不記錯誤：這是擺放規則，不是資料錯誤）；資料本身壞掉才記錯誤。
static func plan(rows: Variant, surface_y: Callable, enemy_x: PackedFloat32Array, tile_size: float, where: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if rows == null:
		return result
	if typeof(rows) != TYPE_ARRAY:
		push_error("[NearForeground] %s 的 near_foreground 必須是陣列" % where)
		return result
	var pieces := library()
	for index in (rows as Array).size():
		var row: Variant = rows[index]
		var label := "%s near_foreground[%d]" % [where, index]
		if typeof(row) != TYPE_DICTIONARY:
			push_error("[NearForeground] %s 必須是物件" % label)
			continue
		var spec := row as Dictionary
		var anchor := str(spec.get("anchor", ""))
		var ids: Variant = spec.get("pieces", [])
		var spacing: Variant = spec.get("spacing", [80, 160])
		if anchor not in ["bottom", "top"] or typeof(ids) != TYPE_ARRAY or (ids as Array).is_empty() \
				or typeof(spacing) != TYPE_ARRAY or (spacing as Array).size() != 2 or not _numbers(spacing as Array) \
				or float(spacing[0]) < 8.0 or float(spacing[1]) < float(spacing[0]) or not _numbers([spec.get("from", 0), spec.get("to", 0), spec.get("rise", 0), spec.get("above", 0)]):
			push_error("[NearForeground] %s 的 anchor、pieces、spacing、from、to、rise、above 有誤，這一排不放" % label)
			continue
		var usable: Array[String] = []
		for id: Variant in ids:
			var piece: Variant = pieces.get(str(id))
			if typeof(piece) != TYPE_DICTIONARY or str((piece as Dictionary).get("anchor", "")) != anchor:
				push_error("[NearForeground] %s 的零件 %s 不存在或不是 %s 用的，略過" % [label, id, anchor])
				continue
			usable.append(str(id))
		if usable.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:%d" % [where, index])
		var x := float(spec.get("from", 0)) * tile_size + rng.randf_range(0.0, float(spacing[0]))
		var end := float(spec.get("to", 0)) * tile_size
		var rise := minf(float(spec.get("rise", CALF_RISE)), CALF_RISE)
		var above := float(spec.get("above", DEFAULT_ABOVE))
		while x < end:
			var id := usable[rng.randi() % usable.size()]
			var info := _piece_info(pieces[id] as Dictionary, id, label)
			if info.is_empty():
				x += float(spacing[1])
				continue
			var width: float = info["width"]
			var height: float = info["height"]
			if x + width > end:
				break
			var span_low := INF
			var span_high := -INF
			# 捲動時零件會左右偏 MAX_DRIFT 以內：檢查的範圍包含偏移。
			var probe := x - MAX_DRIFT
			while probe <= x + width + MAX_DRIFT:
				var floor_y := float(surface_y.call(probe))
				span_low = minf(span_low, floor_y)
				span_high = maxf(span_high, floor_y)
				probe += tile_size * 0.5
			var combat := _near_enemy(x, width, enemy_x)
			var rect := Rect2()
			if anchor == "bottom":
				if span_high - span_low > FLAT_TOLERANCE or not is_finite(span_low):
					x += width + rng.randf_range(float(spacing[0]), float(spacing[1]))
					continue
				var shown := minf(rise, COMBAT_RISE) if combat else rise
				rect = Rect2(x, span_low - shown, width, height)
			else:
				# 從最高的走道往上 above 垂下來；底邊要離那條走道至少 HEAD_CLEAR。
				if combat or not is_finite(span_low) or span_high - span_low > FLAT_TOLERANCE or above - height < HEAD_CLEAR:
					x += width + rng.randf_range(float(spacing[0]), float(spacing[1]))
					continue
				rect = Rect2(x, span_low - above, width, height)
			result.append({"id": id, "anchor": anchor, "rect": rect, "texture": info["texture"], "region": info["region"],
				"flip_v": info["flip_v"], "sway": info["sway"]})
			x += width + rng.randf_range(float(spacing[0]), float(spacing[1]))
	return result


static func _piece_info(piece: Dictionary, id: String, label: String) -> Dictionary:
	var texture := RigLibrary.optional_texture(str(piece.get("texture", "")))
	var width := float(piece.get("width", 0.0)) if typeof(piece.get("width")) in [TYPE_INT, TYPE_FLOAT] else 0.0
	if texture == null or width < 4.0:
		push_error("[NearForeground] %s 的零件 %s 沒有貼圖或寬度（%s），略過" % [label, id, piece.get("texture", "")])
		return {}
	var region := Rect2(Vector2.ZERO, texture.get_size())
	var raw_region: Variant = piece.get("region")
	if typeof(raw_region) == TYPE_ARRAY and (raw_region as Array).size() == 4 and _numbers(raw_region as Array):
		var size := texture.get_size()
		region = Rect2(float(raw_region[0]) * size.x, float(raw_region[1]) * size.y, float(raw_region[2]) * size.x, float(raw_region[3]) * size.y)
	if region.size.x < 1.0 or region.size.y < 1.0:
		push_error("[NearForeground] %s 的零件 %s 的 region 無效，略過" % [label, id])
		return {}
	var sway := float(piece.get("sway", 0.0)) if typeof(piece.get("sway")) in [TYPE_INT, TYPE_FLOAT] else 0.0
	return {"texture": texture, "region": region, "width": width, "height": width * region.size.y / region.size.x,
		"flip_v": piece.get("flip_v", false) == true, "sway": clampf(sway, 0.0, 8.0)}


static func _near_enemy(x: float, width: float, enemy_x: PackedFloat32Array) -> bool:
	for enemy in enemy_x:
		if enemy > x - COMBAT_REACH and enemy < x + width + COMBAT_REACH:
			return true
	return false


static func _numbers(values: Array) -> bool:
	for value: Variant in values:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return true


## 依排好的位置建立剪影。fill 是剪影的顏色，rim 是邊緣光的顏色，rim_direction 是主光（或輪廓光）所在的方向。
func build(placements: Array[Dictionary], fill: Color, rim: Color, rim_direction: Vector2) -> void:
	name = "NearForeground"
	z_as_relative = false
	z_index = WorldLayers.NEAR_FOREGROUND
	for entry in placements:
		var sprite := Sprite2D.new()
		var texture: Texture2D = entry["texture"]
		var region: Rect2 = entry["region"]
		var rect: Rect2 = entry["rect"]
		sprite.texture = texture
		sprite.centered = false
		sprite.region_enabled = region.size != texture.get_size() or region.position != Vector2.ZERO
		sprite.region_rect = region
		sprite.flip_v = entry["flip_v"]
		var scale_factor := rect.size.x / region.size.x
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.position = rect.position
		var sway: float = entry["sway"]
		sprite.material = _material(sway, entry["anchor"] == "top", fill, rim, rim_direction)
		sprite.set_instance_shader_parameter(&"rim_texels", RIM_WIDTH / scale_factor)
		add_child(sprite)
		_sprites.append(sprite)
		_base_x.append(rect.position.x)
		_half_width.append(rect.size.x * 0.5)
		if sway > 0.0:
			var kick := SwayKick.attach(sprite, [sprite], Rect2(Vector2.ZERO, region.size), sway)
			if kick != null:
				_kicks.append(kick)
	Settings.display_changed.connect(_apply_motion)
	_apply_motion()


func _material(sway: float, hang: bool, fill: Color, rim: Color, rim_direction: Vector2) -> ShaderMaterial:
	for i in _materials.size():
		if is_equal_approx(_swaying[i], sway) and _materials[i].get_shader_parameter(&"hang") == hang:
			return _materials[i]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"fill_color", fill)
	material.set_shader_parameter(&"rim_color", rim)
	material.set_shader_parameter(&"rim_direction", rim_direction.normalized() if rim_direction.length_squared() > 0.0001 else Vector2(0.6, -0.8))
	material.set_shader_parameter(&"hang", hang)
	material.set_shader_parameter(&"amplitude", sway)
	_materials.append(material)
	_swaying.append(sway)
	return material


## 「減少動態」或低畫質：風吹與被帶動都停掉（剪影本身照畫）。
func _apply_motion() -> void:
	var still := Settings.get_reduce_ui_motion() or LightQuality.tier() == LightQuality.Tier.LOW
	for i in _materials.size():
		_materials[i].set_shader_parameter(&"amplitude", 0.0 if still else _swaying[i])
	for kick in _kicks:
		if is_instance_valid(kick):
			kick.set_deferred(&"monitoring", not still)


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera_x := (viewport.get_canvas_transform().affine_inverse() * (viewport.get_visible_rect().size * 0.5)).x
	if absf(camera_x - _last_camera_x) < 0.5:
		return
	_last_camera_x = camera_x
	for i in _sprites.size():
		_sprites[i].position.x = _base_x[i] - drift_at(camera_x, _base_x[i] + _half_width[i])


## 鏡頭中心在 camera_x 時，中心在 piece_x 的零件往左偏多少（鏡頭往右走，近前景走得更快）。
static func drift_at(camera_x: float, piece_x: float) -> float:
	return clampf((camera_x - piece_x) * DRIFT, -MAX_DRIFT, MAX_DRIFT)
