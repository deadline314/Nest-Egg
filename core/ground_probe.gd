class_name GroundProbe
extends RefCounted
## 地面高度查詢（腳要踩在地上的生物用）：從 from_y 往下射一條線找固體地面，找不到就回傳 fallback。
## 查詢參數重複使用，不每次配置。

const DEFAULT_DOWN := 72.0

var _query: PhysicsRayQueryParameters2D


func ground_y(space: PhysicsDirectSpaceState2D, world_x: float, from_y: float, fallback: float, down := DEFAULT_DOWN) -> float:
	if _query == null:
		_query = PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.DOWN, Layers.SOLID)
	_query.from = Vector2(world_x, from_y)
	_query.to = Vector2(world_x, from_y + down)
	var hit := space.intersect_ray(_query)
	return (hit["position"] as Vector2).y if not hit.is_empty() else fallback
