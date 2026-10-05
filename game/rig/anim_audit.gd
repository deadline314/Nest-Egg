class_name AnimAudit
extends RefCounted
## 動畫稽核（開發與測試用）：把一個骨架角色的各種狀態與專屬動作逐格播放，量出「合不合理」的數字：
##   骨頭長度（IK 沒有把手腳拉長）、關節活動範圍（手肘與膝蓋不反折）、軀幹與頭的傾斜、腳踩實地（不陷進地面、不懸空）、
##   手握住武器、前後格的角度跳動（沒有瞬間錯位）、倒下後身體躺在地上。
## 每一項回傳最糟的一格（數值、限制、哪個情境、第幾格），超出限制的就是問題。用法：AnimAudit.audit(rig, skin, actions) -> Dictionary。

const DT := 1.0 / 60.0
## 各項的限制（單位：像素或弧度）。
const LIMITS := {
	"bone_stretch": 0.3,      # 手腳骨頭長度和靜止時差多少像素
	"elbow_hyper": 0.6,       # 前臂相對上臂往反折方向轉的弧度（正值＝反折）
	"knee_hyper": 0.1,       # 小腿相對大腿往反折方向轉的弧度（正值＝反折）
	"trunk_lean": 1.15,       # 胸相對骨盆的傾斜
	"head_turn": 1.0,         # 頭（含頸）相對胸的傾斜
	"foot_below_ground": 2.0, # 站著時腳底陷進地面多少像素（起跑與停步的過渡約 1.8）
	"foot_floating": 0.5,     # 站著時最低的腳底離地多少像素
	"grip_gap": 1.5,          # 前手與武器握把的距離
	"angle_pop": 0.9,         # 單格內骨頭角度的跳動
	"corpse_height": 0.5,     # 倒下結束時最高的骨頭離地，佔站立身高的比例（躺平或癱倒）
	"corpse_below_ground": 3.0,
}
const ARM_BONES: Array = [[&"arm_front_upper", &"arm_front_lower", &"hand_front"], [&"arm_back_upper", &"arm_back_lower", &"hand_back"]]
const LEG_BONES: Array = [[&"leg_front_upper", &"leg_front_lower", &"foot_front"], [&"leg_back_upper", &"leg_back_lower", &"foot_back"]]
## 專屬動作的單格跳動允許更大（揮斬本來就很快）。
const ACTION_POP_SCALE := 2.2
const COMMON_ACTIONS: Array[String] = []


