extends Node
const Audit = preload("res://tests/helpers/gait_handoff_audit.gd")
const Broken = preload("res://tests/helpers/broken_gait_handoff.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if not out.is_absolute_path():
		push_error("[NE277] gait output directory must be absolute")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var failures: Array[String] = []
	var rows: Array[Dictionary] = []
	for facing in [-1, 1]:
		for body in [Vector3.ZERO, Vector3(14, 5, 0.35)]:
			for broken in [false, true]:
				var rig := CharacterRig.new()
				add_child(rig)
				if not rig.setup("rin"):
					failures.append("rig setup failed")
					continue
				if broken:
					rig.animator = Broken.new(rig)
				var result := Audit.measure(rig, facing, body)
				var name := "%s/%d/negative-%s" % ["idle" if body == Vector3.ZERO else "lunge", facing, str(broken)]
				result.merge({"name": name, "facing": facing, "body": str(body), "negative_control": broken})
				if bool(result["accepted"]) == broken:
					failures.append("incorrect acceptance: %s" % str([facing, body, broken]))
				rows.append(result)
				rig.queue_free()
				await get_tree().process_frame
	var result := {"scope": "kinematic fixed-step idle/run/idle impulses, both directions; deliberate lost-idle-target negative controls", "rows": rows, "failures": failures}
	var file := FileAccess.open(out.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("NE277_GAIT_HANDOFF ", JSON.stringify({"rows": rows.size(), "failures": failures}))
	await AudioRelease.settle(get_tree())
	get_tree().quit(0 if failures.is_empty() and rows.size() == 8 else 1)
