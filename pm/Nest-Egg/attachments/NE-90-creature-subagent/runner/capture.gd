extends Node2D
## Native review snapshots, NOT a pixel seam pass.
func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	print("AUDIT_RENDER engine=", Engine.get_version_info(), " driver=", RenderingServer.get_current_rendering_driver_name(), " method=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name())
	var bg := ColorRect.new()
	bg.color = Color(0.38,0.38,0.38,1)
	bg.size = Vector2(1280,720)
	add_child(bg)
	var label := Label.new()
	label.position = Vector2(12,12)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	overlay.add_child(label)
	var ids := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="):
			ids = arg.trim_prefix("--ids=").split(",")
	for file in DirAccess.get_files_at("res://art/creatures"):
		if not file.ends_with(".json") or file == "test_creature.json":
			continue
		var id := file.trim_suffix(".json")
		if not ids.is_empty() and not ids.has(id):
			continue
		var data := RigLibrary.load_json("res://art/creatures/" + file)
		for face: int in [-1,1]:
			var wrapper := Node2D.new()
			wrapper.position = Vector2(320,250 if id == "salvage_arm" else 210)
			wrapper.scale = Vector2(3.4,3.4)
			add_child(wrapper)
			var creature: Node2D
			var camera: Camera2D
			if data.has("parts"):
				creature = PartCreature.new()
			elif data.has("tentacles"):
				creature = ChainCreature.new()
			else:
				creature = WormCreature.new()
				wrapper.scale = Vector2.ONE
				camera = Camera2D.new()
				camera.position = Vector2(320-float(face)*25,210)
				camera.zoom = Vector2(3.4,3.4)
				add_child(camera)
			wrapper.add_child(creature)
			if not creature.setup(id):
				push_error("capture setup failed " + id)
				get_tree().quit(1)
				return
			if creature is WormCreature:
				creature.reset_trail(Vector2(float(face),0))
			elif creature is ChainCreature:
				var mounted := load("res://data/enemies/%s.tres" % id) as EnemyData
				if mounted != null:
					creature.body_scale = mounted.creature_scale
			var state: String = data.get("states",{}).keys()[0]
			for frame in 120:
				if creature is PartCreature:
					creature.animate(1.0/60.0,StringName(state),Vector2.ZERO,face)
				elif creature is ChainCreature:
					creature.facing = face
					creature.animate(1.0/60.0,StringName(state),Vector2.ZERO)
				else:
					creature.animate(1.0/60.0,StringName(state))
			label.text = "%s / %s / frame119 / face%d / zoom3.4 / snapshot only" % [id,state,face]
			for wait_frame in 4:
				await get_tree().process_frame
			var im := preload("res://tools/viewport_capture.gd").image(get_viewport())
			var path := "res://pm/Nest-Egg/images/NE-90-creature-subagent/%s-%s-frame119-face%d-zoom3.4.png" % [id,state,face]
			var err := im.save_png(path)
			print("NATIVE_PNG ",path," size=",im.get_size()," code=",err," transform=",creature.global_transform)
			wrapper.free()
			if camera != null:
				camera.free()
	get_tree().quit()
