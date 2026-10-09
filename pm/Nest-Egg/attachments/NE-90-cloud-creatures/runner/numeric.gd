extends Node
## Owned diagnostic: samples every supported state, both faces and scales.
## Finite geometry is NOT a rendered seam/anatomy verdict.
const OUT := "res://pm/Nest-Egg/attachments/NE-90-cloud-creatures/numeric.json"
var failures: Array[String] = []
var samples := 0
var rows: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_msec()
	for file in DirAccess.get_files_at("res://art/creatures"):
		if not file.ends_with(".json") or file == "test_creature.json":
			continue
		var id := file.trim_suffix(".json")
		var data := RigLibrary.load_json("res://art/creatures/" + file)
		for state: String in data.get("states", {}).keys():
			for face: int in [-1, 1]:
				for zoom: float in [1.0, 3.4]:
					var creature: Node2D
					if data.has("parts"):
						creature = PartCreature.new()
					elif data.has("tentacles"):
						creature = ChainCreature.new()
					else:
						creature = WormCreature.new()
					var wrapper := Node2D.new()
					wrapper.scale = Vector2(zoom, zoom)
					add_child(wrapper)
					wrapper.add_child(creature)
					if not creature.setup(id):
						failures.append("setup: " + id)
						wrapper.free()
						continue
					var count := 0
					var speed := float(data.get("gait", {}).get("full_speed", 40.0))
					for frame in 120:
						var points: Array[Vector2] = []
						if creature is PartCreature:
							creature.animate(1.0 / 60.0, StringName(state), Vector2(speed * face, 0), face)
							for part in creature.part_names():
								points.append(creature.joint_of(part).global_position)
								var joint: Node2D = creature.joint_of(part)
								if not is_finite(joint.global_rotation) or not is_finite(joint.scale.x) or not is_finite(joint.scale.y):
									failures.append("transform: %s/%s/%s/%d" % [id, part, state, frame])
						elif creature is ChainCreature:
							creature.facing = face
							creature.position.x += speed * face / 60.0
							creature.animate(1.0 / 60.0, StringName(state), Vector2(speed * face, 0))
							for chain in creature.tentacle_count():
								points.append(creature.tip_of(chain))
						else:
							creature.scale.x = float(face)
							creature.position.x += speed * face / 60.0
							creature.animate(1.0 / 60.0, StringName(state))
							for joint in creature.joint_count():
								points.append(creature.joint_position(joint))
						if points.is_empty():
							failures.append("empty geometry: " + id)
						for point in points:
							if not is_finite(point.x) or not is_finite(point.y):
								failures.append("nonfinite: %s/%s/%d/%d/%s" % [id,state,frame,face,zoom])
						count = points.size()
						if creature is PartCreature and count != data["parts"].size():
							failures.append("missing actual part: " + id)
						samples += 1
					rows.append({"id":id,"state":state,"face":face,"zoom":zoom,"frames":120,"actual_points":count,"seams":"UNVERIFIED","anatomy":"UNVERIFIED"})
					wrapper.free()
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"samples":samples,"failures":failures,"rows":rows,"elapsed_ms":Time.get_ticks_msec()-started},"\t"))
	print("CREATURE_NUMERIC samples=%d failures=%d elapsed_ms=%d" % [samples,failures.size(),Time.get_ticks_msec()-started])
	get_tree().quit(0 if failures.is_empty() and samples > 0 else 1)
