class_name HazardZones
extends RefCounted
## 敵人知道要避開的危險範圍（NE-408）：機關在危險期間登記一塊世界座標矩形（例如通電或預警中的積水），結束時撤掉。
## 敵人巡邏、被警報或誘餌引過去時，下一步會踩進這些範圍就停下或回頭；已經站在裡面的不會逃（預警是給玩家看的）。
## 沒有任何登記時 blocks() 直接回傳 false，不多花成本。

static var _zones: Dictionary[int, Rect2] = {}


static func register(owner: Object, rect: Rect2) -> void:
	if owner == null or not rect.is_finite() or rect.has_area() == false:
		push_error("[HazardZones] 無效的危險範圍：%s（來源 %s）" % [rect, owner])
		return
	_zones[owner.get_instance_id()] = rect


static func unregister(owner: Object) -> void:
	if owner != null:
		_zones.erase(owner.get_instance_id())


## point 是否在任何危險範圍內。
static func blocks(point: Vector2) -> bool:
	if _zones.is_empty():
		return false
	for rect: Rect2 in _zones.values():
		if rect.has_point(point):
			return true
	return false


static func is_empty() -> bool:
	return _zones.is_empty()


static func clear() -> void:
	_zones.clear()
