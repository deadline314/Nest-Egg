class_name WorldPropAction
extends RefCounted
## Bounded presentation on the real player. Inventory and durable results belong
## to StoryResultCompletion; this owner only moves a hand and temporary visuals.
## 種類：insert（把持有的物品送進插口）、take_paper（接住出紙口的紙）、turn（握住手輪沿輪緣轉動，ST-21）。
## turn 的資料：hub＝手輪中心、radius＝輪緣的橢圓半徑（側視時是扁的橢圓）、sweep＝手沿前半圈從哪個角度推到哪個角度（度，0＝右、90＝前下緣）、
## strokes＝推幾次（每次推完鬆手回到起點再握）、stall＝推到幾成就卡住（1＝推到底；小於 1 會在那裡頂住、往回彈一點，表示轉不動）。
## support（扶人坐下，ST-21）：沒有擺設，對象就是正在交談的場景人物；station 相對於人物的位置，person_facing 是人物在演出中面向哪邊
## （例如面向櫃檯坐下），bone＋contact 是手扶的地方（人物骨頭加偏移；contact.x 正的是人物前方、負的是背後），
## pose 是扶完之後人物的姿勢（例如 sit）。人物換姿勢時手跟著那根骨頭下來；演出只換姿勢與面向，旗標仍由保存成功後的結果寫入。
## place（拿起、沖洗、放好，ST-19）：手到擺設的 pick 點拿起一件只用來呈現的東西（texture／width／grip，例如一只碗），
## 繞著 pick 點做 scrub_loops 圈小動作（scrub 是橢圓半徑，往上繞；0 圈就是直接拿起），再放到 drop 點、放手。不需要擺設的反應物件，也不動任何物品。
## hand_angle（選填，度）：手掌朝向，0＝朝前平舉、正的往下彎（例如在水槽邊向下沖碗）；沒寫就是 0。

const TABLE := "res://data/cutscene/world_prop_actions.json"
const CONTACT_TOLERANCE := 0.25
const MAX_APPROACH := 64.0
const APPROACH_SPEED := 28.0
const MAX_SECONDS := 20.0

static var _table: Dictionary = {}

var done := false
var failed := false
var error := ""
var failure_hint := &"unavailable"
var phase := ""
var contact_error := 0.0
var contacts_completed := 0
var paper_instance := 0
var intake_error := INF
var paper_grip_error := INF
var _player: WeakRef
var _prop: WeakRef
var _reaction: WeakRef
var _request := 0
var _spec: Dictionary
var _sequence: Array[Dictionary] = []
var _index := 0
var _elapsed := 0.0
var _age := 0.0
var _duration := 0.0
var _start_position := Vector2.ZERO
var _station := Vector2.ZERO
var _from_hand := Vector2.ZERO
var _last_hand := Vector2.ZERO
var _phase_started := false
var _hand_started := false
var _source: WeakRef
var _camera: WeakRef
var _carrier: Node2D
var _disk: Sprite2D
var _paper: PropPaperVisual
var _paper_start := Vector2.ZERO
var _disk_scale := 1.0
var _grip := Vector2.ZERO
var _tip := Vector2.ZERO


static func definition(id: String) -> Dictionary:
	if _table.is_empty():
		var file := FileAccess.open(TABLE, FileAccess.READ) if FileAccess.file_exists(TABLE) else null
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null and file.get_length() <= 65536 else null
		if parsed is Dictionary and parsed.size() <= 32:
			_table = parsed
	var value: Variant = _table.get(id, {})
	return value if value is Dictionary else {}


