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


func _physics_process(_delta: float) -> void:
	if not active or damage <= 0:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or hurtbox.team == team or not hurtbox.can_receive():
			continue
		var info := DamageInfo.create(damage, team, source_id)
		var side := signf(hurtbox.global_position.x - global_position.x)
		if side == 0.0:
			side = 1.0
		if knockback_override != Vector2.ZERO:
			info.knockback = Vector2(knockback_override.x * side, knockback_override.y)
		else:
			info.knockback = Vector2(side * knockback_force, -knockback_force * 0.6)
		info.origin = global_position
		hurtbox.receive(info)
