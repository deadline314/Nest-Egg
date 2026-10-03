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
const MAX_AIM_ANGLE := deg_to_rad(105.0)
const SPRING_STIFFNESS := 140.0
const SPRING_DAMPING := 11.0
## 次級動態（衣襬、頭髮）的預設設定；骨架定義（rig json）有 "springs" 時以它為準。
## bone：彈簧骨；rest：靜止時的角度；gain：跟隨「移動造成的目標角度」的倍率；
## trail／lift／wind：往前跑向後飄、上升下落、微風各自的倍率（預設 1）；stiffness／damping：彈簧硬度與阻尼；min／max：角度上下限。
const DEFAULT_SPRINGS: Array[Dictionary] = [
	{"bone": "coat_1", "rest": 0.15, "gain": 0.7},
	{"bone": "coat_2", "rest": 0.0, "gain": 0.5},
	{"bone": "hair_1", "rest": 0.25, "gain": 0.5},
	{"bone": "hair_2", "rest": 0.0, "gain": 0.4},
]
## 動作資料（art/motion/<角色>.json）缺的欄位用這份預設補（等於凜原本的手感）；每個角色都要有自己的檔案，測試會檢查不重複。
const MOTION_PATH := "res://art/motion/%s.json"
const DEFAULT_MOTION := {
	"idle": {"breath_speed": 2.4, "breath_amp": 0.02, "hip_bob": 0.3, "chest": 0.0, "legs": [-0.12, 0.12, 0.2, 0.08]},
	"move": {"stride": 50.0, "swing": 0.8, "knee_bend": 1.2, "knee_base": 0.15, "hip_bounce": 1.4, "chest_lean": 0.12, "threshold": 0.08},
	"crouch": {"hip_drop": 8.0, "chest": 0.18, "legs": [-1.25, 2.05, -0.55, 1.85]},
	"air": {"rise": {"chest": 0.05, "legs": [-0.95, 1.4, 0.35, 0.7]}, "fall": {"chest": -0.05, "legs": [-0.35, 0.45, 0.45, 0.25]}},
	"dash": {"forward": {"chest": 0.38, "legs": [-1.0, 0.6, 0.85, 1.0]}, "back": {"chest": -0.22, "legs": [0.5, 0.9, -0.7, 0.4]}},
	"block": {"chest": 0.1, "legs": [-0.4, 0.5, 0.5, 0.2]},
	"hurt": {"stagger_chest": -0.35, "kick": 0.3},
	"look": {"chest": 0.12, "neck": 0.12, "head": 0.3, "head_min": -0.35, "head_max": 0.3},
	"npc": {"stand": {}, "talk_speed": 1.0, "talk_amp": 1.0},
	"death": {"duration": 0.45, "rotation": -1.56, "drop": 21.0, "hip_x": -6.0, "chest": 0.15, "head": 0.35, "fold": 0.0, "ease": "out_cubic",
			"legs": [0.3, 0.1, 0.45, 0.05], "fold_legs": [-1.4, 2.0, -1.2, 1.9]},
}
const ACTIONS_PATH := "res://art/rigs/action_poses.json"
const SPRING_MIN := -0.8
const SPRING_MAX := 1.6
const RECOIL_RECOVERY := 9.0
const HURT_TIME := 0.22
const CROUCH_DROP := 8.0

const LEGS: Array[StringName] = [&"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"]

var _rig: CharacterRig
var _angles: Dictionary[StringName, float] = {}
var _hip_offset := Vector2.ZERO
var _phase := 0.0
var _time := 0.0
var _recoil := 0.0
var _hurt_left := 0.0
var _death_time := 0.0
## 專屬動作：目前（或剛結束、正在淡出）的動作、各骨頭的目標角度與權重。
var _action_pose: Dictionary = {}
var _action_w := 0.0
var _action_skip_ik := false
var _action_weapon_angle := NAN  # 動作指定的武器角度（NAN＝跟著手轉）
var _springs: Array[Dictionary] = []
## 這個角色自己的動作資料（預設值被 art/motion/<角色>.json 蓋過後的結果）。
var _motion: Dictionary = {}
var _spring_angle: Dictionary[StringName, float] = {}
var _spring_velocity: Dictionary[StringName, float] = {}
# FK 快取（骨架空間）
var _global_angle: Dictionary[StringName, float] = {}
var _global_pos: Dictionary[StringName, Vector2] = {}