static func problem(id: Variant, scene: String, overlay: Variant) -> String:
	if not id is String or not id.is_valid_identifier() or overlay != true:
		return "world_action requires a named action in an overlay scene"
	var spec := definition(id)
	if spec.is_empty() or spec.get("scene") != scene or spec.get("kind") not in ["insert", "take_paper", "turn", "support", "place"]:
		return "world_action is missing or belongs to another scene"
	var required: Array[String] = ["level", "source", "prop", "reaction"]
	if spec["kind"] == "support":
		required = ["level", "source", "bone", "pose"]
	elif spec["kind"] == "place":
		required = ["level", "source", "prop"]
	for key: String in required:
		if not spec.get(key) is String or spec[key].is_empty():
			return "world_action requires " + key
	if not spec["level"].begins_with("res://data/levels/") or not spec["source"].begins_with("res://data/npcs/"):
		return "world_action requires authored level and NPC resources"
	if not ResourceLoader.exists(spec["level"]) or not ResourceLoader.exists(spec["source"]):
		return "world_action level/source is unavailable"
	if typeof(spec.get("facing")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(spec["facing"])) or absf(float(spec["facing"])) != 1.0:
		return "world_action facing must be -1 or 1"
	var points: Array[String] = ["station"]
	if spec["kind"] == "insert":
		points.append_array(["grip", "tip"])
		if not spec.get("texture") is String or not spec["texture"].begins_with("res://art/items/world/") or not ResourceLoader.exists(spec["texture"]):
			return "world_action requires a registered world-item texture"
		if not spec.get("item") is String or not spec.get("anchor") is String:
			return "world_action requires item and contact anchor"
		if typeof(spec.get("width")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(spec["width"])) or float(spec["width"]) < 1.0 or float(spec["width"]) > 8.0:
			return "world_action width must be 1..8"
	if spec["kind"] == "place":
		points.append_array(["grip", "pick", "drop", "scrub"])
		var texture: Variant = spec.get("texture")
		if not texture is String or not (texture.begins_with("res://art/items/world/") or texture.begins_with("res://art/environment/scene_props/")) \
				or not ResourceLoader.exists(texture):
			return "world_action place requires a registered held texture"
		if typeof(spec.get("width")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(spec["width"])) or float(spec["width"]) < 1.0 or float(spec["width"]) > 12.0:
			return "world_action place width must be 1..12"
		var tilt: Variant = spec.get("hand_angle", 0.0)
		if typeof(tilt) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(tilt)) or absf(float(tilt)) > 100.0:
			return "world_action hand_angle must be within ±100 degrees"
		var loops: Variant = spec.get("scrub_loops", 0)
		if typeof(loops) not in [TYPE_INT, TYPE_FLOAT] or float(loops) != floorf(float(loops)) or int(loops) < 0 or int(loops) > 3:
			return "world_action scrub_loops must be 0..3"
	if spec["kind"] == "support":
		points.append("contact")
		if not spec["bone"].is_valid_identifier() or spec["pose"] not in ["sit", "idle", "lean", "crouch"]:
			return "world_action support requires a bone name and a known pose"
		if typeof(spec.get("person_facing")) not in [TYPE_INT, TYPE_FLOAT] or absf(float(spec["person_facing"])) != 1.0:
			return "world_action support person_facing must be -1 or 1"
	if spec["kind"] == "turn":
		points.append_array(["hub", "radius", "sweep"])
		var strokes: Variant = spec.get("strokes", 1)
		if typeof(strokes) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(strokes)) or float(strokes) != floorf(float(strokes)) or int(strokes) < 1 or int(strokes) > 3:
			return "world_action strokes must be 1..3"
		var stall: Variant = spec.get("stall", 1.0)
		if typeof(stall) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(stall)) or float(stall) <= 0.0 or float(stall) > 1.0:
			return "world_action stall must be in (0, 1]"
	for key: String in points:
		var point: Variant = spec.get(key)
		if not point is Array or point.size() != 2:
			return "world_action requires a two-number " + key
		for component: Variant in point:
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)) or absf(float(component)) > 256.0:
				return "world_action coordinates must be finite and bounded"
	if spec["kind"] == "turn":
		if float(spec["radius"][0]) < 1.0 or float(spec["radius"][1]) < 0.0 or float(spec["radius"][1]) > float(spec["radius"][0]):
			return "world_action radius must be a flat rim ellipse (1 <= x, 0 <= y <= x)"
		var sweep := absf(float(spec["sweep"][1]) - float(spec["sweep"][0]))
		if sweep < 10.0 or sweep > 180.0:
			return "world_action sweep must cover 10..180 degrees of the rim"
	return ""


