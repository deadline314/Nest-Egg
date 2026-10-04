class_name ContactHitbox
extends Area2D
## 接觸傷害（敵人身體、尖刺、雷射柵欄）。
## 每個物理影格檢查重疊：目標無敵結束後若仍重疊，會再次受傷。

var team: Combat.Team = Combat.Team.ENEMY
var damage: int = 1
var source_id: StringName = &""
var knockback_force: float = 160.0
## 非零時使用固定擊退向量（x 會依目標方向翻轉），例如尖刺固定往上彈。
var knockback_override: Vector2 = Vector2.ZERO
var active: bool = true

var _shape: RectangleShape2D
var _shape_node: CollisionShape2D


func setup(p_team: Combat.Team, p_damage: int, p_source: StringName, size: Vector2, offset := Vector2.ZERO) -> void:
	team = p_team
	damage = p_damage
	source_id = p_source
	collision_layer = 0
	collision_mask = Combat.hurtbox_mask_against(team)
	monitorable = false
	monitoring = true
	_shape = RectangleShape2D.new()
	_shape.size = size
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = _shape
	_shape_node.position = offset
	add_child(_shape_node)


## 改變碰撞範圍（例如火焰隨長度伸縮）。size 與 offset 都是這個節點的本地座標。
func resize(size: Vector2, offset := Vector2.ZERO) -> void:
	if _shape == null:
		return
	_shape.size = size
	_shape_node.position = offset


func _physics_process(_delta: float) -> void:
	if not active or damage <= 0:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or hurtbox.team == team or not hurtbox.can_receive():
			continue
		var info := DamageInfo.create(damage, team, source_id)
		# 以碰撞形狀中心作為攻擊來源（而非節點原點／腳底），讓格擋方向判定準確。
		var origin := _origin_for(hurtbox)
		var side := signf(hurtbox.global_position.x - origin.x)
		if side == 0.0:
			side = 1.0
		if knockback_override != Vector2.ZERO:
			info.knockback = Vector2(knockback_override.x * side, knockback_override.y)
		else:
			info.knockback = Vector2(side * knockback_force, -knockback_force * 0.6)
		info.origin = origin
		info.attacker = weakref(get_parent())
		hurtbox.receive(info)


## 攻擊來源（世界座標）。子類別有多個形狀時覆寫，回傳離目標最近的那個。
func _origin_for(_hurtbox: Hurtbox) -> Vector2:
	return _shape_node.global_position
