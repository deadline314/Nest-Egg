extends Node2D
## 開發工具：把所有骨架角色排成一列，展示各種動作（檢查零件綁定與動畫）。
## 用法：godot --path . res://tools/rig_preview.tscn -- --out=/絕對路徑/檔名.png [--chars=old_k,mei]
## --chars：改成每個角色一列，展示八種動作（站、跑、瞄準、蹲、跳、格擋、倒下、硬直），一次最多兩個角色。
## --closeup（搭配 --chars）：改成每個角色一張大的站姿，檢查臉、衣服與裝備的細節，一次最多四個角色。
## --head（搭配 --chars）：只放大頭與肩膀，檢查臉部與頭髮，一次最多四個角色；--zoom=倍率 可調整放大倍數。
## --death（搭配 --chars，最多三個角色）：四種最後一擊（正面輕、背面輕、正面重、背面重）倒下後的樣子。
## --gait（搭配 --chars，用第一個角色）：並排看跑一個步伐週期的八個時間點（--speed=速度，預設 70；--run-speed=滿速，預設是速度的兩倍＝半速跑，
## 要看遊戲裡全速奔跑的樣子就讓兩者相同，例如 --speed=150 --run-speed=150），檢查落腳、腳底貼地與滑步。
## --weapon=武器外觀 id（搭配 --chars）：改用指定的手持武器（空字串＝空手），例如 --weapon=handset。
## --seq=名稱（搭配 --chars，用第一個角色）：依時間序列取樣八格，看隨時間變化的動作。名稱見 SEQUENCES
## （start 起步、stop 煞車、idle 待機八秒、jump 起跳到落地、land 原地落下、dash 衝刺）；速度依玩家的數值模擬（加速 1600／2100 px/s²、跳躍 420、重力 1000、衝刺 360 持續 0.17 秒），
## 每格都是從頭模擬到該時間點，所以不受取樣影響。
## --relaxed（搭配 --chars）：模擬還沒發現玩家的放鬆姿勢（槍垂下），舉槍與格擋除外。
## --bare（搭配 --damage）：不拿武器、手臂垂向前下方，看得到上半身的衣物。
## --cloth（搭配 --chars）：第一個角色放大排成一列（站、跑、上升、下落、蹲、仰射），檢查衣襬、頭髮、槍套等次級動態。
## --npc（搭配 --chars）：第一個角色用 NPC 動畫器排成一列：站、坐、靠牆、蹲、說話、聆聽、揮手、工作循環（--loop=名稱，預設 stir；--loop-pose=stand/sit/lean/squat）。
## --rigid：所有角色維持剛體零件（不做關節網格），拿來和預設的樣子比較（NE-204）。
## --joints（搭配 --chars，用第一個角色）：並排看膝與肘彎曲的程度，左邊是舊的剛體零件、右邊是關節網格（NE-204）；
## --level=0~3 選彎曲程度（約 3°、50°、90°、125°，預設 2），--zoom 預設 5。
## --action=名稱（搭配 --chars）：第一個角色依進度 0、20%…100% 排成一列，檢查專屬動作（art/rigs/action_poses.json）。
## --damage（搭配 --chars）：第一個角色依生命比例 100%→0% 排成一列，檢查裝甲與衣物逐片脫落的樣子（--zoom 預設 3.0）。

