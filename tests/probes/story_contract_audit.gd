extends Node
const Sources := preload("res://game/story_result_sources.gd")
const Completion := preload("res://game/story_result_completion.gd")
func _ready() -> void:
	var checks:=0
	var failures: Array[String]=[]
	var owned: Array[String]=[]
	var declared: Array[String]=[]
	for id: String in Story._scenes:
		var scene: Dictionary=Story._scenes[id]
		if scene.get("completion_policy","") in Completion.COMPLETION_POLICIES:
			declared.append(id)
			checks+=1
			if not Sources.owns_boundary(id):failures.append("declared source has no independent finite owner: "+id)
		if Sources.owns_boundary(id):
			owned.append(id)
			checks+=1
			if Sources.boundary(id,Story._scenes,Story._scene_sources).is_empty():failures.append("original authored finite contract differs: "+id)
	var result := {"checks":checks,"failures":failures,"owned":owned,"declared":declared}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			var output := argument.trim_prefix("--out=")
			DirAccess.make_dir_recursive_absolute(output)
			var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
			if file == null:
				failures.append("cannot preserve the authored ownership audit")
			else:
				file.store_string(JSON.stringify(result, "  "))
				file.close()
	print("OWNED_AUDIT ", JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
