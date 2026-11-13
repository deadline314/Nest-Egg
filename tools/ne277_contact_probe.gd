extends "res://tools/ne277_delivery_probe.gd"
## Actual contacts added to the same 42-move/held-input and original joint/grip matrix.
## Individual moves are selected directly; held cases use the public input path.
class ContactControl extends MeleeModule:
	var control := ""
	var bypass_geometry := false
	func _uses_visible_contact() -> bool:
		return false if control == "early-broad" or bypass_geometry else super._uses_visible_contact()
	func hit_pass() -> void:
		bypass_geometry = control == "late-broad"
		super.hit_pass()
		bypass_geometry = false

const HOLD_DISTANCE := {"blade":30.0,"dagger":16.0,"glaive":46.0,"maul":26.0,"whip":64.0}
var _contact_control := ""
var _only_move := ""
var _foe: Enemy
var _case_name := ""
var _case_held := false
var _desired: Dictionary = {}
var _distance := 0.0
var _side := 1
var _hit_facts: Array = []
var _case_sound_from := 0
var _sounds: Array = []
var _case_start := 0.0
var _record_start := 0
var _first_image := ""
var _audio := AudioEffectRecord.new()
var _audio_index := -1
var _prior_culling := true

func _ready() -> void:
	super._ready()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-control="):
			_contact_control = arg.trim_prefix("--contact-control=")
		elif arg.begins_with("--move="):
			_only_move = arg.trim_prefix("--move=")
	_prior_culling = Enemy.activation_culling_enabled
	Enemy.activation_culling_enabled = false

func _run() -> void:
	var valid := out_dir.is_absolute_path() and (_only == "" or _only in WEAPONS) and _negative in ["", "missing-input"] and not (_capture and DisplayServer.get_name() == "headless") and not _sides.is_empty()
	for side in _sides:
		valid = valid and side in [-1, 1]
	if not valid or _contact_control not in ["", "early-broad", "late-broad"]:
		push_error("[NE277] invalid contact probe arguments")
		get_tree().quit(2)
		return
	_record_start = Time.get_ticks_usec()
	Sfx.sound_played.connect(_heard)
	if _capture:
		_audio.format = AudioStreamWAV.FORMAT_16_BITS
		_audio_index = AudioServer.get_bus_effect_count(0)
		AudioServer.add_bus_effect(0, _audio)
		_audio.set_recording_active(true)
	await super._run()

func _heard(id: StringName) -> void:
	var matching := is_instance_valid(player) and not _desired.is_empty() and player.melee.attack == _desired and (not _case_held or player.melee.hold_mode != "")
	_sounds.append({"case":_case_name,"id":str(id),"matching":matching,"tick":Engine.get_physics_frames(),"seconds":(Time.get_ticks_usec()-_record_start)/1000000.0})

func _move(id: String, weapon: WeaponData, set: MeleeSet, move: String, side: int, held: bool) -> void:
	if _only_move != "" and _only_move != move:
		return
	await clear_enemies()
	if _contact_control != "":
		var previous := player.melee
		player.remove_child(previous)
		previous.queue_free()
		var controlled := ContactControl.new(player)
		controlled.control = _contact_control
		player.melee = controlled
		player.add_child(controlled)
	_desired = set.attack(move, move == set.extension_attack())
	_case_name = "%s/%d/%s%s" % [id,side,move,"-held" if held else ""]
	_case_held = held
	_distance = float(HOLD_DISTANCE[id]) if held else maxf(float(_desired["min_range"])+12.0,float(_desired["range"])*0.65)
	_side = side
	_hit_facts = []
	_first_image = ""
	_case_sound_from = _sounds.size()
	_case_start = (Time.get_ticks_usec()-_record_start)/1000000.0
	_foe = spawn_enemy("res://data/enemies/grunt.tres",12)
	_foe.data = _foe.data.duplicate()
	_foe.data.detect_range = 0
	_foe.data.attack_range = 0
	_foe.data.move_speed = 0
	_foe.health.setup(9999,0)
	_foe.position.x = 192.0 + side * _distance
	_foe.health.damaged.connect(_damaged)
	await super._move(id,weapon,set,move,side,held)
	var row: Dictionary = _rows[-1]
	row["contact_hits"] = _hit_facts.duplicate(true)
	row["contact_target_distance"] = _distance
	row["contact_target_tracks_player"] = held
	row["contact_start_seconds"] = _case_start
	row["contact_end_seconds"] = (Time.get_ticks_usec()-_record_start)/1000000.0
	row["contact_first_image"] = _first_image
	row["contact_sounds"] = _sounds.slice(_case_sound_from)
	row["contact_control"] = _contact_control
	row["contact_definition"] = _desired.duplicate(true)
	row["contact_hold_spec"] = set.hold().duplicate(true)
	_check(not _hit_facts.is_empty(), _case_name+" has a real matching authored-move damage event")
	if held:
		var mode := str(set.hold()["mode"])
		if mode == "sustain":
			_check(_hit_facts.size() >= 2, _case_name+" actually sustains at least two contacts")

