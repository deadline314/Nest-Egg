class_name BoneHitbox
extends ContactHitbox
## 跟著骨頭移動的傷害判定：一組小圓（觸手的尖端與各節），每影格用 set_points 搬到骨頭的世界座標。
## 傷害、擊退與無敵時間的處理和 ContactHitbox 完全相同；圓的數量固定（建立時決定），重複使用，不每影格配置。
## 沒有呼叫 set_points（或 points 為空）時所有圓都停用。

var _circles: Array[CollisionShape2D] = []
var _active_count := 0


func setup_bones(p_team: Combat.Team, p_damage: int, p_source: StringName, max_points: int) -> void:
	team = p_team
	damage = p_damage
	source_id = p_source
	collision_layer = 0
	collision_mask = Combat.hurtbox_mask_against(team)
	monitorable = false
	monitoring = true
	for i in maxi(1, max_points):
		var node := CollisionShape2D.new()
		node.shape = CircleShape2D.new()
		node.disabled = true
		add_child(node)
		_circles.append(node)


## points 是世界座標；超過容量的點被忽略。
func set_points(points: PackedVector2Array, radius: float) -> void:
	var count := mini(points.size(), _circles.size())
	for i in count:
		var node := _circles[i]
		node.global_position = points[i]
		(node.shape as CircleShape2D).radius = radius
		if node.disabled:
			node.set_deferred(&"disabled", false)
	for i in range(count, _active_count):
		_circles[i].set_deferred(&"disabled", true)
	_active_count = count


func clear_points() -> void:
	set_points(PackedVector2Array(), 0.0)


func point_count() -> int:
	return _active_count


func _origin_for(hurtbox: Hurtbox) -> Vector2:
	var best := global_position
	var best_distance := INF
	for i in _active_count:
		var d := _circles[i].global_position.distance_squared_to(hurtbox.global_position)
		if d < best_distance:
			best_distance = d
			best = _circles[i].global_position
	return best
