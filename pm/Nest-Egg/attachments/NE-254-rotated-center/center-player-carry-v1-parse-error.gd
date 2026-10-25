class_name PlayerCarry
extends Node2D
## 玩家撿起、舉著、丟出場景物件（NE-254）。掛在玩家底下、畫在世界座標（top_level），只在拿著東西時更新與重畫。
## 操作：靠近物件按互動鍵撿起；拿著時按射擊鍵往準星方向丟、再按互動鍵放下；衝刺、近戰、格擋或受傷會先把東西放下，不卡住其他動作。
## 拿著時畫出拋物線與落點（油桶加畫爆炸範圍），在高低落差與斜向、上下投擲時看得出會落在哪裡。

enum Phase { NONE, LIFTING, HOLDING, THROWING }

const PICK_RANGE_X := 22.0
const PICK_RANGE_Y := 28.0
## 舉在頭上的高度（相對腳底）；拋物線預覽的步長、最長時間。
const HOLD_HEIGHT := 50.0
const PREVIEW_STEP := 0.04
const PREVIEW_TIME := 1.6
const PREVIEW_DOTS := 40
const THROW_POSE_TIME := 0.25
const POSE_LIFT := &"rin.carry_lift"
const POSE_HOLD := &"rin.carry_hold"
const POSE_THROW := &"rin.carry_throw"

var player: Player
var phase: Phase = Phase.NONE
var held: Throwable
var _phase_t := 0.0
var _hinted := false
## 丟出去的那一下射擊鍵還按著：放開之前不算開槍（否則每丟一次就多開一槍或多揮一刀）。
var _throw_press_held := false
var _preview: PackedVector2Array = []
var _preview_land := Vector2.INF
var _preview_collision := KinematicCollision2D.new()
var _pickup_ray := PhysicsRayQueryParameters2D.new()
var _pickup_target: Throwable


func _ready() -> void:
	top_level = true
	z_index = WorldLayers.CHARACTER_MAX_Z + 1  # 預覽線畫在角色前面
	_pickup_ray.collision_mask = Layers.WORLD
	_pickup_ray.hit_from_inside = true
	set_physics_process(false)


func is_holding() -> bool:
	return phase != Phase.NONE and phase != Phase.THROWING and is_instance_valid(held)


## 丟東西用掉的那一下射擊鍵還沒放開：玩家這時不開槍、不用射擊鍵近戰；其他動作照常。
func holds_back_shoot() -> bool:
	return _throw_press_held


## 拿著東西時的移動速度倍率。
func speed_scale() -> float:
	return held.data.carry_speed_scale if is_holding() else 1.0


## 玩家每個物理影格在一般狀態呼叫：回傳 true 代表這一格的攻擊輸入已被拿東西用掉（不要再開槍或近戰）。
func handle_input() -> bool:
	if _throw_press_held and not Input.is_action_pressed(&"shoot"):
		_throw_press_held = false
	if phase != Phase.NONE and not is_instance_valid(held) and phase != Phase.THROWING:
		_reset()
	if phase == Phase.NONE or phase == Phase.THROWING:
		# Refresh in physics; rendered prompts read the same target without querying a locked space.
		var target := nearest_pickable()
		if Input.is_action_just_pressed(&"interact"):
			if target != null:
				pick(target)
				return true
		return false
	# 拿著：衝刺、近戰、格擋會先放下（不吃掉輸入，讓那個動作照常發生）。
	for action: StringName in [&"dash", &"melee", &"block"]:
		if Input.is_action_just_pressed(action):
			put_down()
			return false
	if phase == Phase.HOLDING and Input.is_action_just_pressed(&"shoot"):
		throw_toward(player.aim_dir)
		_throw_press_held = true
		return true
	if Input.is_action_just_pressed(&"interact"):
		put_down()
		return true
	return true


## 腳邊範圍內最近、可以撿的物件。
func nearest_pickable() -> Throwable:
	if Engine.is_in_physics_frame():
		_pickup_target = _find_nearest_pickable()
	if not is_instance_valid(_pickup_target) or not _pickup_target.can_pick_up():
		return null
	var offset := _pickup_target.global_position - player.global_position
	if absf(offset.x) > PICK_RANGE_X + _pickup_target.data.size.x * 0.5 or absf(offset.y) > PICK_RANGE_Y:
		return null
	return _pickup_target


func _find_nearest_pickable() -> Throwable:
	var best: Throwable = null
	var best_d := INF
	var height := Player.CROUCH_HEIGHT if player.is_crouching else Player.BODY_SIZE.y
	var origin := player.global_position + Vector2(0, -height * 0.5)
	for node in get_tree().get_nodes_in_group(Throwable.GROUP):
		var item := node as Throwable
		if item == null or not item.can_pick_up():
			continue
		var offset := item.global_position - player.global_position
		if absf(offset.x) > PICK_RANGE_X + item.data.size.x * 0.5 or absf(offset.y) > PICK_RANGE_Y:
			continue
		if absf(offset.x) < best_d:
			_pickup_ray.from = origin
			_pickup_ray.to = item.world_center()
			if not get_world_2d().direct_space_state.intersect_ray(_pickup_ray).is_empty():
				continue
			best = item
			best_d = absf(offset.x)
	return best


func pick(item: Throwable) -> void:
	held = item
	item.pick_up()
	phase = Phase.LIFTING
	_phase_t = 0.0
	Sfx.play(&"equip_heavy", -8.0)
	set_physics_process(true)
	if not _hinted:
		_hinted = true
		EventBus.toast_requested.emit(InputBindings.format("{shoot} 往準星丟出，{interact} 放下"))


