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
## events（選填）：只對列出的一次性事件反應，值是該事件注入的角速度（取代 impulse × gain）；例如胸口只在起跳、落地、急停跟一下，走路與站著不動（NE-257）。
##   事件：jump 起跳、land 落地、dash 衝刺、hurt 受擊、stop 跑動中急停。
const DEFAULT_SPRINGS: Array[Dictionary] = [
	{"bone": "coat_1", "rest": 0.15, "gain": 0.7},
	{"bone": "coat_2", "rest": 0.0, "gain": 0.5},
	{"bone": "hair_1", "rest": 0.25, "gain": 0.5},
	{"bone": "hair_2", "rest": 0.0, "gain": 0.4},
]
## 動作資料（art/motion/<角色>.json）缺的欄位用這份預設補（等於凜原本的手感）；每個角色都要有自己的檔案，測試會檢查不重複。
## 注意：合併時只收這份預設裡有的欄位（打錯字的欄位會被忽略），所以新增欄位一定要先在這裡給「不啟用」的預設值。
## 跑步（grounding＝true）的進階欄位，預設值都是不啟用，只有寫了數值的角色會改變：
##   move.duty／lift／reach：踩地比例（低於 0.5＝有騰空）、抬腳高度、伸展腿的長度比例（小於 1＝著地時膝蓋微彎）；
##   move.stride_exp／stride_floor：步長隨速度縮放（真人速度越慢步長越短，約 v^0.4～0.8）：步長＝stride × 速度比例^stride_exp，不低於 stride × stride_floor（stride_exp 為 0＝不縮放，步長固定）；
##   move.bounce／rise：踩地中段身體下沉、騰空時身體上升的像素（兩者都 0＝舊的固定下限）；
##   move.level／bob_slow：等高跑法（level＞0 啟用）：身體高度固定在「腿剛好夠得到最大步幅」的高度（膝蓋彎曲吸收，不靠身體上下），
##     bounce／rise 變成相對於這個高度的額外起伏（峰谷 = bounce + rise，建議 ≤ 0.09 L）；bob_slow 是慢速時起伏的比例（0~1，速度越快越接近 1）；
##   foot：腳掌滾動（heel 著地腳尖翹、toe_off 蹬地腳尖壓、droop 抬腳時下垂）；
##   torso：骨盆擺動 hip_swing、胸反向 chest_counter、胸的起伏 chest_wobble（wobble_phase 相位）、頭保持穩定 head_hold；
##   inertia：慣性前傾（見 InertiaLean）；
## 空中與落地（NE-192，同樣預設不啟用）：
##   air.apex_speed／apex／takeoff：垂直速度的絕對值低於 apex_speed 時在「上升／下落」與「頂點」姿勢之間連續混合（0＝舊的二選一）、起跳後 takeoff.time 秒的蹬地伸展；
##   land：落地吸收——gain＝衝擊 1 時彈簧的初速、stiffness／damping、drop＝身體下沉像素、chest＝前傾、legs＝膝蓋彎曲的腿姿（用彈簧所以回彈有過衝）；
##   dash.hip_drop：衝刺時身體壓低；impulse：起跳／落地／衝刺／受擊時對衣襬與頭髮彈簧注入的角速度（乘上各彈簧自己的 gain）；idle.pin_feet／pin_reach／feet_x／counter：待機時腳固定在地上、feet_x＝兩腳（前腳、後腳）離骨盆的前後距離像素（空陣列＝用 legs 的站姿腿角算出來的位置）、骨盆左右微移讓膝蓋彎曲（重心轉移）、pin_reach 是站姿腿長比例、counter 是胸的反向補償。
const MOTION_PATH := "res://art/motion/%s.json"
const DEFAULT_MOTION := {
	"grounding": false,
	"idle": {"breath_speed": 2.4, "breath_amp": 0.02, "hip_bob": 0.3, "chest": 0.0, "legs": [-0.12, 0.12, 0.2, 0.08], "sway": 0.0, "sway_speed": 1.3, "pin_feet": false, "pin_reach": 0.95, "counter": 0.0, "feet_x": []},
	"move": {"stride": 50.0, "swing": 0.8, "knee_bend": 1.2, "knee_base": 0.15, "hip_bounce": 1.4, "chest_lean": 0.12, "threshold": 0.08,
			"duty": 0.55, "lift": 5.0, "reach": 0.985, "bounce": 0.0, "rise": 0.0, "stride_exp": 0.0, "stride_floor": 0.45, "level": 0.0, "bob_slow": 0.5},
	"foot": {"droop": 0.25, "heel": 0.0, "toe_off": 0.0},
	"torso": {"hip_swing": 0.0, "chest_counter": 0.0, "chest_wobble": 0.0, "wobble_phase": 0.0, "head_hold": 0.0},
	"inertia": {"gain": 0.0, "ref_accel": 1600.0, "stiffness": 90.0, "damping": 11.0, "max": 0.3},
	"crouch": {"hip_drop": 8.0, "chest": 0.18, "legs": [-1.25, 2.05, -0.55, 1.85], "kneel": {}},
	# 空手時手臂怎麼垂、怎麼擺：hang＝[前上臂, 前前臂, 後上臂, 後前臂]（弧度；負的往前）。前手垂在身側、後手略往前，
	# 兩隻手臂的角度不能一樣，否則站著時會並排在同一側，看起來像一邊長了兩隻手。swing＝滿速時上臂前後擺的幅度，停下來就不擺。
	"arms": {"hang": [0.02, -0.18, -0.2, -0.28], "swing": 0.38},
	"air": {"rise": {"chest": 0.05, "legs": [-0.95, 1.4, 0.35, 0.7]}, "fall": {"chest": -0.05, "legs": [-0.35, 0.45, 0.45, 0.25]},
			"apex": {"chest": 0.0, "legs": [-0.6, 0.9, 0.4, 0.5]}, "apex_speed": 0.0, "takeoff": {"time": 0.0, "chest": 0.0, "legs": [0.0, 0.0, 0.0, 0.0]}},
	"dash": {"forward": {"chest": 0.38, "legs": [-1.0, 0.6, 0.85, 1.0]}, "back": {"chest": -0.22, "legs": [0.5, 0.9, -0.7, 0.4]}, "hip_drop": 0.0},
	"land": {"gain": 0.0, "stiffness": 220.0, "damping": 16.0, "drop": 0.0, "chest": 0.0, "legs": [-0.8, 1.3, 0.1, 0.9]},
	"impulse": {"jump": 0.0, "land": 0.0, "dash": 0.0, "hurt": 0.0, "stop": 0.0},
	"block": {"chest": 0.1, "legs": [-0.4, 0.5, 0.5, 0.2]},
	"hurt": {"stagger_chest": -0.35, "kick": 0.3},
	"look": {"chest": 0.12, "neck": 0.12, "head": 0.3, "head_min": -0.35, "head_max": 0.3},
	"npc": {"stand": {}, "talk_speed": 1.0, "talk_amp": 1.0, "life": {}},
	"relax": {"aim": 0.75, "reach": 0.8, "chest": -0.04, "speed": 6.0},
	"recoil": {"chest": 0.06, "reach": 2.5, "hip": 0.0, "decay": 9.0},
	"death": {"duration": 0.45, "rotation": -1.56, "drop": 21.0, "hip_x": -6.0, "chest": 0.15, "head": 0.35, "fold": 0.0, "fold_keep": 0.4, "ease": "out_cubic",
			"legs": [0.3, 0.1, 0.45, 0.05], "fold_legs": [-1.4, 2.0, -1.2, 1.9], "keys": {}, "rest_height": -1.0},
}
## 空著的手：手的貼圖是五指朝 +X 畫的（握槍時沿瞄準方向），手臂自然垂著時必須轉 90 度才會順著前臂；
## 不轉的話手腕會折成直角（看起來像手腕錯位）。稍微小於 90 度，手腕保持一點自然的彎。
const HAND_FOLLOWS_FOREARM := 1.4
## 後手握近戰武器的桿子時，最遠伸到手臂長度的幾成（再遠就不握，免得手肘打直或搆不到）。
const SECOND_HAND_REACH := 0.96
## 後手握點離肩膀至少是手臂全長的這個比例（再近手臂就縮在肩膀上）。
const SECOND_HAND_MIN := 0.25
const ARM_CHAINS: Array = [[&"arm_front_upper", &"arm_front_lower", &"hand_front"], [&"arm_back_upper", &"arm_back_lower", &"hand_back"]]
const ACTIONS_PATH := "res://art/rigs/action_poses.json"
const SPRING_MIN := -0.8
const SPRING_MAX := 1.6
const HURT_TIME := 0.22
## 腳踩實地補償的上限（像素）。
const GROUND_MAX_SHIFT := 16.0
## 躺平時骨頭中心離地的距離（肢體的厚度的一半）。
const CORPSE_THICKNESS := 3.0
## 跑步落腳：身體至少下沉多少（膝蓋微彎）、IK 與關節動畫的切換速度（每秒）。
const GAIT_MIN_SAG := 1.0
const GAIT_BLEND_SPEED := 8.0
## 受擊時頭與骨盆跟著身體的幅度（頭是胸的比例，骨盆往後頂的像素 / 弧度）。
const HURT_HEAD_RATIO := 0.6
const HURT_HIP_PUSH := 8.0
## 重擊致死時倒下的時間縮短到幾倍、倒下角度加大幾倍。
const DEATH_FORCE_TIME := 0.6
const DEATH_FORCE_ROTATION := 1.12
## 倒下的身體最多轉多少（超過 100° 腳會翹到空中）。
const DEATH_MAX_ROTATION := 1.75
const CROUCH_DROP := 8.0
## 單膝跪姿淡入淡出的速度（每秒）：約 0.15 秒跪到位，起身一樣快，不拖住操作。
const KNEEL_BLEND_SPEED := 7.0

