class_name CoverSpots
extends RefCounted
## 敵人可以躲的掩體（NE-415）：落地的吊掛貨箱登記自己的世界座標矩形（擋路也擋子彈），被移除時撤掉。
## 遠程敵人交戰時找同一層地面上、離自己不遠、隔在自己和玩家之間的掩體，躲到遠離玩家的那一側；
## 不會為了躲而穿過掩體（玩家繞到同一側就不再算掩護）。沒有任何登記時直接回傳空結果，不多花成本。

## 躲在掩體邊緣外多遠（像素）。
const SIDE_MARGIN := 12.0
## 腳底和掩體底邊差多少以內才算同一層地面（像素）。
const FLOOR_TOLERANCE := 6.0

static var _covers: Dictionary[int, Rect2] = {}


static func register(owner: Object, rect: Rect2) -> void:
	if owner == null or not rect.is_finite() or not rect.has_area():
		push_error("[CoverSpots] 無效的掩體範圍：%s（來源 %s）" % [rect, owner])
		return
	_covers[owner.get_instance_id()] = rect


static func unregister(owner: Object) -> void:
	if owner != null:
		_covers.erase(owner.get_instance_id())


static func is_empty() -> bool:
	return _covers.is_empty()


static func clear() -> void:
	_covers.clear()


## 站在 feet 的角色要躲 threat_x 那一側的攻擊：回傳 {"x": 該躲到的腳底 x, "top": 掩體頂端 y}；
## 找不到（太遠、不在同一層、玩家不在掩體另一側、要穿過掩體才到得了）回傳空字典。
static func spot_behind(feet: Vector2, threat_x: float, reach: float) -> Dictionary:
	var best := {}
	var best_distance := INF
	for rect: Rect2 in _covers.values():
		if absf(rect.end.y - feet.y) > FLOOR_TOLERANCE:
			continue
		var center := rect.get_center().x
		# 玩家要在掩體外、另一側；角色本身已經在遠離玩家的那一側（或站在掩體正中以外的同側）。
		if threat_x >= rect.position.x and threat_x <= rect.end.x:
			continue
		var away := 1.0 if threat_x < center else -1.0
		if (feet.x - center) * away < 0.0:
			continue
		var x := (rect.end.x + SIDE_MARGIN) if away > 0.0 else (rect.position.x - SIDE_MARGIN)
		var distance := absf(x - feet.x)
		if distance <= reach and distance < best_distance:
			best_distance = distance
			best = {"x": x, "top": rect.position.y}
	return best
