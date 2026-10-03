extends Node
## 子彈物件池：重複使用 Projectile，避免大量生成／釋放造成卡頓與記憶體碎片。
## 超過上限時拒絕生成（優雅降級），不會無限成長。

const INITIAL_SIZE := 96
const MAX_SIZE := 512

var _container: Node2D
var _free: Array[Projectile] = []
var _total := 0


func bind_container(container: Node2D) -> void:
	_reset()
	_container = container
	container.tree_exiting.connect(_on_container_exiting.bind(container), CONNECT_ONE_SHOT)
	for i in INITIAL_SIZE:
		_free.append(_create())


func _on_container_exiting(container: Node2D) -> void:
	# 舊關卡離開時，新關卡可能已綁定，必須確認是同一個容器。
	if container == _container:
		_reset()


func _reset() -> void:
	_free.clear()
	_total = 0
	_container = null


func spawn(spec: ProjectileSpec, origin: Vector2, direction: Vector2, team: Combat.Team, speed_multiplier := 1.0) -> Projectile:
	if _container == null or spec == null:
		return null
	var projectile: Projectile
	if not _free.is_empty():
		projectile = _free.pop_back()
	elif _total < MAX_SIZE:
		projectile = _create()
	else:
		return null
	projectile.activate(spec, origin, direction, team, speed_multiplier)
	return projectile


## 消除範圍內某陣營的子彈（電磁脈衝用）。回傳消除的數量。
func clear_in_radius(center: Vector2, radius: float, team: Combat.Team) -> int:
	if _container == null:
		return 0
	var cleared := 0
	var limit := radius * radius
	for child in _container.get_children():
		var projectile := child as Projectile
		if projectile != null and projectile.active and projectile.team == team \
				and projectile.global_position.distance_squared_to(center) <= limit:
			projectile.deactivate()
			cleared += 1
	return cleared


func active_count() -> int:
	return _total - _free.size()


func _create() -> Projectile:
	var projectile := Projectile.new()
	projectile.expired.connect(_on_expired)
	_container.add_child(projectile)
	_total += 1
	return projectile


func _on_expired(projectile: Projectile) -> void:
	if _container != null and is_instance_valid(projectile) and projectile.get_parent() == _container:
		_free.append(projectile)