func _init(rig: CharacterRig) -> void:
	_rig = rig
	_motion = _load_motion(rig.skin_id)
	for bone_name in rig.bone_order():
		_angles[bone_name] = 0.0
	for entry in (rig.springs() if not rig.springs().is_empty() else DEFAULT_SPRINGS):
		var bone_name := StringName(str(entry.get("bone", "")))
		if not rig.has_bone(bone_name):
			continue  # 這個骨架沒有這根骨頭（例如舊骨架的衣襬）：略過
		_springs.append(entry)
		_spring_angle[bone_name] = 0.0
		_spring_velocity[bone_name] = 0.0


## 讀這個角色的動作資料並補上預設；檔案缺失或格式錯誤時記錄具體位置並整份用預設。
static func _load_motion(skin_id: String) -> Dictionary:
	var merged: Dictionary = DEFAULT_MOTION.duplicate(true)
	var path := MOTION_PATH % skin_id
	if not ResourceLoader.exists(path):
		RigLibrary.report_once("motion:" + skin_id, "[HumanoidAnimator] %s 沒有動作資料，使用預設動作。" % path)
		return merged
	var data := RigLibrary.load_json(path)
	_merge_into(merged, data)
	return merged


static func _merge_into(base: Dictionary, over: Dictionary) -> void:
	for key: Variant in over.keys():
		if typeof(over[key]) == TYPE_DICTIONARY and base.has(key) and typeof(base[key]) == TYPE_DICTIONARY:
			_merge_into(base[key], over[key])
		elif base.has(key) and typeof(base[key]) == typeof(over[key]):
			base[key] = over[key]


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
	_apply_action(delta, input, target)
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
	var m := _motion
	var speed_ratio := clampf(absf(v.x) / maxf(1.0, input.run_speed), 0.0, 1.3)
	var idle: Dictionary = m["idle"]
	var move: Dictionary = m["move"]

	if input.dead:
		_death_pose(pose, m["death"])
		return pose

	pose[&"hip"] = 0.0
	pose[&"_hip_y"] = 0.0
	if input.crouching:
		var crouch: Dictionary = m["crouch"]
		pose[&"_hip_y"] = float(crouch["hip_drop"])
		pose[&"chest"] = float(crouch["chest"])
		_set_legs_from(pose, crouch["legs"])
	elif input.dashing:
		var dash: Dictionary = m["dash"]["forward" if signf(v.x) >= 0.0 else "back"]
		pose[&"chest"] = float(dash["chest"])
		_set_legs_from(pose, dash["legs"])
	elif not input.on_floor:
		var air: Dictionary = m["air"]["rise" if v.y < 0.0 else "fall"]
		pose[&"chest"] = float(air["chest"])
		_set_legs_from(pose, air["legs"])
	elif speed_ratio > float(move["threshold"]):
		_phase += v.x * TAU / maxf(8.0, float(move["stride"])) * delta
		var swing := float(move["swing"]) * minf(speed_ratio, 1.0)
		var front := sin(_phase)
		var back := sin(_phase + PI)
		var base := float(move["knee_base"])
		var bend := float(move["knee_bend"])
		pose[&"leg_front_upper"] = -front * swing
		pose[&"leg_front_lower"] = base + maxf(0.0, cos(_phase)) * bend * swing
		pose[&"leg_back_upper"] = -back * swing
		pose[&"leg_back_lower"] = base + maxf(0.0, cos(_phase + PI)) * bend * swing
		pose[&"_hip_y"] = -absf(sin(_phase)) * float(move["hip_bounce"]) * swing
		pose[&"chest"] = float(move["chest_lean"]) * speed_ratio * signf(v.x)
	else:
		# 待機：微微呼吸、重心落在後腳（呼吸的快慢與幅度、站姿都是這個角色自己的）。
		var breath := sin(_time * float(idle["breath_speed"]))
		pose[&"chest"] = float(idle["chest"]) + breath * float(idle["breath_amp"])
		pose[&"_hip_y"] = breath * float(idle["hip_bob"])
		_set_legs_from(pose, idle["legs"])

	var block: Dictionary = m["block"]
	var hurt: Dictionary = m["hurt"]
	if input.blocking:
		pose[&"chest"] = float(pose.get(&"chest", 0.0)) + float(block["chest"])
		if input.on_floor and not input.crouching:
			_set_legs_from(pose, block["legs"])
	if input.staggered:
		pose[&"chest"] = float(hurt["stagger_chest"])
	if _hurt_left > 0.0:
		pose[&"chest"] = float(pose.get(&"chest", 0.0)) - float(hurt["kick"]) * (_hurt_left / HURT_TIME)
	# 上半身跟著準星微轉，頭看向準星。
	var look: Dictionary = m["look"]
	pose[&"chest"] = float(pose.get(&"chest", 0.0)) + aim_angle * float(look["chest"]) - _recoil * 0.06
	pose[&"neck"] = aim_angle * float(look["neck"])
	pose[&"head"] = clampf(aim_angle * float(look["head"]), float(look["head_min"]), float(look["head_max"]))
	return pose


