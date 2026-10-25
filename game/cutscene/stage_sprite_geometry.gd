class_name StageSpriteGeometry
extends RefCounted
## 圖集的 region／pivot 使用原始畫布像素；匯入縮圖後仍保持同一舞台尺寸與支點。

const MAX_SOURCE := 8192.0


static func problem(def: Dictionary) -> String:
	if not def.has("region") and not def.has("pivot") and not def.has("parent_prop") and not def.has("anchor"):
		return ""
	if def.get("kind") != "sprite":
		return "region and pivot require a sprite layer"
	if def.has("parent_prop") or def.has("anchor"):
		if not def.get("id") is String or not String(def["id"]).is_valid_identifier() or not def.get("parent_prop") is String or not String(def["parent_prop"]).is_valid_identifier():
			return "anchored sprite requires named child and parent props"
		if def["parent_prop"] == def["id"]:
			return "sprite cannot anchor to itself"
		if not _tuple(def.get("anchor"), 2):
			return "sprite anchor must contain two finite parent-source pixels"
	var native := RigLibrary.texture_size(str(def.get("path", "")))
	if native.x <= 0.0 or native.y <= 0.0:
		return "sprite geometry requires an existing texture"
	var source: Variant = def.get("source_width", native.x)
	if not _number(source) or float(source) < 1.0 or float(source) > MAX_SOURCE:
		return "sprite source_width must be finite and within 1..8192"
	var canvas := native * (float(source) / native.x)
	var region := Rect2(Vector2.ZERO, canvas)
	if def.has("region"):
		var raw: Variant = def["region"]
		if not _tuple(raw, 4):
			return "sprite region must contain four finite numbers"
		region = Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
		if region.position.x < 0.0 or region.position.y < 0.0 or region.size.x <= 0.0 or region.size.y <= 0.0:
			return "sprite region must have a nonnegative origin and positive size"
		# 匯入時高度四捨五入可能相差不到一個原始像素。
		if region.end.x > canvas.x + 1.0 or region.end.y > canvas.y + 1.0:
			return "sprite region exceeds its source canvas"
	if def.has("pivot"):
		var raw: Variant = def["pivot"]
		if not _tuple(raw, 2):
			return "sprite pivot must contain two finite numbers"
		var pivot := Vector2(float(raw[0]), float(raw[1]))
		if pivot.x < 0.0 or pivot.y < 0.0 or pivot.x > region.size.x or pivot.y > region.size.y:
			return "sprite pivot must lie inside its selected region"
		if def.get("centered", false):
			return "sprite pivot and centered cannot be combined"
	return ""


static func source_frame(def: Dictionary) -> Rect2:
	var native := RigLibrary.texture_size(str(def.get("path", "")))
	var width: Variant = def.get("source_width", native.x)
	if native.x <= 0.0 or not _number(width) or float(width) <= 0.0:
		return Rect2()
	if def.has("region"):
		if not _tuple(def["region"], 4):
			return Rect2()
		var raw: Array = def["region"]
		return Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
	return Rect2(Vector2.ZERO, native * (float(width) / native.x))


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _tuple(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for component: Variant in value:
		if not _number(component):
			return false
	return true


static func apply(sprite: Sprite2D, source_width: float, region: Rect2, pivot: Vector2) -> void:
	if sprite.texture == null or source_width <= 0.0:
		return
	var ratio := float(sprite.texture.get_width()) / source_width
	if sprite.region_enabled:
		sprite.region_rect = Rect2(region.position * ratio, region.size * ratio)
		sprite.region_filter_clip_enabled = true
	sprite.offset = -pivot * ratio


## 畫布上的點轉為 Sprite 本地點；可供實際握點使用，無效或落在 region 外回傳 INF。
static func source_point(sprite: Sprite2D, point: Vector2, source_width: float, region: Rect2) -> Vector2:
	if sprite.texture == null or source_width <= 0.0 or not point.is_finite():
		return Vector2.INF
	if point.x < region.position.x or point.y < region.position.y or point.x > region.end.x or point.y > region.end.y:
		return Vector2.INF
	var ratio := float(sprite.texture.get_width()) / source_width
	var local := point * ratio + sprite.offset
	var size := Vector2(sprite.texture.get_size())
	if sprite.region_enabled:
		local -= region.position * ratio
		size = sprite.region_rect.size
	if sprite.centered:
		local -= size * 0.5
	return local