const CHARACTERS := [["rin", "rifle"], ["trooper", "smg"], ["grenadier", "launcher"], ["enforcer", "pistol"], ["warden", "minigun"]]
## --cloth 的動作（"fall"：下落）。
const CLOTH_POSES := ["idle", "run", "jump", "fall", "crouch", "aim_up"]
## --seq 的序列：pre＝取樣時間 0 之前先模擬的秒數、times＝八個取樣時間（秒，從 0 起算）。
const SEQUENCES := {
	"start": {"pre": 0.6, "times": [0.0, 0.04, 0.08, 0.13, 0.2, 0.3, 0.45, 0.7]},
	"stop": {"pre": 1.0, "times": [0.0, 0.04, 0.08, 0.12, 0.2, 0.3, 0.45, 0.8]},
	"idle": {"pre": 0.0, "times": [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5]},
	"jump": {"pre": 0.6, "times": [0.0, 0.06, 0.18, 0.42, 0.66, 0.84, 0.92, 1.1]},
	"dash": {"pre": 0.6, "times": [0.0, 0.03, 0.07, 0.12, 0.17, 0.22, 0.3, 0.5]},
	"land": {"pre": 0.2, "times": [0.0, 0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.5]},
}
const SEQ_JUMP_VELOCITY := 420.0
const SEQ_GRAVITY := 1000.0
const SEQ_DASH_SPEED := 360.0
const SEQ_DASH_TIME := 0.17
const SEQ_RUN_SPEED := 150.0
const SEQ_ACCEL := 1600.0
const SEQ_DECEL := 2100.0
## --npc 的動作。
const NPC_POSES := ["stand", "sit", "lean", "squat", "talk", "listen", "wave", "loop"]
const POSES := ["idle", "run", "aim_up", "crouch", "jump", "block", "dead"]
## --chars 模式的動作（多一個受傷硬直）與各角色預設的手持武器（空字串＝空手）。
const SHEET_POSES := ["idle", "run", "aim_up", "crouch", "jump", "block", "stagger", "dead"]
const SHEET_WEAPONS := {
	"rin": "rifle", "trooper": "smg", "grenadier": "launcher", "enforcer": "pistol", "warden": "minigun",
	"trooper_elite": "rifle", "slasher": "", "stalker": "rifle", "old_k": "pistol", "mei": "smg", "wataru": "", "reclaimer": "rifle", "sniper": "sniper", "flamer": "flamethrower", "heavy_gunner": "minigun",
}