## 死亡姿勢（每個角色自己的死法）：fold＝先把腿折起來的程度（0＝直接倒，1＝先跪下／癱坐），rotation＝身體倒下的角度（負＝向後、正＝向前），
## ease＝倒下的節奏（out_cubic 先快後慢、linear、in_cubic 先慢後快）。
func _death_pose(pose: Dictionary, d: Dictionary) -> void:
	var t := clampf(_death_time / maxf(0.05, float(d["duration"])), 0.0, 1.0)
	var fold := float(d["fold"])
	var fold_t := 1.0 if fold <= 0.0 else clampf(t / 0.45, 0.0, 1.0)
	var fall_t := t if fold <= 0.0 else clampf((t - 0.3) / 0.7, 0.0, 1.0)
	var eased := _ease(fall_t, str(d["ease"]))
	var legs: Array = d["legs"]
	var folded: Array = d["fold_legs"]
	pose[&"hip"] = float(d["rotation"]) * eased
	pose[&"_hip_y"] = float(d["drop"]) * (eased if fold <= 0.0 else lerpf(fold_t * 0.45, 1.0, eased))
	pose[&"_hip_x"] = float(d["hip_x"]) * eased
	pose[&"chest"] = float(d["chest"]) * eased
	pose[&"neck"] = 0.1
	pose[&"head"] = float(d["head"]) * eased
	for i in 4:
		var bone: StringName = [&"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"][i]
		pose[bone] = lerpf(float(legs[i]), float(folded[i]), fold * fold_t * (1.0 - eased * 0.6))


static func _ease(t: float, kind: String) -> float:
	match kind:
		"linear":
			return t
		"in_cubic":
			return t * t * t
	return 1.0 - pow(1.0 - t, 3.0)


func _set_legs_from(pose: Dictionary, legs: Variant) -> void:
	var values: Array = legs
	_set_legs(pose, float(values[0]), float(values[1]), float(values[2]), float(values[3]))


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
	for bone_name: StringName in _spring_angle.keys():
		_rig.bone(bone_name).rotation = _spring_angle[bone_name]


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
	if _action_skip_ik and _action_w > 0.3:
		# 專屬動作自己決定手臂：武器跟著前手走，不再握槍瞄準。
		if _rig.has_bone(&"hand_front"):
			weapon_root.visible = not weapon.is_empty()
			weapon_root.position = _global_pos.get(&"hand_front", Vector2.ZERO)
			weapon_root.rotation = _global_angle.get(&"hand_front", 0.0) - PI * 0.5 if is_nan(_action_weapon_angle) else _action_weapon_angle
		return
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