func start(id: String, player: Player, scene: String) -> bool:
	error = problem(id, scene, true)
	if not error.is_empty() or not is_instance_valid(player) or not player.is_inside_tree():
		return _fail("world action data or player is unavailable: " + error)
	_spec = definition(id)
	_request = Story.current_presentation_request()
	if not player.interaction.active or Story._current_cinematic != StringName(scene) or _request == 0 \
			or player.is_dead() or player.is_on_phone() or not player.is_on_floor() or absf(player.velocity.y) > 0.1 \
			or (player.carry != null and player.carry.is_holding()):
		return _fail("world action requires a grounded player with free hands and its active request", &"stance")
	var level := player.get_parent()
	while level != null and not level is Level:
		level = level.get_parent()
	if level == null or (level as Level).data.resource_path != _spec["level"]:
		return _fail("world action requires its authored Level")
	var source: NpcActor
	for node: Node in player.get_tree().get_nodes_in_group(NpcActor.GROUP):
		if node is NpcActor and level.is_ancestor_of(node) and node.data != null and node.data.resource_path == _spec["source"] \
				and node._talking and Story.current_presentation_context().get("source_id") == node.state_key():
			if source != null:
				return _fail("world action source is ambiguous")
			source = node
	if source == null:
		return _fail("world action requires the actual talking source")
	_source = weakref(source)
	if _spec["kind"] == "support":
		return _start_support(player, source)
	var prop: PropNode
	for node: Node in player.get_tree().get_nodes_in_group(PropNode.GROUP):
		if node is PropNode and level.is_ancestor_of(node) and node.data != null and String(node.data.id) == _spec["prop"]:
			if prop != null:
				return _fail("world action prop is ambiguous")
			prop = node
	if prop == null or prop.flip:
		return _fail("world action prop is unavailable or mirrored")
	if _spec["kind"] == "place":
		return _start_place(player, prop)
	var reaction: PropReaction
	for child in prop.get_children():
		if child is PropReaction and String(child.reaction_id) == _spec["reaction"]:
			if reaction != null:
				return _fail("world action reaction is ambiguous")
			reaction = child
	if reaction == null or not player._visual.rig.has_hand_grip(&"front"):
		return _fail("world action requires a fixture reaction and registered grip")
	_player = weakref(player)
	_prop = weakref(prop)
	_reaction = weakref(reaction)
	_start_position = player.global_position
	_station = prop.to_global(Vector2(_spec["station"][0], _spec["station"][1]))
	if not route_clear(player, _station):
		return _fail("world action approach is blocked or unsupported", &"route")
	player.velocity = Vector2.ZERO
	if _spec["kind"] == "insert":
		if not StoryItems.holds(StringName(_spec["item"])) or not reaction.contact_global(StringName(_spec["anchor"])).is_finite():
			return _fail("world action requires the held original and a real intake anchor")
		var texture := RigLibrary.optional_texture(_spec["texture"])
		if texture == null:
			return _fail("world action item texture is unavailable")
		_grip = Vector2(_spec["grip"][0], _spec["grip"][1])
		_tip = Vector2(_spec["tip"][0], _spec["tip"][1])
		var rect := Rect2(Vector2.ZERO, texture.get_size())
		if not rect.has_point(_grip) or not rect.has_point(_tip) or _tip.x <= _grip.x:
			return _fail("world action item grip/tip is outside its texture")
		_disk_scale = float(_spec["width"]) / texture.get_width()
		_make_carrier(player)
		_disk = Sprite2D.new()
		_disk.texture = texture
		_disk.centered = false
		_disk.hide()
		_carrier.add_child(_disk)
		_sequence = [{"id":"approach"}, {"id":"pocket", "time":0.4}, {"id":"present", "time":0.4},
			{"id":"contact", "time":0.6}, {"id":"insert", "time":0.6}, {"id":"release", "time":0.35}]
	elif _spec["kind"] == "turn":
		_sequence = turn_sequence(int(_spec.get("strokes", 1)), float(_spec.get("stall", 1.0)))
	else:
		if not reaction._paper_shown:
			return _fail("world action has no receipt at the outlet")
		_make_carrier(player)
		_sequence = [{"id":"approach"}, {"id":"feed", "time":0.1}, {"id":"take", "time":0.5},
			{"id":"pull", "time":0.3}, {"id":"stow", "time":0.65}, {"id":"release", "time":0.35}]
	_enter_phase()
	_frame_camera(player, prop.global_position.x + prop.data.size.x * 0.5)
	return true


## 演出期間鏡頭對準站位與互動對象的中間，腳底留在對話框之上；鏡頭已被別的演出持有時維持原樣。
func _frame_camera(player: Player, subject_x: float) -> void:
	var camera := player.get_viewport().get_camera_2d() as LevelCamera
	if camera == null:
		return
	var feet_y := CutsceneChecker.FEET_MAX_SCREEN_Y - 4.0
	var point := Vector2((_station.x + subject_x) * 0.5, _station.y - (feet_y - player.get_viewport_rect().size.y * 0.5) / camera.zoom.y)
	if camera.acquire_presentation_focus(self, point):
		_camera = weakref(camera)


