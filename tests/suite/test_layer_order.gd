class_name LayerOrderSuite
extends TestSuite
## 圖層順序：角色後側的手腳零件（z 最低 -9）不能被背景蓋住。關卡的背牆、地形、裝飾與背景道具、導軌，
## 以及過場舞台的背景各層，都要排在所有角色零件之下；舞台的前景各層排在其上。

const LEVEL_PATHS: Array[String] = ["res://data/levels/level_01.tres", "res://data/levels/level_02.tres", "res://data/levels/ch1_pawnshop.tres"]


func run() -> void:
	_test_character_z_range()
	_test_stage_layers()
	await _test_actor_layers()
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


## 過場裡每個演員的零件圖層範圍互不重疊（走過、並肩時衣服不會一半在前一半在後），而且都夾在舞台背景與前景之間。
func _test_actor_layers() -> void:
	var scene := {"mode": "animated", "steps": [
		{"do": "scene", "id": "test_room", "fade": 0.0},
		{"do": "actor", "id": "a", "kind": "rin", "pos": [100, 290]},
		{"do": "actor", "id": "b", "kind": "old_k", "pos": [120, 290]},
		{"do": "actor", "id": "c", "kind": "nurse", "pos": [140, 290]},
		{"do": "actor", "id": "a", "kind": "rin", "pos": [100, 290]},
		{"do": "wait", "time": 30.0}]}
	check(CutsceneChecker.validate("test_layers", scene, {}).is_empty(), "the actor scene passes the checker: %s" % [CutsceneChecker.validate("test_layers", scene, {})])
	var bad := {"mode": "animated", "steps": [{"do": "scene", "id": "test_room"}, {"do": "actor", "id": "a", "kind": "rin", "pos": [1, 1], "layer": 99}]}
	check(not CutsceneChecker.validate("test_bad_layer", bad, {}).is_empty(), "a layer group outside the registered range is reported")
	var player := CutscenePlayer.new()
	player.speed = 1.0
	runner.add_child(player)
	player.play(&"test_layers", scene)
	await frames(6)
	var ranges: Array[Vector2i] = []
	for id: StringName in [&"a", &"b", &"c"]:
		var actor := player._actors.get(id) as CutsceneActor
		if actor == null or actor.rig == null:
			check(false, "actor %s exists with a skeleton" % id)
			continue
		var low := 1 << 30
		var high := -(1 << 30)
		for sprite in actor.rig.find_children("*", "Sprite2D", true, false):
			var z := _effective_z(sprite as CanvasItem)
			low = mini(low, z)
			high = maxi(high, z)
		ranges.append(Vector2i(low, high))
	check(ranges.size() == 3, "all three actors were built")
	for i in ranges.size():
		check(ranges[i].x > WorldLayers.STAGE_BACK and ranges[i].y < WorldLayers.STAGE_FRONT, "actor %d stays between the stage background and foreground (%s)" % [i, ranges[i]])
		for j in range(i + 1, ranges.size()):
			check(ranges[i].y < ranges[j].x or ranges[j].y < ranges[i].x, "actors %d and %d do not interleave their parts (%s, %s)" % [i, j, ranges[i], ranges[j]])
	check((player._actors[&"a"] as CutsceneActor).layer_slot == 0, "an actor that is placed again keeps its layer group")
	player.queue_free()
	await frames(2)


## 節點實際的 z：沿著祖先把「相對」的 z_index 加起來。
func _effective_z(item: CanvasItem) -> int:
	var total := 0
	var node: Node = item
	while node is CanvasItem:
		total += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return total


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
	# 看板、檢查點、出入口、開關這類實體排在角色零件之下，角色站在它們前面時不會「後腳在後、前腳在前」。
	var offenders := PackedStringArray()
	var signs := 0
	for node in level.get_node("World/Entities").get_children():
		var item := node as CanvasItem
		if item == null or WorldLayers.is_character(node):
			continue
		signs += 1 if node is HintSign else 0
		if item.z_index == 0:
			offenders.append(node.name)
	check(offenders.is_empty(), "%s: no entity sits in the middle of the character layers: %s" % [path.get_file(), ", ".join(offenders)])
	if path.contains("ch1_pawnshop"):
		check(signs > 0, "%s: the level has a hint sign to check" % path.get_file())
	await end_level(level)