## 稽核一個角色，回傳 { 項目: { "value": 最糟的數值, "limit": 限制, "where": 情境與格數 } }；沒有超標的項目 value 仍會列出，方便看餘裕。
static func audit(rig: CharacterRig, skin: String, action_names: Array[String]) -> Dictionary:
	var ctx := {"rig": rig, "results": {}, "where": "", "frame": 0, "prev": {}, "grounded": false, "pop_scale": 1.0, "skip_pop": 0}
	var input := RigInput.new()
	_reset(input, rig)
	_hold(ctx, input, 40, "idle")
	input.relaxed = true
	_hold(ctx, input, 60, "idle-relaxed")
	input.relaxed = false
	for aim in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		input.aim_dir = Vector2.RIGHT.rotated(aim)
		_hold(ctx, input, 40, "aim %.1f" % aim)
	input.aim_dir = Vector2.RIGHT
	for speed in [30.0, 60.0, 120.0]:
		input.velocity = Vector2(speed, 0.0)
		input.run_speed = maxf(40.0, speed * 1.5)
		_hold(ctx, input, 120, "run %.0f" % speed)
		input.relaxed = true
		_hold(ctx, input, 60, "run-relaxed %.0f" % speed)
		input.relaxed = false
	# 全速奔跑（速度比例 1）：只有「有騰空」的角色才量（兩腳會同時離地，所以不量腳底與地面，其他項目照量）。
	if rig.animator != null and rig.animator.has_flight():
		input.velocity = Vector2(120.0, 0.0)
		input.run_speed = 120.0
		_hold(ctx, input, 120, "run full", false)
	input.velocity = Vector2.ZERO
	_hold(ctx, input, 30, "stop")
	input.crouching = true
	_hold(ctx, input, 50, "crouch")
	input.aim_dir = Vector2.RIGHT.rotated(-0.6)
	_hold(ctx, input, 30, "crouch-aim")
	input.aim_dir = Vector2.RIGHT
	input.crouching = false
	_hold(ctx, input, 40, "stand-up")
	input.blocking = true
	_hold(ctx, input, 30, "block")
	input.blocking = false
	input.staggered = true
	_hold(ctx, input, 40, "stagger")
	input.staggered = false
	for dir in [1.0, -1.0]:
		input.hurt = true
		input.hurt_scale = 2.2
		input.hurt_dir = dir
		_hold(ctx, input, 1, "hurt")
		input.hurt = false
		_hold(ctx, input, 30, "hurt-recover")
	input.recoil = 1.0
	_hold(ctx, input, 1, "recoil")
	input.recoil = 0.0
	_hold(ctx, input, 30, "recoil-recover")
	for action in action_names:
		_play_action(ctx, input, StringName(action))
	# 空中（不量腳底與地面）
	input.on_floor = false
	input.velocity = Vector2(80, -200)
	ctx["grounded"] = false
	input.jumped = true
	_hold(ctx, input, 20, "jump", false)
	input.velocity = Vector2(80, 0)  # 頂點：上升與下落的姿勢在這裡連續混合
	_hold(ctx, input, 12, "apex", false)
	input.velocity = Vector2(80, 260)
	_hold(ctx, input, 20, "fall", false)
	input.on_floor = true
	input.velocity = Vector2.ZERO
	input.landed = 0.75  # 落地吸收（骨盆下沉再彈回）；落地當下的前幾格是過渡，不量腳底與地面
	_hold(ctx, input, 12, "land-absorb", false)
	_hold(ctx, input, 30, "land")
	# 衝刺：蹬出、衝刺中、結束後回到站姿
	input.dash_started = true
	input.dashing = true
	input.velocity = Vector2(300.0, 0.0)
	_hold(ctx, input, 12, "dash", false)
	input.dashing = false
	input.velocity = Vector2.ZERO
	_hold(ctx, input, 12, "dash-exit", false)
	_hold(ctx, input, 30, "dash-settle")
	# 倒下：從前面／背後、輕／重
	for variant: Array in [[1.0, 0.0], [-1.0, 0.0], [1.0, 1.0], [-1.0, 1.0]]:
		_death(ctx, rig, variant[0], variant[1])
	return ctx["results"]


## 稽核一個 NPC（NPC 動畫器）：基本姿勢 pose（stand／sit／lean／crouch）、說話、聆聽、揮手與專屬工作循環 loop（空字串＝沒有）。
static func audit_npc(rig: CharacterRig, pose: StringName, loop: StringName) -> Dictionary:
	var ctx := {"rig": rig, "results": {}, "where": "", "frame": 0, "prev": {}, "grounded": false, "pop_scale": 1.0, "skip_pop": 0}
	var input := RigInput.new()
	input.facing = 1
	input.on_floor = true
	input.npc_pose = pose
	var grounded := pose != &"sit"
	var label := "%s" % pose
	_hold(ctx, input, 60, label + " idle", grounded)
	input.talking = true
	_hold(ctx, input, 90, label + " talk", grounded)
	input.talking = false
	input.listening = true
	_hold(ctx, input, 60, label + " listen", grounded)
	input.listening = false
	input.waving = true
	_hold(ctx, input, 90, label + " wave", grounded)
	input.waving = false
	if loop != &"":
		input.npc_loop = loop
		for loop_scale in [1.0, 1.6]:
			input.npc_loop_scale = loop_scale
			_hold(ctx, input, 420, "%s loop %s x%.1f" % [label, loop, loop_scale], grounded)
		input.talking = true
		_hold(ctx, input, 90, "%s loop %s + talk" % [label, loop], grounded)
		input.talking = false
		input.npc_loop = &""
		_hold(ctx, input, 60, label + " after loop", grounded)
	return ctx["results"]