## Static preflight, once per action. Never move the paused body through a wall or gap.
static func route_clear(player: Player, station: Vector2) -> bool:
	if not station.is_finite() or absf(station.y - player.global_position.y) > 1.0 or absf(station.x - player.global_position.x) > MAX_APPROACH:
		return false
	var motion := Vector2(station.x - player.global_position.x, 0.0)
	if player.test_move(player.global_transform, motion, null, 0.001, false):
		return false
	var space := player.get_world_2d().direct_space_state
	var samples := maxi(1, ceili(absf(motion.x) / 4.0))
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = Layers.SOLID
	query.exclude = [player.get_rid()]
	for i in samples + 1:
		var foot := player.global_position + motion * (float(i) / samples)
		query.from = foot + Vector2(0, -0.5)
		query.to = foot + Vector2(0, 1.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit["normal"] as Vector2).y > -0.9 or absf((hit["position"] as Vector2).y - station.y) > 1.0:
			return false
	return true


func before_frame(input: RigInput, delta: float) -> void:
	input.velocity = Vector2.ZERO
	input.hand_grip_front = false
	if done:
		return
	var player := _live_player()
	var reaction := _live_reaction()
	var source := _source.get_ref() as NpcActor if _source != null else null
	if player == null or (reaction == null and not _without_reaction()) or not is_instance_valid(source) or not source.is_inside_tree() or source.is_queued_for_deletion() \
			or not source._talking or not player.interaction.active or Story.current_presentation_request() != _request or Story._current_cinematic != StringName(_spec["scene"]):
		_fail("world action owner/request retired")
		close()
		return
	var dt := clampf(delta, 0.0, 0.1)
	_age += dt
	_elapsed += dt
	if _age > MAX_SECONDS:
		_fail("world action exceeded its bounded presentation time")
		return
	input.facing = int(_spec["facing"])
	input.aim_dir = Vector2(input.facing, 0)
	input.on_floor = true  # Start was physically grounded; route support was checked.
	# Presentation turns only the rig input. Gameplay facing stays paired with its
	# actual aim, so restoring the held weapon cannot create a crossed-arm frame.
	if phase == "approach":
		var t := clampf(_elapsed / _duration, 0.0, 1.0)
		player.global_position = _start_position.lerp(_station, smoothstep(0.0, 1.0, t))
		input.velocity.x = (_station.x - _start_position.x) * 6.0 * t * (1.0 - t) / _duration
		input.run_speed = player.tuning.run_speed
		if absf(_station.x - _start_position.x) > 0.01:
			input.facing = 1 if _station.x > _start_position.x else -1
			input.aim_dir = Vector2(input.facing, 0)
	elif phase == "feed" and reaction != null:
		reaction.presentation_tick(dt)
	else:
		input.hand_grip_front = true


