class_name NearForeground
extends Node2D
## 近前景（BG-68、BG-71）：畫在角色前面、不透明、比走道最暗處還暗的剪影。
## 走道外緣：一條連續的底座（欄杆、花台邊、路緣與矮樁）把整段串起來，上面再放大小不一、互相壓一點的物件（玫瑰叢、花台）；
## 高架段（走道比區域地面高出 DECK_RISE 以上，底下是空的）不放圍欄，改放橋面下的鋼樑、托架、垂下的纜線與走道邊的矮樁。
## 畫面上緣：垂下來的纜線、燈籠串、枝葉。亮邊只在朝主光的上緣、細細一條，細的網格與線條本身不吃亮邊；
## 亮邊強度是區段資料（地圖的 "near_foreground_rim"，沒寫時有主光 0.45、沒有主光 0.12）。
## 資料：地圖 JSON 頂層的 "near_foreground"（每一排：anchor、pieces、base、deck_pieces、deck_base、rise 或 above、spacing、scale、from、to），
## 零件在 LIBRARY_PATH（貼圖零件只取形狀；"strip" 零件由程式畫成連續的一段）。
## 零件庫的 "needs_sky": true 標記枝葉這種壓在深色背景上會糊掉的垂掛物：地圖要把它放在後面是天空的欄位
## （tools/scenarios/sky_behind_scenario.gd 掃描每一欄後面的亮度並檢查實際放的位置）。
##
## 判讀優先：走道那排最多只露出小腿高（CALF_RISE），戰鬥範圍（敵人出生點附近）更矮；垂掛物的底邊離下面最高的走道
## 至少 HEAD_CLEAR，戰鬥範圍不放。放不下就略過那一件。規則集中在 plan()，遊戲與自動檢查用同一份。
## 貼圖零件比走道捲動得略快（DRIFT，最多 MAX_DRIFT 像素）；連續的底座固定在走道邊上（跟著走道，不越過階梯的邊）。
## 垂掛物被風吹、被經過的角色帶動，「減少動態」或低畫質時靜止；三個畫質都畫（它是構圖不是特效）。靜止時只有鏡頭移動才更新位置。

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
## 走道比區域的地面高出這麼多就算高架段（底下是空的）。
const DECK_RISE := 48.0
## 底座最短多長才畫。
const MIN_STRIP := 24.0
## 邊緣光的寬度（遊戲像素）與預設強度（有主光／沒有主光）。
const RIM_WIDTH := 1.0
const RIM_KEYED := 0.45
const RIM_PLAIN := 0.12
const MAX_RIM := 1.0

static var _library: Dictionary = {}
static var _library_loaded := false

var _drifting: Array[Node2D] = []
var _base_x := PackedFloat32Array()
var _half_width := PackedFloat32Array()
var _kicks: Array[SwayKick] = []
var _materials: Array[ShaderMaterial] = []
var _material_keys: Array[String] = []
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