## 只稽核指定的專屬動作（主角等不走敵人那套站姿與步伐的角色用）：骨頭長度、手肘、驅幹與頭、角度跳動。
static func audit_actions(rig: CharacterRig, action_names: Array[String]) -> Dictionary:
	var ctx := {"rig": rig, "results": {}, "where": "", "frame": 0, "prev": {}, "grounded": false, "pop_scale": 1.0, "skip_pop": 0}
	var input := RigInput.new()
	_reset(input, rig)
	_hold(ctx, input, 40, "idle", false)
	for action in action_names:
		_play_action(ctx, input, StringName(action))
	return ctx["results"]


static func _reset(input: RigInput, rig: CharacterRig) -> void:
	input.facing = 1
	input.on_floor = true
	input.aim_dir = Vector2.RIGHT
	input.two_handed = true
	input.velocity = Vector2.ZERO
	input.crouching = false
	input.blocking = false
	input.staggered = false
	input.dead = false
	input.relaxed = false
	input.action = &""
	input.action_t = 0.0
	input.shield_forward = rig.skin_id == "enforcer"
	input.two_handed = rig.skin_id != "enforcer"


static func _hold(ctx: Dictionary, input: RigInput, frames: int, label: String, grounded := true) -> void:
	ctx["grounded"] = grounded
	var rig: CharacterRig = ctx["rig"]
	for i in frames:
		rig.animate(DT, input)
		input.hurt = false
		input.recoil = 0.0
		input.jumped = false  # 一次性事件只在第一格有效
		input.landed = 0.0
		input.dash_started = false
		ctx["where"] = label
		ctx["frame"] = i
		_measure(ctx)


static func _play_action(ctx: Dictionary, input: RigInput, action: StringName) -> void:
	var rig: CharacterRig = ctx["rig"]
	var actions: Variant = RigLibrary.load_json(HumanoidAnimator.ACTIONS_PATH).get("actions", {})
	if typeof(actions) != TYPE_DICTIONARY or not (actions as Dictionary).has(String(action)):
		return
	var def: Dictionary = (actions as Dictionary)[String(action)]
	var duration := maxf(0.05, float(def.get("duration", 0.5)))
	input.action = action
	ctx["pop_scale"] = ACTION_POP_SCALE
	ctx["grounded"] = not bool(def.get("skip_ik", false)) or true
	var t := 0.0
	var frame := 0
	while t < duration + 0.3:
		input.action_t = clampf(t / duration, 0.0, 1.0)
		rig.animate(DT, input)
		ctx["where"] = "action %s" % action
		ctx["frame"] = frame
		_measure(ctx)
		t += DT
		frame += 1
	input.action = &""
	input.action_t = 0.0
	_hold(ctx, input, 30, "after %s" % action)
	ctx["pop_scale"] = 1.0


static func _death(ctx: Dictionary, rig: CharacterRig, dir: float, force: float) -> void:
	var input := RigInput.new()
	_reset(input, rig)
	var fresh := CharacterRig.new()
	rig.get_parent().add_child(fresh)
	if not fresh.setup(rig.skin_id):
		fresh.queue_free()
		return
	fresh.set_weapon("rifle")
	for i in 20:
		fresh.animate(DT, input)
	input.dead = true
	input.death_dir = dir
	input.death_force = force
	var label := "death %s %s" % ["front" if dir > 0.0 else "back", "heavy" if force > 0.5 else "light"]
	var inner := {"rig": fresh, "results": ctx["results"], "where": label, "frame": 0, "prev": {}, "grounded": false, "pop_scale": 1.0}
	for i in 90:
		fresh.animate(DT, input)
		inner["frame"] = i
		_measure(inner, false)
	_final_corpse(inner, label)
	fresh.get_parent().remove_child(fresh)
	fresh.free()


