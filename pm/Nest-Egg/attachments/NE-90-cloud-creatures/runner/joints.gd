extends Node
## Non-human source/hinge bands, derived from actual parts and chain bones.
## Uses the existing 128 cell and 8-world-pixel radius; no human joint registry.
const CELL := 128
const COLUMNS := 16
const IMAGE_DIR := "res://pm/Nest-Egg/images/NE-90-cloud-creatures/joints"
const REPORT_DIR := "res://pm/Nest-Egg/attachments/NE-90-cloud-creatures"
var controls := false
var id_filter := ""
var state_filter := ""
var part_filter := ""
var tag := ""
var frames := 120
var zooms: Array[float] = [1.0,3.4]
var faces: Array[int] = [-1,1]

func _ready() -> void:
	controls = OS.get_cmdline_user_args().has("--negative-control")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): id_filter = arg.trim_prefix("--id=")
		elif arg.begins_with("--state="): state_filter = arg.trim_prefix("--state=")
		elif arg.begins_with("--part="): part_filter = arg.trim_prefix("--part=")
		elif arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
		elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--zoom="): zooms.assign([float(arg.trim_prefix("--zoom="))])
		elif arg.begins_with("--face="): faces.assign([int(arg.trim_prefix("--face="))])
	if frames <= 0 or not faces.all(func(v: int) -> bool: return v in [-1,1]) or not zooms.all(func(v: float) -> bool: return v > 0.0):
		push_error("invalid nonhuman audit frames/face/zoom")
		get_tree().quit(1)
		return
	if (not id_filter.is_empty() or not state_filter.is_empty() or not part_filter.is_empty() or frames != 120 or faces.size() != 2 or zooms.size() != 2) and tag.is_empty():
		push_error("filtered repro requires --tag to preserve full evidence")
		get_tree().quit(1)
		return
	if tag.contains("/") or tag.contains("\\") or tag.contains(".."):
		push_error("invalid repro tag")
		get_tree().quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(IMAGE_DIR)
	var models: Array[Dictionary] = []
	for file in DirAccess.get_files_at("res://art/creatures"):
		if file.ends_with(".json") and file != "test_creature.json":
			if not id_filter.is_empty() and file.trim_suffix(".json") != id_filter: continue
			var data := RigLibrary.load_json("res://art/creatures/" + file)
			if data.has("parts") or data.has("tentacles"):
				models.append({"id":file.trim_suffix(".json"),"data":data})
	var groups: Array[Dictionary] = []
	for zoom: float in zooms:
		for state_index in (1 if controls else 9):
			var entries: Array[Dictionary] = []
			var viewport := SubViewport.new()
			viewport.transparent_bg = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			for model in models:
				var data: Dictionary = model["data"]
				var states: Array = data.get("states",{}).keys()
				if state_index >= states.size(): continue
				var state: String = states[state_index]
				if not state_filter.is_empty() and state != state_filter: continue
				var descriptors: Array[Dictionary] = []
				if data.has("parts"):
					for part: Dictionary in data["parts"]:
						var shown: Array = data["states"][state].get("show",[])
						if not shown.is_empty() and not shown.has(part["name"]): continue
						descriptors.append({"name":part["name"],"parent":part.get("parent",""),"kind":"hinge" if part.has("parent") else "single_source_band"})
				else:
					for chain in data["tentacles"].size():
						var spec: Dictionary = data["tentacles"][chain]
						var n := clampi(int(spec.get("segments",data["tentacle"].get("segments",8))),2,24)
						for bone in n:
							descriptors.append({"name":"chain%d_bone%d" % [chain,bone],"chain":chain,"bone":bone,"kind":"body_chain" if bone == 0 else "continuous_mesh_band"})
				for face: int in faces:
					for descriptor in descriptors:
						if not part_filter.is_empty() and descriptor["name"] != part_filter: continue
						var index := entries.size()
						var clip := Control.new()
						clip.position = Vector2((index % COLUMNS)*CELL,(index / COLUMNS)*CELL)
						clip.size = Vector2(CELL,CELL)
						clip.clip_contents = true
						viewport.add_child(clip)
						var holder := Node2D.new()
						holder.scale = Vector2.ONE*zoom
						clip.add_child(holder)
						var creature: Node2D = PartCreature.new() if data.has("parts") else ChainCreature.new()
						holder.add_child(creature)
						if not creature.setup(model["id"]):
							push_error("audit missing model " + model["id"])
							get_tree().quit(1)
							return
						var material := CanvasItemMaterial.new()
						material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
						if creature is PartCreature:
							for part: Dictionary in creature._parts:
								part["sprite"].visible = part["name"] in [descriptor["name"],descriptor["parent"]]
								part["sprite"].material = material
								for child in part["sprite"].get_children():
									if child is CanvasItem: child.visible = false
						else:
							if creature._body != null:
								creature._body.visible = int(descriptor["bone"]) == 0
								creature._body.material = material
							for chain in creature._chains.size():
								creature._chains[chain]["polygon"].visible = chain == int(descriptor["chain"])
								creature._chains[chain]["polygon"].material = material
						var speed := float(data.get("gait",{}).get("full_speed",40.0)) if state in ["walk","crawl","chase","slide","prowl","circle","patrol","hover","follow","drift","fly","glide","turn"] else 0.0
						entries.append({"creature":creature,"holder":holder,"clip":clip,"descriptor":descriptor,"char":model["id"],"state":state,"facing":face,"speed":speed,"radius":ceili(8.0*zoom),"rect":[int(clip.position.x),int(clip.position.y),CELL,CELL]})
			if entries.is_empty():
				viewport.free()
				continue
			viewport.size = Vector2i(COLUMNS*CELL,ceili(float(entries.size())/COLUMNS)*CELL)
			var samples: Array[Dictionary] = []
			for frame in (1 if controls else frames):
				for entry in entries:
					var creature: Node2D = entry["creature"]
					var descriptor: Dictionary = entry["descriptor"]
					var center: Vector2
					if creature is PartCreature:
						creature.animate(1.0/60.0,StringName(entry["state"]),Vector2(float(entry["speed"])*int(entry["facing"]),0),int(entry["facing"]))
						center = creature.joint_of(descriptor["name"]).global_position
						if controls and not str(descriptor["parent"]).is_empty():
							creature.joint_of(descriptor["name"]).position += Vector2(32,0)
					else:
						creature.facing = int(entry["facing"])
						creature.animate(1.0/60.0,StringName(entry["state"]),Vector2(float(entry["speed"])*int(entry["facing"]),0))
						center = creature.bone_of(int(descriptor["chain"]),int(descriptor["bone"])).global_position
					entry["holder"].position += Vector2(CELL,CELL)*0.5 - (center-entry["clip"].global_position)
				await RenderingServer.frame_post_draw
				var basename := "%s%sindex%d_zoom%.1f_frame%03d.png" % [tag+"_" if not tag.is_empty() else "","negative_" if controls else "",state_index,zoom,frame]
				viewport.get_texture().get_image().save_png(IMAGE_DIR.path_join(basename))
				samples.append({"file":"../../images/NE-90-cloud-creatures/joints/"+basename,"frame":frame,"seconds":float(frame+1)/60.0})
			var cells: Array[Dictionary] = []
			for entry in entries:
				cells.append({"char":entry["char"],"joint":entry["descriptor"]["name"],"kind":entry["descriptor"]["kind"],"actual_state":entry["state"],"facing":entry["facing"],"radius":entry["radius"],"rect":entry["rect"]})
			groups.append({"pose":"actual_state_index%d" % state_index,"zoom":zoom,"cells":cells,"samples":samples})
			print("NONHUMAN_JOINTS index=%d zoom=%.1f cells=%d frames=%d" % [state_index,zoom,entries.size(),samples.size()])
			viewport.free()
	var file := FileAccess.open(REPORT_DIR.path_join(tag+"-frames.json" if not tag.is_empty() else ("negative-frames.json" if controls else "frames.json")),FileAccess.WRITE)
	file.store_string(JSON.stringify(groups,"\t"))
	print("NONHUMAN_JOINTS elapsed_ms=",Time.get_ticks_msec()-started)
	get_tree().quit(0 if not groups.is_empty() else 1)
