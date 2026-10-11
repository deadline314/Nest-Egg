class_name BossStrikeArea
extends Area2D
## 頭目招式的一次性攻擊判定（盾擊、掃描線…）：arm() 之後每個目標最多吃一次，結果用 struck 通知
## （DAMAGED＝打中、BLOCKED＝被格擋），招式就能分辨「撲空」與「打中」。disarm() 或下一次 arm() 前不會重複傷害。
## 和 ContactHitbox 不同：接觸傷害是持續的（重疊就會再受傷），這裡一招只算一次。

signal struck(result: Hurtbox.Result)

var team: Combat.Team = Combat.Team.ENEMY
var source_id: StringName = &""
var damage := 1
var knockback_force := 180.0

var _shape := RectangleShape2D.new()
var _shape_node := CollisionShape2D.new()
var _armed := false
var _hit: Dictionary = {}
var _landed := false


func setup(p_team: Combat.Team, p_source: StringName) -> void:
	team = p_team
	source_id = p_source
	collision_layer = 0
	collision_mask = Combat.hurtbox_mask_against(team)
	monitorable = false
	monitoring = true
	_shape_node.shape = _shape
	_shape_node.disabled = true
	add_child(_shape_node)


## 開始一次判定：大小與位置是這個節點的本地座標；之前的命中紀錄清掉。
func arm(p_damage: int, size: Vector2, offset: Vector2) -> void:
	damage = maxi(0, p_damage)
	_hit.clear()
	_landed = false
	_armed = true
	reshape(size, offset)
	_shape_node.set_deferred(&"disabled", false)


## 招式進行中改變範圍（例如往外延伸的掃描線）。
func reshape(size: Vector2, offset: Vector2) -> void:
	_shape.size = Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	_shape_node.position = offset


func disarm() -> void:
	_armed = false
	_shape_node.set_deferred(&"disabled", true)


func is_armed() -> bool:
	return _armed


## 這次判定有沒有真的打中（不含被格擋）。
func landed() -> bool:
	return _landed


func _physics_process(_delta: float) -> void:
	if not _armed or damage <= 0:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or hurtbox.team == team:
			continue
		var target := hurtbox.root()
		if _hit.has(target) or not target.can_receive():
			continue
		var info := DamageInfo.create(damage, team, source_id)
		var origin := _shape_node.global_position
		var side := signf(target.global_position.x - origin.x)
		info.knockback = Vector2((side if side != 0.0 else 1.0) * knockback_force, -knockback_force * 0.5)
		info.origin = origin
		info.attacker = weakref(get_parent())
		var result := target.receive(info)
		if result == Hurtbox.Result.IGNORED:
			continue
		_hit[target] = true
		_landed = _landed or result == Hurtbox.Result.DAMAGED
		struck.emit(result)
