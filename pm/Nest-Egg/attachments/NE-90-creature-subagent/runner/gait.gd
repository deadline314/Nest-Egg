extends Node
## Actual FootGait and existing multi-leg chain measurements.
## No humanoid IK; tip-to-target is NOT material sole contact.
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var foot := FootGait.new()
	foot.place(Vector2(100,7))
	for frame in 120:
		if foot.advance(1.0/60.0) or foot.foot != Vector2(100,7): failures.append("planted foot moved")
	foot.begin_step(Vector2(120,7),0.3,5.0)
	var landed := 0
	for frame in 120:
		if foot.advance(1.0/60.0): landed += 1
	if landed != 1 or foot.foot != Vector2(120,7) or foot.target() != foot.foot or foot.stepping:
		failures.append("FootGait must land once at target")
	for mount: String in ["salvage_arm","buoy_worm","buoy_worm_small"]:
		var id := "buoy_worm" if mount == "buoy_worm_small" else mount
		var data := RigLibrary.load_json(ChainCreature.PATH % id)
		for face: int in [-1,1]:
			for zoom: float in [1.0,3.4]:
				var wrapper := Node2D.new()
				wrapper.scale = Vector2.ONE * zoom
				add_child(wrapper)
				var creature := ChainCreature.new()
				wrapper.add_child(creature)
				if not creature.setup(id):
					failures.append("chain setup " + id)
					wrapper.free()
					continue
				var mounted := load("res://data/enemies/%s.tres" % mount) as EnemyData
				creature.body_scale = mounted.creature_scale
				creature.facing = face
				creature.ground_probe = func(_x: float) -> float: return 0.0
				var full := float(data["gait"]["full_speed"])
				for phase: String in ["idle","walk_half_speed","walk_full_speed","turn"]:
					var max_slip := 0.0
					var max_ground_error := 0.0
					var max_tip_error := 0.0
					var worst_tip := {}
					var overlapping_groups := 0
					var planted_samples := 0
					var legs := 0
					for frame in 120:
						var previous: Array[Vector2] = []
						var stepping_before: Array[bool] = []
						for chain in creature._chains:
							previous.append(chain["foot"].foot)
							stepping_before.append(chain["foot"].stepping or not chain["foot_planted"])
						var direction := face if phase != "turn" or frame < 60 else -face
						var speed := 0.0 if phase == "idle" else full * (0.5 if phase == "walk_half_speed" else 1.0)
						creature.facing = direction
						creature.global_position.x += speed * direction / 60.0
						creature.animate(1.0/60.0,&"idle" if phase == "idle" else &"walk",Vector2(speed*direction,0))
						var groups := {}
						legs = 0
						for i in creature._chains.size():
							var chain: Dictionary = creature._chains[i]
							if not chain["leg"]: continue
							legs += 1
							var gait: FootGait = chain["foot"]
							if gait.stepping:
								groups[gait.group] = true
							else:
								planted_samples += 1
								max_ground_error = maxf(max_ground_error,absf(gait.foot.y))
								var tip := creature.tip_of(i)
								var error := tip.distance_to(gait.foot)
								if error > max_tip_error:
									max_tip_error = error
									worst_tip = {"frame":frame,"leg":i,"foot_target":[gait.foot.x,gait.foot.y],"geometry_tip":[tip.x,tip.y],"rig_origin":[creature._rig.global_position.x,creature._rig.global_position.y],"segment_length":chain["seg_len"]}
								if not stepping_before[i]: max_slip = maxf(max_slip,gait.foot.distance_to(previous[i]))
						if groups.size() > 1: overlapping_groups += 1
					if legs == 0 or planted_samples == 0: failures.append("empty foot coverage " + id)
					rows.append({"id":id,"mount":mount,"body_scale":creature.body_scale,"face":face,"zoom":zoom,"phase":phase,"frames":120,"actual_legs":legs,"planted_samples":planted_samples,"max_world_slip_both_frames_planted":max_slip,"max_target_ground_error":max_ground_error,"max_geometry_tip_to_foot_target":max_tip_error,"worst_tip":worst_tip,"overlapping_group_frames":overlapping_groups,"material_contact":"UNVERIFIED"})
				wrapper.free()
	var f := FileAccess.open("res://pm/Nest-Egg/attachments/NE-90-creature-subagent/gait.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"footgait_assertions":2,"failures":failures,"rows":rows},"\t"))
	print("FOOT_GAIT assertions=2 cases=%d failures=%d" % [rows.size(),failures.size()])
	get_tree().quit(0 if failures.is_empty() and not rows.is_empty() else 1)