const LEGS: Array[StringName] = [&"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"]
## 兩條腿的骨頭鏈（大腿、小腿、腳掌），順序＝前腳、後腳。
const LEG_CHAINS: Array = [[&"leg_front_upper", &"leg_front_lower", &"foot_front"], [&"leg_back_upper", &"leg_back_lower", &"foot_back"]]
## 跑步疊加層（骨盆、胸、頭的週期擺動）淡入淡出的速度（每秒）。
const RUN_OVERLAY_BLEND := 8.0
## 騰空只在接近全速時出現：速度比例低於 FLIGHT_FROM 是走路的落腳（總有一腳踩地、身體不上升），到 FLIGHT_FULL 才是資料寫的踩地比例與上升量。
const FLIGHT_FROM := 0.7
const FLIGHT_FULL := 1.0
const WALK_DUTY := 0.55

var _rig: CharacterRig
var _angles: Dictionary[StringName, float] = {}
var _hip_offset := Vector2.ZERO
var _phase := 0.0
var _time := 0.0
var _recoil := 0.0
var _hurt_left := 0.0
var _hurt_scale := 1.0
var _hurt_dir := 1.0
var _death_dir := 1.0
var _death_force := 0.0
var _death_time := 0.0
## 腳踩實地（資料 grounding＝true 的角色）：腳底離地時整個身體上下補償；站在地上時最低的腳底高度（骨架空間）、目前的補償量。
var _ground_y := 0.0
var _leg_length := 25.0
## 跑步的落腳（腳踩實地的角色）：這一格有沒有在跑、步伐幅度（腳在髖前後各移多遠）、踩地比例、抬腳高度、IK 權重與目前幅度。
var _gait_on := false
var _gait_amp := 0.0
var _gait_amp_now := 0.0
var _gait_duty := 0.55
var _gait_lift := 5.0
var _gait_w := 0.0
var _ground_shift := 0.0
## 跑步進階（見 DEFAULT_MOTION 的說明）：步伐週期 0~1、速度比例、疊加層的權重，以及不經過平滑、直接加在骨頭角度上的疊加角度。
var _cycle := 0.0
var _gait_speed_ratio := 0.0
var _gait_reach := 0.985
var _gait_floor := NAN
## 等高跑法（move.level）：這一格有沒有啟用、相對於固定高度的額外起伏（像素）。
var _gait_level := false
var _gait_bob := 0.0
var _run_w := 0.0
var _overlay: Dictionary[StringName, float] = {}
## 慣性前傾與面向（翻轉時重置加速度）。
var _inertia := InertiaLean.new()
var _lean := 0.0
var _last_facing := 0
## 落腳事件：某隻腳從前擺進入著地的那一格記一次（腳步聲對齊腳掌著地），擁有者用 consume_footfalls() 領走；上限避免沒人領時累積。
const MAX_PENDING_FOOTFALLS := 4
var _footfalls := 0
var _was_stance: Array[bool] = [false, false]
var _stance_known := false
## 起跳後蹬地伸展的剩餘秒數、落地吸收彈簧（位置 0＝站直、1＝吸收到最深；速度）。
var _takeoff_left := 0.0
var _land_x := 0.0
var _land_v := 0.0
## 待機：腳固定在地上（重心轉移）時兩腳的固定位置（骨架空間 x，前腳與後腳）、這一格是不是待機、固定的權重。
var _idle_on := false
var _idle_pin_w := 0.0
var _kneel_w := 0.0
var _kneel_parts := false  # 跪姿的專屬零件（前大腿用坐姿畫的那一塊）有沒有換上
var _idle_foot_x: Array[float] = [0.0, 0.0]
## 放鬆程度 0（舉槍）～1（槍垂下）。
var _relax := 0.0
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
		_angles[bone_name] = HAND_FOLLOWS_FOREARM if bone_name in [&"hand_front", &"hand_back"] else 0.0
	_forward_kinematics()
	_ground_y = _lowest_foot_y()
	if _global_pos.has(&"leg_front_upper"):
		_leg_length = maxf(8.0, _ground_y - _global_pos[&"leg_front_upper"].y)
	for entry in (rig.springs() if not rig.springs().is_empty() else DEFAULT_SPRINGS):
		var bone_name := _spring_key(entry)
		if not entry.has("warp") and not rig.has_bone(bone_name):
			continue  # 這個骨架沒有這根骨頭（例如舊骨架的衣襬）：略過
		var problem := spring_problem(entry)
		if not problem.is_empty():
			RigLibrary.report_once("spring:%s:%s" % [rig.skin_id, bone_name], "[HumanoidAnimator] %s 的擺動 %s 設定不合理（%s），這一項不擺動。" % [rig.skin_id, bone_name, problem])
			continue
		_springs.append(entry)
		_spring_angle[bone_name] = 0.0
		_spring_velocity[bone_name] = 0.0
	_far_arm_tuck = _measure_far_arm_tuck()
	_record_idle_feet()


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
			# 預設是空字典＝自由格式的欄位（例如 npc.stand、npc.life 的項目由資料決定），整份採用，不是逐鍵蓋過。
			if (base[key] as Dictionary).is_empty():
				base[key] = (over[key] as Dictionary).duplicate(true)
			else:
				_merge_into(base[key], over[key])
		elif base.has(key) and typeof(base[key]) == typeof(over[key]):
			base[key] = over[key]


func update(delta: float, input: RigInput) -> void:
	_time += delta
	if input.recoil > _recoil:
		_recoil = input.recoil
	_recoil = move_toward(_recoil, 0.0, float((_motion["recoil"] as Dictionary)["decay"]) * delta)
	if input.hurt:
		_hurt_left = HURT_TIME
		_hurt_scale = input.hurt_scale
		_hurt_dir = input.hurt_dir
		_kick_springs("hurt", input.hurt_dir)
	_take_events(delta, input)
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_death_time = _death_time + delta if input.dead else 0.0
	if input.dead and _death_time <= delta:  # 剛死的那一格記下最後一擊的方向與力道
		_death_dir = input.death_dir
		_death_force = input.death_force

	var local_velocity := Vector2(input.velocity.x * input.facing, input.velocity.y)
	# 翻面、瞬移（重生、過場換位）時，頭髮與衣襬不能被當成「瞬間移動了很遠」而甩一大下：彈簧直接放回靜止位置。
	var here := _rig.global_position
	var jumped := _last_position.is_finite() and here.distance_to(_last_position) > TELEPORT_DISTANCE
	_last_position = here
	if input.facing != _last_facing:
		_inertia.reset(local_velocity.x)  # 翻轉面向時速度的正負號會變，不能當成加速度
		if _last_facing != 0:
			reset_springs()
		_last_facing = input.facing
	elif jumped:
		reset_springs()
	_detect_stop(input, local_velocity)
	_lean = _inertia.update(delta, local_velocity.x, _motion["inertia"]) if not input.dead else 0.0
	var local_aim := Vector2(input.aim_dir.x * input.facing, input.aim_dir.y)
	var aim_angle := clampf(local_aim.angle(), -MAX_AIM_ANGLE, MAX_AIM_ANGLE)
	var relax: Dictionary = _motion["relax"]
	_relax = move_toward(_relax, 1.0 if input.relaxed and not input.dead else 0.0, float(relax["speed"]) * delta)
	var look_angle := aim_angle * (1.0 - _relax)  # 頭與上身看前方，不跟著垂下的槍口低頭
	aim_angle = lerpf(aim_angle, float(relax["aim"]), _relax)

	_gait_on = false
	_gait_floor = NAN
	_gait_level = false
	_idle_on = false
	var target := _body_pose(delta, input, local_velocity, look_angle)
	if not _gait_on:
		_stance_known = false  # 重新起跑時第一次著地不算「剛著地」，避免用舊狀態誤判
	_run_w = lerpf(_run_w, 1.0 if _gait_on else 0.0, 1.0 - exp(-RUN_OVERLAY_BLEND * delta))
	_update_run_overlay()
	target[&"_hip_x"] = float(target.get(&"_hip_x", 0.0)) - _recoil * float((_motion["recoil"] as Dictionary)["hip"])  # 開火的後座把身體往後頂
	_apply_action(delta, input, target)
	_apply_melee_body(input, target)
	var blend := 1.0 - exp(-POSE_SHARPNESS * delta)
	for bone_name: StringName in target.keys():
		if bone_name == &"_hip_y" or bone_name == &"_hip_x":
			continue
		_angles[bone_name] = lerp_angle(_angles.get(bone_name, 0.0), target[bone_name], blend)
	_hip_offset = _hip_offset.lerp(Vector2(target.get(&"_hip_x", 0.0), target.get(&"_hip_y", 0.0)), blend)

	_update_springs(delta, local_velocity, input)
	_ground_shift = 0.0
	_apply_body()
	_forward_kinematics()
	_feet_placed = false
	_post_pose(delta, input)
	_kneel(delta, input)
	var can_plant := bool(_motion.get("grounding", false)) and input.on_floor and not input.dead and not input.dashing and not input.crouching
	var can_pin := can_plant and _idle_on and not input.blocking and not input.staggered
	_gait_w = move_toward(_gait_w, 1.0 if _gait_on and can_plant else 0.0, GAIT_BLEND_SPEED * delta)
	_idle_pin_w = move_toward(_idle_pin_w, 1.0 if can_pin else 0.0, GAIT_BLEND_SPEED * delta)
	_gait_amp_now = lerpf(_gait_amp_now, _gait_amp if _gait_on else 0.0, 1.0 - exp(-10.0 * delta))
	if bool(_motion.get("grounding", false)) and input.on_floor and not input.dead and not input.dashing:
		if _gait_w > 0.01:
			_step_legs()
		elif not _feet_placed:  # 姿勢已經把腳放在地上（NPC 坐、蹲）時，不再用補償推翻它
			_plant_feet(delta)
			if _idle_pin_w > 0.01:
				_pin_feet()
	if input.dead:
		_rest_corpse()
	_drape_hems()
	if not input.dead:
		_solve_arms(input, aim_angle)
		_solve_melee_path(input)
		_forward_kinematics()  # 手臂 IK 之後重算一次，位置快取才是最終的姿勢
	else:
		_rig.weapon_root().visible = false


