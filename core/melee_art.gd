class_name MeleeArt
extends RefCounted
## 近戰武器的外觀。三種用途共用同一份：角色手上與撿取物直接畫（draw）、背包卡片圖示（item_icon）、HUD 武器欄圖示（ammo_icon），
## 所以三處看得出是同一把。
## 有圖的武器（NE-260，data/weapon_art/melee.json，由 tools/assets/melee_art.py 產生）畫圖加發光層：握把對在手上、刃尖朝揮的方向，
## 握把位置與長度和線條版相同。沒有圖、圖遺失或資料壞掉時記錄是哪一把，退回用幾條線段描出的剪影（segments，
## 由武器資料的 melee_shape、melee_length、color 決定）；衝刺殘影的剪影也用這份線段。
## 鞭子只有握把是圖，發光的細線仍然用線段畫（會甩動的東西不適合做成一張圖）。

const ITEM_SIZE := Vector2i(64, 24)
const AMMO_SIZE := Vector2i(40, 56)
const STEEL := Color(0.62, 0.68, 0.74)
const GRIP := Color(0.2, 0.22, 0.26)
const WHIP_SEGMENTS := 10

const ART_PATH := "res://data/weapon_art/melee.json"

static var _cache: Dictionary = {}
## 武器 id → {texture, glow（可能是 null）, size, grip, light}；沒有圖的武器沒有這一筆。
static var _art: Dictionary = {}
static var _art_loaded := false
static var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _quad_uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
static var _quad_color := PackedColorArray([Color.WHITE])


## 線段清單：每筆 {a, b, w（粗細）, c（顏色）, glow（是否發光）}；座標以握把為原點、刃尖朝 +x。
static func segments(weapon: WeaponData) -> Array[Dictionary]:
	var length := maxf(6.0, weapon.melee_length)
	var tint := weapon.color
	var out: Array[Dictionary] = []
	match weapon.melee_shape:
		"heavy":
			# 連續柄穿入槌頭；握把跨手腕前後，避免只在手後方畫一段暗線。
			out.append(_seg(-5.0, 0.0, length * 0.86, 0.0, 3.2, GRIP.darkened(0.2), false))
			out.append(_seg(-5.0, 0.0, length * 0.86, 0.0, 2.2, STEEL, false))
			out.append(_seg(2.5, -0.55, length * 0.82, -0.55, 0.65, STEEL.lightened(0.35), false))
			out.append(_seg(length * 0.68, -1.7, length * 0.68, 1.7, 2.4, GRIP, false))
			out.append(_seg(length * 0.68, -1.2, length * 0.68, 1.2, 1.0, STEEL, false))
			# 外殼、內側平面與斜邊分開；液壓縫保持暗色，不把整個槌頭發光。
			out.append(_seg(length * 0.86, -5.5, length * 0.86, 5.5, length * 0.3, STEEL.darkened(0.15), false))
			out.append(_seg(length * 0.86, -4.4, length * 0.86, 4.4, length * 0.23, STEEL.lightened(0.12), false))
			out.append(_seg(length * 0.75, -4.4, length * 0.97, -4.4, 0.8, STEEL.lightened(0.4), false))
			out.append(_seg(length * 0.75, 4.4, length * 0.97, 4.4, 0.8, STEEL.darkened(0.35), false))
			out.append(_seg(length * 0.8, 0.0, length * 0.94, 0.0, 0.8, GRIP, false))
			out.append(_seg(length * 0.98, -3.7, length * 0.98, 3.7, 1.0, tint, true))
			out.append(_seg(-4.0, 0.0, 3.0, 0.0, 3.0, GRIP, false))
			out.append(_seg(-2.5, -0.8, 1.5, -0.8, 0.6, GRIP.lightened(0.2), false))
		"polearm":
			out.append(_seg(-length * 0.3, 0.0, length * 0.82, 0.0, 1.8, STEEL, false))
			out.append(_seg(length * 0.78, 0.0, length, 0.0, 3.0, tint, true))
			out.append(_seg(length * 0.74, -4.0, length * 0.9, 0.0, 1.4, tint, true))
			out.append(_seg(length * 0.74, 4.0, length * 0.9, 0.0, 1.4, tint, true))
			out.append(_seg(-3.0, 0.0, 3.0, 0.0, 2.6, GRIP, false))
		"whip":
			out.append(_seg(-5.0, 0.0, 3.0, 0.0, 2.8, GRIP, false))
			var previous := Vector2(3.0, 0.0)
			for i in range(1, WHIP_SEGMENTS + 1):
				var t := float(i) / WHIP_SEGMENTS
				var point := Vector2(3.0 + (length - 3.0) * t, sin(t * TAU * 1.25) * 3.5 * t)
				out.append({"a": previous, "b": point, "w": lerpf(1.8, 0.9, t), "c": tint, "glow": true})
				previous = point
		_:
			out.append(_seg(-4.0, 0.0, 0.0, 0.0, 2.6, GRIP, false))
			out.append(_seg(0.0, -3.0, 0.0, 3.0, 1.6, STEEL, false))
			out.append(_seg(0.0, 0.0, length, 0.0, 2.4, tint, true))
			out.append(_seg(1.0, -0.8, length - 1.0, -0.8, 0.8, Color.WHITE, true))
	return out