static func _final_corpse(ctx: Dictionary, label: String) -> void:
	var rig: CharacterRig = ctx["rig"]
	var animator := rig.animator
	var ground := animator.ground_level()
	var top := INF
	var bottom := -INF
	var top_bone := &""
	for bone_name in rig.bone_order():
		var y := animator.bone_pos(bone_name).y
		if y < top:
			top = y
			top_bone = bone_name
		bottom = maxf(bottom, y)
	var standing := maxf(RigLibrary.standing_height(rig.skin_id), animator._leg_length * 2.0)
	# 癱坐的角色（腿一直折著）坐著的高度本來就比躺平高，允許多 30%。
	var seated := float((animator._motion["death"] as Dictionary).get("fold_keep", 0.4)) >= 0.9
	_record(ctx, "corpse_height", (ground - top) / standing / (1.3 if seated else 1.0), "%s (最高的骨頭 %s, 站高 %.0f)" % [label, top_bone, standing], 90)
	_record(ctx, "corpse_below_ground", bottom - ground, label, 90)


static func _record(ctx: Dictionary, check: String, value: float, where: String, frame: int) -> void:
	var results: Dictionary = ctx["results"]
	var entry: Dictionary = results.get(check, {"value": -INF, "limit": float(LIMITS.get(check, 0.0)), "where": ""})
	if value > float(entry["value"]):
		entry["value"] = value
		entry["where"] = "%s #%d" % [where, frame]
	results[check] = entry


static func _measure(ctx: Dictionary, with_ground := true) -> void:
	var rig: CharacterRig = ctx["rig"]
	var animator := rig.animator
	var where: String = ctx["where"]
	var frame: int = ctx["frame"]
	# 骨頭長度
	var stretch := 0.0
	for chain: Array in ARM_BONES + LEG_BONES:
		if not (rig.has_bone(chain[0]) and rig.has_bone(chain[1]) and rig.has_bone(chain[2])):
			continue
		stretch = maxf(stretch, absf(animator.bone_pos(chain[0]).distance_to(animator.bone_pos(chain[1])) - rig.rest(chain[1]).length()))
		stretch = maxf(stretch, absf(animator.bone_pos(chain[1]).distance_to(animator.bone_pos(chain[2])) - rig.rest(chain[2]).length()))
	_record(ctx, "bone_stretch", stretch, where, frame)
	# 關節活動範圍：手肘往反折方向（正）、膝蓋往反折方向（負）
	for chain: Array in ARM_BONES:
		if rig.has_bone(chain[1]):
			_record(ctx, "elbow_hyper", rig.bone(chain[1]).rotation, where, frame)
	for chain: Array in LEG_BONES:
		if rig.has_bone(chain[1]):
			_record(ctx, "knee_hyper", -rig.bone(chain[1]).rotation, where, frame)
	if rig.has_bone(&"chest"):
		_record(ctx, "trunk_lean", absf(rig.bone(&"chest").rotation), where, frame)
	if rig.has_bone(&"head"):
		var head := absf(rig.bone(&"head").rotation + (rig.bone(&"neck").rotation if rig.has_bone(&"neck") else 0.0))
		_record(ctx, "head_turn", head, where, frame)
	# 腳底與地面
	if with_ground and ctx.get("grounded", false):
		var ground := animator.ground_level()
		var low := -INF
		for foot: StringName in [&"foot_front", &"foot_back"]:
			if rig.has_bone(foot):
				low = maxf(low, animator.bone_pos(foot).y)
		if low > -INF:
			_record(ctx, "foot_below_ground", low - ground, where, frame)
			_record(ctx, "foot_floating", ground - low, where, frame)
	# 手握武器
	var weapon := rig.weapon_def()
	if not weapon.is_empty() and rig.weapon_root().visible and rig.has_bone(&"hand_front") and not where.begins_with("action") and not (where.begins_with("after") and frame < 10):
		var grip := rig.weapon_root().position
		_record(ctx, "grip_gap", grip.distance_to(animator.bone_pos(&"hand_front")), where, frame)
	# 前後格的角度跳動
	var prev: Dictionary = ctx["prev"]
	var pop := 0.0
	for bone_name in rig.bone_order():
		var angle := rig.bone(bone_name).rotation
		if prev.has(bone_name):
			pop = maxf(pop, absf(angle_difference(prev[bone_name], angle)))
		prev[bone_name] = angle
	if int(ctx.get("skip_pop", 0)) > 0:
		ctx["skip_pop"] = int(ctx["skip_pop"]) - 1
	elif frame > 0:
		_record(ctx, "angle_pop", pop / float(ctx.get("pop_scale", 1.0)), where, frame)