## 依資料排出每一件的位置（不建立節點）。貼圖零件：{id, anchor, rect, texture, region, flip_v, sway, rim_all}；
## 底座：{id, anchor: "bottom", strip: true, rect, seed}。surface_y(x) 回傳 x 處最高可走地面的 y；ground_y 是區域的地面高度
## （用來分出高架段）；enemy_x 是敵人出生點；where 用在錯誤訊息。不合規則的擺放直接略過；資料本身壞掉才記錯誤。
static func plan(rows: Variant, surface_y: Callable, enemy_x: PackedFloat32Array, tile_size: float, where: String, ground_y := INF) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if rows == null:
		return result
	if typeof(rows) != TYPE_ARRAY:
		push_error("[NearForeground] %s 的 near_foreground 必須是陣列" % where)
		return result
	for index in (rows as Array).size():
		var row: Variant = rows[index]
		var label := "%s near_foreground[%d]" % [where, index]
		if typeof(row) != TYPE_DICTIONARY:
			push_error("[NearForeground] %s 必須是物件" % label)
			continue
		var spec := row as Dictionary
		var anchor := str(spec.get("anchor", ""))
		var spacing: Variant = spec.get("spacing", [80, 160])
		var scale_range: Variant = spec.get("scale", [0.8, 1.2])
		if anchor not in ["bottom", "top"] or typeof(spacing) != TYPE_ARRAY or (spacing as Array).size() != 2 or not _numbers(spacing as Array) \
				or float(spacing[1]) < float(spacing[0]) or typeof(scale_range) != TYPE_ARRAY or (scale_range as Array).size() != 2 \
				or not _numbers(scale_range as Array) or float(scale_range[0]) <= 0.1 or float(scale_range[1]) < float(scale_range[0]) \
				or not _numbers([spec.get("from", 0), spec.get("to", 0), spec.get("rise", 0), spec.get("above", 0)]):
			push_error("[NearForeground] %s 的 anchor、spacing、scale、from、to、rise、above 有誤，這一排不放" % label)
			continue
		var ground_pieces := _usable(spec.get("pieces", []), anchor, false, label)
		var deck_pieces := _usable(spec.get("deck_pieces", []), anchor, false, label)
		var ground_base := _usable(spec.get("base", []), anchor, true, label)
		var deck_base := _usable(spec.get("deck_base", []), anchor, true, label)
		if ground_pieces.is_empty() and deck_pieces.is_empty() and ground_base.is_empty() and deck_base.is_empty():
			push_error("[NearForeground] %s 沒有可用的零件，這一排不放" % label)
			continue
		var from := float(spec.get("from", 0)) * tile_size
		var to := float(spec.get("to", 0)) * tile_size
		if anchor == "bottom" and not (ground_base.is_empty() and deck_base.is_empty()):
			_plan_strips(result, ground_base, deck_base, from, to, surface_y, enemy_x, tile_size, ground_y, float(spec.get("rise", CALF_RISE)), where, index)
		if ground_pieces.is_empty() and deck_pieces.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s:%d" % [where, index])
		var x := from + rng.randf_range(0.0, maxf(0.0, float(spacing[0])))
		var rise := minf(float(spec.get("rise", CALF_RISE)), CALF_RISE)
		var above := float(spec.get("above", DEFAULT_ABOVE))
		while x < to:
			var floor_here := float(surface_y.call(x))
			var deck := is_finite(ground_y) and floor_here < ground_y - DECK_RISE
			var choices := deck_pieces if deck else ground_pieces
			if choices.is_empty():
				x += tile_size
				continue
			var id := choices[rng.randi() % choices.size()]
			var info := _piece_info(library()[id] as Dictionary, id, label)
			if info.is_empty():
				x += maxf(tile_size, float(spacing[1]))
				continue
			var grow := rng.randf_range(float(scale_range[0]), float(scale_range[1]))
			var width: float = info["width"] * grow
			var height: float = info["height"] * grow
			if x + width > to:
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
			var advance := width + rng.randf_range(float(spacing[0]), float(spacing[1]))
			if anchor == "bottom":
				if span_high - span_low > FLAT_TOLERANCE or not is_finite(span_low):
					x += maxf(tile_size, advance)
					continue
				var shown := minf(rise, COMBAT_RISE) if combat else rise
				# 大小不一的物件露出的高度也不同（較小的露出得少），輪廓才不會是一條直線。
				shown = minf(shown, shown * clampf(grow, 0.6, 1.0) + 2.0)
				rect = Rect2(x, span_low - shown, width, height)
			else:
				# 從最高的走道往上 above 垂下來；底邊要離那條走道至少 HEAD_CLEAR。
				if combat or not is_finite(span_low) or span_high - span_low > FLAT_TOLERANCE or above - height < HEAD_CLEAR:
					x += maxf(tile_size, advance)
					continue
				rect = Rect2(x, span_low - above, width, height)
			result.append({"id": id, "anchor": anchor, "rect": rect, "texture": info["texture"], "region": info["region"],
				"flip_v": info["flip_v"], "sway": info["sway"], "rim_all": info["rim_all"]})
			# 間隔可以是負的：相鄰的物件互相壓住一點，連成一段。
			x += maxf(width * 0.35, advance)
	return result


