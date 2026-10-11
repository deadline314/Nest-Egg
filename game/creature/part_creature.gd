class_name PartCreature
extends Node2D
## 零件式生物（NE-99、NE-100）：一組貼圖零件（掛在父零件的關節上）加上資料驅動的程序動畫，給機械類與動物類的非人形敵人用。
## 資料在 art/creatures/<id>.json：
##   dir / texture_scale   零件圖資料夾與貼圖縮放（預設 0.25：貼圖 4 像素＝世界 1 像素）
##   parts[]               name、file、pivot（關節在貼圖上的像素位置）、pos（相對父零件關節的世界像素）、parent、z、rot、tint、
##                         aim（跟著瞄準方向轉，倍率）、recoil（開火時往後退的位移 [x, y]）、muzzle（零件座標的槍口 [x, y]）
##   states{}              每個狀態有 channels[]（part、prop＝rot／x／y／sx／sy、base、amp、freq、phase、abs）與 root{bob_amp、bob_freq、tilt}
##   channels 的 vfreq     頻率隨速度增加：實際頻率 = freq + vfreq × 速度比例（速度 ÷ gait.full_speed，上限 1.5），拍翼隨飛行速度加快用
##   gait{}                腳的步態：stride（一個週期走多遠）、hop（身體起伏）、legs[]（part、phase、swing、lift）
## 切換狀態時各通道的參數（基準、幅度、頻率）平滑過渡，波形的相位連續，不會跳。資料有錯（缺貼圖、找不到父零件、通道指向不存在的零件）時
## 記錄具體位置並略過那一項，不會崩潰；整份資料不可用時 setup 回傳 false，呼叫端改用程式繪製。

const PATH := "res://art/creatures/%s.json"
const BLEND_SPEED := 8.0
const DEFAULT_TEXTURE_SCALE := 0.25
const FLASH_TIME := 0.06
const FLASH_BRIGHTNESS := 1.45
const RECOIL_RECOVERY := 8.0
const GAIT_THRESHOLD := 6.0
const PROPS: Array[String] = ["rot", "x", "y", "sx", "sy"]

var creature_id := ""
var state: StringName = &"idle"
var state_time := 0.0

var _root: Node2D
var _parts: Array[Dictionary] = []
var _by_name: Dictionary = {}
var _states: Dictionary = {}
var _channels: Dictionary = {}
var _gait: Dictionary = {}
var _time := 0.0
var _gait_phase := 0.0
var _speed_ratio := 0.0
var _speed_all := 0.0
var _aim := 0.0
var _recoil := 0.0
var _flash_left := 0.0
var _wear := Color.WHITE
var _root_params := {"bob_amp": 0.0, "bob_freq": 1.5, "tilt": 0.0}
var _root_target := {"bob_amp": 0.0, "bob_freq": 1.5, "tilt": 0.0}
var _bob_phase := 0.0
var _shown := PackedStringArray()  # 目前狀態只顯示這些零件；空 = 全部顯示
var _hidden: Dictionary[String, bool] = {}  # 遊戲中被拿掉的零件（例如頭目打壞的砲塔），任何狀態都不顯示
var _tilt := 0.0
## 外部加上的整體變換（受擊的踉蹌、震動、傾斜等）：疊在狀態動畫上。
var extra_position := Vector2.ZERO
var extra_rotation := 0.0
var extra_scale := Vector2.ONE


## 建立零件。回傳 false 代表資料無法使用（已記錄原因）。
func setup(id: String) -> bool:
	creature_id = id
	var data := RigLibrary.load_json(PATH % id)
	if data.is_empty():
		return false
	var dir := str(data.get("dir", "res://art/creatures/%s/" % id))
	var texture_scale := float(data.get("texture_scale", DEFAULT_TEXTURE_SCALE))
	_root = Node2D.new()
	_root.name = "Root"
	add_child(_root)
	var parts: Variant = data.get("parts", [])
	if typeof(parts) != TYPE_ARRAY or (parts as Array).is_empty():
		RigLibrary.report_once("part_creature_parts:" + id, "[PartCreature] %s 沒有 parts" % (PATH % id))
		return false
	for entry: Variant in parts:
		if typeof(entry) == TYPE_DICTIONARY:
			_add_part(entry as Dictionary, dir, texture_scale)
	if _parts.is_empty():
		return false
	_states = data.get("states", {})
	_gait = data.get("gait", {})
	_collect_channels()
	_apply_state_targets()
	for channel: Dictionary in _channels.values():
		channel["base"] = channel["t_base"]
		channel["amp"] = channel["t_amp"]
		channel["freq"] = channel["t_freq"]
	return true


