extends Node2D
## 開發工具：把所有骨架角色排成一列，展示各種動作（檢查零件綁定與動畫）。
## 用法：godot --path . res://tools/rig_preview.tscn -- --out=/絕對路徑/檔名.png [--chars=old_k,mei]
## --chars：改成每個角色一列，展示八種動作（站、跑、瞄準、蹲、跳、格擋、倒下、硬直），一次最多兩個角色。
## --closeup（搭配 --chars）：改成每個角色一張大的站姿，檢查臉、衣服與裝備的細節，一次最多四個角色。
## --head（搭配 --chars）：只放大頭與肩膀，檢查臉部與頭髮，一次最多四個角色；--zoom=倍率 可調整放大倍數。

const CHARACTERS := [["rin", "rifle"], ["trooper", "smg"], ["grenadier", "launcher"], ["enforcer", "pistol"], ["warden", "minigun"]]
const POSES := ["idle", "run", "aim_up", "crouch", "jump", "block", "dead"]
## --chars 模式的動作（多一個受傷硬直）與各角色預設的手持武器（空字串＝空手）。
const SHEET_POSES := ["idle", "run", "aim_up", "crouch", "jump", "block", "stagger", "dead"]
const SHEET_WEAPONS := {
	"rin": "rifle", "trooper": "smg", "grenadier": "launcher", "enforcer": "pistol", "warden": "minigun",
	"old_k": "pistol", "mei": "smg", "wataru": "", "reclaimer": "rifle", "sniper": "sniper", "flamer": "flamethrower", "heavy_gunner": "minigun",
}

var _out := ""
var _chars: PackedStringArray = []
var _closeup := false
var _head_only := false
var _zoom := 6.5
var _rigs: Array[CharacterRig] = []
var _inputs: Array[RigInput] = []
var _poses: Array[String] = []
var _time := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--zoom="):
			_zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--head":
			_head_only = true
		elif arg == "--closeup":
			_closeup = true
		elif arg.begins_with("--chars="):
			_chars = arg.trim_prefix("--chars=").split(",", false)
	add_child(LightKit.create_environment())
	var bg := ColorRect.new()
	bg.color = Color("121826")
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
	elif _head_only:
		for i in mini(_chars.size(), 4):
			_spawn(_chars[i], "", Vector2(320.0 + (i - (mini(_chars.size(), 4) - 1) * 0.5) * 20.0 * _zoom, 190 + 44.0 * _zoom), "idle", _zoom)
	elif _closeup:
		for i in mini(_chars.size(), 4):
			_spawn(_chars[i], str(SHEET_WEAPONS.get(_chars[i], "")), Vector2(80 + i * 160, 330), "idle", 3.6)
	else:
		for row in mini(_chars.size(), 2):
			for i in SHEET_POSES.size():
				_spawn(_chars[row], str(SHEET_WEAPONS.get(_chars[row], "")), Vector2(40 + i * 80, 160 + row * 180), SHEET_POSES[i], 2.0)
	for spot: Array in [[Vector2(160, 40), Palette.CYAN], [Vector2(480, 40), Color("ff2e88")], [Vector2(320, 220), Palette.WARM_LIGHT]]:
		var light := LightKit.create_point_light(spot[1], 340.0, 0.7)
		light.position = spot[0]
		add_child(light)
	if not _out.is_empty():
		_capture.call_deferred()


func _spawn(skin: String, weapon: String, pos: Vector2, pose: String, zoom: float) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2.ONE * zoom
	add_child(holder)
	var rig := CharacterRig.new()
	holder.add_child(rig)
	if not rig.setup(skin):
		return
	rig.set_weapon(weapon)
	var input := RigInput.new()
	_rigs.append(rig)
	_inputs.append(input)
	_poses.append(pose)


func _process(delta: float) -> void:
	_time += delta
	for i in _rigs.size():
		var input := _inputs[i]
		input.facing = 1
		input.aim_dir = Vector2.RIGHT
		input.on_floor = true
		input.velocity = Vector2.ZERO
		input.crouching = false
		input.blocking = false
		input.staggered = false
		input.dead = false
		input.shield_forward = _rigs[i].skin_id == "enforcer"
		input.two_handed = _rigs[i].skin_id != "enforcer"
		match _poses[i]:
			"run":
				input.velocity = Vector2(150, 0)
			"aim_up":
				input.aim_dir = Vector2(1, -1).normalized()
			"crouch":
				input.crouching = true
			"jump":
				input.on_floor = false
				input.velocity = Vector2(80, -200)
			"block":
				input.blocking = true
				input.aim_dir = Vector2(1, -0.2).normalized()
			"stagger":
				input.staggered = true
			"dead":
				input.dead = true
		_rigs[i].animate(delta, input)


func _capture() -> void:
	for i in 90:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out)
	print("saved ", _out)
	get_tree().quit()