## 專屬動作：把目前進度的骨頭角度（keys 之間緩動內插）依權重混進目標姿勢；沒有動作時權重淡出到 0。
func _apply_action(delta: float, input: RigInput, target: Dictionary) -> void:
	var def: Dictionary = {}
	if input.action != &"":
		var actions: Variant = RigLibrary.load_json(ACTIONS_PATH).get("actions", {})
		if typeof(actions) == TYPE_DICTIONARY and (actions as Dictionary).has(str(input.action)):
			def = (actions as Dictionary)[str(input.action)]
		else:
			RigLibrary.report_once("action:" + str(input.action), "[HumanoidAnimator] %s 沒有專屬動作「%s」" % [ACTIONS_PATH, input.action])
	if def.is_empty():
		_action_w = move_toward(_action_w, 0.0, 10.0 * delta)
	else:
		_action_skip_ik = bool(def.get("skip_ik", false))
		_action_weapon_angle = float(def["weapon_angle"]) if def.has("weapon_angle") else NAN
		_action_w = move_toward(_action_w, 1.0, float(def.get("blend", 12.0)) * delta)
		_action_pose = _sample_action(def, clampf(input.action_t, 0.0, 1.0))
	if _action_w <= 0.0:
		return
	for key: Variant in _action_pose.keys():
		var bone_name := StringName(str(key))
		var goal: float = _action_pose[key]
		if bone_name == &"_hip_x" or bone_name == &"_hip_y":
			target[bone_name] = lerpf(float(target.get(bone_name, 0.0)), goal, _action_w)
		else:
			target[bone_name] = lerp_angle(float(target.get(bone_name, _angles.get(bone_name, 0.0))), goal, _action_w)


## 動作在進度 t 的各骨頭角度（含 _hip_x／_hip_y）：每根骨頭只看有寫到它的 key，之間用 smoothstep 內插，前後超出就停在端點。
func _sample_action(def: Dictionary, t: float) -> Dictionary:
	var tracks: Dictionary = {}  # bone -> Array of [t, value]
	for key_entry: Variant in def.get("keys", []):
		if typeof(key_entry) != TYPE_DICTIONARY:
			continue
		var k := key_entry as Dictionary
		var kt := float(k.get("t", 0.0))
		var values: Dictionary = (k.get("bones", {}) as Dictionary).duplicate() if typeof(k.get("bones", {})) == TYPE_DICTIONARY else {}
		if k.has("hip_x"):
			values["_hip_x"] = k["hip_x"]
		if k.has("hip_y"):
			values["_hip_y"] = k["hip_y"]
		for bone: Variant in values.keys():
			if not tracks.has(bone):
				tracks[bone] = []
			(tracks[bone] as Array).append([kt, float(values[bone])])
	var out: Dictionary = {}
	for bone: Variant in tracks.keys():
		var points: Array = tracks[bone]
		var bone_name := StringName(str(bone))
		if bone_name != &"_hip_x" and bone_name != &"_hip_y" and not _rig.has_bone(bone_name):
			RigLibrary.report_once("action_bone:" + str(bone), "[HumanoidAnimator] %s 的動作用到不存在的骨頭：%s" % [ACTIONS_PATH, bone])
			continue
		var value: float = (points[points.size() - 1] as Array)[1]
		if t <= float((points[0] as Array)[0]):
			value = (points[0] as Array)[1]
		else:
			for i in range(points.size() - 1):
				var a: Array = points[i]
				var b: Array = points[i + 1]
				if t <= float(b[0]):
					var span := maxf(0.0001, float(b[0]) - float(a[0]))
					value = lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, (t - float(a[0])) / span))
					break
		out[bone_name] = value
	return out


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
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var dt := delta / steps
	for spring in _springs:
		var bone_name := StringName(str(spring.get("bone", "")))
		var base := trail * float(spring.get("trail", 1.0)) + lift * float(spring.get("lift", 1.0)) + wind * float(spring.get("wind", 1.0))
		if input.dead:
			base = 0.6
		var target := float(spring.get("rest", 0.0)) + base * float(spring.get("gain", 0.5))
		var stiffness := float(spring.get("stiffness", SPRING_STIFFNESS))
		var damping := float(spring.get("damping", SPRING_DAMPING))
		var low := float(spring.get("min", SPRING_MIN))
		var high := float(spring.get("max", SPRING_MAX))
		var velocity: float = _spring_velocity[bone_name]
		var angle: float = _spring_angle[bone_name]
		for i in steps:
			velocity += ((target - angle) * stiffness - velocity * damping) * dt
			angle = clampf(angle + velocity * dt, low, high)
		_spring_velocity[bone_name] = velocity
		_spring_angle[bone_name] = angle