func _add_part(entry: Dictionary, dir: String, texture_scale: float) -> void:
	var part_name := str(entry.get("name", ""))
	if part_name.is_empty() or _by_name.has(part_name):
		RigLibrary.report_once("part_creature_name:%s:%s" % [creature_id, part_name], "[PartCreature] %s 的零件名稱空白或重複：「%s」" % [PATH % creature_id, part_name])
		return
	var file := str(entry.get("file", ""))
	var path := dir.path_join(file)
	if not ResourceLoader.exists(path):
		RigLibrary.report_once("part_creature_tex:" + path, "[PartCreature] %s 的零件「%s」找不到貼圖：%s" % [PATH % creature_id, part_name, path])
		return
	var parent_name := str(entry.get("parent", ""))
	var parent_node: Node2D = _root
	if not parent_name.is_empty():
		if not _by_name.has(parent_name):
			RigLibrary.report_once("part_creature_parent:%s:%s" % [creature_id, part_name], "[PartCreature] %s 的零件「%s」找不到父零件「%s」（父零件要先定義）" % [PATH % creature_id, part_name, parent_name])
			return
		parent_node = _parts[int(_by_name[parent_name])]["joint"]
	var joint := Node2D.new()
	joint.name = part_name
	joint.position = RigLibrary.vec2(entry.get("pos"))
	joint.rotation = float(entry.get("rot", 0.0))
	joint.z_index = int(entry.get("z", 0))
	parent_node.add_child(joint)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = LitTextures.load_texture(path, Vector2i(16, 16))
	sprite.offset = -RigLibrary.vec2(entry.get("pivot"))
	sprite.scale = Vector2.ONE * texture_scale
	var tint := float(entry.get("tint", 1.0))
	sprite.self_modulate = Color(tint, tint, tint, 1.0)
	joint.add_child(sprite)
	var recoil: Variant = entry.get("recoil", [0.0, 0.0])
	_by_name[part_name] = _parts.size()
	_parts.append({
		"name": part_name, "joint": joint, "sprite": sprite,
		"rest_pos": joint.position, "rest_rot": joint.rotation,
		"aim": float(entry.get("aim", 0.0)),
		"recoil": Vector2(float(recoil[0]), float(recoil[1])) if typeof(recoil) == TYPE_ARRAY and (recoil as Array).size() >= 2 else Vector2.ZERO,
		"muzzle": RigLibrary.vec2(entry.get("muzzle"), Vector2.ZERO) if entry.has("muzzle") else Vector2.INF,
		"pos": Vector2.ZERO, "rot": 0.0, "scale": Vector2.ONE,
	})


## 所有狀態用到的通道（零件＋屬性）合成一份表；每個通道各自有目前參數、目標參數與相位。
func _collect_channels() -> void:
	for state_name: String in _states.keys():
		var def: Variant = _states[state_name]
		if typeof(def) != TYPE_DICTIONARY:
			continue
		for channel: Variant in (def as Dictionary).get("channels", []):
			if typeof(channel) != TYPE_DICTIONARY:
				continue
			var c := channel as Dictionary
			var key := _channel_key(c)
			if key.is_empty() or _channels.has(key):
				continue
			var part_name := str(c.get("part", ""))
			if not _by_name.has(part_name):
				RigLibrary.report_once("part_creature_channel:%s:%s" % [creature_id, part_name], "[PartCreature] %s 的狀態「%s」有通道指向不存在的零件「%s」" % [PATH % creature_id, state_name, part_name])
				continue
			if not PROPS.has(str(c.get("prop", ""))):
				RigLibrary.report_once("part_creature_prop:%s:%s" % [creature_id, key], "[PartCreature] %s 的通道 %s 屬性不是 %s" % [PATH % creature_id, key, PROPS])
				continue
			_channels[key] = {
				"part": int(_by_name[part_name]), "prop": str(c["prop"]), "abs": false,
				"base": 0.0, "amp": 0.0, "freq": float(c.get("freq", 1.0)), "phase": 0.0, "offset": float(c.get("phase", 0.0)),
				"t_base": 0.0, "t_amp": 0.0, "t_freq": float(c.get("freq", 1.0)), "vfreq": 0.0, "t_vfreq": 0.0,
			}


