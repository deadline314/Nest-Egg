class_name Midground
extends RefCounted
## 中景（BG-69）：立面與走道之間的一排靠牆物件（花台、回收桶、販賣機、貨箱），讓角色不是貼著一面平牆。
## 資料：地圖 JSON 頂層的 "midground"：{"pieces": [擺設 id], "spacing": [最小, 最大], "from": 欄, "to": 欄}。
## 物件用一般的場景擺設資料（站在地上、有接地陰影、經過同樣的支撐檢查），只是由這裡依規則排出位置：
## 只放在背後真的有立面的地方（靠牆，空曠的高台不放）、不和地圖上手擺的擺設重疊、不擋在出入口、人物、拾取物這類實體前面；密度有上限（MAX_PER_VIEW），
## 戰鬥範圍（敵人出生點附近）間隔加倍。畫的時候比角色暗一階（TINT）。規則集中在 plan()，遊戲與檢查共用。

## 比角色暗一階、比立面清楚。
const TINT := Color(0.74, 0.72, 0.74)
## 一個畫面寬（約 640 遊戲像素）裡最多幾件；戰鬥範圍最多幾件。
const VIEW_WIDTH := 640.0
const MAX_PER_VIEW := 5
const MAX_PER_VIEW_COMBAT := 2
## 物件之間至少隔多遠；離實體（出入口、人物、拾取物…）的中心至少多遠。
const MIN_GAP := 40.0
const ENTITY_CLEAR := 28.0
const COMBAT_REACH := 160.0


## 排出中景的擺設項目（和地圖 props 同一種格式，多一個 "midground": true）。
## taken 是地圖上手擺擺設的範圍；entity_x 是所有實體出生點的 x；enemy_x 是敵人出生點；where 用在錯誤訊息。
## walls 是立面的範圍（null 代表不檢查有沒有靠牆）。
static func plan(spec: Variant, layout: LevelLayout, dirs: PackedStringArray, taken: Array[Rect2], entity_x: PackedFloat32Array,
		enemy_x: PackedFloat32Array, where: String, walls: BackWallGeometry = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if spec == null:
		return result
	if typeof(spec) != TYPE_DICTIONARY:
		push_error("[Midground] %s 的 midground 必須是物件" % where)
		return result
	var data := spec as Dictionary
	var ids: Variant = data.get("pieces", [])
	var spacing: Variant = data.get("spacing", [60, 140])
	if typeof(ids) != TYPE_ARRAY or (ids as Array).is_empty() or typeof(spacing) != TYPE_ARRAY or (spacing as Array).size() != 2 \
			or typeof(spacing[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(spacing[1]) not in [TYPE_INT, TYPE_FLOAT] \
			or float(spacing[0]) < MIN_GAP or float(spacing[1]) < float(spacing[0]) \
			or typeof(data.get("from", 0)) not in [TYPE_INT, TYPE_FLOAT] or typeof(data.get("to", 0)) not in [TYPE_INT, TYPE_FLOAT]:
		push_error("[Midground] %s 的 midground 要有 pieces、spacing [最小（至少 %d）, 最大]、from、to，這一層不放" % [where, int(MIN_GAP)])
		return result
	var props: Array[PropData] = []
	for id: Variant in ids:
		var prop := PropLibrary.find_in(StringName(str(id)), dirs)
		if prop == null:
			push_error("[Midground] %s 的 midground 零件 %s 不在這一區的擺設資料夾裡，略過" % [where, id])
			continue
		props.append(prop)
	if props.is_empty():
		return result
	var tile := float(layout.tile_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:midground" % where)
	var cursor := float(data.get("from", 0)) * tile + rng.randf_range(0.0, float(spacing[0]))
	var end := minf(float(data.get("to", 0)) * tile, layout.pixel_size().x)
	var placed_rects: Array[Rect2] = []
	while cursor < end:
		var prop := props[rng.randi() % props.size()]
		var entry := {"id": String(prop.id), "x": int(cursor / tile), "dx": snappedf(fmod(cursor, tile), 0.1), "ground": true, "midground": true}
		var resolved := PropPlacement.resolve(entry, prop, layout)
		var gap := rng.randf_range(float(spacing[0]), float(spacing[1]))
		if resolved.is_empty():
			cursor += tile
			continue
		var rect: Rect2 = resolved["rect"]
		var combat := _near(rect, enemy_x, COMBAT_REACH)
		if rect.end.x > end or _overlaps(rect.grow(MIN_GAP * 0.5), taken) or _overlaps(rect.grow(MIN_GAP * 0.5 - 1.0), placed_rects) \
				or _near(rect, entity_x, ENTITY_CLEAR) or not ScenerySupport.has_ground(layout, rect, prop.id) \
				or (walls != null and not walls.covers(rect)) \
				or _count_in_view(rect, placed_rects) >= (MAX_PER_VIEW_COMBAT if combat else MAX_PER_VIEW):
			cursor += tile
			continue
		result.append(entry)
		placed_rects.append(rect)
		cursor = rect.end.x + (gap * 2.0 if combat else gap)
	return result


static func _overlaps(rect: Rect2, others: Array[Rect2]) -> bool:
	for other in others:
		if rect.intersects(other):
			return true
	return false


static func _near(rect: Rect2, xs: PackedFloat32Array, reach: float) -> bool:
	for x in xs:
		if x > rect.position.x - reach and x < rect.end.x + reach:
			return true
	return false


## 以這一件為中心、一個畫面寬內已經有幾件。
static func _count_in_view(rect: Rect2, placed: Array[Rect2]) -> int:
	var center := rect.get_center().x
	var count := 0
	for other in placed:
		if absf(other.get_center().x - center) < VIEW_WIDTH * 0.5:
			count += 1
	return count
