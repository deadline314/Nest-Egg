class_name LayerOrderSuite
extends TestSuite
## 圖層順序：角色後側的手腳零件（z 最低 -9）不能被背景蓋住。關卡的背牆、地形、裝飾與背景道具、導軌，
## 以及過場舞台的背景各層，都要排在所有角色零件之下；舞台的前景各層排在其上。

const LEVEL_PATHS: Array[String] = ["res://data/levels/level_01.tres", "res://data/levels/level_02.tres"]


func run() -> void:
	_test_character_z_range()
	_test_stage_layers()
	for path in LEVEL_PATHS:
		await _test_level_scenery(path)


## 真實的角色資料沒有超出登記的 z 範圍（超出的話背景的排法要跟著改）。
func _test_character_z_range() -> void:
	var lowest := 0
	var highest := 0
	var count := 0
	for dir in DirAccess.get_directories_at("res://art/characters"):
		var path := "res://art/characters/%s/character.json" % dir
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for part: Variant in (parsed as Dictionary).get("parts", []):
			if typeof(part) == TYPE_DICTIONARY:
				lowest = mini(lowest, int((part as Dictionary).get("z", 0)))
				highest = maxi(highest, int((part as Dictionary).get("z", 0)))
				count += 1
	check(count > 100, "the character data was read (%d parts)" % count)
	check(lowest >= WorldLayers.CHARACTER_MIN_Z and highest <= WorldLayers.CHARACTER_MAX_Z, "every character part is inside the registered z range (%d to %d)" % [lowest, highest])
	check(WorldLayers.SCENERY_MAX < WorldLayers.CHARACTER_MIN_Z and WorldLayers.STAGE_BACK < WorldLayers.CHARACTER_MIN_Z, "scenery is registered below the lowest character part")
	check(WorldLayers.STAGE_FRONT > WorldLayers.CHARACTER_MAX_Z and WorldLayers.STAGE_FRONT < CutscenePlayer.EFFECT_Z, "the stage foreground is above the characters and below the effect layers")
	check(WorldLayers.BACK_WALL < WorldLayers.RAILS and WorldLayers.RAILS < WorldLayers.DECOR and WorldLayers.DECOR < WorldLayers.PROPS and WorldLayers.PROPS < WorldLayers.TERRAIN, "the scenery keeps its back-to-front order")


func _test_stage_layers() -> void:
	var stage := StageLibrary.build(&"test_room")
	check(stage.back.z_index < WorldLayers.CHARACTER_MIN_Z, "the stage background layers are below every actor part (%d)" % stage.back.z_index)
	check(stage.front.z_index > WorldLayers.CHARACTER_MAX_Z, "the stage foreground layers are above every actor part (%d)" % stage.front.z_index)
	stage.free()


func _test_level_scenery(path: String) -> void:
	var level := await start_level(load(path) as LevelData)
	var world := level.get_node("World")
	var lowest_character := WorldLayers.CHARACTER_MIN_Z
	var bad := PackedStringArray()
	var scenery := 0
	for node in world.get_children():
		var item := node as CanvasItem
		if item == null:
			continue
		var is_scenery := node is BackWall or node is Terrain or node.name == "Terrain"
		if is_scenery:
			scenery += 1
			if item.z_index >= lowest_character:
				bad.append("%s（%d）" % [node.name, item.z_index])
	check(scenery >= 2, "%s: the back wall and the terrain were found" % path.get_file())
	check(bad.is_empty(), "%s: the back wall and terrain are below the lowest character part: %s" % [path.get_file(), ", ".join(bad)])
	var player := level.get_node_or_null("World/Entities/Player")
	var rig_min := 0
	if player != null:
		for sprite in player.find_children("*", "Sprite2D", true, false):
			rig_min = mini(rig_min, (sprite as Sprite2D).z_index)
	check(player == null or rig_min >= WorldLayers.CHARACTER_MIN_Z, "%s: the player's lowest part (%d) is not below the registered minimum" % [path.get_file(), rig_min])
	await end_level(level)