## 連續的底座：沿著走道把「平、同一種地形（地面或高架）、同一種戰鬥狀態」的一段畫成一條。
static func _plan_strips(result: Array[Dictionary], ground_base: Array[String], deck_base: Array[String], from: float, to: float,
		surface_y: Callable, enemy_x: PackedFloat32Array, tile_size: float, ground_y: float, row_rise: float, where: String, index: int) -> void:
	var step := tile_size * 0.5
	var start := from
	var start_y := float(surface_y.call(from))
	var start_deck := is_finite(ground_y) and start_y < ground_y - DECK_RISE
	var start_combat := _near_enemy(from, step, enemy_x)
	var x := from + step
	while x <= to + 0.01:
		var y := float(surface_y.call(minf(x, to - 0.01)))
		var deck := is_finite(ground_y) and y < ground_y - DECK_RISE
		var combat := _near_enemy(x, step, enemy_x)
		var ended := x >= to - 0.01
		if ended or absf(y - start_y) > FLAT_TOLERANCE or deck != start_deck or combat != start_combat:
			var end := minf(x, to)
			if end - start >= MIN_STRIP and is_finite(start_y):
				for id in (deck_base if start_deck else ground_base):
					var info := library()[id] as Dictionary
					var rise := minf(minf(float(info.get("rise", 8)), row_rise), COMBAT_RISE if start_combat else CALF_RISE)
					var depth := float(info.get("depth", 12))
					result.append({"id": id, "anchor": "bottom", "strip": true, "seed": hash("%s:%d:%d" % [where, index, int(start)]),
						"rect": Rect2(start, start_y - rise, end - start, rise + depth)})
			start = x
			start_y = y
			start_deck = deck
			start_combat = combat
		x += step


static func _usable(ids: Variant, anchor: String, strips: bool, label: String) -> Array[String]:
	var usable: Array[String] = []
	if typeof(ids) != TYPE_ARRAY:
		push_error("[NearForeground] %s 的零件清單必須是陣列" % label)
		return usable
	for id: Variant in ids:
		var piece: Variant = library().get(str(id))
		if typeof(piece) != TYPE_DICTIONARY or str((piece as Dictionary).get("anchor", "")) != anchor or ((piece as Dictionary).get("strip", false) == true) != strips:
			push_error("[NearForeground] %s 的零件 %s 不存在、不是 %s 用的，或放錯清單（底座放 base／deck_base），略過" % [label, id, anchor])
			continue
		usable.append(str(id))
	return usable


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
		"flip_v": piece.get("flip_v", false) == true, "sway": clampf(sway, 0.0, 8.0), "rim_all": piece.get("rim_all", false) == true}


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


## 依排好的位置建立剪影。fill 是剪影的顏色，rim 是邊緣光的顏色，rim_strength 是亮邊強度（區段資料），
## light_side 是主光在左（-1）還是右（1）：亮邊只在上緣，稍微偏向主光那一側。
func build(placements: Array[Dictionary], fill: Color, rim: Color, rim_strength: float, light_side: float) -> void:
	name = "NearForeground"
	z_as_relative = false
	z_index = WorldLayers.NEAR_FOREGROUND
	var rim_direction := Vector2(0.35 * signf(light_side), -1.0).normalized()
	for entry in placements:
		var rect: Rect2 = entry["rect"]
		if entry.get("strip", false) == true:
			var strip := _Strip.new()
			strip.shape = StringName(str(entry["id"]))
			strip.size = rect.size
			strip.position = rect.position
			strip.rise = float((library()[str(entry["id"])] as Dictionary).get("rise", 8))
			strip.seed_value = int(entry["seed"])
			strip.fill = fill
			strip.rim = Color(rim, clampf(rim_strength, 0.0, MAX_RIM))
			add_child(strip)
			continue
		var sprite := Sprite2D.new()
		var texture: Texture2D = entry["texture"]
		var region: Rect2 = entry["region"]
		sprite.texture = texture
		sprite.centered = false
		sprite.region_enabled = region.size != texture.get_size() or region.position != Vector2.ZERO
		sprite.region_rect = region
		sprite.flip_v = entry["flip_v"]
		var scale_factor := rect.size.x / region.size.x
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.position = rect.position
		var sway: float = entry["sway"]
		sprite.material = _material(sway, entry["anchor"] == "top", entry.get("rim_all", false) == true, fill, rim, rim_strength, rim_direction)
		sprite.set_instance_shader_parameter(&"rim_texels", RIM_WIDTH / scale_factor)
		add_child(sprite)
		_drifting.append(sprite)
		_base_x.append(rect.position.x)
		_half_width.append(rect.size.x * 0.5)
		if sway > 0.0:
			var kick := SwayKick.attach(sprite, [sprite], Rect2(Vector2.ZERO, region.size), sway)
			if kick != null:
				_kicks.append(kick)
	Settings.display_changed.connect(_apply_motion)
	_apply_motion()


