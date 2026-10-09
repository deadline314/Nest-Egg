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
		# surface_heights is the first solid from above (rain/roof), not a walkable floor.
		var surface := ground_surface(layout, center)
		if surface == INF:
			return {}
		bottom = surface + ScenerySupport.ground_offset(prop.id, prop.size.y)
	if str(entry.get("support", "")) == "ceiling" and entry.has("ceiling_row"):
		bottom = float(int(entry["ceiling_row"]) * tile) + prop.size.y
	bottom += float(entry.get("dy", 0.0))
	var left := float(column * tile) + float(entry.get("dx", 0.0))
	return {"rect": Rect2(Vector2(left, bottom - prop.size.y), prop.size), "flip": bool(entry.get("flip", false))}


static func ground_surface(layout: LevelLayout, column: int) -> float:
	for row in range(1, layout.height):
		if layout.cell(column, row) in ["#", "=", "~"] and layout.cell(column, row - 1) != "#":
			return float(row * layout.tile_size)
	return INF
