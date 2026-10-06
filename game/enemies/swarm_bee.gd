class_name SwarmBee
extends Enemy
## 蜂群（第三章，群體）：極小的裝甲蜂，只有 1 點生命，靠數量壓人。
## 行為：一群在玩家四周繞圈（群集：彼此保持距離、朝同一方向、被玩家吸引）；每隻自己挑時間蓄力（抖得更快，預兆 0.45 秒），然後直線衝刺螫人，再飛回隊伍。
## 應對：範圍武器與散射一次清一片；蓄力抖動的那隻就是要衝過來的，先擊落它。
## 群體移動不是每隻各自動畫：隊形由群集規則決定，個體只做拍翅與抖動。

const GROUP := &"swarm_bees"
const NEIGHBOR_RADIUS := 26.0
const SEPARATION_RADIUS := 11.0
const MAX_NEIGHBORS := 6
const ORBIT_RADIUS := 62.0
const ORBIT_SPEED := 0.9
const STEER := 260.0
const STING_RECOVER := 0.5

## 這個物理影格的群成員快取（所有蜂共用，每影格只查一次群組）。
static var _members_frame := -1
static var _members_cache: Array[Node] = []

var _slot := 0.0
var _cooldown := 1.0
var _sting_dir := Vector2.RIGHT


## 在 center 附近生成一群（count 隻）。回傳生成的蜂；parent 是要加進去的節點（關卡的實體層）。
static func spawn_swarm(parent: Node, data: EnemyData, center: Vector2, count: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for i in count:
		var bee := data.behavior.new() as Enemy
		if bee == null:
			push_error("[SwarmBee] %s 的 behavior 不是 Enemy。" % data.id)
			return out
		bee.configure(data)
		bee.position = center + Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(1, count))) * randf_range(6.0, 22.0)
		parent.add_child(bee)
		out.append(bee)
	return out


func _setup_states() -> void:
	_slot = randf() * TAU
	_cooldown = randf_range(0.8, data.attack_cooldown)
	add_to_group(GROUP)
	fsm.add(&"fly", _fly_tick)
	fsm.add(&"buzz", _buzz_tick, _buzz_enter)
	fsm.add(&"sting", _sting_tick, _sting_enter)
	fsm.add(&"recover", _recover_tick)
	fsm.start(&"fly")
	hurtbox.resize(data.body_size + Vector2(3, 3), Vector2(0, -data.body_size.y * 0.5))


func _fly_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_steer(delta, 1.0)
	if _cooldown <= 0.0 and _token_free() and _distance_to_target() <= data.attack_range and _target() != null:
		fsm.transition(&"buzz")


func _steer(delta: float, strength: float) -> void:
	var target := _target()
	var desired := Vector2.ZERO
	if target != null and _distance_to_target() <= data.detect_range:
		var ring := target.global_position + Vector2(0, -24) + Vector2.RIGHT.rotated(_slot + _anim_time * ORBIT_SPEED) * ORBIT_RADIUS
		desired = (ring - global_position).limit_length(data.move_speed)
	else:
		desired = (_home + Vector2.RIGHT.rotated(_slot + _anim_time * 0.4) * 30.0 - global_position).limit_length(data.move_speed * 0.5)
	# 群集：和近鄰保持距離，順著鄰居的方向（只看最近 MAX_NEIGHBORS 隻，避免群體變大時每影格 O(n²)）。
	var separation := Vector2.ZERO
	var heading := Vector2.ZERO
	var seen := 0
	for node in _members():
		if seen >= MAX_NEIGHBORS:
			break
		var other := node as SwarmBee
		if other == null or other == self or other.is_dying():
			continue
		var offset := global_position - other.global_position
		var distance := offset.length()
		if distance > NEIGHBOR_RADIUS:
			continue
		seen += 1
		heading += other.velocity
		if distance < SEPARATION_RADIUS and distance > 0.01:
			separation += offset / distance * (SEPARATION_RADIUS - distance)
	if seen > 0:
		desired += separation * 9.0 + heading / float(seen) * 0.25
	velocity = velocity.move_toward(desired.limit_length(data.move_speed * 1.2), STEER * strength * delta)
	if absf(velocity.x) > 8.0:
		facing = 1 if velocity.x > 0.0 else -1


func _members() -> Array[Node]:
	var frame := Engine.get_physics_frames()
	if frame != _members_frame:
		_members_frame = frame
		_members_cache = get_tree().get_nodes_in_group(GROUP)
	return _members_cache


func _buzz_enter() -> void:
	_start_telegraph(data.telegraph_time)


func _buzz_tick(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
	_face_target()
	_sting_dir = (_target_point() - _center()).normalized()
	if not is_telegraphing():
		fsm.transition(&"sting")


func _sting_enter() -> void:
	velocity = _sting_dir * data.ability_speed


func _sting_tick(_delta: float) -> void:
	if fsm.time_in_state >= data.ability_time or get_slide_collision_count() > 0:
		fsm.transition(&"recover")


func _recover_tick(delta: float) -> void:
	_steer(delta, 0.6)
	if fsm.time_in_state >= STING_RECOVER:
		_cooldown = _scaled_cooldown(data.attack_cooldown) * randf_range(0.8, 1.4)
		fsm.transition(&"fly")


func _on_stunned() -> void:
	fsm.transition(&"recover")


func _draw_body(color: Color) -> void:
	draw_circle(Vector2(0, -data.body_size.y * 0.5), 2.5, color)
