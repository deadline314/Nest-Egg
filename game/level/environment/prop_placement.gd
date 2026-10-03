class_name PropPlacement
extends RefCounted
## 道具擺放的換算：地圖 JSON 的一筆 props（格座標）→ 世界座標的矩形。Level 生成道具與測試共用同一份邏輯。


## 回傳 {"rect": Rect2（世界座標）, "flip": bool}；站在地表但該欄下方沒有地表時回傳空字典。
static func resolve(entry: Dictionary, prop: PropData, layout: LevelLayout) -> Dictionary:
	var tile := layout.tile_size
	var column := int(entry["x"])
	var bottom := float((int(entry.get("y", 0)) + 1) * tile)
	if bool(entry.get("ground", false)):
		var center := clampi(column + int(prop.size.x / float(tile) * 0.5), 0, layout.width - 1)
		var surface := layout.surface_heights[center]
		if surface == INF:
			return {}
		bottom = surface
	bottom += float(entry.get("dy", 0.0))
	var left := float(column * tile) + float(entry.get("dx", 0.0))
	return {"rect": Rect2(Vector2(left, bottom - prop.size.y), prop.size), "flip": bool(entry.get("flip", false))}