func after_frame(rig: CharacterRig) -> void:
	if done:
		return
	var player := _live_player()
	var reaction := _live_reaction()
	if player == null or (reaction == null and not _without_reaction()):
		_fail("world action lost its fixture")
		return
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	if phase not in ["approach", "feed"]:
		if not _phase_started:
			_from_hand = _last_hand if _hand_started else rig.hand_contact_global(&"front")
			_hand_started = true
			_phase_started = true
		var goal := _goal(player, reaction)
		if not goal.is_finite() or not _from_hand.is_finite():
			_fail("world action contact is unavailable")
			return
		var target := _from_hand.lerp(goal, eased)
		if phase in ["turn", "recoil", "lower", "scrub"]:
			target = goal  # 沿輪緣走、跟著人物的肩膀下來，不是直線內插
		elif phase == "regrip":
			target += Vector2(0.0, -1.5 * sin(PI * eased))  # 鬆手回到起點時微微抬起，不在輪緣上拖
		var weight := 1.0 - eased if phase == "release" else 1.0
		var angle := hand_angle()
		var placed := rig.place_hand(&"front", target, angle, weight)
		_last_hand = rig.hand_contact_global(&"front")
		contact_error = _last_hand.distance_to(target)
		if phase != "release" and t >= 1.0 and (not placed or contact_error > CONTACT_TOLERANCE):
			if _elapsed > _duration + 0.5:
				_fail("world action cannot physically reach its contact (%s phase, palm %.2f from %s)" % [phase, contact_error, target])
			return
		_update_held(reaction, eased)
	# Retire presentation footsteps rather than replaying stale falls after unpause.
	player._visual.consume_footfalls()
	if t < 1.0:
		return
	if phase == "feed" and not reaction.paper_ready():
		if _elapsed > 3.0:
			_fail("receipt did not finish feeding")
		return
	if phase == "pocket":
		_disk.show()
		_update_held(reaction, 1.0)
	elif phase == "contact":
		intake_error = _disk.to_global(_tip).distance_to(reaction.contact_global(StringName(_spec["anchor"])))
		if intake_error > CONTACT_TOLERANCE:
			_fail("the visible disk tip did not reach the real intake")
			return
		contacts_completed += 1
	elif phase == "insert":
		_disk.hide()
		contacts_completed += 1
		Sfx.play(&"switch", -10.0)
	elif phase == "take":
		paper_grip_error = _last_hand.distance_to(reaction.paper_tip_global())
		if paper_grip_error > CONTACT_TOLERANCE:
			_fail("the visible paper did not touch the real palm")
			return
		_paper_start = _last_hand
		_paper = reaction.claim_paper(_carrier)
		if _paper == null:
			_fail("receipt visual is already owned or unavailable")
			return
		paper_instance = _paper.get_instance_id()
		contacts_completed += 1
		_update_held(reaction, 0.0)
	elif phase == "stow" and is_instance_valid(_paper):
		_paper.hide()
	elif phase == "turn":
		contacts_completed += 1
		Sfx.play(&"switch", -12.0)
	elif phase == "recoil":
		Sfx.play(&"empty", -6.0)
	elif phase == "lower":
		contacts_completed += 1
	elif phase == "lift":
		if is_instance_valid(_disk):
			_disk.show()
			_update_held(reaction, 1.0)
		Sfx.play(&"step_wet", -14.0)  # 碗離開水面的水聲
	elif phase == "place":
		contacts_completed += 1
		if is_instance_valid(_disk):
			_disk.hide()
		Sfx.play(&"switch", -14.0)
	_index += 1
	if _index >= _sequence.size():
		done = true
	else:
		_enter_phase()


func _enter_phase() -> void:
	phase = _sequence[_index]["id"]
	if phase == "lower":
		var source := _source.get_ref() as NpcActor if _source != null else null
		if is_instance_valid(source):
			source.present_pose(StringName(_spec["pose"]))
	_elapsed = 0.0
	_phase_started = false
	_duration = maxf(0.1, absf(_station.x - _start_position.x) / APPROACH_SPEED * 1.5) if phase == "approach" else float(_sequence[_index]["time"])


func _goal(player: Player, reaction: PropReaction) -> Vector2:
	var side := float(_spec["facing"])
	match phase:
		"pocket", "stow": return player.global_position + Vector2(side * 6.0, -34.0)
		"present": return player.global_position + Vector2(side * 9.0, -35.0)
		"contact": return reaction.contact_global(StringName(_spec["anchor"])) - Vector2((_tip.x - _grip.x) * _disk_scale, 0.0)
		"insert": return reaction.contact_global(StringName(_spec["anchor"])) - Vector2(0.3, 0.0)
		"take": return reaction.paper_tip_global()
		"steady", "lower": return support_global()
		"pick", "lift": return _prop_point("pick")
		"scrub": return _prop_point("pick") + _scrub_offset(clampf(_elapsed / _duration, 0.0, 1.0))
		"place": return _prop_point("drop")
		"reach", "regrip": return rim_global(float(_spec["sweep"][0])) if _spec["kind"] == "turn" else support_global()
		"turn": return rim_global(_turn_angle(smoothstep(0.0, 1.0, clampf(_elapsed / _duration, 0.0, 1.0))))
		"recoil": return rim_global(lerpf(_turn_angle(1.0), _turn_angle(1.0) - signf(float(_spec["sweep"][1]) - float(_spec["sweep"][0])) * RECOIL_DEGREES,
				sin(PI * clampf(_elapsed / _duration, 0.0, 1.0))))
		"pull": return _paper_start + Vector2(0.0, 1.0)
		"release": return _from_hand
	return Vector2.INF


