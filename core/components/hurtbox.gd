class_name Hurtbox
extends Area2D
## 受擊框：被動區域，接收攻擊後轉交 HealthComponent。
## 可設定 guard（格擋判定）實作盾牌、玩家格擋與完美反彈等防禦機制。

enum Result { IGNORED, BLOCKED, REFLECTED, DAMAGED }
## guard 回呼的回傳值：不格擋／格擋（攻擊無效）／反彈（子彈改由我方擁有並飛回）。
enum Guard { NONE, BLOCK, REFLECT }

signal hit_received(info: DamageInfo)
signal hit_blocked(info: DamageInfo)
signal hit_reflected(info: DamageInfo)

var team: Combat.Team = Combat.Team.ENEMY
var health: HealthComponent
## 格擋判定回呼：func(info: DamageInfo) -> Hurtbox.Guard。未設定則不格擋。
var guard: Callable = Callable()
## 反彈子彈時的飛行方向（例如玩家的準星方向）；零向量代表原路彈回。
var reflect_direction: Vector2 = Vector2.ZERO
## 傷害倍率（例如頭目露出弱點時 > 1）。
var damage_scale: float = 1.0
## 停用時不會被任何攻擊判定到（透過 deferred 切換，物理回呼中呼叫也安全）。
var enabled: bool = true:
	set(value):
		enabled = value
		set_deferred(&"monitorable", value)

var _shape: RectangleShape2D
var _shape_node: CollisionShape2D


func setup(p_team: Combat.Team, p_health: HealthComponent, size: Vector2, offset := Vector2.ZERO) -> void:
	team = p_team
	health = p_health
	collision_layer = Layers.PLAYER_HURTBOX if team == Combat.Team.PLAYER else Layers.ENEMY_HURTBOX
	collision_mask = 0
	monitoring = false
	monitorable = true
	_shape = RectangleShape2D.new()
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = _shape
	add_child(_shape_node)
	resize(size, offset)


func resize(size: Vector2, offset: Vector2) -> void:
	if _shape == null:
		return
	_shape.size = size
	_shape_node.position = offset


func can_receive(info: DamageInfo = null) -> bool:
	return enabled and health != null and health.can_take_damage(info)


func receive(info: DamageInfo) -> Result:
	if info == null or info.team == team or not can_receive(info):
		return Result.IGNORED
	if guard.is_valid() and not info.bypass_guard:
		match int(guard.call(info)):
			Guard.BLOCK:
				hit_blocked.emit(info)
				return Result.BLOCKED
			Guard.REFLECT:
				hit_reflected.emit(info)
				return Result.REFLECTED
	if damage_scale != 1.0:
		info.amount = maxi(1, roundi(info.amount * damage_scale))
	if health.take_damage(info):
		hit_received.emit(info)
		return Result.DAMAGED
	return Result.IGNORED
