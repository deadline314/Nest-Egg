extends "res://tests/probes/clinic_completion.gd"
const ATLAS := "res://art/environment/scene_props/revival_room_contacts/clinic_atlas.png"
const SURFACE_Y := 194.0-270.0*80.0/1097.0
var observing := true
var baseline := {}
var max_length_error := 0.0
var max_contact_error := 0.0
var max_cup_angle := 0.0
var premature_item := false
var cup_starts := 0
var cloth_starts := 0
var cup_was_held := false
var cloth_was_held := false
var overflow := false
var cancelled_during_hold := false
var rows: Array = []
var shots := {}
var last_where := ""
var where_frames := 0

func _ready() -> void:
	super._ready()
	_observe()

func _observe() -> void:
	while observing:
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var movie := _movie()
		if movie == null or Story._current_cinematic != Clinic.TAKE or movie._stage == null:
			continue
		var actor: CutsceneActor = movie._actors.get(&"rin")
		if actor == null or actor.rig == null:
			continue
		var stage: Node2D = movie._stage
		var where: String = movie._current_where
		where_frames = where_frames+1 if where == last_where else 0
		last_where = where
		var row := {"where":where,"frame":Engine.get_process_frames(),"props":{},"lengths":{}}
		for side: String in ["front","back"]:
			var a := stage.to_local(actor.rig.bone(StringName("arm_"+side+"_upper")).global_position)
			var b := stage.to_local(actor.rig.bone(StringName("arm_"+side+"_lower")).global_position)
			var c := stage.to_local(actor.rig.bone(StringName("hand_"+side)).global_position)
			row.lengths[side+"_upper"] = a.distance_to(b)
			row.lengths[side+"_lower"] = b.distance_to(c)
		for id: String in ["clinic_cup","clinic_cloth","clinic_tray"]:
			var sprite: StageLayers._Sprite = stage.prop_node(id)
			if sprite == null:
				continue
			var point := Vector2(162,858) if id == "clinic_cup" else Vector2(704,967) if id == "clinic_cloth" else Vector2(149,663)
			var p := stage.to_local(sprite.to_global(sprite.source_point(point)))
			var held: bool = stage.prop_held(id)
			var hand := &"back" if id == "clinic_cup" else &"front"
			var palm := stage.to_local(actor.hand_contact_global(hand))
			var basis := stage.global_transform.affine_inverse()*sprite.global_transform
			var support_source := Vector2(329,1090) if id == "clinic_cup" else Vector2(710,1055) if id == "clinic_cloth" else Vector2(149,663)
			var support := stage.to_local(sprite.to_global(sprite.source_point(support_source)))
			row.props[id] = {"point":[p.x,p.y],"support":[support.x,support.y],"held":held,"visible":sprite.visible,"angle":basis.x.angle(),"error":p.distance_to(palm)}
			if id == "clinic_tray":
				var right := stage.to_local(sprite.to_global(sprite.source_point(Vector2(1100,663))))
				row.props[id]["right_support"] = [right.x,right.y]
		if baseline.is_empty():
			baseline = row.lengths.duplicate()
		for key: String in baseline:
			max_length_error = maxf(max_length_error,absf(row.lengths[key]-baseline[key]))
		premature_item = premature_item or StoryItems.owns(&"ch1_grey_cloth") or GameState.has_flag(&"has_grey_cloth")
		var cup: Dictionary = row.props.get("clinic_cup",{})
		var cloth: Dictionary = row.props.get("clinic_cloth",{})
		if cup.get("held",false):
			cup_starts += 0 if cup_was_held else 1
			max_contact_error = maxf(max_contact_error,cup.error)
			max_cup_angle = maxf(max_cup_angle,absf(cup.angle))
		if cloth.get("held",false):
			cloth_starts += 0 if cloth_was_held else 1
			max_contact_error = maxf(max_contact_error,cloth.error)
		cup_was_held = cup.get("held",false)
		cloth_was_held = cloth.get("held",false)
		if rows.size() < 2048:
			rows.append(row)
		else:
			overflow = true
		if DisplayServer.get_name() != "headless" and where_frames == 0 and not shots.has(where):
			shots[where] = rows.size()
			DirAccess.make_dir_recursive_absolute(output)
			preload("res://tools/viewport_capture.gd").image(get_viewport()).save_png(output.path_join("action-%02d.png" % shots.size()))

