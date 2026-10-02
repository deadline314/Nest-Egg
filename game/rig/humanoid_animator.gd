class_name HumanoidAnimator
extends RefCounted
## 人形程式動畫：所有人形角色共用，不需要逐格動畫。
##
## 每影格流程：
##   1. 依狀態（待機／跑／跳／落下／蹲／衝刺／格擋／硬直／死亡）算出身體與腿的目標角度，平滑過渡
##   2. 正向運動學（FK）求出肩膀位置
##   3. 雙臂反向動力學（2-bone IK）：前手握槍把、後手扶護木，槍枝跟隨準星
##   4. 頭髮與衣襬以阻尼彈簧做次級動態
## 所有角度在「骨架空間」（面向右、未翻轉）計算；骨頭靜止時沿 +Y 延伸。

const POSE_SHARPNESS := 18.0
## 每移動 1 世界像素，跑步循環前進的弧度（約每 50px 一個步伐週期）。
const STRIDE_PER_PIXEL := TAU / 50.0
const MAX_AIM_ANGLE := deg_to_rad(105.0)
const SPRING_STIFFNESS := 140.0
const SPRING_DAMPING := 11.0
const RECOIL_RECOVERY := 9.0
const HURT_TIME := 0.22
const CROUCH_DROP := 8.0
const DEATH_DROP := 21.0

const LEGS: Array[StringName] = [&"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"]
const SPRING_BONES: Array[StringName] = [&"coat_1", &"coat_2", &"hair_1", &"hair_2"]

var _rig: CharacterRig
var _angles: Dictionary[StringName, float] = {}
var _hip_offset := Vector2.ZERO
var _phase := 0.0
var _time := 0.0
var _recoil := 0.0
var _hurt_left := 0.0
var _death_time := 0.0
var _spring_angle: Dictionary[StringName, float] = {}
var _spring_velocity: Dictionary[StringName, float] = {}
# FK 快取（骨架空間）
var _global_angle: Dictionary[StringName, float] = {}
var _global_pos: Dictionary[StringName, Vector2] = {}


func _init(rig: CharacterRig) -> void:
	_rig = rig
	for bone_name in rig.bone_order():
		_angles[bone_name] = 0.0
	for bone_name in SPRING_BONES:
		_spring_angle[bone_name] = 0.0
		_spring_velocity[bone_name] = 0.0


func update(delta: float, input: RigInput) -> void:
	_time += delta
	if input.recoil > _recoil:
		_recoil = input.recoil
	_recoil = move_toward(_recoil, 0.0, RECOIL_RECOVERY * delta)
	if input.hurt:
		_hurt_left = HURT_TIME
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_death_time = _death_time + delta if input.dead else 0.0

	var local_velocity := Vector2(input.velocity.x * input.facing, input.velocity.y)
	var local_aim := Vector2(input.aim_dir.x * input.facing, input.aim_dir.y)
	var aim_angle := clampf(local_aim.angle(), -MAX_AIM_ANGLE, MAX_AIM_ANGLE)

	var target := _body_pose(delta, input, local_velocity, aim_angle)
	var blend := 1.0 - exp(-POSE_SHARPNESS * delta)
	for bone_name: StringName in target.keys():
		if bone_name == &"_hip_y" or bone_name == &"_hip_x":
			continue
		_angles[bone_name] = lerp_angle(_angles.get(bone_name, 0.0), target[bone_name], blend)
	_hip_offset = _hip_offset.lerp(Vector2(target.get(&"_hip_x", 0.0), target.get(&"_hip_y", 0.0)), blend)

	_update_springs(delta, local_velocity, input)
	_apply_body()
	_forward_kinematics()
	if not input.dead:
		_solve_arms(input, aim_angle)
	else:
		_rig.weapon_root().visible = false


# ---------------------------------------------------------------------------
# 1. 身體姿勢
# ---------------------------------------------------------------------------