## 這一格姿勢有沒有已經把腳放到地上（子類別的 _post_pose 設定）；為真時跳過「腳踩實地」的補償。
var _feet_placed := false


## 姿勢算完、骨頭套用並求出位置之後的修正（子類別覆寫；NPC 動畫器用它把腳放平在地上）。預設什麼都不做。
func _post_pose(_delta: float, _input: RigInput) -> void:
	pass


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
		pose[&"_hip_y"] = float((m["dash"] as Dictionary)["hip_drop"])
		_set_legs_from(pose, dash["legs"])
	elif not input.on_floor:
		_air_pose(pose, m["air"], v.y)
	elif speed_ratio > float(move["threshold"]):
		var swing := float(move["swing"]) * minf(speed_ratio, 1.0)
		var grounded := bool(m.get("grounding", false))
		var stride := maxf(8.0, float(move["stride"]))
		var stride_exp := float(move["stride_exp"])
		if stride_exp > 0.0:
			stride *= clampf(pow(minf(speed_ratio, 1.0), stride_exp), float(move["stride_floor"]), 1.0)
		_phase += v.x * TAU / stride * delta
		if grounded:
			# 落腳：腳踩在地上時隨身體往後移（不滑），再抬起前擺；步伐幅度由資料的 stride 與踩地比例算出。
			_gait_on = true
			var flight := smoothstep(FLIGHT_FROM, FLIGHT_FULL, speed_ratio)
			_gait_duty = clampf(lerpf(maxf(WALK_DUTY, float(move["duty"])), float(move["duty"]), flight), 0.3, 0.8)
			_gait_amp = minf(stride * _gait_duty * 0.5, _leg_length * 0.75)
			_gait_lift = float(move["lift"]) * (0.5 + 0.5 * minf(speed_ratio, 1.0))
			_gait_reach = clampf(float(move["reach"]), 0.7, 1.0)
			_gait_speed_ratio = speed_ratio
			_cycle = fposmod(_phase / TAU, 1.0)
			_gait_floor = GaitShape.body_sag(_cycle, _gait_duty, float(move["bounce"]), float(move["rise"]) * flight)
			_gait_level = float(move["level"]) > 0.0
			if _gait_level:
				var slow := lerpf(float(move["bob_slow"]), 1.0, minf(speed_ratio, 1.0))
				var bob := GaitShape.body_sag(_cycle, _gait_duty, float(move["bounce"]) * slow, float(move["rise"]) * flight * slow)
				_gait_bob = 0.0 if is_nan(bob) else bob
			pose[&"chest"] = float(move["chest_lean"]) * speed_ratio * signf(v.x)
			pose[&"_hip_y"] = 0.0
		else:
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
		pose[&"_hip_x"] = sin(_time * float(idle["sway_speed"])) * float(idle["sway"])  # 重心左右微移
		pose[&"chest"] = float(pose[&"chest"]) + sin(_time * float(idle["sway_speed"]) + 0.6) * float(idle["counter"])  # 重心移動時胸反向補償
		_set_legs_from(pose, idle["legs"])
		_blend_land_legs(pose)
		_idle_on = bool(idle["pin_feet"])

	pose[&"chest"] = float(pose.get(&"chest", 0.0)) + _lean  # 慣性：加速前傾、煞車後仰
	if input.on_floor:
		pose[&"chest"] = float(pose[&"chest"]) + _land_x * float((m["land"] as Dictionary)["chest"])  # 落地吸收：身體前傾
	var block: Dictionary = m["block"]
	var hurt: Dictionary = m["hurt"]
	if input.blocking:
		pose[&"chest"] = float(pose.get(&"chest", 0.0)) + float(block["chest"])
		if input.on_floor and not input.crouching:
			_set_legs_from(pose, block["legs"])
	if input.staggered:
		pose[&"chest"] = float(hurt["stagger_chest"])
	if _hurt_left > 0.0:
		var kick := float(hurt["kick"]) * _hurt_scale * _hurt_dir * (_hurt_left / HURT_TIME)
		pose[&"chest"] = float(pose.get(&"chest", 0.0)) - kick
		pose[&"head"] = float(pose.get(&"head", 0.0)) - kick * HURT_HEAD_RATIO
		pose[&"_hip_x"] = float(pose.get(&"_hip_x", 0.0)) - kick * HURT_HIP_PUSH
	# 上半身跟著準星微轉，頭看向準星。
	var look: Dictionary = m["look"]
	pose[&"chest"] = float(pose.get(&"chest", 0.0)) + aim_angle * float(look["chest"]) - _recoil * float((_motion["recoil"] as Dictionary)["chest"])
	pose[&"neck"] = aim_angle * float(look["neck"])
	pose[&"head"] = clampf(aim_angle * float(look["head"]), float(look["head_min"]), float(look["head_max"]))
	return pose


## 死亡姿勢（每個角色自己的死法）：fold＝先把腿折起來的程度（0＝直接倒，1＝先跪下／癱坐），rotation＝身體倒下的角度（負＝向後、正＝向前），
## ease＝倒下的節奏（out_cubic 先快後慢、linear、in_cubic 先慢後快）。
func _death_pose(pose: Dictionary, d: Dictionary) -> void:
	var keyed := _death_keys()
	if not keyed.is_empty():
		_death_keyed_pose(pose, keyed)
		return
	var rotation := float(d["rotation"])
	# 從背後中彈：向後倒的角色改成向前撲（腿不先折起來），其他倒法不變。
	var flipped := _death_dir < 0.0 and rotation < 0.0
	var side := -1.0 if flipped else 1.0
	var duration := float(d["duration"]) * lerpf(1.0, DEATH_FORCE_TIME, _death_force)
	rotation = clampf(rotation * lerpf(1.0, DEATH_FORCE_ROTATION, _death_force), -DEATH_MAX_ROTATION, DEATH_MAX_ROTATION)
	var t := clampf(_death_time / maxf(0.05, duration), 0.0, 1.0)
	var fold := 0.0 if flipped else float(d["fold"])
	var fold_t := 1.0 if fold <= 0.0 else clampf(t / 0.45, 0.0, 1.0)
	var fall_t := t if fold <= 0.0 else clampf((t - 0.3) / 0.7, 0.0, 1.0)
	var eased := _ease(fall_t, str(d["ease"]))
	var legs: Array = d["legs"]
	var folded: Array = d["fold_legs"]
	pose[&"hip"] = rotation * side
	pose[&"_hip_y"] = float(d["drop"]) * (eased if fold <= 0.0 else lerpf(fold_t * 0.45, 1.0, eased))
	pose[&"_hip_x"] = float(d["hip_x"]) * eased * side
	pose[&"chest"] = float(d["chest"]) * eased * side
	pose[&"neck"] = 0.1
	pose[&"head"] = float(d["head"]) * eased * side
	# 手臂無力地順著身體放下（躺平時貼著身體、癱坐時垂在身前），前手比後手多彎一點；不撐著地面。
	# 癱坐（腿一直折著）時手臂垂向地面，躺下時貼著身體。
	var droop := 0.0
	if fold > 0.9 and float(d["fold_keep"]) > 0.9:
		droop = clampf(-(float(pose[&"hip"]) + float(pose[&"chest"])) * 0.8, -2.2, 2.2)
	pose[&"arm_front_upper"] = droop + 0.18
	pose[&"arm_front_lower"] = -0.3
	pose[&"arm_back_upper"] = droop + 0.05
	pose[&"arm_back_lower"] = -0.15
	pose[&"hand_front"] = HAND_FOLLOWS_FOREARM
	pose[&"hand_back"] = HAND_FOLLOWS_FOREARM
	for i in 4:
		var bone: StringName = [&"leg_front_upper", &"leg_front_lower", &"leg_back_upper", &"leg_back_lower"][i]
		pose[bone] = lerpf(float(legs[i]), float(folded[i]), fold * fold_t * (1.0 - eased * (1.0 - float(d["fold_keep"]))))