func _sustain_sample_frames(def: Dictionary, set: MeleeSet) -> int:
	return int(float(def["active"]) * 60.0) + ceili(maxf(0.8, float(set.hold().get("interval", 0.25)) * 3.0) * 60.0)

func _step() -> void:
	if _case_held and is_instance_valid(_foe) and is_instance_valid(player):
		_foe.global_position.x = player.global_position.x + _side * _distance
	await super._step()

func _measure_grips(row: Dictionary, frame: Dictionary) -> void:
	super._measure_grips(row, frame)
	frame["visible_progress"] = player._visual._input.action_t
	if player.melee.phase != MeleeModule.Phase.ACTIVE or not is_instance_valid(_foe):
		return
	var held := player._visual.melee_held()
	var xf := held.draw_transform()
	var target_xf := _foe.hurtbox._shape_node.global_transform
	var current: Array = []
	var previous: Array = []
	for point: Vector2 in held.contact_sweep().current:
		current.append([point.x, point.y])
	for point: Vector2 in held.contact_sweep().previous:
		previous.append([point.x, point.y])
	var contact := held.contact_point(_foe.hurtbox)
	frame["contact_observation"] = {"current":current,"previous":previous,"nominees":player.melee.targets(player.melee.attack).size(),
		"target_position":[_foe.global_position.x,_foe.global_position.y],"target_center":[_foe.hurtbox.center().x,_foe.hurtbox.center().y],
		"target_size":[_foe.hurtbox._shape.size.x,_foe.hurtbox._shape.size.y],"target_transform":[target_xf.x.x,target_xf.x.y,target_xf.y.x,target_xf.y.y,target_xf.origin.x,target_xf.origin.y],
		"draw_transform":[xf.x.x,xf.x.y,xf.y.x,xf.y.y,xf.origin.x,xf.origin.y],"visible_progress":player._visual._input.action_t,
		"actual_contact":[contact.x,contact.y] if contact.is_finite() else null}

