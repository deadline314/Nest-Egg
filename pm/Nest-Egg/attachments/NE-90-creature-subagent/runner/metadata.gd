extends Node
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var mounts: Array[Dictionary] = []
	for dir: String in ["res://data/enemies","res://data/enemies/strike"]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"): continue
			var path := dir.path_join(file)
			var data := load(path) as EnemyData
			if data == null: continue
			var parents: Array[String] = []
			var script := data.behavior
			while script != null:
				parents.append(script.resource_path)
				script = script.get_base_script()
			mounts.append({"path":path,"id":String(data.id),"rig_skin":data.rig_skin,"rig_weapon":data.rig_weapon,"creature_skin":data.creature_skin,"creature_scale":data.creature_scale,"creature_states":data.creature_states,"behavior_chain":parents,"is_boss":data.is_boss,"body_size":[data.body_size.x,data.body_size.y],"move_speed":data.move_speed,"uses_gravity":data.uses_gravity})
	var textures: Array[Dictionary] = []
	for file in DirAccess.get_files_at("res://art/creatures"):
		if not file.ends_with(".json") or file == "test_creature.json": continue
		var data := RigLibrary.load_json("res://art/creatures/"+file)
		if not data.has("parts"): continue
		var creature := PartCreature.new()
		add_child(creature)
		if not creature.setup(file.trim_suffix(".json")): continue
		for part in creature._parts:
			var sprite: Sprite2D = part["sprite"]
			var tex: Texture2D = sprite.texture
			var item := {"id":file.trim_suffix(".json"),"part":part["name"],"actual_joint_parent":part["joint"].get_parent().name,"actual_z":part["joint"].z_index,"sprite_offset":[sprite.offset.x,sprite.offset.y],"sprite_scale":[sprite.scale.x,sprite.scale.y],"loaded_size":[tex.get_width(),tex.get_height()],"texture_class":tex.get_class()}
			if tex is CanvasTexture:
				item["normal_loaded"] = tex.normal_texture != null
				item["normal_size"] = [tex.normal_texture.get_width(),tex.normal_texture.get_height()] if tex.normal_texture != null else []
			textures.append(item)
		creature.free()
	var f := FileAccess.open("res://pm/Nest-Egg/attachments/NE-90-creature-subagent/runtime-metadata.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"mounts":mounts,"textures":textures,"engine":Engine.get_version_info()},"\t"))
	print("RUNTIME_METADATA enemy_resources=%d loaded_parts=%d" % [mounts.size(),textures.size()])
	get_tree().quit(0 if not mounts.is_empty() and not textures.is_empty() else 1)