## 分段倒地（動作資料 death.keys 有內容時使用）：正面中彈用 supine（向後仰躺、臉朝上），背後中彈用 prone（向前俯臥、臉朝下）。
## 每一種是一串關鍵姿勢：{"duration": 秒, "frames": [{"t": 0~1, "hip_y": 骨盆下沉, "hip_x": 骨盆前後移, "bones": {骨頭: 角度}}, ...]}，
## 依序是失衡、重心下降、軀幹落地、四肢跟隨、停止；相鄰兩格之間平滑內插，某一格沒寫的骨頭沿用它上一次出現的角度。
## 力道大的一擊倒得比較快（和舊的倒法同一個倍率）。沒有這份資料的角色維持原本的倒法。
func _death_keys() -> Dictionary:
	var keys: Variant = (_motion["death"] as Dictionary).get("keys", {})
	if typeof(keys) != TYPE_DICTIONARY:
		return {}
	var chosen: Variant = (keys as Dictionary).get("prone" if _death_dir < 0.0 else "supine", {})
	if typeof(chosen) != TYPE_DICTIONARY or typeof((chosen as Dictionary).get("frames")) != TYPE_ARRAY or ((chosen as Dictionary)["frames"] as Array).size() < 2:
		return {}
	return chosen


## 這次倒地從開始到躺定要多久（秒）。
func _death_duration() -> float:
	var keyed := _death_keys()
	var base := float(keyed.get("duration", 0.9)) if not keyed.is_empty() else float(_motion["death"]["duration"])
	return base * lerpf(1.0, DEATH_FORCE_TIME, _death_force)


func _death_keyed_pose(pose: Dictionary, keyed: Dictionary) -> void:
	var frames: Array = keyed["frames"]
	var t := clampf(_death_time / maxf(0.05, _death_duration()), 0.0, 1.0)
	var next := 1
	while next < frames.size() - 1 and float((frames[next] as Dictionary).get("t", 1.0)) < t:
		next += 1
	var from: Dictionary = frames[next - 1]
	var to: Dictionary = frames[next]
	var t0 := float(from.get("t", 0.0))
	var span := maxf(0.0001, float(to.get("t", 1.0)) - t0)
	var w := smoothstep(0.0, 1.0, clampf((t - t0) / span, 0.0, 1.0))
	pose[&"_hip_y"] = lerpf(float(from.get("hip_y", 0.0)), float(to.get("hip_y", 0.0)), w)
	pose[&"_hip_x"] = lerpf(float(from.get("hip_x", 0.0)), float(to.get("hip_x", 0.0)), w)
	for bone_name in _rig.bone_order():
		var key := String(bone_name)
		var a := _death_key_angle(frames, next - 1, key)
		var b := _death_key_angle(frames, next, key)
		if is_nan(a) and is_nan(b):
			continue
		var rest := HAND_FOLLOWS_FOREARM if bone_name in [&"hand_front", &"hand_back"] else 0.0
		pose[bone_name] = lerp_angle(rest if is_nan(a) else a, rest if is_nan(b) else b, w)


## 某根骨頭在第 index 格（或更早的格）最後一次寫下的角度；從來沒寫過就回傳 NAN。
func _death_key_angle(frames: Array, index: int, key: String) -> float:
	for i in range(index, -1, -1):
		var bones: Variant = (frames[i] as Dictionary).get("bones", {})
		if typeof(bones) == TYPE_DICTIONARY and (bones as Dictionary).has(key):
			return float((bones as Dictionary)[key])
	return NAN


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

## 跑步的落腳：兩隻腳各有一個踩地／前擺的循環，踩地時腳底貼地並隨身體往後移動，前擺時抬起畫弧；
## 身體高度由腿能不能夠到地面決定（腿張最開時最低），兩段骨頭用 IK 夠到腳的位置，膝蓋朝前彎。
## 動作資料有 bounce／rise 時，身體高度另外依步伐起伏（踩地中段壓低、騰空時升高），腳掌依相位滾動（GaitShape）。
func _step_legs() -> void:
	var offsets: Array[Vector2] = []
	var angles: Array[float] = []
	var foot: Dictionary = _motion["foot"]
	_cycle = fposmod(_phase / TAU, 1.0)
	for i in LEG_CHAINS.size():
		var p := fposmod(_cycle + (0.0 if i == 0 else 0.5), 1.0)
		var stance := p < _gait_duty
		if _gait_on and _stance_known and stance and not _was_stance[i]:
			_footfalls = mini(_footfalls + 1, MAX_PENDING_FOOTFALLS)
		_was_stance[i] = stance
		var x := 0.0
		var lift := 0.0
		if p < _gait_duty:
			x = _gait_amp_now * (1.0 - 2.0 * p / _gait_duty)
		else:
			var t := (p - _gait_duty) / (1.0 - _gait_duty)
			x = _gait_amp_now * (-1.0 + 2.0 * smoothstep(0.0, 1.0, t))
			lift = _gait_lift * sin(PI * t)
		offsets.append(Vector2(x, lift))
		angles.append(GaitShape.foot_angle(p, _gait_duty, lift / maxf(0.1, _gait_lift), foot))
	_stance_known = _gait_on
	var floor_sag := GAIT_MIN_SAG if is_nan(_gait_floor) else _gait_floor
	if _gait_level:
		# 等高：固定在腿剛好夠得到最大步幅的高度（膝蓋彎曲吸收），再加上資料指定的小幅起伏。
		var reach := _leg_length * _gait_reach
		floor_sag = maxf(GAIT_MIN_SAG, _leg_length - sqrt(maxf(0.0, reach * reach - _gait_amp_now * _gait_amp_now))) + _gait_bob
	_place_feet(offsets, angles, _gait_w, floor_sag, _gait_reach, false, _land_sag())


## 待機時兩腳固定在地上：骨盆左右微移、身體隨之起伏，膝蓋自然彎曲（重心轉移），腳不滑。
func _pin_feet() -> void:
	var offsets: Array[Vector2] = []
	var angles: Array[float] = []
	for i in LEG_CHAINS.size():
		offsets.append(Vector2(_idle_foot_x[i] - _global_pos[LEG_CHAINS[i][0]].x, 0.0))
		angles.append(0.0)
	_place_feet(offsets, angles, _idle_pin_w, 0.0, float((_motion["idle"] as Dictionary)["pin_reach"]), true, _land_sag())


## 兩隻腳用 IK 放到指定位置：offsets 是相對各自髖關節的目標（x＝前後，y＝抬離地面的高度），angles 是腳掌的絕對角度；
## 身體下沉量＝兩隻腳都夠得到的最小值，但不低於 floor_sag（可以是負的＝身體上升）；weight 是 IK 結果與原本關節動畫的混合（0~1），
## extra_sag 是額外再壓低的像素（落地吸收：腿比夠得到的距離更彎）；blend_shift 為真時身體高度也跟著 weight 從目前的高度混過去（淡入中的待機固定腳用，不然身體先到位、腿還沒到位會陷進地面）。
func _place_feet(offsets: Array[Vector2], angles: Array[float], weight: float, floor_sag: float, reach_ratio: float, blend_shift := false, extra_sag := 0.0) -> void:
	var reach := _leg_length * reach_ratio
	var drop := floor_sag
	for offset in offsets:
		drop = maxf(drop, _leg_length - offset.y - sqrt(maxf(0.0, reach * reach - offset.x * offset.x)))
	drop = minf(drop + extra_sag, GROUND_MAX_SHIFT)
	_ground_shift = lerpf(_ground_shift, drop, weight) if blend_shift else drop
	_apply_body()
	_forward_kinematics()
	for i in LEG_CHAINS.size():
		var chain: Array = LEG_CHAINS[i]
		var upper: StringName = chain[0]
		var lower: StringName = chain[1]
		var foot: StringName = chain[2]
		if not (_rig.has_bone(upper) and _rig.has_bone(lower) and _rig.has_bone(foot)):
			continue
		var before := [_rig.bone(upper).rotation, _rig.bone(lower).rotation, _rig.bone(foot).rotation]
		var hip: Vector2 = _global_pos[upper]
		_reach_leg(upper, lower, foot, Vector2(hip.x + offsets[i].x, _ground_y - offsets[i].y), angles[i])
		_rig.bone(upper).rotation = lerp_angle(before[0], _rig.bone(upper).rotation, weight)
		_rig.bone(lower).rotation = lerp_angle(before[1], _rig.bone(lower).rotation, weight)
		_rig.bone(foot).rotation = lerp_angle(before[2], _rig.bone(foot).rotation, weight)
	_forward_kinematics()


