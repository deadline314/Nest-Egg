class_name CutsceneActor
extends Node2D
## 過場裡的角色。有骨架外觀（art/characters/<kind>/）就用骨架（與遊戲內同一套動畫）；
## 沒有骨架的角色用頭像做剪影，輕微呼吸起伏。座標是舞台座標，原點在腳底。

const POSES: PackedStringArray = ["idle", "walk", "run", "crouch", "aim_up", "block", "dead", "jump", "sit", "lean", "squat", "wave", "listen"]
const BREATH_PERIOD := 3.2

var actor_id: StringName = &""
## 劇本裡講話的人（章節 speakers 的 id）：說這個人的台詞時，這個演員會點頭比手勢。沒有指定就用 actor_id。
var speaker_id: StringName = &""
var pose: StringName = &"idle"
## 舞台上這個演員用的圖層組（見 WorldLayers.stage_actor_z）。
var layer_slot := 0
## 地面線（舞台座標的腳底 y；NAN＝沒有登記）：從坐姿站起來時，腳要落回這條線（坐在桌上、箱子上的演員不會站起來浮在半空）。
var ground_y := NAN
## 站起來落回地面的速度（舞台像素／秒）與是否正在落下。
const SETTLE_SPEED := 160.0
var _settling := false
var facing := 1
var rig: CharacterRig
var _input := RigInput.new()
var _portrait: Sprite2D
var _t := 0.0
var _last_position := Vector2.ZERO
var _position_known := false
var _listen_flag := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_input.on_floor = true


## kind 是骨架外觀 id；找不到時用 portrait（圖片路徑）做剪影，兩者都沒有回傳 false。
func setup(id: StringName, kind: String, portrait_path: String, unit_scale: float, weapon: String) -> bool:
	actor_id = id
	scale = Vector2.ONE * unit_scale
	if kind != "" and not RigLibrary.character(kind).is_empty():
		rig = CharacterRig.new()
		rig.use_level_lighting = false
		add_child(rig)
		if rig.setup(kind, "npc"):
			rig.set_weapon(weapon)
			_input.two_handed = weapon != ""
			return true
		rig.queue_free()
		rig = null
	var tex := RigLibrary.optional_texture(portrait_path)
	if tex == null:
		return false
	_portrait = Sprite2D.new()
	_portrait.texture = tex
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.centered = true
	var height := 64.0
	_portrait.scale = Vector2.ONE * (height / maxf(1.0, float(tex.get_height())))
	_portrait.position = Vector2(0, -height * 0.5)
	add_child(_portrait)
	return true


func set_pose(new_pose: StringName) -> void:
	var was_seated := pose == &"sit"
	pose = new_pose
	# 從坐姿換成站、走、跑…：位置還在座位的高度，要落回地面線，不能浮空。
	if was_seated and new_pose != &"sit" and not is_nan(ground_y) and absf(position.y - ground_y) > 0.5:
		_settling = true


## 專屬工作循環（art/rigs/npc_animations.json 的 loops，空字串＝沒有）；scale 放大縮小幅度。
func set_loop(loop_name: StringName, scale := 1.0) -> void:
	_input.npc_loop = loop_name
	_input.npc_loop_scale = scale


## 說話中（點頭與手勢）。
func set_talking(value: bool) -> void:
	_input.talking = value


## 聆聽中（微微偏頭）。
func set_listening(value: bool) -> void:
	_listen_flag = value


func face(direction: int) -> void:
	facing = 1 if direction >= 0 else -1
	if _portrait != null:
		_portrait.flip_h = facing < 0


func _process(delta: float) -> void:
	_t += delta
	if _settling:
		position.y = move_toward(position.y, ground_y, SETTLE_SPEED * delta)
		_settling = not is_equal_approx(position.y, ground_y)
	if rig != null:
		# Stage translation and enlarged actors must use the same space as the leg solver.
		var velocity := (position - _last_position) / maxf(delta * absf(scale.x) * rig.body_scale(), 0.0001) if _position_known else Vector2.ZERO
		_apply_pose(velocity)
		rig.animate(delta, _input)
	elif _portrait != null:
		_portrait.position.y = -32.0 + sin(_t * TAU / BREATH_PERIOD) * 0.8
	_last_position = position
	_position_known = true


func _apply_pose(velocity: Vector2) -> void:
	_input.facing = facing
	_input.aim_dir = Vector2(float(facing), 0.0)
	_input.velocity = Vector2.ZERO
	_input.on_floor = true
	_input.crouching = false
	_input.blocking = false
	_input.dead = false
	_input.npc_pose = &"stand"
	_input.waving = false
	_input.listening = _listen_flag
	match pose:
		&"sit", &"lean":
			_input.npc_pose = pose
		&"squat":
			_input.npc_pose = &"crouch"
		&"wave":
			_input.waving = true
		&"listen":
			_input.listening = true
		&"walk", &"run":
			_input.velocity = Vector2(velocity.x, 0.0)
		&"crouch":
			_input.crouching = true
		&"aim_up":
			_input.aim_dir = Vector2(float(facing), -1.0).normalized()
		&"block":
			_input.blocking = true
		&"dead":
			_input.dead = true
		&"jump":
			_input.on_floor = false
			_input.velocity = Vector2(60.0 * facing, -120.0)