var _out := ""
var _chars: PackedStringArray = []
var _closeup := false
var _head_only := false
var _damage := false
var _cloth := false
var _bare := false
var _relaxed := false
var _weapon_override := ""
var _weapon_set := false
var _gait := false
var _death := false
var _gait_speed := 70.0
var _gait_run_speed := 0.0
var _seq := ""
var _npc := false
var _joints := false
var _joint_level := 2
var _action := ""
var _loop := "stir"
var _loop_pose := "stand"
var _zoom := 6.5
var _rigs: Array[CharacterRig] = []
var _inputs: Array[RigInput] = []
var _poses: Array[String] = []
var _time := 0.0
## --bright：檢視用的亮場景（淺灰背景、柔和白光），暗場景下看不清零件時用；遊戲裡的實際光影不變。
var _bright := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--bright":
			_bright = true
		elif arg == "--head":
			_head_only = true
		elif arg == "--closeup":
			_closeup = true
		elif arg == "--damage":
			_damage = true
		elif arg == "--cloth":
			_cloth = true
		elif arg == "--bare":
			_bare = true
		elif arg == "--relaxed":
			_relaxed = true
		elif arg.begins_with("--weapon="):
			_weapon_override = arg.trim_prefix("--weapon=")
			_weapon_set = true
		elif arg == "--gait":
			_gait = true
		elif arg == "--death":
			_death = true
		elif arg.begins_with("--speed="):
			_gait_speed = float(arg.trim_prefix("--speed="))
		elif arg.begins_with("--seq="):
			_seq = arg.trim_prefix("--seq=")
		elif arg.begins_with("--run-speed="):
			_gait_run_speed = float(arg.trim_prefix("--run-speed="))
		elif arg.begins_with("--action="):
			_action = arg.trim_prefix("--action=")
		elif arg == "--npc":
			_npc = true
		elif arg == "--rigid":
			CharacterRig.force_rigid_limbs = true
		elif arg == "--joints":
			_joints = true
		elif arg.begins_with("--level="):
			_joint_level = clampi(int(arg.trim_prefix("--level=")), 0, 3)
		elif arg.begins_with("--loop="):
			_loop = arg.trim_prefix("--loop=")
		elif arg.begins_with("--loop-pose="):
			_loop_pose = arg.trim_prefix("--loop-pose=")
		elif arg.begins_with("--chars="):
			_chars = arg.trim_prefix("--chars=").split(",", false)
	add_child(LightKit.create_environment())
	var bg := ColorRect.new()
	bg.color = Color("5b6577") if _bright else Color("121826")
	bg.size = Vector2(640, 360)
	bg.z_index = -10
	add_child(bg)
	for y: float in [160.0, 340.0]:
		var floor_line := Line2D.new()
		floor_line.points = PackedVector2Array([Vector2(0, y), Vector2(640, y)])
		floor_line.width = 2.0
		floor_line.default_color = Color("2a3446")
		add_child(floor_line)
	if _chars.is_empty():
		# 第一列：主角七種動作（放大 2.4 倍）；第二列：所有角色（放大 1.6 倍）。
		for i in POSES.size():
			_spawn("rin", "rifle", Vector2(42 + i * 88, 160), POSES[i], 2.4)
		for i in CHARACTERS.size():
			_spawn(CHARACTERS[i][0], CHARACTERS[i][1], Vector2(55 + i * 118, 340), "idle" if i != 4 else "aim_up", 1.6)
	elif _death:
		for row in mini(_chars.size(), 3):
			for i in 4:
				_spawn(_chars[row], str(SHEET_WEAPONS.get(_chars[row], "")), Vector2(70 + i * 150, 140 + row * 110), "death:%d" % i, _zoom if _zoom != 6.5 else 2.0)
	elif not _seq.is_empty():
		if not SEQUENCES.has(_seq):
			push_error("[rig_preview] --seq=%s 不存在，可用：%s" % [_seq, ", ".join(SEQUENCES.keys())])
			get_tree().quit(1)
			return
		for i in 8:
			_spawn(_chars[0], str(SHEET_WEAPONS.get(_chars[0], "")), Vector2(44 + i * 76, 330), "seq:%d" % i, _zoom if _zoom != 6.5 else 2.2)
	elif _joints:
		for column in 2:
			CharacterRig.force_rigid_limbs = column == 0
			_spawn(_chars[0], "", Vector2(180 + column * 280, 340), "joint:%d" % _joint_level, _zoom if _zoom != 6.5 else 5.0)
		CharacterRig.force_rigid_limbs = false
	elif _gait:
		for i in 8:
			_spawn(_chars[0], str(SHEET_WEAPONS.get(_chars[0], "")), Vector2(44 + i * 76, 330), "gait:%d" % i, _zoom if _zoom != 6.5 else 2.2)
	elif not _action.is_empty():
		for i in 6:
			_spawn(_chars[0], str(SHEET_WEAPONS.get(_chars[0], "")), Vector2(60 + i * 100, 330), "action:%d" % i, _zoom if _zoom != 6.5 else 2.4)
	elif _npc:
		for i in NPC_POSES.size():
			_spawn(_chars[0], "", Vector2(50 + i * 80, 330), NPC_POSES[i], _zoom if _zoom != 6.5 else 2.2)
	elif _cloth:
		for i in CLOTH_POSES.size():
			_spawn(_chars[0], str(SHEET_WEAPONS.get(_chars[0], "")), Vector2(70 + i * 100, 335), CLOTH_POSES[i], 3.4)
	elif _damage:
		var ratios := [1.0, 0.85, 0.65, 0.45, 0.3, 0.15, 0.0]
		var scale_up := 3.0 if _zoom == 6.5 else _zoom
		for i in ratios.size():
			_spawn(_chars[0], "" if _bare else str(SHEET_WEAPONS.get(_chars[0], "")), Vector2(50 + i * 90, 330), "idle", scale_up, ratios[i])
	elif _head_only:
		for i in mini(_chars.size(), 4):
			_spawn(_chars[i], "", Vector2(320.0 + (i - (mini(_chars.size(), 4) - 1) * 0.5) * 20.0 * _zoom, 190 + 44.0 * _zoom), "idle", _zoom)
	elif _closeup:
		for i in mini(_chars.size(), 4):
			_spawn(_chars[i], str(SHEET_WEAPONS.get(_chars[i], "")), Vector2(80 + i * 160, 330), "idle", 3.6)
	else:
		for row in mini(_chars.size(), 2):
			for i in SHEET_POSES.size():
				_spawn(_chars[row], str(SHEET_WEAPONS.get(_chars[row], "")), Vector2(40 + i * 80, 160 + row * 180), SHEET_POSES[i], _zoom if _zoom != 6.5 else 2.0)
	for spot: Array in [[Vector2(160, 40), Palette.CYAN], [Vector2(480, 40), Color("ff2e88")], [Vector2(320, 220), Palette.WARM_LIGHT]]:
		var light := LightKit.create_point_light(Color("f0f4ff") if _bright else spot[1], 900.0 if _bright else 340.0, 0.75 if _bright else 0.7)
		light.position = spot[0]
		add_child(light)
	if not _out.is_empty():
		_capture.call_deferred()