## 單膝跪（動作資料 crouch.kneel 有內容時，蹲下就用它）：後膝著地、後腳腳尖點地，前腳掌用 IK 平放在地上。
## 骨盆高度由後大腿的角度與膝蓋半徑算出來，不是手調的 hip_drop，所以腿長不同的骨架用同一份資料也不會懸空或陷進地面。
## kneel：{"back_thigh": 後大腿相對直立的角度, "back_shin": 後小腿相對大腿, "back_foot": 後腳相對小腿（都是弧度，正的往後折）,
##         "knee_radius": 膝蓋中心離地（世界像素）, "front_foot_x": 前腳踝在骨盆前方多遠（大腿長的倍數）}。
## 骨架原點在腳底，所以地面是 y = 0；_ground_y 是站立時腳踝的高度，前腳踝就放在那裡。
func _kneel(delta: float, input: RigInput) -> void:
	var kneel: Dictionary = (_motion["crouch"] as Dictionary).get("kneel", {})
	var want := 1.0 if input.crouching and input.on_floor and not input.dead and not kneel.is_empty() else 0.0
	_kneel_w = move_toward(_kneel_w, want, KNEEL_BLEND_SPEED * delta)
	# 有跪姿專屬零件的外觀，跪下過半時換上、起身過半時換回；只收回自己換上的那一組，不動別人選的（過場的坐姿）。
	if (_kneel_w >= 0.5) != _kneel_parts:
		_kneel_parts = not _kneel_parts
		if _kneel_parts and _rig.has_pose_parts(&"kneel"):
			_rig.set_pose_parts(&"kneel")
		elif _rig.active_pose_parts() == &"kneel":
			_rig.set_pose_parts(&"")
	if _kneel_w <= 0.001 or kneel.is_empty():
		return
	var bones: Array[StringName] = [&"leg_back_upper", &"leg_back_lower", &"foot_back", &"leg_front_upper", &"leg_front_lower", &"foot_front"]
	for bone_name in bones:
		if not _rig.has_bone(bone_name):
			return
	_feet_placed = true
	var thigh := _rig.rest(&"leg_back_lower").length()
	var back_thigh := float(kneel.get("back_thigh", 0.0))
	var hip_y := -float(kneel.get("knee_radius", 0.0)) - thigh * cos(back_thigh)
	_ground_shift = lerpf(_ground_shift, hip_y - _rig.rest(&"leg_back_upper").y - _rig.rest(&"hip").y - _hip_offset.y, _kneel_w)
	_apply_body()
	_forward_kinematics()
	var before: Array[float] = []
	for bone_name in bones:
		before.append(_rig.bone(bone_name).rotation)
	_rig.bone(&"leg_back_upper").rotation = back_thigh - float(_global_angle.get(&"hip", 0.0))
	_rig.bone(&"leg_back_lower").rotation = float(kneel.get("back_shin", 0.0))
	_rig.bone(&"foot_back").rotation = float(kneel.get("back_foot", 0.0))
	var hip: Vector2 = _global_pos[&"leg_front_upper"]
	_reach_leg(&"leg_front_upper", &"leg_front_lower", &"foot_front", Vector2(hip.x + float(kneel.get("front_foot_x", 1.0)) * thigh, _ground_y), 0.0)
	for i in bones.size():
		_rig.bone(bones[i]).rotation = lerp_angle(before[i], _rig.bone(bones[i]).rotation, _kneel_w)
	_forward_kinematics()
	# 跪下與起身的途中兩個姿勢各佔一部分，腳可能陷進地面或懸空：把最低的那隻腳放回地面（跪到位時前腳本來就在地上，這裡是 0）。
	# 只移骨盆：_apply_body 會把腿的角度換回姿勢資料的值。
	var lift := _ground_y - _lowest_foot_y()
	_ground_shift += lift
	_rig.bone(&"hip").position.y += lift
	_forward_kinematics()


## 空中姿勢：垂直速度的絕對值低於 apex_speed 時，在「頂點」與「上升／下落」姿勢之間連續混合（沒有頂點瞬間切換）；apex_speed 為 0 時是舊的二選一。
## 起跳後 takeoff.time 秒內再混入蹬地伸展（腿打直、胸挺起），隨後收腿。
func _air_pose(pose: Dictionary, air: Dictionary, vy: float) -> void:
	var apex_speed := float(air["apex_speed"])
	var chest := 0.0
	var legs: Array = []
	if apex_speed <= 0.0:
		var side: Dictionary = air["rise" if vy < 0.0 else "fall"]
		chest = float(side["chest"])
		legs = side["legs"]
	else:
		var w := clampf(vy / apex_speed, -1.0, 1.0)
		var apex: Dictionary = air["apex"]
		var far: Dictionary = air["rise" if w < 0.0 else "fall"]
		var k := absf(w)
		chest = lerpf(float(apex["chest"]), float(far["chest"]), k)
		for i in 4:
			legs.append(lerpf(float((apex["legs"] as Array)[i]), float((far["legs"] as Array)[i]), k))
	var takeoff: Dictionary = air["takeoff"]
	var takeoff_time := float(takeoff["time"])
	if takeoff_time > 0.0 and _takeoff_left > 0.0:
		var t := smoothstep(0.0, 1.0, _takeoff_left / takeoff_time)
		chest = lerpf(chest, float(takeoff["chest"]), t)
		for i in 4:
			legs[i] = lerpf(float(legs[i]), float((takeoff["legs"] as Array)[i]), t)
	pose[&"chest"] = chest
	_set_legs_from(pose, legs)


## 一次性事件（起跳、落地、衝刺）：起跳啟動蹬地伸展、落地給吸收彈簧一個初速，並對衣襬與頭髮注入衝量。吸收彈簧每格推進。
func _take_events(delta: float, input: RigInput) -> void:
	var motion_air: Dictionary = _motion["air"]
	if input.jumped:
		_takeoff_left = float((motion_air["takeoff"] as Dictionary)["time"])
		_kick_springs("jump", 1.0)
	if input.landed > 0.0:
		_land_v += input.landed * float((_motion["land"] as Dictionary)["gain"])
		_kick_springs("land", input.landed)
	if input.dash_started:
		_kick_springs("dash", 1.0)
	_takeoff_left = maxf(0.0, _takeoff_left - delta)
	var land: Dictionary = _motion["land"]
	if float(land["gain"]) <= 0.0:
		_land_x = 0.0
		_land_v = 0.0
		return
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var dt := delta / steps
	for i in steps:
		_land_v += (-_land_x * float(land["stiffness"]) - _land_v * float(land["damping"])) * dt
		_land_x = clampf(_land_x + _land_v * dt, -0.3, 1.2)


## 落地吸收的身體下沉像素（彈簧位置 × 資料的 drop；回彈過衝時不往上抬，免得腳離地）。
func _land_sag() -> float:
	return maxf(0.0, _land_x) * float((_motion["land"] as Dictionary)["drop"])


## 落地吸收時把腿從原本的姿勢混向「膝蓋彎曲」的腿姿（沒有用 IK 固定腳的角色用；用 IK 的由 _land_sag 壓低身體）。
func _blend_land_legs(pose: Dictionary) -> void:
	if _land_x <= 0.001:
		return
	var folded: Array = (_motion["land"] as Dictionary)["legs"]
	var k := clampf(_land_x, 0.0, 1.0)
	for i in 4:
		pose[LEGS[i]] = lerpf(float(pose[LEGS[i]]), float(folded[i]), k)


## 垂在腿前的下襬（圍裙、長衣襬）在坐下、蹲下時搭在大腿上：彈簧資料寫 "drape": 大腿骨頭名（可加 "drape_tip": 第二節骨頭）。大腿抬起超過 DRAPE_FROM 弧度後，
## 下襬逐漸跟著大腿轉；走路的擺腿幅度在這之下，下襬不跟（跟了就會像裂成兩片）。腿的 IK 都做完之後才呼叫。
const DRAPE_FROM := 0.55
const DRAPE_FULL := 1.1
func _drape_hems() -> void:
	for spring in _springs:
		if not spring.has("drape"):
			continue
		var hem := _rig.bone(_spring_key(spring))
		var thigh := _rig.bone(StringName(str(spring["drape"])))
		if hem == null or thigh == null or hem.get_parent() != thigh.get_parent():
			continue
		var follow := thigh.rotation * smoothstep(DRAPE_FROM, DRAPE_FULL, absf(thigh.rotation)) * float(spring.get("drape_gain", 1.0))
		hem.rotation += follow
		# 比大腿長的下襬（長圍裙）：過了膝蓋的那一段垂下來，不是一塊板子伸出去。"drape_tip": 下襬第二節的骨頭名。
		var tip := _rig.bone(StringName(str(spring.get("drape_tip", ""))))
		if tip != null:
			tip.rotation -= follow * float(spring.get("drape_tip_gain", 0.9))


## 一格內移動超過這個距離（世界像素）就當成瞬移，不是跑過去的（衝刺每格約 6）。
const TELEPORT_DISTANCE := 48.0
var _last_position := Vector2.INF


## 所有次級擺動（頭髮、衣襬、區域擺動）回到靜止位置、速度歸零。重生、進出過場、換場景後呼叫；翻面與瞬移時動畫器自己會呼叫。
func reset_springs() -> void:
	_stop_peak = 0.0
	for spring in _springs:
		var key := _spring_key(spring)
		_spring_angle[key] = clampf(float(spring.get("rest", 0.0)), float(spring.get("min", SPRING_MIN)), float(spring.get("max", SPRING_MAX)))
		_spring_velocity[key] = 0.0
		if spring.has("warp"):
			_rig.set_sway(key, 0.0)


## 彈簧的名字：有骨頭的用骨頭名，區域擺動（warp）用自己的 id。
func _spring_key(spring: Dictionary) -> StringName:
	return StringName(str(spring.get("id", ""))) if spring.has("warp") else StringName(str(spring.get("bone", "")))


## 對所有次級動態彈簧（衣襬、頭髮）注入角速度：資料的 impulse 乘上事件強度與各彈簧自己的 gain，沒設定就不動。
## 有 events 的彈簧只對列出的事件反應，用自己的數值。
func _kick_springs(event: String, strength: float) -> void:
	var shared := float((_motion["impulse"] as Dictionary).get(event, 0.0)) * strength
	for spring in _springs:
		var amount := shared * float(spring.get("gain", 0.5))
		var events: Variant = spring.get("events")
		if typeof(events) == TYPE_DICTIONARY:
			amount = float((events as Dictionary).get(event, 0.0)) * strength
		if is_zero_approx(amount):
			continue
		var bone_name := _spring_key(spring)
		_spring_velocity[bone_name] = float(_spring_velocity[bone_name]) + amount