func _update_held(_reaction: PropReaction, t: float) -> void:
	if is_instance_valid(_disk) and _disk.visible:
		var flat := lerpf(1.0, 0.12, t) if phase == "contact" else (0.12 if phase == "insert" else 1.0)
		var basis := Transform2D(Vector2(_disk_scale, 0), Vector2(0, _disk_scale * flat), Vector2.ZERO)
		basis.origin = _last_hand - basis.basis_xform(_grip)
		_disk.global_transform = basis
		if phase == "insert":
			_disk.region_enabled = true
			_disk.region_rect = Rect2(0, 0, lerpf(float(_disk.texture.get_width()), _grip.x, t), _disk.texture.get_height())
	if is_instance_valid(_paper) and _paper.visible:
		var fold := lerpf(1.0, 0.45, t) if phase == "stow" else 1.0
		var basis := Transform2D(Vector2.RIGHT, Vector2(0, fold), Vector2.ZERO)
		basis.origin = _last_hand - basis.basis_xform(Vector2(0, _paper.length))
		_paper.global_transform = basis


func _make_carrier(player: Player) -> void:
	_carrier = Node2D.new()
	_carrier.name = "InteractionProp"
	_carrier.z_index = player._visual.rig.hand_draw_z(&"front")
	player._visual.rig.add_child(_carrier)
	player._visual.rig.move_child(_carrier, 0)


func close() -> void:
	var camera := _camera.get_ref() as LevelCamera if _camera != null else null
	if is_instance_valid(camera):
		camera.release_presentation_focus(self)
	_camera = null
	var reaction := _live_reaction()
	if reaction != null and is_instance_valid(_carrier):
		reaction.return_paper(_carrier)
	if is_instance_valid(_carrier):
		_carrier.queue_free()
	_carrier = null
	_disk = null
	_paper = null
	done = true


func _fail(reason: String, hint: StringName = &"unavailable") -> bool:
	error = reason
	failure_hint = hint
	failed = true
	done = true
	return false


func _live_player() -> Player:
	var value := _player.get_ref() as Player if _player != null else null
	return value if is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion() else null


func _live_reaction() -> PropReaction:
	var value := _reaction.get_ref() as PropReaction if _reaction != null else null
	return value if is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion() else null


## 推手輪卡住時往回彈的角度（度）。
const RECOIL_DEGREES := 8.0


## turn 的階段：走過去、伸手握住、推（卡住時多一段回彈）、鬆手回起點再握……最後放手。
static func turn_sequence(strokes: int, stall: float) -> Array[Dictionary]:
	var sequence: Array[Dictionary] = [{"id": "approach"}, {"id": "reach", "time": 0.35}]
	for i in strokes:
		if i > 0:
			sequence.append({"id": "regrip", "time": 0.25})
		sequence.append({"id": "turn", "time": 0.55 * maxf(0.3, stall)})
		if stall < 1.0:
			sequence.append({"id": "recoil", "time": 0.3})
	sequence.append({"id": "release", "time": 0.35})
	return sequence


## 這一推走到的輪緣角度（度）：卡住時只走到 stall 那一成。
func _turn_angle(progress: float) -> float:
	var stall := float(_spec.get("stall", 1.0))
	return lerpf(float(_spec["sweep"][0]), float(_spec["sweep"][1]), progress * stall)


## 手輪輪緣上某個角度的世界座標（擺設自己的座標系，0 度＝右、90 度＝前下緣）。
func rim_global(degrees: float) -> Vector2:
	var prop := _prop.get_ref() as PropNode if _prop != null else null
	if not is_instance_valid(prop):
		return Vector2.INF
	var radians := deg_to_rad(degrees)
	var hub := Vector2(_spec["hub"][0], _spec["hub"][1])
	return prop.to_global(hub + Vector2(float(_spec["radius"][0]) * cos(radians), float(_spec["radius"][1]) * sin(radians)))


