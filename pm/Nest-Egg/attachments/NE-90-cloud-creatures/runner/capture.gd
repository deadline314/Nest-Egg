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
	add_child(label)
	for file in DirAccess.get_files_at("res://art/creatures"):
		if not file.ends_with(".json") or file == "test_creature.json":
			continue
		var id := file.trim_suffix(".json")
		var data := RigLibrary.load_json("res://art/creatures/" + file)
		for face: int in [-1,1]:
			var wrapper := Node2D.new()
			wrapper.position = Vector2(320,210)
			wrapper.scale = Vector2(3.4,3.4)
			add_child(wrapper)
			var creature: Node2D
			if data.has("parts"):
				creature = PartCreature.new()
			elif data.has("tentacles"):
				creature = ChainCreature.new()
			else:
				creature = WormCreature.new()
			wrapper.add_child(creature)
			if not creature.setup(id):
				push_error("capture setup failed " + id)
				get_tree().quit(1)
				return
			var state: String = data.get("states",{}).keys()[0]
			for frame in 120:
				if creature is PartCreature:
					creature.animate(1.0/60.0,StringName(state),Vector2.ZERO,face)
				elif creature is ChainCreature:
					creature.facing = face
					creature.animate(1.0/60.0,StringName(state),Vector2.ZERO)
				else:
					creature.scale.x = float(face)
					creature.animate(1.0/60.0,StringName(state))
			label.text = "%s / %s / frame119 / face%d / zoom3.4 / snapshot only" % [id,state,face]
			for wait_frame in 4:
				await get_tree().process_frame
			var im := get_viewport().get_texture().get_image()
			var path := "res://pm/Nest-Egg/images/NE-90-cloud-creatures/%s-%s-frame119-face%d-zoom3.4.png" % [id,state,face]
			var err := im.save_png(path)
			print("NATIVE_PNG ",path," size=",im.get_size()," code=",err," transform=",creature.global_transform)
			wrapper.free()
	get_tree().quit()