## 這把武器的圖：{texture, glow, size, grip, light}；沒有圖回傳空的。
static func art(weapon: WeaponData) -> Dictionary:
	_load_art()
	return _art.get(weapon.id, {}) if weapon != null else {}


## 這把武器的刃光：{radius 拿在手上的光池半徑、energy 亮度、swing 揮動時放大幾倍、at 光在刀身的哪裡（離握把多遠）}。
## 沒有設定回傳空的（沒有刃光）。
static func light_spec(weapon: WeaponData) -> Dictionary:
	return art(weapon).get("light", {})


## 畫在 CanvasItem 上：from 是握把位置、direction 是刃尖朝向（單位向量）；glow 是發光亮度（>1 會帶泛光，呼叫端自己限制上限）。
## 朝左時把圖上下對調，刃口才不會翻到上面。
## shade 是本體的明暗（0～1）：這個函式畫的東西不受場景光影響，暗的區域裡由呼叫端把本體壓暗，發光部位不受影響。
static func draw(item: CanvasItem, from: Vector2, direction: Vector2, weapon: WeaponData, glow := 1.4, shade := 1.0) -> void:
	var entry := art(weapon)
	var xf := Transform2D(direction.angle(), from)
	if not entry.is_empty():
		var size: Vector2 = entry["size"]
		var grip: Vector2 = entry["grip"]
		var down := Vector2(-direction.y, direction.x) * (-1.0 if direction.x < 0.0 else 1.0)
		var top_left := from - direction * grip.x - down * grip.y
		_quad[0] = top_left
		_quad[1] = top_left + direction * size.x
		_quad[2] = _quad[1] + down * size.y
		_quad[3] = top_left + down * size.y
		_quad_color[0] = Color(shade, shade, shade)
		item.draw_polygon(_quad, _quad_color, _quad_uv, entry["texture"])
		if entry["glow"] != null:
			_quad_color[0] = LightKit.glow(Color.WHITE, glow)
			item.draw_polygon(_quad, _quad_color, _quad_uv, entry["glow"])
		if weapon.melee_shape != "whip":
			return
	for seg in segments(weapon):
		# 有圖的鞭子：握把是圖，只補畫發光的細線。
		if not entry.is_empty() and not bool(seg["glow"]):
			continue
		var color: Color = seg["c"]
		if bool(seg["glow"]):
			color = LightKit.glow(color, glow)
		item.draw_line(xf * (seg["a"] as Vector2), xf * (seg["b"] as Vector2), color, float(seg["w"]))


## 背包卡片圖示（64×24）。
static func item_icon(weapon: WeaponData) -> Texture2D:
	return _icon("item", weapon, ITEM_SIZE, 0.0, 0.0)


## HUD 武器欄圖示（40×56）：斜著擺。電量空時變暗、偏低時偏紅（沿用彈種圖示的三種狀態）。
static func ammo_icon(weapon: WeaponData, state: AmmoIcons.State = AmmoIcons.State.FULL) -> Texture2D:
	return _icon("ammo%d" % state, weapon, AMMO_SIZE, -PI * 0.28, float(state))