## support：走到人物旁、手扶住、他換姿勢時手跟著下來、放手。對象是正在交談的人物本身，不需要擺設。
func _start_support(player: Player, source: NpcActor) -> bool:
	if not player._visual.rig.has_hand_grip(&"front"):
		return _fail("world action requires a registered grip")
	if not source.bone_global(StringName(_spec["bone"])).is_finite():
		return _fail("world action support needs the person's rig bone")
	_player = weakref(player)
	_start_position = player.global_position
	_station = source.global_position + Vector2(_spec["station"][0], _spec["station"][1])
	# 世界在演出中暫停，人物不會自己轉頭；先讓他面向資料寫的方向（例如櫃檯），手扶的位置才對得上。
	if source._actor != null:
		source._actor.face(int(_spec["person_facing"]))
	if not route_clear(player, _station):
		return _fail("world action approach is blocked or unsupported", &"route")
	player.velocity = Vector2.ZERO
	_sequence = [{"id": "approach"}, {"id": "reach", "time": 0.4}, {"id": "steady", "time": 0.3}, {"id": "lower", "time": 1.1}, {"id": "release", "time": 0.4}]
	_enter_phase()
	_frame_camera(player, source.global_position.x)
	return true


## 手扶的位置：人物那根骨頭的世界位置加上偏移（偏移依人物面向左右翻）。
func support_global() -> Vector2:
	var source := _source.get_ref() as NpcActor if _source != null else null
	if not is_instance_valid(source):
		return Vector2.INF
	var at := source.bone_global(StringName(_spec["bone"]))
	if not at.is_finite():
		return Vector2.INF
	var side := float(source._actor.facing) if source._actor != null else 1.0
	return at + Vector2(float(_spec["contact"][0]) * side, float(_spec["contact"][1]))


func _without_reaction() -> bool:
	return _spec.get("kind") in ["support", "place"]


## place：走到擺設前、伸手到 pick 點、拿起要呈現的東西、繞小圈、放到 drop 點、放手。
func _start_place(player: Player, prop: PropNode) -> bool:
	if not player._visual.rig.has_hand_grip(&"front"):
		return _fail("world action requires a registered grip")
	var texture := RigLibrary.optional_texture(_spec["texture"])
	if texture == null:
		return _fail("world action held texture is unavailable")
	_grip = Vector2(_spec["grip"][0], _spec["grip"][1])
	if not Rect2(Vector2.ZERO, texture.get_size()).has_point(_grip):
		return _fail("world action grip is outside its texture")
	_player = weakref(player)
	_prop = weakref(prop)
	_start_position = player.global_position
	_station = prop.to_global(Vector2(_spec["station"][0], _spec["station"][1]))
	if not route_clear(player, _station):
		return _fail("world action approach is blocked or unsupported", &"route")
	player.velocity = Vector2.ZERO
	_disk_scale = float(_spec["width"]) / texture.get_width()
	_make_carrier(player)
	_disk = Sprite2D.new()
	_disk.texture = texture
	_disk.centered = false
	_disk.hide()
	_carrier.add_child(_disk)
	_sequence = place_sequence(int(_spec.get("scrub_loops", 0)))
	_enter_phase()
	_frame_camera(player, prop.global_position.x + prop.data.size.x * 0.5)
	return true


## place 的階段：走過去、伸手、拿起、（繞圈）、放到定點、放手。
static func place_sequence(loops: int) -> Array[Dictionary]:
	var sequence: Array[Dictionary] = [{"id": "approach"}, {"id": "pick", "time": 0.35}, {"id": "lift", "time": 0.2}]
	if loops > 0:
		sequence.append({"id": "scrub", "time": 0.5 * loops})
	sequence.append_array([{"id": "place", "time": 0.5}, {"id": "release", "time": 0.35}])
	return sequence


func _prop_point(key: String) -> Vector2:
	var prop := _prop.get_ref() as PropNode if _prop != null else null
	return prop.to_global(Vector2(_spec[key][0], _spec[key][1])) if is_instance_valid(prop) else Vector2.INF


## 繞圈的偏移：progress 0→1 走完 scrub_loops 圈，起點與終點都在 pick 點上。
func _scrub_offset(progress: float) -> Vector2:
	var loops := float(_spec.get("scrub_loops", 0))
	var angle := TAU * loops * progress
	return Vector2(float(_spec["scrub"][0]) * sin(angle), -float(_spec["scrub"][1]) * (1.0 - cos(angle)) * 0.5)


## 放手時的手掌世界角度：朝右時就是 hand_angle，朝左時左右鏡像。
func hand_angle() -> float:
	var tilt := deg_to_rad(float(_spec.get("hand_angle", 0.0)))
	return tilt if int(_spec["facing"]) > 0 else PI - tilt