func _damaged(info: DamageInfo) -> void:
	if player.melee.attack != _desired or (_case_held and player.melee.hold_mode == ""):
		return
	var visual := player._visual
	var sweep := visual.melee_held().contact_sweep()
	var current: PackedVector2Array = sweep.get("current")
	var previous: PackedVector2Array = sweep.get("previous")
	var now_points: Array = []
	var old_points: Array = []
	for i in current.size():
		now_points.append([current[i].x,current[i].y])
		old_points.append([previous[i].x,previous[i].y])
	var center := _foe.hurtbox.center()
	var dimensions: Vector2 = _foe.hurtbox._shape.size
	var xf := visual.melee_held().draw_transform()
	var canvas := visual.melee_held().global_transform
	var rope: Array = []
	var soft := visual.melee_held().whip()
	if soft != null and soft.is_laid():
		for i in SoftWhip.NODES:
			rope.append([soft.node(i).x, soft.node(i).y])
	var shape_xf := _foe.hurtbox._shape_node.global_transform
	var fact := {"tick":Engine.get_physics_frames(),"seconds":(Time.get_ticks_usec()-_record_start)/1000000.0,
		"amount":info.amount,"part":str(info.part),"weak":info.weak_hit,"point":[info.contact_point.x,info.contact_point.y],
		"team":info.team,"source":str(info.source_id),"attacker_matches":info.attacker != null and info.attacker.get_ref() == player,
		"phase":player.melee.phase,"time":player.melee.time,"progress":player.melee.pose_progress(),"visual_progress":visual._input.action_t,
		"held_input":Input.is_action_pressed(&"melee"),"hold_mode":player.melee.hold_mode,"charged":player.melee.charged,
		"window":player.melee.hit_window,"resolved_from":player.melee._contact_previous,"resolved_to":player.melee._contact_current,
		"from_fraction":player.melee.contact_from,"to_fraction":player.melee.contact_to,
		"mesh_tick":sweep.get("tick"),"previous_tick":sweep.get("previous_tick"),"current":now_points,"previous":old_points,
		"target_center":[center.x,center.y],"target_size":[dimensions.x,dimensions.y],"target_hp":_foe.health.current,
		"target_area_in_space":PhysicsServer2D.area_get_space(_foe.hurtbox.get_rid()).is_valid(),
		"target_transform":[shape_xf.x.x,shape_xf.x.y,shape_xf.y.x,shape_xf.y.y,shape_xf.origin.x,shape_xf.origin.y],
		"draw_transform":[xf.x.x,xf.x.y,xf.y.x,xf.y.y,xf.origin.x,xf.origin.y],
		"canvas_transform":[canvas.x.x,canvas.x.y,canvas.y.x,canvas.y.y,canvas.origin.x,canvas.origin.y],"rope_nodes":rope,
		"contact_span":[player.melee.set_in_use.contact_span().x,player.melee.set_in_use.contact_span().y]}
	_hit_facts.append(fact)
	_check(info.contact_point.is_finite() and player.melee.phase == MeleeModule.Phase.ACTIVE,_case_name+" contact is finite and belongs to ACTIVE")
	_check(info.attacker != null and info.attacker.get_ref() == player and info.team == Combat.Team.PLAYER and info.source_id == &"melee",_case_name+" damage belongs to the real player's melee source")
	_check(is_equal_approx(visual._input.action_t,player.melee.pose_progress()) and int(sweep.get("tick"))==Engine.get_physics_frames(),_case_name+" damage sees this frame's published visible weapon pose")

func _capture_frame(name: String, index: int, frame: Dictionary) -> void:
	super._capture_frame(name,index,frame)
	if _first_image == "" and not _hit_facts.is_empty():
		var path := "contacts/"+name.replace("/","-")+"-first.png"
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("contacts"))
		_check(preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(out_dir.path_join(path))==OK,name+" saves first matching contact at original viewport resolution")
		_first_image = path

func finish() -> void:
	_check(not _rows.is_empty(), "contact probe requires nonempty measured move coverage")
	if _capture:
		_audio.set_recording_active(false)
		var wav := _audio.get_recording()
		_check(wav != null and wav.data.size()>1024,"native contact matrix records actual master PCM")
		if wav != null:
			_check(wav.save_to_wav(out_dir.path_join("contact-master.wav"))==OK,"writes original contact master WAV")
		AudioServer.remove_bus_effect(0,_audio_index)
	Sfx.sound_played.disconnect(_heard)
	Enemy.activation_culling_enabled = _prior_culling
	var file := FileAccess.open(out_dir.path_join("contact-result.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"rows":_rows,"checks":_checks,"failures":_failures,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"capture":_capture,"output_device":AudioServer.output_device,"mix_rate":AudioServer.get_mix_rate(),"scope":"formal stationary grunt; held targets follow original fixed-distance regression; direct isolated moves and public held input; no human listening/controller/performance claim"},"\t"))
		file.close()
	else:
		_check(false,"writes contact result")
	await super.finish()
