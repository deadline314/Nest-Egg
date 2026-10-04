class_name SurfaceWalker
extends RefCounted
## 貼著固體表面（地、牆、天花板）爬行的幾何：身體中心離表面 radius，沿表面切線前進，
## 遇到前方的牆（凹角）轉到那面牆，表面在腳下結束（凸角）就繞過去。表面法線只用上下左右四個方向。
## 純幾何（需要物理空間查詢），不管動畫與敵人狀態；攀牆者用它，之後其他貼附型生物也可以重用。

var normal := Vector2.UP
## 沿表面前進的方向：+1 = 法線順時針轉 90 度（在地板上就是向右）。
var dir := 1
var radius := 5.0
var mask := Layers.SOLID

var _query: PhysicsRayQueryParameters2D


func tangent() -> Vector2:
	return normal.rotated(PI * 0.5 * float(dir))


## 身體要轉多少弧度才會「背朝外」貼著表面（法線朝上時 0）。
func angle() -> float:
	return Vector2.UP.angle_to(normal)


func reverse() -> void:
	dir = -dir


func _ray(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	if _query == null:
		_query = PhysicsRayQueryParameters2D.create(from, to, mask)
	_query.from = from
	_query.to = to
	return space.intersect_ray(_query)


static func _snap(v: Vector2) -> Vector2:
	return Vector2(signf(v.x), 0.0) if absf(v.x) >= absf(v.y) else Vector2(0.0, signf(v.y))


## 往前爬 distance 像素，回傳新的中心位置（法線可能因轉角改變）。
func advance(space: PhysicsDirectSpaceState2D, position: Vector2, distance: float) -> Vector2:
	var t := tangent()
	# 凹角：前方有牆，轉到那面牆上。
	var wall := _ray(space, position, position + t * (radius + distance + 1.0))
	if not wall.is_empty():
		normal = _snap(wall["normal"])
		return (wall["position"] as Vector2) + normal * radius
	position += t * distance
	# 還貼著表面：貼回去。
	var ground := _ray(space, position, position - normal * (radius + 3.0))
	if not ground.is_empty():
		return (ground["position"] as Vector2) + normal * radius
	# 凸角：表面在這裡結束，繞到轉角另一側的面。
	var turned := t
	var around := position - normal * radius
	var side := _ray(space, around, around - turned * (radius + distance + 2.0))
	normal = _snap(turned)
	if not side.is_empty():
		return (side["position"] as Vector2) + normal * radius
	return around


## 從空中落到表面：沿 from → to 找第一個碰到的固體，回傳 {position, normal}；沒碰到回傳空字典。
func land(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> Dictionary:
	var hit := _ray(space, from, to)
	if hit.is_empty():
		return {}
	var n := _snap(hit["normal"])
	return {"position": (hit["position"] as Vector2) + n * radius, "normal": n}


## 貼回最近的表面（出生時、被推開後）：往四個方向找最近的固體。回傳是否找到。
func attach(space: PhysicsDirectSpaceState2D, position: Vector2, reach := 24.0) -> Dictionary:
	var best := {}
	var best_distance := INF
	for direction: Vector2 in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		var hit := _ray(space, position, position + direction * reach)
		if not hit.is_empty():
			var d := position.distance_to(hit["position"] as Vector2)
			if d < best_distance:
				best_distance = d
				best = {"position": (hit["position"] as Vector2) + _snap(hit["normal"]) * radius, "normal": _snap(hit["normal"])}
	return best
