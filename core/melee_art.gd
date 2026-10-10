class_name MeleeArt
extends RefCounted
## 近戰武器的外觀：用幾條線段描出剪影（刃、重錘、長柄、鞭），由武器資料的 melee_shape、melee_length、color 決定。
## 同一份線段有三種用途：角色手上與撿取物直接畫（draw）、背包卡片圖示（item_icon）、HUD 武器欄圖示（ammo_icon）。
## 沒有新增任何圖檔；以後有正式美術時，在 ItemIcons／AmmoIcons 的圖檔路徑放同名 PNG 即可，這裡只是缺圖時的程式繪製。

const ITEM_SIZE := Vector2i(64, 24)
const AMMO_SIZE := Vector2i(40, 56)
const STEEL := Color(0.62, 0.68, 0.74)
const GRIP := Color(0.2, 0.22, 0.26)
const WHIP_SEGMENTS := 10

static var _cache: Dictionary = {}


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


## 畫在 CanvasItem 上：from 是握把位置、direction 是刃尖朝向（單位向量）；glow 是發光亮度（>1 會帶泛光，呼叫端自己限制上限）。
static func draw(item: CanvasItem, from: Vector2, direction: Vector2, weapon: WeaponData, glow := 1.4) -> void:
	var xf := Transform2D(direction.angle(), from)
	for seg in segments(weapon):
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
	var list := segments(weapon)
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var xf := Transform2D(angle, Vector2.ZERO)
	for seg in list:
		for p: Vector2 in [seg["a"], seg["b"]]:
			var q := xf * p
			min_p = min_p.min(q)
			max_p = max_p.max(q)
	var extent := max_p - min_p
	var fit := minf((size.x - 6.0) / maxf(1.0, extent.x), (size.y - 6.0) / maxf(1.0, extent.y))
	fit = minf(fit, 3.0)
	var offset := Vector2(size) * 0.5 - (min_p + extent * 0.5) * fit
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
