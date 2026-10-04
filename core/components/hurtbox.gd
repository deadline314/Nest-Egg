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
## 傷害倍率（例如頭目露出弱點時 > 1）。部位受擊框（頭、核心）再乘上自己的倍率。
var damage_scale: float = 1.0
## 部位受擊框：掛在整體受擊框（main）底下，共用同一份生命與格擋，部位 id 與倍率各自設定。
## 同一個攻擊命中重疊的部位時，取 parts 排在前面的（較小、較重要的部位），而且只算一次傷害。
var part_id: StringName = &""
## 命中材質（data/feel/materials.json 的 id）；空字串＝用整體受擊框的，再沒有就用 generic。
var hit_material: StringName = &""
var main: Hurtbox
var parts: Array[Hurtbox] = []
## 停用時不會被任何攻擊判定到（透過 deferred 切換，物理回呼中呼叫也安全）。
var enabled: bool = true:
	set(value):
		enabled = value
		set_deferred(&"monitorable", value)

var _shape: RectangleShape2D
var _shape_node: CollisionShape2D


## 受擊框的中心（世界座標）；Area 本身在腳底，形狀有位移，距離與角度判定用這個。
func center() -> Vector2:
	return _shape_node.global_position if _shape_node != null else global_position


func material_id() -> StringName:
	if hit_material != &"":
		return hit_material
	return main.material_id() if main != null and main != self else &""


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


## 這個受擊框所屬的整體（部位回傳它的 main，整體回傳自己）。
func root() -> Hurtbox:
	return main if main != null else self


## 新增一個部位受擊框（排在前面的優先）：共用生命與格擋，位置與大小自己設，之後用 move_part 跟著動作移動。
func add_part(id: StringName, size: Vector2, offset: Vector2, scale: float) -> Hurtbox:
	var part := Hurtbox.new()
	part.main = self
	part.part_id = id
	part.damage_scale = scale
	add_child(part)
	part.setup(team, health, size, offset)
	part.guard = guard
	parts.append(part)
	return part


## 判定形狀中心（受擊框本地座標）。
func shape_offset() -> Vector2:
	return _shape_node.position if _shape_node != null else Vector2.ZERO


func move_part(part: Hurtbox, offset: Vector2) -> void:
	if part._shape_node != null:
		part._shape_node.position = offset


## 攻擊命中的位置落在哪個部位：依 parts 順序找第一個包含該點（四周放寬 margin，補償子彈有大小）的部位，找不到就是整體。
func resolve_at(point: Vector2, margin := 3.0) -> Hurtbox:
	var owner_box := root()
	for part in owner_box.parts:
		if part.enabled and part.contains_point(point, margin):
			return part
	return owner_box


func contains_point(point: Vector2, margin := 0.0) -> bool:
	if _shape_node == null:
		return false
	var local := _shape_node.global_transform.affine_inverse() * point
	return absf(local.x) <= _shape.size.x * 0.5 + margin and absf(local.y) <= _shape.size.y * 0.5 + margin


func can_receive(info: DamageInfo = null) -> bool:
	return enabled and (main == null or main.enabled) and health != null and health.can_take_damage(info)


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
	var scale := damage_scale * (main.damage_scale if main != null else 1.0)
	info.part = part_id
	info.weak_hit = main != null and damage_scale > 1.0
	if scale != 1.0:
		info.amount = maxi(1, roundi(info.amount * scale))
	if health.take_damage(info):
		hit_received.emit(info)
		return Result.DAMAGED
	return Result.IGNORED
