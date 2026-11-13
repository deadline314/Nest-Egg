extends Node2D
## CPU geometry replay for already-failed native sensor frames. No verdict/render edits.
const AUDIT := preload("res://tools/rig_joint_audit.gd")
var _out := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if not _out.is_absolute_path():
		get_tree().quit(2)
		return
	var audit := AUDIT.new()
	var results: Array[Dictionary] = []
	for run in ["npc-performance-final-lf-v1", "npc-transitions-final-lf-v1"]:
		var path: String = "res://pm/Nest-Egg/attachments/NE-267-guest-rigs/" + run + "/report.json"
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var groups := {}
		for failure in report.failures:
			if failure.facing != 1:
				continue
			var key := "%s/%s/%s" % [failure.pose, failure.zoom, failure.joint]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(failure)
		for key in groups:
			var failures: Array = groups[key]
			var first: Dictionary = failures[0]
			var clip := Control.new()
			add_child(clip)
			var holder := Node2D.new()
			holder.scale = Vector2.ONE * float(first.zoom)
			clip.add_child(holder)
			var rig := CharacterRig.new()
			holder.add_child(rig)
			assert(rig.setup("guest_zheng", "npc"))
			(rig.animator as NpcAnimator).seated_sag = .298
			rig.set_weapon("")
			var pair: Array = AUDIT.JOINTS[first.joint]
			for part in rig._parts:
				rig._set_base_part_visible(part, pair.slice(1).has(StringName(part.name)))
			var input := RigInput.new()
			input.facing = 1
			input.aim_dir = Vector2.RIGHT
			input.on_floor = true
			input.two_handed = false
			var transition: bool = run.contains("transitions")
			input.npc_pose = (&"stand" if first.pose == "sit_down" else &"sit") if transition else (&"sit" if str(first.pose).begins_with("sit") else &"stand")
			for tick in 180:
				rig.animate(1.0 / 60.0, input)
			if transition:
				input.npc_pose = &"sit" if first.pose == "sit_down" else &"stand"
			else:
				input.talking = first.pose == "sit_talk"
				input.listening = first.pose == "sit_listen"
				input.waving = first.pose == "wave"
			var last := int(failures.back().frame)
			for frame in last + 1:
				rig.animate(1.0 / 60.0, input)
				holder.position += Vector2(64, 64) - rig.bone(pair[0]).global_position
				for failure in failures:
					if int(failure.frame) != frame:
						continue
					var anchors := {}
					for name: String in AUDIT.JOINTS:
						if name.begins_with("coat_"):
							continue
						var point := rig.bone(AUDIT.JOINTS[name][0]).global_position
						anchors[name] = [point.x, point.y]
					results.append({"run": run, "failure": failure, "geometry": audit._material_geometry(rig, clip), "cpu_joint_anchors": anchors})
			clip.free()
	audit.free()
	var file := FileAccess.open(_out, FileAccess.WRITE)
	file.store_string(JSON.stringify({"classification": "CPU replay geometry for frozen native failed frames; independently validate against native before adopting a material repair", "results": results}, "\t"))
	print("NE267_CPU_GEOMETRY ", results.size())
	get_tree().quit()