## 會被風吹、被角色帶動的垂掛物有幾件（給檢查用）。
func swaying_count() -> int:
	return _kicks.size()


func _material(sway: float, hang: bool, rim_all: bool, fill: Color, rim: Color, rim_strength: float, rim_direction: Vector2) -> ShaderMaterial:
	var key := "%.3f:%s:%s" % [sway, hang, rim_all]
	var found := _material_keys.find(key)
	if found >= 0:
		return _materials[found]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"fill_color", fill)
	material.set_shader_parameter(&"rim_color", rim)
	material.set_shader_parameter(&"rim_direction", rim_direction)
	material.set_shader_parameter(&"rim_strength", clampf(rim_strength, 0.0, MAX_RIM))
	material.set_shader_parameter(&"rim_all_sides", rim_all)
	material.set_shader_parameter(&"hang", hang)
	material.set_shader_parameter(&"amplitude", sway)
	_materials.append(material)
	_material_keys.append(key)
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
	for i in _drifting.size():
		_drifting[i].position.x = _base_x[i] - drift_at(camera_x, _base_x[i] + _half_width[i])


## 鏡頭中心在 camera_x 時，中心在 piece_x 的零件往左偏多少（鏡頭往右走，近前景走得更快）。
static func drift_at(camera_x: float, piece_x: float) -> float:
	return clampf((camera_x - piece_x) * DRIFT, -MAX_DRIFT, MAX_DRIFT)