static func _channel_key(channel: Dictionary) -> String:
	var part_name := str(channel.get("part", ""))
	var prop := str(channel.get("prop", ""))
	return "" if part_name.is_empty() or prop.is_empty() else "%s:%s" % [part_name, prop]


func set_state(new_state: StringName) -> void:
	if new_state != state:
		state = new_state
		state_time = 0.0
		_apply_state_targets()


## 目前狀態的各通道目標參數：狀態沒有的通道目標回到「靜止」（基準 0、幅度 0）。
func _apply_state_targets() -> void:
	var def: Dictionary = {}
	var found: Variant = _states.get(String(state), _states.get("idle", {}))
	if typeof(found) == TYPE_DICTIONARY:
		def = found
	elif not _states.is_empty():
		RigLibrary.report_once("part_creature_state:%s:%s" % [creature_id, state], "[PartCreature] %s 沒有狀態「%s」，改用 idle" % [PATH % creature_id, state])
	for channel: Dictionary in _channels.values():
		channel["t_base"] = 0.0
		channel["t_vfreq"] = 0.0
		channel["t_amp"] = 0.0
	for entry: Variant in def.get("channels", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var c := entry as Dictionary
		var key := _channel_key(c)
		if not _channels.has(key):
			continue
		var channel: Dictionary = _channels[key]
		channel["t_base"] = float(c.get("base", 0.0))
		channel["t_amp"] = float(c.get("amp", 0.0))
		channel["t_freq"] = float(c.get("freq", channel["t_freq"]))
		channel["t_vfreq"] = float(c.get("vfreq", 0.0))
		channel["abs"] = bool(c.get("abs", false))
		channel["offset"] = float(c.get("phase", 0.0))
	_shown = PackedStringArray(def.get("show", []))
	var root: Dictionary = def.get("root", {})
	_root_target = {"bob_amp": float(root.get("bob_amp", 0.0)), "bob_freq": float(root.get("bob_freq", 1.5)), "tilt": float(root.get("tilt", 0.0))}


## 每影格呼叫：velocity 是敵人的速度（步態與傾斜用）、facing 是 -1／1、aim_angle 是瞄準方向相對面向的弧度（有 aim 的零件用）。
func animate(delta: float, new_state: StringName, velocity := Vector2.ZERO, face := 1, aim_angle := 0.0) -> void:
	if _parts.is_empty():
		return
	set_state(new_state)
	_time += delta
	state_time += delta
	scale.x = float(face)
	_aim = aim_angle
	var blend := 1.0 - exp(-BLEND_SPEED * delta)
	for channel: Dictionary in _channels.values():
		channel["base"] = lerpf(float(channel["base"]), float(channel["t_base"]), blend)
		channel["amp"] = lerpf(float(channel["amp"]), float(channel["t_amp"]), blend)
		channel["freq"] = lerpf(float(channel["freq"]), float(channel["t_freq"]), blend)
		channel["vfreq"] = lerpf(float(channel["vfreq"]), float(channel["t_vfreq"]), blend)
		channel["phase"] = float(channel["phase"]) + TAU * (float(channel["freq"]) + float(channel["vfreq"]) * _speed_all) * delta
	for key: String in _root_params.keys():
		_root_params[key] = lerpf(float(_root_params[key]), float(_root_target[key]), blend)
	_bob_phase += TAU * float(_root_params["bob_freq"]) * delta
	_recoil = move_toward(_recoil, 0.0, RECOIL_RECOVERY * delta)
	_speed_all = clampf(velocity.length() / maxf(1.0, float(_gait.get("full_speed", 80.0))), 0.0, 1.5)
	_update_gait(delta, velocity)
	for part: Dictionary in _parts:
		part["pos"] = Vector2.ZERO
		part["rot"] = 0.0
		part["scale"] = Vector2.ONE
	for channel: Dictionary in _channels.values():
		var wave := sin(float(channel["phase"]) + float(channel["offset"]))
		if bool(channel["abs"]):
			wave = absf(wave)
		var value := float(channel["base"]) + float(channel["amp"]) * wave
		var part: Dictionary = _parts[int(channel["part"])]
		match str(channel["prop"]):
			"rot":
				part["rot"] = float(part["rot"]) + value
			"x":
				part["pos"] = (part["pos"] as Vector2) + Vector2(value, 0.0)
			"y":
				part["pos"] = (part["pos"] as Vector2) + Vector2(0.0, value)
			"sx":
				part["scale"] = (part["scale"] as Vector2) + Vector2(value, 0.0)
			"sy":
				part["scale"] = (part["scale"] as Vector2) + Vector2(0.0, value)
	_apply_gait_to_parts()
	for part: Dictionary in _parts:
		var joint: Node2D = part["joint"]
		var rot := float(part["rot"]) + float(part["aim"]) * _aim
		joint.position = (part["rest_pos"] as Vector2) + (part["pos"] as Vector2) + (part["recoil"] as Vector2) * _recoil
		joint.rotation = float(part["rest_rot"]) + rot
		joint.scale = part["scale"]
		joint.visible = (_shown.is_empty() or _shown.has(str(part["name"]))) and not _hidden.has(str(part["name"]))
	var bob := sin(_bob_phase) * float(_root_params["bob_amp"]) - float(_gait.get("hop", 0.0)) * absf(sin(_gait_phase)) * _speed_ratio
	_tilt = lerpf(_tilt, clampf(velocity.x * float(face) / 100.0, -1.0, 1.0) * float(_root_params["tilt"]), blend)
	_root.position = Vector2(0.0, bob) + extra_position
	_root.rotation = _tilt + extra_rotation
	_root.scale = extra_scale
	_update_flash(delta)


## 步態：踩一個週期走 stride 像素；速度比例決定腿擺多大（走得慢擺得小）。
func _update_gait(delta: float, velocity: Vector2) -> void:
	var stride := maxf(4.0, float(_gait.get("stride", 14.0)))
	var speed := absf(velocity.x)
	_speed_ratio = clampf(speed / maxf(1.0, float(_gait.get("full_speed", 80.0))), 0.0, 1.0) if speed > GAIT_THRESHOLD else 0.0
	_gait_phase += speed * delta / stride * TAU


func _apply_gait_to_parts() -> void:
	for leg: Variant in _gait.get("legs", []):
		if typeof(leg) != TYPE_DICTIONARY:
			continue
		var l := leg as Dictionary
		var part_name := str(l.get("part", ""))
		if not _by_name.has(part_name):
			continue
		var part: Dictionary = _parts[int(_by_name[part_name])]
		var phase := _gait_phase + float(l.get("phase", 0.0))
		part["rot"] = float(part["rot"]) + float(l.get("swing", 0.6)) * _speed_ratio * sin(phase)
		part["pos"] = (part["pos"] as Vector2) + Vector2(0.0, -float(l.get("lift", 2.0)) * _speed_ratio * maxf(0.0, cos(phase)))


## 受擊閃白（亮度提高一下，不是純白，外形與顏色看得出來）。
func flash() -> void:
	_flash_left = FLASH_TIME
	_update_flash(0.0)


func _update_flash(delta: float) -> void:
	_flash_left = maxf(0.0, _flash_left - delta)
	var k := FLASH_BRIGHTNESS if _flash_left > 0.0 else 1.0
	modulate = Color(_wear.r * k, _wear.g * k, _wear.b * k, 1.0)


## 損傷狀態的外觀變舊（乘在所有零件上）。
func set_wear(color: Color) -> void:
	_wear = color


## 開火的後座：有 recoil 的零件往後退，之後回復。
func kick() -> void:
	_recoil = 1.0


## 某個零件的槍口（資料裡的 muzzle）世界座標；沒有設定時回傳該零件關節的世界座標。
func muzzle_global(part_name: String) -> Vector2:
	if not _by_name.has(part_name):
		return global_position
	var part: Dictionary = _parts[int(_by_name[part_name])]
	var joint: Node2D = part["joint"]
	var local: Vector2 = part["muzzle"]
	return joint.to_global(Vector2.ZERO if local == Vector2.INF else local)


func part_names() -> PackedStringArray:
	var names := PackedStringArray()
	for part: Dictionary in _parts:
		names.append(part["name"])
	return names


## 遊戲中拿掉或放回某個零件（連同掛在它下面的零件）；回傳這個零件是否存在。
func set_part_hidden(part_name: String, hidden: bool) -> bool:
	if not _by_name.has(part_name):
		return false
	if hidden:
		_hidden[part_name] = true
	else:
		_hidden.erase(part_name)
	(_parts[int(_by_name[part_name])]["joint"] as Node2D).visible = not hidden
	return true


## 零件的目前關節（測試與稽核用）。
func joint_of(part_name: String) -> Node2D:
	return _parts[int(_by_name[part_name])]["joint"] if _by_name.has(part_name) else null