static func _icon(kind: String, weapon: WeaponData, size: Vector2i, angle: float, state: float) -> Texture2D:
	var key := "%s/%s/%s/%s/%s" % [kind, weapon.id, weapon.melee_shape, weapon.melee_length, weapon.color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var entry := art(weapon)
	var list := segments(weapon)
	if not entry.is_empty():
		# 有圖的武器：圖示用同一張圖，線段只留鞭子發光的細線。
		list = list.filter(func(seg: Dictionary) -> bool: return weapon.melee_shape == "whip" and bool(seg["glow"]))
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var xf := Transform2D(angle, Vector2.ZERO)
	for seg in list:
		for p: Vector2 in [seg["a"], seg["b"]]:
			var q := xf * p
			min_p = min_p.min(q)
			max_p = max_p.max(q)
	if not entry.is_empty():
		var art_size: Vector2 = entry["size"]
		var art_grip: Vector2 = entry["grip"]
		for corner: Vector2 in [Vector2.ZERO, Vector2(art_size.x, 0.0), art_size, Vector2(0.0, art_size.y)]:
			var q := xf * (corner - art_grip)
			min_p = min_p.min(q)
			max_p = max_p.max(q)
	var extent := max_p - min_p
	var fit := minf((size.x - 6.0) / maxf(1.0, extent.x), (size.y - 6.0) / maxf(1.0, extent.y))
	fit = minf(fit, 3.0)
	var offset := Vector2(size) * 0.5 - (min_p + extent * 0.5) * fit
	if not entry.is_empty():
		_stamp_art(image, entry, xf, fit, offset, state)
	for seg in list:
		var color: Color = seg["c"]
		if state == float(AmmoIcons.State.EMPTY):
			color = color.darkened(0.7)
		elif state == float(AmmoIcons.State.LOW):
			color = color.lerp(Palette.DANGER, 0.6)
		_stamp_line(image, (xf * (seg["a"] as Vector2)) * fit + offset, (xf * (seg["b"] as Vector2)) * fit + offset, maxf(1.0, float(seg["w"]) * fit), color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## 把武器的圖縮放、旋轉後蓋到圖示上：圖示的每個像素反推回圖上的位置取色；發光層疊在上面。
static func _stamp_art(image: Image, entry: Dictionary, xf: Transform2D, fit: float, offset: Vector2, state: float) -> void:
	var source := _readable_image(entry["texture"])
	var glow := _readable_image(entry["glow"]) if entry["glow"] != null else null
	if source == null:
		return
	var art_size: Vector2 = entry["size"]
	var art_grip: Vector2 = entry["grip"]
	var per_unit := Vector2(source.get_size()) / art_size
	var back := xf.affine_inverse()
	for y in image.get_height():
		for x in image.get_width():
			var at := (back * ((Vector2(x + 0.5, y + 0.5) - offset) / fit) + art_grip) * per_unit
			if at.x < 0.0 or at.y < 0.0 or at.x >= source.get_width() or at.y >= source.get_height():
				continue
			var color := source.get_pixelv(Vector2i(at))
			if glow != null:
				var lit := glow.get_pixelv(Vector2i(at))
				color = color.lerp(Color(lit.r, lit.g, lit.b, 1.0), lit.a)
				color.a = maxf(color.a, lit.a)
			if color.a < 0.3:
				continue
			color.a = 1.0
			if state == float(AmmoIcons.State.EMPTY):
				color = color.darkened(0.7)
			elif state == float(AmmoIcons.State.LOW):
				color = color.lerp(Palette.DANGER, 0.6)
			image.set_pixel(x, y, color)


static func _readable_image(texture: Texture2D) -> Image:
	var image := texture.get_image() if texture != null else null
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


## 讀近戰武器的圖表。檔案不存在、格式不對、某一把的圖遺失時記錄一次，那一把退回線條。
static func _load_art() -> void:
	if _art_loaded:
		return
	_art_loaded = true
	if not FileAccess.file_exists(ART_PATH):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART_PATH))
	if not raw is Dictionary or not (raw as Dictionary).get("weapons") is Dictionary:
		push_error("[MeleeArt] 讀不到近戰武器的圖表：%s（全部改用線條）" % ART_PATH)
		return
	var weapons: Dictionary = raw["weapons"]
	for id: String in weapons:
		var entry: Variant = weapons[id]
		if not entry is Dictionary:
			push_error("[MeleeArt] %s 裡「%s」的資料不是物件，改用線條" % [ART_PATH, id])
			continue
		var path := str(entry.get("texture", ""))
		var size := _vec2(entry.get("size"))
		if not ResourceLoader.exists(path) or size.x <= 0.0 or size.y <= 0.0:
			push_error("[MeleeArt] 近戰武器「%s」的圖不存在或大小不對（%s），改用線條" % [id, path])
			continue
		var glow_path := str(entry.get("glow", ""))
		var light: Dictionary = entry.get("light", {}) if entry.get("light") is Dictionary else {}
		if not light.is_empty():
			light = light.duplicate()
			light["at"] = float(entry.get("glow_at", size.x * 0.5))
		_art[StringName(id)] = {
			"texture": load(path) as Texture2D,
			"glow": load(glow_path) as Texture2D if ResourceLoader.exists(glow_path) else null,
			"size": size,
			"grip": _vec2(entry.get("grip")),
			"light": light,
		}


static func _vec2(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) if value is Array and (value as Array).size() >= 2 else Vector2.ZERO


## 清掉讀過的圖表與圖示（測試用）。
static func clear_cache() -> void:
	_cache.clear()
	_art.clear()
	_art_loaded = false


static func _seg(ax: float, ay: float, bx: float, by: float, width: float, color: Color, glow: bool) -> Dictionary:
	return {"a": Vector2(ax, ay), "b": Vector2(bx, by), "w": width, "c": color, "glow": glow}


## 把粗線蓋到圖上（沿線每個像素蓋一個圓點；圖示很小，這樣最省事）。
static func _stamp_line(image: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := maxi(1, ceili(a.distance_to(b)))
	var radius := width * 0.5
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / steps)
		for y in range(floori(p.y - radius), ceili(p.y + radius) + 1):
			for x in range(floori(p.x - radius), ceili(p.x + radius) + 1):
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and Vector2(x + 0.5, y + 0.5).distance_to(p) <= radius + 0.3:
					image.set_pixel(x, y, color)