func _spawn(skin: String, weapon: String, pos: Vector2, pose: String, zoom: float, armor_ratio := 1.0) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2.ONE * zoom
	add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	if not rig.setup(skin, "npc" if _npc else ""):
		return
	rig.set_weapon(_weapon_override if _weapon_set else weapon)
	rig.set_armor_ratio(armor_ratio, false)
	var input := RigInput.new()
	_rigs.append(rig)
	_inputs.append(input)
	_poses.append(pose)


func _process(delta: float) -> void:
	_time += delta
	for i in _rigs.size():
		var input := _inputs[i]
		input.facing = 1
		input.aim_dir = Vector2(1.0, 0.9).normalized() if _bare else Vector2.RIGHT
		input.on_floor = true
		input.velocity = Vector2.ZERO
		input.crouching = false
		input.relaxed = _relaxed and _poses[i] != "aim_up" and _poses[i] != "block"
		input.blocking = false
		input.staggered = false
		input.dead = false
		input.shield_forward = _rigs[i].skin_id == "enforcer"
		input.two_handed = _rigs[i].skin_id != "enforcer" and not _npc
		input.npc_pose = &"stand"
		input.npc_loop = &""
		input.talking = false
		input.listening = false
		input.waving = false
		input.action = &""
		input.action_t = 0.0
		if str(_poses[i]).begins_with("action:"):
			input.action = StringName(_action)
			input.action_t = float(str(_poses[i]).trim_prefix("action:")) / 5.0
		if str(_poses[i]).begins_with("gait:"):
			input.velocity = Vector2(_gait_speed, 0)
			input.run_speed = _gait_speed * 2.0
		match _poses[i]:
			"sit", "lean":
				input.npc_pose = StringName(_poses[i])
			"squat":
				input.npc_pose = &"crouch"
			"talk":
				input.talking = true
			"listen":
				input.listening = true
			"wave":
				input.waving = true
			"loop":
				input.npc_loop = StringName(_loop)
				input.npc_pose = &"crouch" if _loop_pose == "squat" else StringName(_loop_pose)
			"run":
				input.velocity = Vector2(150, 0)
			"aim_up":
				input.aim_dir = Vector2(1, -1).normalized()
			"crouch":
				input.crouching = true
			"jump":
				input.on_floor = false
				input.velocity = Vector2(80, -200)
			"fall":
				input.on_floor = false
				input.velocity = Vector2(80, 260)
			"block":
				input.blocking = true
				input.aim_dir = Vector2(1, -0.2).normalized()
			"stagger":
				input.staggered = true
			"dead":
				input.dead = true
		_rigs[i].animate(delta, input)
		if str(_poses[i]).begins_with("joint:"):
			_pose_joints(_rigs[i], int(str(_poses[i]).trim_prefix("joint:")))


## --joints：膝與肘彎曲的四個程度。大腿往前抬、小腿往後折（膝）；上臂往前、前臂往上折（肘）。
func _pose_joints(rig: CharacterRig, level: int) -> void:
	var bend: float = [0.05, 0.9, 1.57, 2.2][level]
	rig.bone(&"leg_front_upper").rotation = -0.5 * float(level) * 0.5
	rig.bone(&"leg_front_lower").rotation = bend
	rig.bone(&"leg_back_upper").rotation = 0.25
	rig.bone(&"leg_back_lower").rotation = bend * 0.6
	rig.bone(&"arm_front_upper").rotation = -0.3 - 0.25 * float(level)
	rig.bone(&"arm_front_lower").rotation = -bend
	rig.bone(&"arm_back_upper").rotation = 0.2
	rig.bone(&"arm_back_lower").rotation = -bend * 0.7
	rig.refresh_limbs()


## --gait：先讓每一隻跑一整個週期的八分之 i 的時間，並排看一個步伐週期的八個時間點。
func _preroll_gait() -> void:
	var dt := 1.0 / 60.0
	for i in _rigs.size():
		var input := _inputs[i]
		input.facing = 1
		input.on_floor = true
		input.velocity = Vector2(_gait_speed, 0)
		input.run_speed = _gait_run_speed if _gait_run_speed > 0.0 else _gait_speed * 2.0
		input.aim_dir = Vector2.RIGHT
		input.relaxed = _relaxed
		input.two_handed = true
		var stride := float(_rigs[i].animator._motion["move"]["stride"])
		var cycle_frames := stride / _gait_speed / dt
		for k in 90 + int(cycle_frames * float(i) / 8.0):
			_rigs[i].animate(dt, input)