func _body_pose(delta: float, input: RigInput, v: Vector2, aim_angle: float) -> Dictionary:
	var pose: Dictionary = {}
	var speed_ratio := clampf(absf(v.x) / maxf(1.0, input.run_speed), 0.0, 1.3)
	var breath := sin(_time * 2.4)

	if input.dead:
		# 向後倒下：整個身體以髖部為軸旋轉並沉到地面。
		var t := clampf(_death_time / 0.45, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 3.0)
		pose[&"hip"] = -1.56 * eased
		pose[&"_hip_y"] = DEATH_DROP * eased
		pose[&"_hip_x"] = -6.0 * eased
		pose[&"chest"] = 0.15 * eased
		pose[&"neck"] = 0.1
		pose[&"head"] = 0.35 * eased
		_set_legs(pose, 0.3, 0.1, 0.45, 0.05)
		return pose

	pose[&"hip"] = 0.0
	pose[&"_hip_y"] = 0.0
	if input.crouching:
		pose[&"_hip_y"] = CROUCH_DROP
		pose[&"chest"] = 0.18
		_set_legs(pose, -1.25, 2.05, -0.55, 1.85)
	elif input.dashing:
		var forward := signf(v.x) >= 0.0
		pose[&"chest"] = 0.38 if forward else -0.22
		if forward:
			_set_legs(pose, -1.0, 0.6, 0.85, 1.0)
		else:
			_set_legs(pose, 0.5, 0.9, -0.7, 0.4)
	elif not input.on_floor:
		if v.y < 0.0:
			pose[&"chest"] = 0.05
			_set_legs(pose, -0.95, 1.4, 0.35, 0.7)
		else:
			pose[&"chest"] = -0.05
			_set_legs(pose, -0.35, 0.45, 0.45, 0.25)
	elif speed_ratio > 0.08:
		_phase += v.x * STRIDE_PER_PIXEL * delta
		var swing := 0.8 * minf(speed_ratio, 1.0)
		var front := sin(_phase)
		var back := sin(_phase + PI)
		pose[&"leg_front_upper"] = -front * swing
		pose[&"leg_front_lower"] = 0.15 + maxf(0.0, cos(_phase)) * 1.2 * swing
		pose[&"leg_back_upper"] = -back * swing
		pose[&"leg_back_lower"] = 0.15 + maxf(0.0, cos(_phase + PI)) * 1.2 * swing
		pose[&"_hip_y"] = -absf(sin(_phase)) * 1.4 * swing
		pose[&"chest"] = 0.12 * speed_ratio * signf(v.x)
	else:
		# 待機：微微呼吸、重心落在後腳。
		pose[&"chest"] = breath * 0.02
		pose[&"_hip_y"] = breath * 0.3
		_set_legs(pose, -0.12, 0.12, 0.2, 0.08)

	if input.blocking:
		pose[&"chest"] = float(pose.get(&"chest", 0.0)) + 0.1
		if input.on_floor and not input.crouching:
			_set_legs(pose, -0.4, 0.5, 0.5, 0.2)
	if input.staggered:
		pose[&"chest"] = -0.35
	if _hurt_left > 0.0:
		pose[&"chest"] = float(pose.get(&"chest", 0.0)) - 0.3 * (_hurt_left / HURT_TIME)
	# 上半身跟著準星微轉，頭看向準星。
	pose[&"chest"] = float(pose.get(&"chest", 0.0)) + aim_angle * 0.12 - _recoil * 0.06
	pose[&"neck"] = aim_angle * 0.12
	pose[&"head"] = clampf(aim_angle * 0.3, -0.35, 0.3)
	return pose


func _set_legs(pose: Dictionary, front_upper: float, front_lower: float, back_upper: float, back_lower: float) -> void:
	pose[&"leg_front_upper"] = front_upper
	pose[&"leg_front_lower"] = front_lower
	pose[&"leg_back_upper"] = back_upper
	pose[&"leg_back_lower"] = back_lower


# ---------------------------------------------------------------------------
# 2. 套用與正向運動學
# ---------------------------------------------------------------------------

func _apply_body() -> void:
	for bone_name: StringName in _angles.keys():
		var b := _rig.bone(bone_name)
		if b != null:
			b.rotation = _angles[bone_name]
	var hip := _rig.bone(&"hip")
	if hip != null:
		hip.position = _rig.rest(&"hip") + _hip_offset
	for bone_name in SPRING_BONES:
		var b := _rig.bone(bone_name)
		if b != null:
			b.rotation = _spring_angle[bone_name]


func _forward_kinematics() -> void:
	for bone_name in _rig.bone_order():
		var parent := _rig.parent_of(bone_name)
		var b := _rig.bone(bone_name)
		if parent == &"":
			_global_angle[bone_name] = b.rotation
			_global_pos[bone_name] = b.position
		else:
			var parent_angle: float = _global_angle.get(parent, 0.0)
			_global_angle[bone_name] = parent_angle + b.rotation
			_global_pos[bone_name] = _global_pos.get(parent, Vector2.ZERO) + b.position.rotated(parent_angle)


# ---------------------------------------------------------------------------
# 3. 手臂 IK 與武器
# ---------------------------------------------------------------------------