## 連續的底座（程式繪製、只畫一次）：rect 的上緣是露出地面的最高點，往下延伸到走道邊下方。
## railing：一排高低略有差異的立柱與上、中兩道橫桿；planter_edge：有唇口的連續花台邊（在走道面下方，不蓋走道的亮邊）；
## curb_bollards：走道面下方的路緣加一排冒出地面的矮樁；deck_beam：高架橋面下的鋼樑、三角托架與垂下的纜線。
## 亮邊只畫在朝上的面，一像素寬。
class _Strip:
	extends Node2D

	var shape: StringName
	var size := Vector2.ZERO
	var rise := 8.0
	var seed_value := 0
	var fill := Color.BLACK
	var rim := Color(1, 1, 1, 0.2)
	## 花台細節（唇口的面、接縫）比剪影亮多少（往主光色混；HDR 2D 把顏色轉成線性，暗的值看起來更暗，所以要比感覺高）；
	## 排水口的大小；托架往下伸多長（進到地面剖面的橋面樑）。
	const DETAIL_MIX := 0.2
	const NOTCH := Vector2(4.0, 4.0)
	const BRACKET := 8.0

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		match shape:
			&"railing":
				_railing(rng)
			&"planter_edge":
				_planter(rng)
			&"curb_bollards":
				_bollards(rng)
			&"deck_beam":
				_beam(rng)
			_:
				draw_rect(Rect2(Vector2(0, size.y - 4.0), Vector2(size.x, 4.0)), fill)

	func _top(from: Vector2, to: Vector2) -> void:
		if rim.a > 0.0:
			draw_line(from, to, rim, 1.0)

	func _railing(rng: RandomNumberGenerator) -> void:
		var top := 1.0
		draw_rect(Rect2(0, top, size.x, 2.0), fill)
		draw_rect(Rect2(0, top + rise * 0.55, size.x, 1.0), fill)
		_top(Vector2(0, top), Vector2(size.x, top))
		var x := rng.randf_range(2.0, 10.0)
		while x < size.x - 2.0:
			var cap := rng.randf_range(-1.0, 2.0)
			# 立柱站在走道面上、不往下穿過走道邊（走道邊緣下方那一帶要留給地面的亮邊對比）。
			draw_rect(Rect2(x, top - cap, 2.5, minf(size.y, rise) - top + cap), fill)
			_top(Vector2(x, top - cap), Vector2(x + 2.5, top - cap))
			x += rng.randf_range(18.0, 28.0)

	func _planter(rng: RandomNumberGenerator) -> void:
		# 一條連續的花台（BG-73）：唇口一段一段有些微高低、比身體略亮的一個面；段與段之間一條接縫；
		# 身體下緣每段切一兩個排水口（看得到後面的地面剖面）；每隔一個接縫一個三角托架往下伸進地面剖面的橋面樑，
		# 花台看起來是架在下面的結構上，不是浮著的一條黑帶。細節只比剪影亮一點，不搶走道。
		var lip := 3.0
		var face := fill.lerp(Color(rim, 1.0), DETAIL_MIX)
		var seam := fill.lerp(Color(rim, 1.0), DETAIL_MIX * 1.6)
		var x := 0.0
		var joint := 0
		while x < size.x:
			var length := minf(rng.randf_range(38.0, 64.0), size.x - x)
			var lift := rng.randf_range(0.0, 1.5)
			# 身體：下緣切出排水口（不畫那一小格，後面的結構露出來）。
			var notch_count := 1 if length < 50.0 else 2
			var cuts: Array[float] = []
			for k in notch_count:
				cuts.append(x + length * (float(k) + 1.0) / (notch_count + 1.0) - NOTCH.x * 0.5)
			var from := x
			for cut in cuts:
				draw_rect(Rect2(from, lip, cut - from, size.y - lip), fill)
				draw_rect(Rect2(cut, lip, NOTCH.x, size.y - lip - NOTCH.y), fill)
				from = cut + NOTCH.x
			draw_rect(Rect2(from, lip, x + length - from, size.y - lip), fill)
			# 唇口：略亮的面、上緣亮邊、下緣一條陰影。身體保持剪影色：走道邊緣下方那一帶要暗，邊緣才讀得出來。
			draw_rect(Rect2(x, lift, length, lip + 1.0), face)
			draw_line(Vector2(x, lip + 1.5), Vector2(x + length, lip + 1.5), fill, 1.0)
			_top(Vector2(x, lift), Vector2(x + length, lift))
			# 接縫與托架（不在最左邊的起點）。
			if x > 0.0:
				draw_line(Vector2(x, lip + 1.0), Vector2(x, size.y), seam, 1.0)
				if joint % 2 == 0:
					draw_colored_polygon(PackedVector2Array([Vector2(x - 5.0, size.y - 1.0), Vector2(x + 5.0, size.y - 1.0),
						Vector2(x + 1.5, size.y + BRACKET), Vector2(x - 1.5, size.y + BRACKET)]), fill)
					draw_circle(Vector2(x, size.y + 2.0), 1.0, seam)
				joint += 1
			x += length

	func _bollards(rng: RandomNumberGenerator) -> void:
		# 路緣在走道面的下面一點（走道的亮邊照樣看得到），只有矮樁冒出地面。
		var curb_top := rise + 1.0
		draw_rect(Rect2(0, curb_top, size.x, maxf(0.0, size.y - curb_top)), fill)
		var x := rng.randf_range(4.0, 16.0)
		while x < size.x - 6.0:
			var height := rise + 1.0 - rng.randf_range(0.0, 2.5)
			var top := curb_top - height
			draw_rect(Rect2(x, top + 1.5, 5.0, height), fill)
			draw_circle(Vector2(x + 2.5, top + 2.0), 2.5, fill)
			_top(Vector2(x + 1.0, top - 0.5), Vector2(x + 4.0, top - 0.5))
			x += rng.randf_range(26.0, 42.0)

	func _beam(rng: RandomNumberGenerator) -> void:
		# rect 的上緣在走道下方：上面一道鋼樑，往下每隔一段一個三角托架，托架之間垂著一兩條纜線。
		var beam := 6.0
		draw_rect(Rect2(0, 0, size.x, beam), fill)
		var x := rng.randf_range(10.0, 30.0)
		var last := 0.0
		while x < size.x - 6.0:
			var drop := rng.randf_range(12.0, 18.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 6.0, beam), Vector2(x + 6.0, beam), Vector2(x + 1.5, beam + drop), Vector2(x - 1.5, beam + drop)]), fill)
			if rng.randf() < 0.7:
				_cable(Vector2(last, beam + 2.0), Vector2(x, beam + 2.0), rng.randf_range(8.0, minf(22.0, size.y - beam - 2.0)))
			last = x
			x += rng.randf_range(44.0, 64.0)

	func _cable(from: Vector2, to: Vector2, sag: float) -> void:
		var points := PackedVector2Array()
		for i in 9:
			var t := float(i) / 8.0
			points.append(from.lerp(to, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
		draw_polyline(points, fill, 1.5)