func _capture(label: String) -> void:
	if action == "write" and phase == "take" and label == "pending":
		# Use the original writer's actual unread Take primary, then cancel while
		# its real cup is held. A different process cold-reads those exact bytes.
		var primary := FileAccess.get_file_as_bytes(store.path)
		var deadline := Time.get_ticks_msec()+30000
		while Time.get_ticks_msec() < deadline:
			var movie := _movie()
			if movie != null and movie._stage != null and movie._stage.prop_held("clinic_cup"):
				cancelled_during_hold = true
				break
			_step()
			await _frames(1)
		_check(cancelled_during_hold,"cancel control reaches the original cup while physically held")
		var old_stage: WeakRef = weakref(_movie()._stage) if _movie() != null and _movie()._stage != null else null
		_main.call("_show_main_menu")
		await _frames(8)
		_check(not Story.is_cinematic_active() and Story.outcomes.context_facts.is_empty() and Story._context_request == 0,"mid-hold menu cancellation releases its real clinic request")
		_check(old_stage == null or old_stage.get_ref() == null,"mid-hold cancellation frees the actual stage and held prop bindings")
		_check(FileAccess.get_file_as_bytes(store.path) == primary and not StoryItems.owns(&"ch1_grey_cloth"),"mid-hold cancel preserves exact unread primary and grants no cloth")
	await super._capture(label)

func _finish() -> void:
	observing = false
	var image := Image.load_from_file(ATLAS)
	_check(image != null and image.get_size() == Vector2i(1254,1254),"contact checks read the original immutable atlas pixels")
	if image != null and image.get_size() == Vector2i(1254,1254):
		for point: Vector2i in [Vector2i(162,858),Vector2i(704,967),Vector2i(329,1090),Vector2i(710,1055),Vector2i(149,663),Vector2i(1100,663)]:
			_check(image.get_pixelv(point).a >= 230.0/255.0,"authored grip/support is actual opaque art: "+str(point))
	_check(not rows.is_empty() and not overflow,"actual first-death action sampling is nonempty and bounded")
	_check(max_length_error <= 0.001,"every sampled action preserves all four original arm bone lengths")
	_check(max_contact_error <= 0.25,"both held props follow actual opaque palm contacts in every sampled frame")
	_check(max_cup_angle <= 0.0001,"held tea remains level through actual lift and relocation")
	_check(not premature_item,"no sampled unfinished action grants cloth or its ownership flag")
	_check(cup_starts == 1,"cup is physically acquired exactly once, including real IO retries")
	if not rows.is_empty():
		var initial: Dictionary = rows.front().props
		for id: String in ["clinic_cup","clinic_cloth"]:
			_check(initial.has(id) and absf(float(initial.get(id,{}).get("support",[0,0])[1])-SURFACE_Y) <= 0.25,"original visible support starts on the tray: "+id)
		var tray: Dictionary = initial.get("clinic_tray",{})
		for key: String in ["support","right_support"]:
			var point: Array = tray.get(key,[0,0])
			_check(absf(float(point[1])-194.0) <= 0.25 and float(point[0]) >= 243.0 and float(point[0]) <= 388.0,"original tray foot lies on the existing examination table: "+key)
	if not cancelled_during_hold:
		_check(cloth_starts == 1,"cloth is physically acquired exactly once, including real IO retries")
		var first: Dictionary = rows.front().props.get("clinic_cup",{})
		var last: Dictionary = rows.back().props.get("clinic_cup",{})
		_check(not first.is_empty() and not last.is_empty() and absf(float(last.point[0])-float(first.point[0])-13.0) <= 0.25,"same original cup moves thirteen stage pixels to the other side")
		_check(not last.get("held",true) and absf(float(last.get("point",[0,0])[1])+6.4-SURFACE_Y) <= 0.25,"released cup base rests on the actual tray surface")
		var lifted := false
		var pocket := false
		for row: Dictionary in rows:
			var cup: Dictionary = row.props.get("clinic_cup",{})
			var cloth: Dictionary = row.props.get("clinic_cloth",{})
			lifted = lifted or (cup.get("held",false) and float(cup.point[1]) < SURFACE_Y-8.9)
			pocket = pocket or (cloth.get("held",false) and Vector2(cloth.point[0],cloth.point[1]).distance_to(Vector2(315,168)) <= 0.25)
		_check(lifted,"cup actually lifts off the support before moving sideways")
		_check(pocket and not rows.back().props.get("clinic_cloth",{}).get("visible",true),"cloth reaches the jacket pocket before it is put away")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("actions.json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":rows,"shots":shots,"max_bone_length_error":max_length_error,"max_contact_error":max_contact_error,"max_cup_angle":max_cup_angle},"  "))
	await super._finish()