func _solve_arms(input: RigInput, aim_angle: float) -> void:
	var weapon := _rig.weapon_def()
	var weapon_root := _rig.weapon_root()
	var anchor: Array = _rig.weapon_anchor()
	var anchor_bone: StringName = anchor[0]
	var anchor_point: Vector2 = _global_pos.get(anchor_bone, Vector2.ZERO) + (anchor[1] as Vector2).rotated(_global_angle.get(anchor_bone, 0.0))
	var reach: float = anchor[2] * (0.7 if input.blocking else 1.0) - _recoil * 2.5
	var aim := Vector2.RIGHT.rotated(aim_angle)
	var grip := anchor_point + aim * reach

	if weapon.is_empty():
		weapon_root.visible = false
		_reach_arm(&"arm_front_upper", &"arm_front_lower", &"hand_front", grip, aim_angle)
	else:
		weapon_root.visible = true
		weapon_root.position = grip
		weapon_root.rotation = aim_angle
		_reach_arm(&"arm_front_upper", &"arm_front_lower", &"hand_front", grip, aim_angle)

	if input.shield_forward:
		var shoulder: Vector2 = _global_pos.get(&"arm_back_upper", anchor_point)
		# 盾牌貼圖是直立的，手部角度只跟著準星微幅傾斜。
		_reach_arm(&"arm_back_upper", &"arm_back_lower", &"hand_back", shoulder + aim * 13.0 + Vector2(0, 2), aim_angle * 0.3)
	elif input.two_handed and not weapon.is_empty():
		var offset := (RigLibrary.vec2(weapon.get("foregrip")) - RigLibrary.vec2(weapon.get("grip"))) * _rig.weapon_scale()
		_reach_arm(&"arm_back_upper", &"arm_back_lower", &"hand_back", grip + offset.rotated(aim_angle), aim_angle)
	else:
		# 空著的後手自然下垂、隨步伐輕擺。
		var swing := sin(_phase + PI) * 0.4
		_set_rotation(&"arm_back_upper", 0.2 + swing)
		_set_rotation(&"arm_back_lower", -0.3)
		_set_rotation(&"hand_back", 0.0)


## 兩段骨頭的 IK：手肘朝下彎，目標超出臂長時手臂伸直指向目標。hand_angle 為手部最終角度（骨架空間）。
func _reach_arm(upper: StringName, lower: StringName, hand: StringName, target: Vector2, hand_angle: float) -> void:
	if not (_rig.has_bone(upper) and _rig.has_bone(lower) and _rig.has_bone(hand)):
		return
	var shoulder: Vector2 = _global_pos[upper]
	var length_upper := _rig.rest(lower).length()
	var length_lower := _rig.rest(hand).length()
	var to_target := target - shoulder
	var distance := clampf(to_target.length(), 0.01, length_upper + length_lower - 0.01)
	var base := to_target.angle()
	var cos_alpha := clampf((length_upper * length_upper + distance * distance - length_lower * length_lower) / (2.0 * length_upper * distance), -1.0, 1.0)
	var upper_dir := base + acos(cos_alpha)
	var elbow := shoulder + Vector2.RIGHT.rotated(upper_dir) * length_upper
	var lower_dir := (target - elbow).angle()
	var parent_angle: float = _global_angle.get(_rig.parent_of(upper), 0.0)
	# 骨頭靜止時沿 +Y（角度 PI/2），所以骨頭的累積旋轉 = 方向角 - PI/2。
	var upper_global := upper_dir - PI * 0.5
	var lower_global := lower_dir - PI * 0.5
	_rig.bone(upper).rotation = upper_global - parent_angle
	_rig.bone(lower).rotation = lower_global - upper_global
	_rig.bone(hand).rotation = hand_angle - lower_global


func _set_rotation(bone_name: StringName, value: float) -> void:
	var b := _rig.bone(bone_name)
	if b != null:
		b.rotation = value


# ---------------------------------------------------------------------------
# 4. 次級動態（衣襬、頭髮）
# ---------------------------------------------------------------------------

func _update_springs(delta: float, v: Vector2, input: RigInput) -> void:
	# 往前跑時向後飄；下落時被氣流往上掀；上升時下垂。
	var trail := clampf(v.x / 220.0, -0.4, 1.0) * 0.9
	var lift := clampf(v.y / 420.0, -0.3, 1.0) * 0.6
	var wind := sin(_time * 3.1) * 0.05
	var base := trail + lift + wind
	if input.dead:
		base = 0.6
	var targets := {
		&"coat_1": 0.15 + base * 0.7,
		&"coat_2": base * 0.5,
		&"hair_1": 0.25 + base * 0.5,
		&"hair_2": base * 0.4,
	}
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var dt := delta / steps
	for i in steps:
		for bone_name in SPRING_BONES:
			var target: float = targets[bone_name]
			var velocity: float = _spring_velocity[bone_name]
			velocity += ((target - _spring_angle[bone_name]) * SPRING_STIFFNESS - velocity * SPRING_DAMPING) * dt
			_spring_velocity[bone_name] = velocity
			_spring_angle[bone_name] = clampf(_spring_angle[bone_name] + velocity * dt, -0.8, 1.6)