## 檢查一項擺動設定的數值是否合理；合理回傳空字串，否則回傳原因（指出欄位）。
static func spring_problem(entry: Dictionary) -> String:
	for key: String in ["rest", "gain", "stiffness", "damping", "min", "max", "trail", "lift", "wind"]:
		if entry.has(key) and not (typeof(entry[key]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(entry[key]))):
			return "%s 不是數字" % key
	if float(entry.get("stiffness", SPRING_STIFFNESS)) <= 0.0:
		return "stiffness 必須大於 0"
	if float(entry.get("damping", SPRING_DAMPING)) < 0.0:
		return "damping 不能是負的"
	if float(entry.get("min", SPRING_MIN)) > float(entry.get("max", SPRING_MAX)):
		return "min 大於 max"
	if entry.has("events"):
		var events: Variant = entry["events"]
		if typeof(events) != TYPE_DICTIONARY:
			return "events 要是「事件：數值」"
		for key: Variant in (events as Dictionary).keys():
			if not str(key) in SPRING_EVENTS:
				return "events 的 %s 不是已知事件（%s）" % [key, ", ".join(SPRING_EVENTS)]
			if not (typeof(events[key]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(events[key]))):
				return "events.%s 不是數字" % key
	return ""


## 會注入擺動的一次性事件。
const SPRING_EVENTS: PackedStringArray = ["jump", "land", "dash", "hurt", "stop"]
## 急停：在地上跑到滿速的這個比例以上，速度又降到這個比例以下，算一次急停（強度＝原本的速度比例）。
const STOP_ARM_RATIO := 0.6
const STOP_DONE_RATIO := 0.12
var _stop_peak := 0.0


## 跑動中急停時對擺動注入一次衝量；只在地上、沒死的時候算，同一次減速只算一次。
func _detect_stop(input: RigInput, local_velocity: Vector2) -> void:
	if not input.on_floor or input.dead:
		_stop_peak = 0.0
		return
	var ratio := absf(local_velocity.x) / maxf(1.0, input.run_speed)
	if ratio >= STOP_ARM_RATIO:
		_stop_peak = maxf(_stop_peak, ratio)
	elif ratio <= STOP_DONE_RATIO and _stop_peak > 0.0:
		_kick_springs("stop", clampf(_stop_peak, 0.0, 1.0))
		_stop_peak = 0.0


## 跑步時骨盆、胸、頭的週期擺動：骨盆隨步伐前後擺，胸反向補償並有自己的起伏，頭抵消這些擺動而保持穩定。
## 直接加在骨頭角度上（不經過姿勢平滑），不然平滑的延遲會讓擺動和腳步對不上。
func _update_run_overlay() -> void:
	_overlay.clear()
	if _run_w < 0.001:
		return
	var torso: Dictionary = _motion["torso"]
	var k := _run_w * clampf(_gait_speed_ratio, 0.0, 1.0)
	var hip_swing := float(torso["hip_swing"]) * sin(TAU * _cycle) * k
	var chest := -hip_swing * float(torso["chest_counter"]) + float(torso["chest_wobble"]) * sin(TAU * 2.0 * _cycle + float(torso["wobble_phase"])) * k
	_overlay[&"hip"] = hip_swing
	_overlay[&"chest"] = chest
	_overlay[&"head"] = -(hip_swing + chest) * float(torso["head_hold"])


## 記下待機站姿（站姿腿角）時兩腳的位置，「腳固定在地上」的待機就釘在這兩點。
func _record_idle_feet() -> void:
	var legs: Array = (_motion["idle"] as Dictionary)["legs"]
	for i in LEGS.size():
		_angles[LEGS[i]] = float(legs[i])
	_apply_body()
	_forward_kinematics()
	for i in LEG_CHAINS.size():
		var foot: StringName = LEG_CHAINS[i][2]
		_idle_foot_x[i] = _global_pos[foot].x if _global_pos.has(foot) else 0.0
	var feet_x: Array = (_motion["idle"] as Dictionary)["feet_x"]
	if feet_x.size() >= 2:
		for i in 2:
			_idle_foot_x[i] = _rig.rest(&"hip").x + float(feet_x[i])
	for bone_name: StringName in _angles.keys():
		_angles[bone_name] = HAND_FOLLOWS_FOREARM if bone_name in [&"hand_front", &"hand_back"] else 0.0
	_apply_body()
	_forward_kinematics()


## 腿的兩段 IK（和手臂相同，只是膝蓋朝前彎）；foot_angle 是腳掌的絕對角度（0＝放平）。
func _reach_leg(upper: StringName, lower: StringName, foot: StringName, target: Vector2, foot_angle: float) -> void:
	var hip: Vector2 = _global_pos[upper]
	var length_upper := _rig.rest(lower).length()
	var length_lower := _rig.rest(foot).length()
	var to_target := target - hip
	var distance := clampf(to_target.length(), 0.01, length_upper + length_lower - 0.01)
	var base := to_target.angle()
	var cos_alpha := clampf((length_upper * length_upper + distance * distance - length_lower * length_lower) / (2.0 * length_upper * distance), -1.0, 1.0)
	var upper_dir := base - acos(cos_alpha)
	var knee := hip + Vector2.RIGHT.rotated(upper_dir) * length_upper
	var lower_dir := (target - knee).angle()
	var parent_angle: float = _global_angle.get(_rig.parent_of(upper), 0.0)
	var upper_global := upper_dir - PI * 0.5
	var lower_global := lower_dir - PI * 0.5
	_rig.bone(upper).rotation = angle_difference(parent_angle, upper_global)
	_rig.bone(lower).rotation = angle_difference(upper_global, lower_global)
	_rig.bone(foot).rotation = angle_difference(lower_global, foot_angle)


## 倒下的身體不陷進地裡：倒下途中只把陷進去的部分往上推，倒完（姿勢到位）後整個貼地躺平。
func _rest_corpse() -> void:
	var low := -INF
	for bone_name in _rig.bone_order():
		if _spring_angle.has(bone_name):
			continue  # 頭髮與衣襬的彈簧骨垂在身體下面時，不能把整個身體墊高
		low = maxf(low, _global_pos[bone_name].y)
	# rest_height（動作資料）：躺定時最低的骨頭離腳底地面多高，也就是身體厚度的一半；負值＝沒設定，用舊的固定值（相對腳踝高度）。
	var rest_height := _death_rest_height()
	var target := -rest_height if rest_height >= 0.0 else _ground_y - CORPSE_THICKNESS
	var settled := _death_time >= _death_duration() * 1.05
	var shift := target - low
	_ground_shift = shift if settled else minf(0.0, shift)
	_apply_body()
	_forward_kinematics()


## 躺定時最低的骨頭離腳底地面多高（動作資料 death.rest_height，仰躺與俯臥可以在 keys 裡各寫各的）；負值＝沒設定。
func _death_rest_height() -> float:
	return float(_death_keys().get("rest_height", (_motion["death"] as Dictionary).get("rest_height", -1.0)))


## 倒地的身體貼著哪個高度（骨架空間）：有設定 rest_height 的角色躺在腳底的地面上（骨架原點），其他角色沿用舊規則（站立時腳踝的高度）。稽核用。
func corpse_floor() -> float:
	return 0.0 if _death_rest_height() >= 0.0 else _ground_y


## 目前身體整個往下沉了多少（骨架空間，往下為正）：蹲下時槍口與準星的高度由它算出。
func current_hip_drop() -> float:
	return _hip_offset.y + _ground_shift


## 兩腳正在用落腳 IK 跑步（腳步聲可以跟著落腳事件走）；停下、蹲著、空中、衝刺時是 false。
func is_stepping() -> bool:
	return _gait_on and _gait_w > 0.5


## 領走自上次呼叫以來的落腳次數（每隻腳著地一次）。
func consume_footfalls() -> int:
	var count := _footfalls
	_footfalls = 0
	return count


## 這個角色全速奔跑時有沒有騰空（踩地比例低於走路的落腳）。
func has_flight() -> bool:
	return bool(_motion.get("grounding", false)) and float((_motion["move"] as Dictionary)["duty"]) < WALK_DUTY


## 稽核用：骨頭目前的位置（骨架空間）與站立時的地面高度。
func bone_pos(bone_name: StringName) -> Vector2:
	return _global_pos.get(bone_name, Vector2.ZERO)


func ground_level() -> float:
	return _ground_y


## 骨頭目前的絕對角度（骨架空間，弧度）；稽核與測試用。
func foot_angle(bone_name: StringName) -> float:
	return _global_angle.get(bone_name, 0.0)


## 最低的腳底（骨架空間，往下為正）。
func _lowest_foot_y() -> float:
	var low := -INF
	for foot: StringName in [&"foot_front", &"foot_back"]:
		if _global_pos.has(foot):
			low = maxf(low, _global_pos[foot].y)
	return low if low > -INF else 0.0


## 腳踩實地：量出最低的腳底離站立時的地面差多少，把整個身體上下補償回去，腳就不會懸空或陷進地裡；
## 跑步時身體高度因此自然隨腿張開而起伏（腿張最開最低、腿併攏最高）。
func _plant_feet(delta: float) -> void:
	var needed := clampf(_ground_y - _lowest_foot_y(), -GROUND_MAX_SHIFT, GROUND_MAX_SHIFT)
	_ground_shift = needed
	_apply_body()
	_forward_kinematics()