## 往 direction（準星方向）丟出：速度與弧線由物件的重量決定，加上一點玩家自己的移動速度。
func throw_toward(direction: Vector2) -> void:
	if not is_holding():
		return
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2(player.facing, -0.3).normalized()
	var item := held
	item.launch(hold_point(), launch_velocity(dir), Combat.Team.PLAYER)
	held = null
	phase = Phase.THROWING
	_phase_t = 0.0
	_preview.clear()
	queue_redraw()


func launch_velocity(direction: Vector2) -> Vector2:
	var data := held.data if is_instance_valid(held) else null
	var speed := data.throw_speed if data != null else 400.0
	return direction * speed + Vector2(player.velocity.x * 0.3, 0.0)


## 放下在腳前（面向那側），回到靜置。
func put_down() -> void:
	if is_instance_valid(held):
		held.put_down(player.global_position + Vector2(player.facing * 14.0, -2.0))
	_reset()


## 被打、上載具、死亡、切換狀態時呼叫：東西掉在原地。
func drop() -> void:
	if is_holding() or phase == Phase.LIFTING:
		put_down()


func _reset() -> void:
	held = null
	phase = Phase.NONE
	_phase_t = 0.0
	_preview.clear()
	set_physics_process(false)
	queue_redraw()


## 舉在頭上的位置（撿起時從腳前抬上來）。
func hold_point() -> Vector2:
	var overhead := player.global_position + Vector2(player.facing * 2.0, -HOLD_HEIGHT)
	if phase == Phase.LIFTING and is_instance_valid(held):
		var t := clampf(_phase_t / maxf(0.01, held.data.lift_time), 0.0, 1.0)
		return (player.global_position + Vector2(player.facing * 12.0, 0.0)).lerp(overhead, ease(t, -2.0))
	return overhead


## 骨架動作：撿起、舉著、丟出（art/rigs/action_poses.json 的 rin.carry_*）；不拿東西時回傳空。
func pose() -> StringName:
	match phase:
		Phase.LIFTING:
			return POSE_LIFT
		Phase.HOLDING:
			return POSE_HOLD
		Phase.THROWING:
			return POSE_THROW
	return &""


func pose_progress() -> float:
	match phase:
		Phase.LIFTING:
			return clampf(_phase_t / maxf(0.01, held.data.lift_time), 0.0, 1.0) if is_instance_valid(held) else 1.0
		Phase.THROWING:
			return clampf(_phase_t / THROW_POSE_TIME, 0.0, 1.0)
	return 0.0


func _physics_process(delta: float) -> void:
	_phase_t += delta
	match phase:
		Phase.LIFTING:
			if not is_instance_valid(held):
				_reset()
				return
			if _phase_t >= held.data.lift_time:
				phase = Phase.HOLDING
		Phase.THROWING:
			if _phase_t >= THROW_POSE_TIME:
				_reset()
				return
	if is_instance_valid(held):
		held.hold_at(hold_point())
		held.rotation = 0.0
	if phase == Phase.HOLDING:
		_update_preview()
	queue_redraw()


## Match the actual fixed-step flight and full rotated shape; sample dots independently.
func _update_preview() -> void:
	_preview.clear()
	_preview_land = Vector2.INF
	_preview_blast_center = Vector2.INF
	var data := held.data
	var position := hold_point()
	var velocity := launch_velocity(player.aim_dir.normalized() if player.aim_dir.length_squared() > 0.0001 else Vector2(player.facing, 0))
	var step := 1.0 / Engine.physics_ticks_per_second
	var angle := 0.0
	var spin := signf(velocity.x) * (3.0 if data.look == ThrowableData.Look.BARREL else 6.0)
	var next_dot := PREVIEW_STEP
	for i in ceili(PREVIEW_TIME / step):
		velocity.y = minf(velocity.y + data.gravity * step, Throwable.MAX_FALL_SPEED)
		angle += spin * step
		var motion := velocity * step
		if held.test_move(Transform2D(angle, position), motion, _preview_collision):
			_preview_land = _preview_collision.get_position()
			_preview_blast_center = held.center_at(Transform2D(angle, position + _preview_collision.get_travel()))
			_preview.append(_preview_land)
			return
		position += motion
		if (i + 1) * step + 0.000001 >= next_dot:
			_preview.append(position + Vector2(0, -data.size.y * 0.5))
			next_dot += PREVIEW_STEP
			if _preview.size() >= PREVIEW_DOTS:
				return


func _draw() -> void:
	if phase != Phase.HOLDING or _preview.is_empty():
		return
	# 點越遠越淡：近處清楚、落點附近不搶畫面。
	for i in _preview.size():
		var fade := 1.0 - float(i) / float(maxi(1, _preview.size()))
		draw_circle(_preview[i], 1.4, Color(LightKit.glow(Palette.CYAN, 1.5), 0.35 + 0.5 * fade))
	if _preview_land != Vector2.INF:
		draw_arc(_preview_land, 4.0, 0.0, TAU, 12, Color(LightKit.glow(Palette.CYAN, 1.8), 0.8), 1.0)
		if is_instance_valid(held) and held.data.is_explosive():
			draw_arc(_preview_blast_center, held.data.explosion_radius, 0.0, TAU, 40, Color(LightKit.glow(Palette.DANGER, 1.4), 0.45), 1.0)
