extends Node2D
## Real loaded S18 steps, rigged actors and room furniture. This observer creates no Level.
## It advances dialogue synthetically through CutscenePlayer; no Story results or human-play claim.

var _out := ""
var _failures: Array[String] = []
var _scenes: Array[Dictionary] = []
var _paper_images: Dictionary[String, Image] = {}
var _pending_images: Array[Dictionary] = []
const SLIP := "zheng_meal_slip"
const SLIP_POINT := Vector2(72, 42)
const SLIP_REST_X := 360.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_out) != OK:
		push_error("[NE267] --out requires an absolute directory")
		get_tree().quit(2)
		return
	for id in ["ch2_t_s18_ticket", "ch2_t_s18_name", "ch2_t_s18_done"]:
		await _scene(id)
	# Preserve each post-draw float frame; encode after live playback has ended.
	for capture in _pending_images:
		var source: Image = capture.image
		var raw_name: String = capture.name + ".raw"
		var raw := FileAccess.open(_out.path_join(raw_name), FileAccess.WRITE)
		raw.store_buffer(source.get_data())
		raw.close()
		capture.metadata["raw"] = {"file": raw_name, "format": source.get_format(), "hdr": capture.hdr,
			"sha256": FileAccess.get_sha256(_out.path_join(raw_name))}
		var encoded := preload("res://tools/viewport_capture.gd").encode(source, capture.hdr)
		if encoded.save_png(_out.path_join(capture.name)) != OK:
			_failures.append(capture.name + ": PNG write failed")
	var file := FileAccess.open(_out.path_join("scenes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"classification": "loaded formal scenes; synthetic dialogue advance without Story outcomes", "godot": Engine.get_version_info().string, "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "scenes": _scenes, "failures": _failures}, "\t"))
	print("NE267_SCENES failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _scene(id: String) -> void:
	var scene: Dictionary = Story._scenes.get(id, {})
	var problems := CutsceneChecker.validate(id, scene, Story._speakers)
	problems.append_array(CutsceneChecker.staging_problems(id, scene))
	if not problems.is_empty():
		_failures.append("%s formal framing: %s" % [id, problems])
		return
	var flags := GameState.world_flags.duplicate(true)
	var credits := Progression.credits
	var player := CutscenePlayer.new()
	add_child(player)
	player.play(StringName(id), scene)
	var start := Time.get_ticks_msec()
	var next_advance := start + 1800
	var captured := {}
	var samples: Array[Dictionary] = []
	var snapshots: Array[Dictionary] = []
	var next_walk_capture := 0
	var travel_started := false
	var travel_finished := false
	var held_contacts: Array[Dictionary] = []
	while player.is_running() and Time.get_ticks_msec() - start < 20000:
		await get_tree().process_frame
		var actor := player._actors.get(&"zheng") as CutsceneActor
		if actor != null and actor.rig != null and actor.rig.animator is NpcAnimator:
			var animation := actor.rig.animator as NpcAnimator
			samples.append({"msec": Time.get_ticks_msec() - start, "target_pose": str(actor.pose), "actor_x": actor.position.x, "actor_y": actor.position.y, "npc_active": animation.posture_active(), "consumed_pose": str(animation._pose_now), "transition_clock": animation._trans_t, "feet_weight": animation._feet_w, "posture_progress": animation.posture_progress(), "hip": actor.rig.bone(&"hip").global_position})
			if actor.pose == &"walk":
				if id == "ch2_t_s18_done" and not travel_started and not animation.posture_ready(&"stand"):
					_failures.append(id + ": travel began before actual stand and foot-IK handoff completed")
				travel_started = true
				if Time.get_ticks_msec() - start >= next_walk_capture:
					next_walk_capture = Time.get_ticks_msec() - start + 250
					snapshots.append(await _snapshot(id, "walk-" + str(snapshots.size()), actor, player._stage))
			if travel_started and actor.pose == &"idle" and id == "ch2_t_s18_done":
				travel_finished = true
				if animation.posture_active() and not animation.posture_ready(&"stand"):
					_failures.append(id + ": arrival resumed an unfinished posture")
			var key := str(actor.pose)
			if id == "ch2_t_s18_done" and key == "idle" and actor.position.x < 469.9:
				key = "rise"
			var expected := &"sit" if actor.pose == &"sit" else &"stand"
			if animation._use_npc and animation._pose_now == expected and animation._trans_t < 0.0 and not captured.has(key):
				captured[key] = true
				snapshots.append(await _snapshot(id, key, actor, player._stage))
			var slip := player._stage.prop_node(SLIP) as StageLayers._Sprite
			if slip != null and player._stage.prop_held(SLIP):
				var palm := player._stage.to_local(actor.hand_contact_global(&"front"))
				var paper_point := player._stage.to_local(slip.to_global(slip.source_point(SLIP_POINT)))
				var distance := palm.distance_to(paper_point)
				held_contacts.append({"msec": Time.get_ticks_msec() - start, "palm_stage": palm, "paper_stage": paper_point, "distance": distance})
				if slip._state != "default":
					var table_delta := _paper_bottom(slip, player._stage) - 180.0
					held_contacts.back()["geometric_state"] = slip._state
					held_contacts.back()["material_table_delta"] = table_delta
					if absf(table_delta) > 1.0:
						_failures.append("%s/%s paper/table delta %.5f" % [id, slip._state, table_delta])
				if distance > StagePropHold.CONTACT_TOLERANCE:
					_failures.append("%s held slip/palm delta %.5f" % [id, distance])
				if not captured.has("slip-held"):
					captured["slip-held"] = true
					snapshots.append(await _snapshot(id, "slip-held", actor, player._stage))
			elif slip != null and slip.visible and absf(slip.position.x - SLIP_REST_X) < 0.05 and not captured.has("slip-rest"):
				captured["slip-rest"] = true
				snapshots.append(await _snapshot(id, "slip-rest", actor, player._stage))
		if player.choice_active():
			await get_tree().create_timer(0.4, true, false, true).timeout
			break
		if Time.get_ticks_msec() >= next_advance:
			player._dialogue.complete()
			player._advance_requested = true
			next_advance = Time.get_ticks_msec() + 600
	if not captured.has("sit"):
		_failures.append(id + ": no stable real seated guest was captured")
	if id == "ch2_t_s18_done" and (not captured.has("idle") or not travel_finished):
		_failures.append(id + ": no stable real standing guest was captured")
	if id == "ch2_t_s18_ticket" and (held_contacts.is_empty() or not captured.has("slip-rest")):
		_failures.append(id + ": real slip hold and table release were not both observed")
	var transitions := {"sit": 0, "idle": 0}
	for sample in samples:
		if sample.posture_progress > 0.0 and sample.posture_progress < .999:
			transitions[sample.target_pose] = int(transitions.get(sample.target_pose, 0)) + 1
	if id == "ch2_t_s18_ticket" and transitions.sit == 0:
		_failures.append(id + ": no actual stand-to-sit animation samples")
	if id == "ch2_t_s18_done" and transitions.idle == 0:
		_failures.append(id + ": no actual sit-to-stand animation samples")
	_scenes.append({"id": id, "steps_sha256": JSON.stringify(scene.get("steps", [])).sha256_text(), "snapshots": snapshots, "posture_samples": samples, "transition_samples": transitions, "held_contacts": held_contacts, "flags_unchanged": GameState.world_flags == flags, "credits_unchanged": Progression.credits == credits})
	if GameState.world_flags != flags or Progression.credits != credits:
		_failures.append(id + ": direct visual playback changed story results")
	player.skip()
	while player.is_running():
		await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame


func _snapshot(id: String, pose: String, actor: CutsceneActor, stage: StageLibrary.Stage) -> Dictionary:
	await RenderingServer.frame_post_draw
	var feet: Array[Dictionary] = []
	var seat: Dictionary = {}
	var textures: Array[Dictionary] = []
	for item in actor.rig._parts:
		if item.visible:
			var bound: Texture2D
			if item is Sprite2D:
				bound = (item as Sprite2D).texture
			elif item is Polygon2D:
				bound = (item as Polygon2D).texture
			if bound is CanvasTexture:
				var canvas := bound as CanvasTexture
				var diffuse := canvas.diffuse_texture
				var normal := canvas.normal_texture
				if diffuse == null:
					_failures.append("%s/%s actual diffuse texture is missing" % [id, item.name])
					continue
				textures.append({"part": str(item.name), "render_node": item.get_class(), "diffuse": diffuse.resource_path,
					"diffuse_size": diffuse.get_size(), "normal": normal.resource_path if normal != null else "missing",
					"normal_size": normal.get_size() if normal != null else Vector2.ZERO})
				if normal == null or normal.get_size() != diffuse.get_size():
					_failures.append("%s/%s actual diffuse+normal binding differs" % [id, item.name])
			else:
				_failures.append("%s/%s actual render node lost its CanvasTexture normal" % [id, item.name])
		if str(item.name) not in ["foot_front", "foot_back", "pelvis"]:
			continue
		if str(item.name) == "pelvis" and item is RigPartMesh:
			seat = _mesh_material_bottom(item as RigPartMesh, stage)
			continue
		if not item is Sprite2D:
			_failures.append(id + ": visible foot is not the expected rigid Sprite2D")
			continue
		var sprite := item as Sprite2D
		var texture := sprite.texture
		if texture is CanvasTexture:
			texture = (texture as CanvasTexture).diffuse_texture
		var pixels := texture.get_image()
		var origin := sprite.get_rect().position
		# The camera transforms the stage holder. Remove it before comparing to stage floor_y.
		var material_to_stage := stage.global_transform.affine_inverse() * sprite.global_transform
		var bottom := -INF
		var seat_bottom := -INF
		for y in pixels.get_height():
			for x in pixels.get_width():
				if pixels.get_pixel(x, y).a >= 0.5:
					var point := material_to_stage * (origin + Vector2(x + 0.5, y + 0.5))
					bottom = maxf(bottom, point.y)
					if point.x >= 377.75 and point.x <= 442.75:
						seat_bottom = maxf(seat_bottom, point.y)
		if str(item.name) == "pelvis":
			seat = {"pelvis_material_bottom_over_chair": seat_bottom, "seat_top_stage_y": 209.0, "delta": seat_bottom - 209.0,
				"method": "opaque pelvic material pixel centres inside the formal right-chair x band; full silhouette still reviewed"}
			continue
		feet.append({"part": str(item.name), "material_bottom_stage_y": bottom, "floor_stage_y": 265.5, "delta_stage_pixels": bottom - 265.5,
			"imported_texture_size": [pixels.get_width(), pixels.get_height()], "image_format": pixels.get_format()})
		if actor.pose not in [&"walk", &"run"] and (not is_finite(bottom) or absf(bottom - 265.5) > 1.0):
			_failures.append("%s/%s/%s material foot delta %.4f stage pixels" % [id, pose, item.name, bottom - 265.5])
	if actor.pose != &"sit":
		seat = {}
	if feet.size() != 2:
		_failures.append(id + ": both actual foot materials must be measured")
	if actor.pose == &"sit" and (seat.is_empty() or not is_finite(float(seat.get("delta", INF))) or absf(float(seat.get("delta", INF))) > 1.0):
		_failures.append("%s/%s actual deformed pelvis/seat delta %s" % [id, pose, seat.get("delta", "missing")])
	var name := "%s-%s.png" % [id, pose]
	var image := get_viewport().get_texture().get_image()
	var paper := stage.prop_node(SLIP) as StageLayers._Sprite
	var paper_metrics := {}
	if paper != null and paper.visible:
		paper_metrics = {"state": paper._state, "material_bottom_stage_y": _paper_bottom(paper, stage), "table_top_stage_y": 180.0}
		if pose == "slip-rest" and (paper._state != "lay_8" or absf(float(paper_metrics["material_bottom_stage_y"]) - 180.0) > 1.0):
			_failures.append(id + ": released paper was not flat on the actual tabletop")
	var metadata := {"pose": pose, "png": name, "size": [image.get_width(), image.get_height()], "skin": str(actor.rig.skin_id), "facing": actor.facing, "actor_position": actor.position, "scale": actor.scale, "seat_sag": (actor.rig.animator as NpcAnimator).seated_sag, "feet": feet, "seat": seat, "support_scope": "both standing/seated foot materials" if actor.pose not in [&"walk", &"run"] else "walking foot material telemetry; swing foot may be airborne", "paper": paper_metrics,
		"actor_fill": actor.rig._fill, "uses_level_lighting": actor.rig.use_level_lighting, "texture_bindings": textures}
	_pending_images.append({"name": name, "image": image, "hdr": get_viewport().use_hdr_2d, "metadata": metadata})
	return metadata


func _paper_bottom(sprite: StageLayers._Sprite, stage: Node2D) -> float:
	var key := sprite.texture.resource_path
	if not _paper_images.has(key):
		_paper_images[key] = sprite.texture.get_image()
	var pixels := _paper_images[key]
	var origin := sprite.get_rect().position
	var material_to_stage := stage.global_transform.affine_inverse() * sprite.global_transform
	var bottom := -INF
	for y in pixels.get_height():
		for x in pixels.get_width():
			if pixels.get_pixel(x, y).a >= .5:
				bottom = maxf(bottom, (material_to_stage * (origin + Vector2(x + .5, y + .5))).y)
	return bottom


## Map opaque source pixel centres through the actual rendered UV triangles.
## A pelvis is a deforming mesh; its original rectangle or bone centre is not its seat contact.
func _mesh_material_bottom(mesh: RigPartMesh, stage: Node2D) -> Dictionary:
	var texture := mesh.texture
	if texture is CanvasTexture:
		texture = (texture as CanvasTexture).diffuse_texture
	var pixels := texture.get_image()
	var uv := mesh.uv
	var vertices := mesh.deformed_vertices()
	var local_to_stage := stage.global_transform.affine_inverse() * mesh.global_transform
	var bottom := -INF
	for polygon: PackedInt32Array in mesh.polygons:
		assert(polygon.size() == 3)
		var a: int = polygon[0]
		var b: int = polygon[1]
		var c: int = polygon[2]
		var source_basis := Transform2D(uv[b] - uv[a], uv[c] - uv[a], uv[a])
		if absf(source_basis.determinant()) < 0.00001:
			continue
		var to_barycentric := source_basis.affine_inverse()
		var to_material := Transform2D(vertices[b] - vertices[a], vertices[c] - vertices[a], vertices[a])
		var low := uv[a].min(uv[b]).min(uv[c]).floor().max(Vector2.ZERO)
		var high := uv[a].max(uv[b]).max(uv[c]).ceil().min(Vector2(pixels.get_size()))
		for y in range(int(low.y), int(high.y)):
			for x in range(int(low.x), int(high.x)):
				if pixels.get_pixel(x, y).a < .5:
					continue
				var weights := to_barycentric * Vector2(x + .5, y + .5)
				if weights.x < 0.0 or weights.y < 0.0 or weights.x + weights.y > 1.0:
					continue
				var point := local_to_stage * (to_material * weights)
				if point.x >= 377.75 and point.x <= 442.75:
					bottom = maxf(bottom, point.y)
	return {"pelvis_material_bottom_over_chair": bottom, "seat_top_stage_y": 209.0, "delta": bottom - 209.0,
		"method": "opaque source pixel centres mapped through actual deformed UV triangles inside the formal right-chair x band"}