func _apply_body() -> void:
	for bone_name: StringName in _angles.keys():
		var b := _rig.bone(bone_name)
		if b != null:
			b.rotation = _angles[bone_name] + _overlay.get(bone_name, 0.0)
	var hip := _rig.bone(&"hip")
	if hip != null:
		hip.position = _rig.rest(&"hip") + _hip_offset + Vector2(0.0, _ground_shift)
	for bone_name: StringName in _spring_angle.keys():
		var bone := _rig.bone(bone_name)
		if bone != null:
			bone.rotation += _spring_angle[bone_name]


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
	var action_arms := {}
	var action_hand := Vector2.ZERO
	var action_weapon_angle := 0.0
	if _action_skip_ik and _action_w > 0.001:
		# 專屬動作自己決定手臂：武器跟著前手走，不再握槍瞄準。權重還沒滿（進出動作的過渡）時，
		# 手臂在「動作姿勢」與「握槍瞄準」之間依權重混合，才不會瞬間跳位。
		if _rig.has_bone(&"hand_front"):
			weapon_root.visible = not weapon.is_empty()
			action_hand = _global_pos.get(&"hand_front", Vector2.ZERO) + _rig.hand_grip_offset(&"hand_front").rotated(_global_angle.get(&"hand_front", 0.0))
			action_weapon_angle = _global_angle.get(&"hand_front", 0.0) - PI * 0.5 if is_nan(_action_weapon_angle) else _action_weapon_angle
			if _action_w >= 0.999:
				weapon_root.position = action_hand
				weapon_root.rotation = action_weapon_angle
				return
			for arm: Array in ARM_CHAINS:
				for bone_name: StringName in arm:
					if _rig.has_bone(bone_name):
						action_arms[bone_name] = _rig.bone(bone_name).rotation
	var anchor: Array = _rig.weapon_anchor()
	var anchor_bone: StringName = anchor[0]
	var anchor_point: Vector2 = _global_pos.get(anchor_bone, Vector2.ZERO) + (anchor[1] as Vector2).rotated(_global_angle.get(anchor_bone, 0.0))
	var reach: float = anchor[2] * (0.7 if input.blocking else 1.0) - _recoil * float((_motion["recoil"] as Dictionary)["reach"])
	var aim := Vector2.RIGHT.rotated(aim_angle)
	if not weapon.is_empty():
		var minimum := 0.0
		var maximum := INF
		for chain: Array in ARM_CHAINS:
			var hand: StringName = chain[2]
			if hand == &"hand_back" and (not input.two_handed or input.shield_forward):
				continue
			if not (_rig.has_bone(chain[0]) and _rig.has_bone(chain[1]) and _rig.has_bone(hand)):
				continue
			var fore := (RigLibrary.vec2(weapon.get("foregrip")) - RigLibrary.vec2(weapon.get("grip"))) * _rig.weapon_scale() if hand == &"hand_back" else Vector2.ZERO
			var delta_to_shoulder: Vector2 = anchor_point + (fore - _rig.hand_grip_offset(hand)).rotated(aim_angle) - _global_pos[chain[0]]
			var length := _rig.rest(chain[1]).length() + _rig.rest(hand).length() - 0.01
			var along := delta_to_shoulder.dot(aim)
			var discriminant := length * length - (delta_to_shoulder.length_squared() - along * along)
			if discriminant < 0.0:
				maximum = -INF
				break
			var span := sqrt(discriminant)
			minimum = maxf(minimum, -along - span)
			maximum = minf(maximum, -along + span)
		if minimum <= maximum:
			reach = clampf(reach, minimum, maximum)
		else:
			RigLibrary.report_once("grip-reach:%s:%s" % [_rig.skin_id, weapon.get("file", "")], "[HumanoidAnimator] %s weapon %s has no reachable two-hand grip at %.2f radians" % [_rig.skin_id, weapon.get("file", ""), aim_angle])
	var grip := anchor_point + aim * reach

	if weapon.is_empty():
		# 沒有武器：雙手自然下垂、隨步伐輕擺（不是伸出去握著空氣）。
		weapon_root.visible = false
		var hang := _arm_hang()
		_set_rotation(&"arm_front_upper", hang[0] + sin(_phase) * _arm_swing(input))
		_set_rotation(&"arm_front_lower", hang[1])
		_set_rotation(&"hand_front", HAND_FOLLOWS_FOREARM)
	else:
		weapon_root.visible = true
		weapon_root.position = grip
		weapon_root.rotation = aim_angle
		_reach_arm(&"arm_front_upper", &"arm_front_lower", &"hand_front", grip - _rig.hand_grip_offset(&"hand_front").rotated(aim_angle), aim_angle)

	if input.shield_forward:
		var shoulder: Vector2 = _global_pos.get(&"arm_back_upper", anchor_point)
		# 盾牌貼圖是直立的，手部角度只跟著準星微幅傾斜。
		_reach_arm(&"arm_back_upper", &"arm_back_lower", &"hand_back", shoulder + aim * 13.0 + Vector2(0, 2), aim_angle * 0.3)
	elif input.two_handed and not weapon.is_empty():
		var offset := (RigLibrary.vec2(weapon.get("foregrip")) - RigLibrary.vec2(weapon.get("grip"))) * _rig.weapon_scale()
		_reach_arm(&"arm_back_upper", &"arm_back_lower", &"hand_back", grip + (offset - _rig.hand_grip_offset(&"hand_back")).rotated(aim_angle), aim_angle)
	elif _second_hand_reaches(input, weapon):
		# 雙手的近戰武器：後手握在桿子上（搆得到才握，不拉長手臂）。
		_reach_arm(&"arm_back_upper", &"arm_back_lower", &"hand_back",
				input.melee_second_target - _rig.hand_grip_offset(&"hand_back").rotated(input.melee_second_angle), input.melee_second_angle)
	else:
		# 空著的後手自然下垂、隨步伐輕擺。
		var far_hang := _far_arm_hang()
		var far_swing := sin(_phase + PI) * _arm_swing(input)
		if far_hang == _far_arm_tuck:  # 藏在身體後面的手，擺動也不探出去（只露出一隻沒有前臂的手，比不擺更糟）
			far_swing = clampf(far_swing, -_far_arm_swing_limit, _far_arm_swing_limit)
			# 跑步時上身前傾、肩膀跟著往前：依現在的肩與髖重算，手才留在髖的正後方
			var far_reach := _rig.rest(&"arm_back_lower").length() + _rig.rest(&"hand_back").length()
			var far_forward := float(_global_pos[&"leg_front_upper"].x) - float(_global_pos[&"arm_back_upper"].x)
			far_hang.x = -asin(clampf(far_forward / far_reach, -0.6, 0.6)) - FAR_ARM_ELBOW * 0.5 - float(_global_angle.get(_rig.parent_of(&"arm_back_upper"), 0.0))
		_set_rotation(&"arm_back_upper", far_hang.x + far_swing)
		_set_rotation(&"arm_back_lower", far_hang.y)
		_set_rotation(&"hand_back", HAND_FOLLOWS_FOREARM)
	_rig.second_hand_on_weapon = _second_hand_reaches(input, weapon)
	if not action_arms.is_empty():
		var w := smoothstep(0.0, 1.0, _action_w)
		for bone_name: StringName in action_arms.keys():
			_rig.bone(bone_name).rotation = lerp_angle(_rig.bone(bone_name).rotation, float(action_arms[bone_name]), w)
		weapon_root.position = weapon_root.position.lerp(action_hand, w)
		weapon_root.rotation = lerp_angle(weapon_root.rotation, action_weapon_angle, w)


## 近戰招式的身體動作（NE-277）：踏步、壓低、轉身疊加在姿勢上，不是只有手臂在動。
func _apply_melee_body(input: RigInput, target: Dictionary) -> void:
	if input.melee_body == Vector3.ZERO or input.dead:
		return
	target[&"_hip_x"] = float(target.get(&"_hip_x", 0.0)) + input.melee_body.x
	target[&"_hip_y"] = float(target.get(&"_hip_y", 0.0)) + input.melee_body.y
	if _rig.has_bone(&"chest"):
		target[&"chest"] = float(target.get(&"chest", _angles.get(&"chest", 0.0))) + input.melee_body.z


## 近戰招式的武器路徑（NE-277）：前手的掌心去追「肩膀＋路徑方向×距離」那一點，手的角度跟著武器；
## 權重沒滿（進出招式）時和原本的姿勢混合，不會跳位。
func _solve_melee_path(input: RigInput) -> void:
	if input.melee_path_w <= 0.001 or not (_rig.has_bone(&"arm_front_upper") and _rig.has_bone(&"arm_front_lower") and _rig.has_bone(&"hand_front")):
		return
	# 肩膀的位置與上一節的角度在 _solve_arms 之前就算好了（手臂 IK 不會動到軀幹），不用再整副重算；之後 update 會整副重算一次。
	var chain: Array = ARM_CHAINS[0]
	var before: Array[float] = []
	for bone_name: StringName in chain:
		before.append(_rig.bone(bone_name).rotation)
	var weapon := input.melee_path_weapon
	var grip: Vector2 = (_global_pos[&"arm_front_upper"] as Vector2) + Vector2.from_angle(input.melee_path_angle) * input.melee_path_reach
	_reach_arm(&"arm_front_upper", &"arm_front_lower", &"hand_front", grip - _rig.hand_grip_offset(&"hand_front").rotated(weapon), weapon)
	var w := smoothstep(0.0, 1.0, input.melee_path_w)
	for i in chain.size():
		var bone := _rig.bone(chain[i])
		# IK 算出來的是兩個方向角相減，可能超出 ±π（同一個姿勢、轉了一圈）；包回來，插值與關節檢查才不會繞遠路。
		bone.rotation = wrapf(lerp_angle(before[i], bone.rotation, w), -PI, PI)