## 序列在時間 t（秒，負值＝取樣前的預備）的狀態：把速度、是否在地上、衝刺中填進 input；prev_t 到 t 之間發生的一次性事件（起跳、落地、衝刺開始）也一併設定。
func _seq_apply(input: RigInput, t: float, prev_t: float) -> void:
	input.on_floor = true
	input.dashing = false
	var speed := 0.0
	match _seq:
		"start":
			speed = minf(SEQ_RUN_SPEED, SEQ_ACCEL * maxf(0.0, t))
		"stop":
			speed = SEQ_RUN_SPEED if t < 0.0 else maxf(0.0, SEQ_RUN_SPEED - SEQ_DECEL * t)
		"jump":
			speed = SEQ_RUN_SPEED
			var landing := 2.0 * SEQ_JUMP_VELOCITY / SEQ_GRAVITY  # 對稱拋物線落回起跳高度的時間
			if t >= 0.0 and t < landing:
				input.on_floor = false
				input.velocity.y = -SEQ_JUMP_VELOCITY + SEQ_GRAVITY * t
			else:
				input.velocity.y = 0.0
			if prev_t < 0.0 and t >= 0.0:
				input.jumped = true
			if prev_t < landing and t >= landing:
				input.landed = clampf((SEQ_JUMP_VELOCITY) / 560.0, 0.0, 1.0)
		"land":  # 原地從高處落下：取樣時間 0 是落地的瞬間
			if t < 0.0:
				input.on_floor = false
				input.velocity.y = SEQ_JUMP_VELOCITY
			if prev_t < 0.0 and t >= 0.0:
				input.landed = SEQ_JUMP_VELOCITY / 560.0
		"dash":
			if t >= 0.0 and t < SEQ_DASH_TIME:
				speed = SEQ_DASH_SPEED
				input.dashing = true
			elif t >= SEQ_DASH_TIME:
				speed = maxf(0.0, SEQ_DASH_SPEED - SEQ_DECEL * (t - SEQ_DASH_TIME))
			if prev_t < 0.0 and t >= 0.0:
				input.dash_started = true
	input.velocity.x = speed


## --seq：每一格從頭模擬到自己的取樣時間（先模擬 pre 秒的預備，再依序列走到 times[i]）。
func _preroll_seq() -> void:
	var dt := 1.0 / 60.0
	var def: Dictionary = SEQUENCES[_seq]
	for i in _rigs.size():
		var input := _inputs[i]
		input.facing = 1
		input.run_speed = SEQ_RUN_SPEED
		input.aim_dir = Vector2.RIGHT
		input.two_handed = true
		var t := -float(def["pre"]) - 1.0  # 多一秒讓待機的呼吸與重心轉移先穩定
		var stop_at := float((def["times"] as Array)[i])
		while t < stop_at - 0.0001:
			var previous := t
			t += dt
			_seq_apply(input, minf(t, stop_at), previous)
			_rigs[i].animate(dt, input)
			input.jumped = false
			input.landed = 0.0
			input.dash_started = false
		if _seq == "jump":  # 起跳高度：把整個角色抬到拋物線上的位置，才看得出在空中
			var at := minf(stop_at, 2.0 * SEQ_JUMP_VELOCITY / SEQ_GRAVITY)
			(_rigs[i].get_parent() as Node2D).position.y -= maxf(0.0, SEQ_JUMP_VELOCITY * at - 0.5 * SEQ_GRAVITY * at * at)


## --death：每個角色四種最後一擊（正面輕、背面輕、正面重、背面重）倒下後 1.5 秒的樣子。
func _preroll_death() -> void:
	var dt := 1.0 / 60.0
	for i in _rigs.size():
		var input := _inputs[i]
		var variant := int(str(_poses[i]).trim_prefix("death:"))
		input.facing = 1
		input.on_floor = true
		input.aim_dir = Vector2.RIGHT
		input.two_handed = true
		for k in 30:
			_rigs[i].animate(dt, input)
		input.dead = true
		input.death_dir = 1.0 if variant % 2 == 0 else -1.0
		input.death_force = 0.0 if variant < 2 else 1.0
		for k in 100:
			_rigs[i].animate(dt, input)


func _capture() -> void:
	if _death:
		_preroll_death()
		set_process(false)
	if _gait:
		_preroll_gait()
		set_process(false)
	if not _seq.is_empty():
		_preroll_seq()
		set_process(false)
	for i in 90:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out)
	print("saved ", _out)
	get_tree().quit()
