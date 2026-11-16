extends Node
## Read-only v7 replay for comparing isolated and whole-body joint views; no runtime files change.
const SNAPSHOT := "res://art_src/characters/harbor_lamplighter_demo/evidence/shoulder-v7-source-snapshot"
const BASE := "res://art/characters/harbor_lamplighter_demo/"

func _ready() -> void:
	var hashes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT.path_join("hashes.json")))
	for relative in hashes:
		assert(FileAccess.get_sha256(SNAPSHOT.path_join(relative)) == hashes[relative])
	var skin: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT.path_join("character.json")))
	RigLibrary._json_cache[BASE.path_join("character.json")] = skin
	RigLibrary._json_cache[str(skin["rig"])] = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT.path_join("rig.json")))
	RigLibrary._json_cache["res://art/motion/harbor_lamplighter_demo.json"] = JSON.parse_string(FileAccess.get_file_as_string(SNAPSHOT.path_join("motion.json")))
	for texture_name in skin["textures"]:
		var definition: Dictionary = skin["textures"][texture_name]
		var file := str(definition["file"]).get_file()
		var source := Image.load_from_file(ProjectSettings.globalize_path(SNAPSHOT.path_join("runtime-parts").path_join(file)))
		assert(source != null)
		var path := BASE.path_join(str(definition["file"]))
		var diffuse := ImageTexture.create_from_image(source)
		var normal_file := file.get_basename() + "_n.png"
		var normal_image := Image.load_from_file(ProjectSettings.globalize_path(SNAPSHOT.path_join("runtime-parts").path_join(normal_file)))
		assert(normal_image != null and normal_image.get_size() == source.get_size())
		var normal := ImageTexture.create_from_image(normal_image)
		var canvas := CanvasTexture.new()
		canvas.diffuse_texture = diffuse
		canvas.normal_texture = normal
		RigLibrary._texture_cache[path] = diffuse
		LitTextures._cache[path] = canvas
		LitTextures._canvas_textures[path] = canvas
		LitTextures._normals[path] = normal
	print("SNAPSHOT_REPLAY v7: all source hashes verified; runtime file paths untouched; raw RGBA textures loaded in memory")
	add_child(preload("res://tools/rig_joint_audit.gd").new())