## 雙手的近戰招式：武器這一格的位置定了之後，後手去握桿上的那一點（骨架座標）。搆不到回傳 false、手不動。
func place_second_hand(target: Vector2, hand_angle: float) -> bool:
	if not (_rig.has_bone(&"arm_back_upper") and _rig.has_bone(&"arm_back_lower") and _rig.has_bone(&"hand_back")) or not _global_pos.has(&"arm_back_upper"):
		return false
	var reach := _rig.rest(&"arm_back_lower").length() + _rig.rest(&"hand_back").length()
	var distance: float = (target - (_global_pos[&"arm_back_upper"] as Vector2)).length()
	if distance > reach * SECOND_HAND_REACH or distance < reach * SECOND_HAND_MIN:
		return false
	_reach_arm(&"arm_back_upper", &"arm_back_lower", &"hand_back", target - _rig.hand_grip_offset(&"hand_back").rotated(hand_angle), hand_angle)
	for bone_name: StringName in ARM_CHAINS[1]:
		_rig.bone(bone_name).rotation = wrapf(_rig.bone(bone_name).rotation, -PI, PI)
	_forward_chain(ARM_CHAINS[1])
	return true


## 只重算一條骨鏈（由根往末端）的位置快取：父骨頭的快取要是新的。比整副重算便宜很多（只有三根骨頭）。
func _forward_chain(chain: Array) -> void:
	for bone_name: StringName in chain:
		var parent := _rig.parent_of(bone_name)
		var parent_angle: float = _global_angle.get(parent, 0.0)
		_global_angle[bone_name] = parent_angle + _rig.bone(bone_name).rotation
		_global_pos[bone_name] = (_global_pos.get(parent, Vector2.ZERO) as Vector2) + _rig.bone(bone_name).position.rotated(parent_angle)


## 後手要不要去握近戰武器的桿子：有要求、手上不是槍、而且那一點在手臂搆得到的範圍裡（留一點彎度，手肘不打直）。
func _second_hand_reaches(input: RigInput, weapon: Dictionary) -> bool:
	if not input.melee_second or not weapon.is_empty() or input.dead or input.shield_forward:
		return false
	if not (_rig.has_bone(&"arm_back_upper") and _rig.has_bone(&"arm_back_lower") and _rig.has_bone(&"hand_back")):
		return false
	var reach := _rig.rest(&"arm_back_lower").length() + _rig.rest(&"hand_back").length()
	var distance: float = (input.melee_second_target - (_global_pos[&"arm_back_upper"] as Vector2)).length()
	return distance <= reach * SECOND_HAND_REACH and distance >= reach * SECOND_HAND_MIN


## 空著垂下的遠側手臂要藏在身體後面：側面看一個站著的人，遠側的手被髖擋住。垂放角度依這副骨架量出來——
## 讓遠側手腕落在髖關節（腿的中心）正後方。固定角度做不到：肩與髖的前後距離每個角色不同，手會從髖的前緣或後緣探出來，
## 只看得到一隻沒有前臂的手，像同一側長了兩隻手。回傳 (上臂, 前臂) 的角度；量不出來時回傳 INF，沿用資料的角度。
var _far_arm_tuck := Vector2.INF
var _far_arm_swing_limit := INF
const FAR_ARM_BODY_SHARE := 0.75
const FAR_ARM_HAND := 1.5
const FAR_ARM_ELBOW := -0.08
func _measure_far_arm_tuck() -> Vector2:
	for bone_name: StringName in [&"arm_back_upper", &"arm_back_lower", &"hand_back", &"leg_front_upper"]:
		if not _global_pos.has(bone_name):
			return Vector2.INF
	var reach := _rig.rest(&"arm_back_lower").length() + _rig.rest(&"hand_back").length()
	if reach < 1.0:
		return Vector2.INF
	var forward := float(_global_pos[&"leg_front_upper"].x) - float(_global_pos[&"arm_back_upper"].x)
	# 擺動時手也要留在身體後面：手腕離髖中心不超過「身體半寬減掉半個手掌」。半寬用肩到髖中心的前後距離估（背在肩的位置）。
	_far_arm_swing_limit = asin(clampf(maxf(absf(forward) * FAR_ARM_BODY_SHARE - FAR_ARM_HAND, 0.0) / reach, 0.0, 0.6))
	return Vector2(-asin(clampf(forward / reach, -0.6, 0.6)) - FAR_ARM_ELBOW * 0.5, FAR_ARM_ELBOW)


## 空手時遠側手臂的垂放角度：動作資料自己寫了 arms.hang 的角色用資料的，其他角色用量出來的藏手角度。
func _far_arm_hang() -> Vector2:
	var hang := _arm_hang()
	var default_hang: Array = (DEFAULT_MOTION["arms"] as Dictionary)["hang"]
	if _far_arm_tuck.is_finite() and is_equal_approx(float(hang[2]), float(default_hang[2])) and is_equal_approx(float(hang[3]), float(default_hang[3])):
		return _far_arm_tuck
	return Vector2(float(hang[2]), float(hang[3]))


## 空手時四段手臂的垂放角度（動作資料 arms.hang）；資料不是四個數字時用預設值。
func _arm_hang() -> Array:
	var hang: Variant = (_motion["arms"] as Dictionary).get("hang")
	if typeof(hang) == TYPE_ARRAY and (hang as Array).size() >= 4:
		return hang
	return (DEFAULT_MOTION["arms"] as Dictionary)["hang"]


## 空手時上臂的擺幅：跟著水平速度從 0 增加到 arms.swing（半速就擺滿），站著不擺。
func _arm_swing(input: RigInput) -> float:
	return float((_motion["arms"] as Dictionary).get("swing", 0.0)) * clampf(absf(input.velocity.x) / maxf(1.0, input.run_speed) * 2.0, 0.0, 1.0)


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
	if input.dead:
		_action_w = 0.0
		_action_pose.clear()
		_action_skip_ik = false
		_action_weapon_angle = NAN
		return
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
		_action_pose = _sample_action(def, clampf(input.action_t, 0.0, 1.0), input.action)
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
## 每個動作的 key 整理成「每根骨頭一條軌跡」只做一次（快取在 _action_tracks，動作資料換了新的字典就重整），
## 每格只做內插；角色在出招時不再每格重新配置字典與陣列。
var _action_tracks: Dictionary = {}  # 動作名稱 → [bones: Array[StringName], times: Array[PackedFloat64Array], values: Array[PackedFloat64Array]]


func _sample_action(def: Dictionary, t: float, name: StringName = &"") -> Dictionary:
	var tracks: Array = _tracks_of(def, name)
	var bones: Array = tracks[0]
	var out: Dictionary = {}
	for i in bones.size():
		var times: PackedFloat64Array = tracks[1][i]
		var values: PackedFloat64Array = tracks[2][i]
		var last := times.size() - 1
		var value: float = values[last]
		if t <= times[0]:
			value = values[0]
		else:
			for k in last:
				if t <= times[k + 1]:
					var span := maxf(0.0001, times[k + 1] - times[k])
					value = lerpf(values[k], values[k + 1], smoothstep(0.0, 1.0, (t - times[k]) / span))
					break
		out[bones[i]] = value
	return out


func _tracks_of(def: Dictionary, name: StringName) -> Array:
	var cached: Variant = _action_tracks.get(name)
	if cached is Array and is_same((cached as Array)[3], def):
		return cached
	var points: Dictionary = {}  # bone -> [[t, value], ...]（照 key 的順序）
	var order: Array = []
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
			if not points.has(bone):
				points[bone] = []
				order.append(bone)
			(points[bone] as Array).append([kt, float(values[bone])])
	var bones: Array = []
	var times: Array = []
	var samples: Array = []
	for bone: Variant in order:
		var bone_name := StringName(str(bone))
		if bone_name != &"_hip_x" and bone_name != &"_hip_y" and not _rig.has_bone(bone_name):
			RigLibrary.report_once("action_bone:" + str(bone), "[HumanoidAnimator] %s 的動作用到不存在的骨頭：%s" % [ACTIONS_PATH, bone])
			continue
		var track_t := PackedFloat64Array()
		var track_v := PackedFloat64Array()
		for point: Array in points[bone]:
			track_t.append(float(point[0]))
			track_v.append(float(point[1]))
		bones.append(bone_name)
		times.append(track_t)
		samples.append(track_v)
	var result := [bones, times, samples, def]
	_action_tracks[name] = result
	return result


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
		var bone_name := _spring_key(spring)
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
			angle += velocity * dt
			if angle < low or angle > high:  # 撞到上下限就停在那裡，不帶著速度繼續頂（否則放開時會彈一大下）
				angle = clampf(angle, low, high)
				velocity = 0.0
		_spring_velocity[bone_name] = velocity
		_spring_angle[bone_name] = angle
		if spring.has("warp"):
			_rig.set_sway(bone_name, angle)
