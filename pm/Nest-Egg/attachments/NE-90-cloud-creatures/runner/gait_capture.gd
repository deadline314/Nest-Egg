extends Node2D
var target := Vector2.ZERO
var tip := Vector2.ZERO
func _draw() -> void:
	draw_line(Vector2(-3000,0),Vector2(3000,0),Color(0.8,0.8,0.8),1)
	draw_circle(target,3,Color.RED,false,1)
	draw_circle(tip,3,Color.CYAN,false,1)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	RenderingServer.set_default_clear_color(Color(0.38,0.38,0.38))
	var camera := Camera2D.new()
	add_child(camera)
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://pm/Nest-Egg/attachments/NE-90-cloud-creatures/gait.json"))["rows"]
	print("GAIT_RENDER driver=",RenderingServer.get_current_rendering_driver_name()," renderer=",RenderingServer.get_current_rendering_method()," adapter=",RenderingServer.get_video_adapter_name())
	for mount: String in ["salvage_arm","buoy_worm","buoy_worm_small"]:
		var id := "buoy_worm" if mount == "buoy_worm_small" else mount
		var wrapper := Node2D.new()
		wrapper.scale = Vector2.ONE*3.4
		add_child(wrapper)
		var creature := ChainCreature.new()
		wrapper.add_child(creature)
		if not creature.setup(id): get_tree().quit(1);return
		creature.body_scale = 0.62 if mount == "buoy_worm_small" else 1.0
		creature.facing = 1
		creature.ground_probe = func(_x: float) -> float: return 0.0
		var data := RigLibrary.load_json(ChainCreature.PATH % id)
		var full := float(data["gait"]["full_speed"])
		for phase: String in ["idle","walk_half_speed","walk_full_speed","turn"]:
			var matching := rows.filter(func(r: Dictionary) -> bool: return r["mount"]==mount and r["phase"]==phase and r["face"]==1 and r["zoom"]==3.4)
			if matching.size()!=1: get_tree().quit(1);return
			var row: Dictionary = matching[0]
			for frame in 120:
				var direction := 1 if phase != "turn" or frame<60 else -1
				var speed := 0.0 if phase=="idle" else full*(0.5 if phase=="walk_half_speed" else 1.0)
				creature.facing = direction
				creature.position.x += speed*direction/60.0
				creature.animate(1.0/60.0,&"idle" if phase=="idle" else &"walk",Vector2(speed*direction,0))
				if frame != int(row["worst_tip"]["frame"]):continue
				var leg := int(row["worst_tip"]["leg"])
				target=creature._chains[leg]["foot"].foot
				tip=creature.tip_of(leg)
				camera.position=creature.global_position+Vector2(0,-40)
				queue_redraw()
				for n in 4:await get_tree().process_frame
				var path := "res://pm/Nest-Egg/images/NE-90-cloud-creatures/%s-gait-%s-frame%d-face1-zoom3.4.png" % [mount,phase,frame]
				var im := get_viewport().get_texture().get_image()
				var err := im.save_png(path)
				print("GAIT_NATIVE ",path," size=",im.get_size()," leg=",leg," actual_face=",direction," tip_error=",tip.distance_to(target)," expected=",row["max_geometry_tip_to_foot_target"]," code=",err)
		wrapper.free()
	get_tree().quit()
