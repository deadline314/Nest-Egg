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
	await _test_level_actor_groups()


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
	# 非角色的實體、世界的每一層都不落在角色圖層組的範圍裡（要嘛全在所有角色之下，要嘛全在之上）。
	var inside := PackedStringArray()
	for node in level.get_node("World/Entities").get_children() + world.get_children():
		if node is CanvasItem and not WorldLayers.is_character(node) and node != level.get_node("World/Entities"):
			var span := WorldLayers.drawn_z_range(node as CanvasItem)
			if span.x <= span.y and span.y >= WorldLayers.CHARACTERS_BOTTOM and span.x <= WorldLayers.CHARACTERS_TOP:
				inside.append("%s[%d..%d]" % [node.name, span.x, span.y])
	check(inside.is_empty(), "%s: nothing but characters is drawn inside the character layer groups: %s" % [path.get_file(), ", ".join(inside)])
	if path.contains("ch1_pawnshop"):
		check(signs > 0, "%s: the level has a hint sign to check" % path.get_file())
	await end_level(level)


## NE-402：關卡裡每個角色佔一整組圖層，兩個角色重疊時一定是整個在前或整個在後；玩家永遠最前；
## 其他角色的組在活著時不變（別人離開也不跳動）；組數用完不出錯、共用最後一組；
## 子彈、特效、雨、前景擺設、前景層、提示與對話氣泡在所有角色之上，接觸陰影與地面霧在所有角色之下，光源照得到最上面一層。
func _test_level_actor_groups() -> void:
	check(WorldLayers.CHARACTERS_BOTTOM > WorldLayers.ENTITY_BEHIND and WorldLayers.CHARACTERS_BOTTOM > WorldLayers.SCENERY_MAX, "the lowest character group is above the entities and scenery that sit behind characters")
	var above := [WorldLayers.KEY_LIGHT_FRONT, WorldLayers.ABOVE_CHARACTERS, WorldLayers.NEAR_FOREGROUND, WorldLayers.PROJECTILES, WorldLayers.STEAM_SCREEN, WorldLayers.FX, WorldLayers.RAIN, WorldLayers.FRONT_PROPS, WorldLayers.FOREGROUND, WorldLayers.WORLD_PROMPTS, WorldLayers.MAP_BUBBLES]
	for i in above.size():
		check(int(above[i]) > WorldLayers.CHARACTERS_TOP and int(above[i]) <= WorldLayers.WORLD_TOP, "overlay layer %d (%d) is above every character part" % [i, above[i]])
		if i > 0:
			check(int(above[i]) > int(above[i - 1]), "overlay layers keep their order (%d > %d)" % [above[i], above[i - 1]])
	check(WorldLayers.WORLD_TOP < RenderingServer.CANVAS_ITEM_Z_MAX, "the top world layer fits in the canvas z range")
	check(WorldLayers.FOG > WorldLayers.TERRAIN and WorldLayers.FOG < WorldLayers.CHARACTERS_BOTTOM, "ground fog sits over terrain but under every character, telegraph and effect (BG-78)")
	var light := LightKit.create_point_light(Color.WHITE, 40.0, 1.0)
	check(light.range_z_min <= WorldLayers.CHARACTERS_BOTTOM and light.range_z_max >= WorldLayers.WORLD_TOP, "scene lights reach every character group and overlay (%d..%d)" % [light.range_z_min, light.range_z_max])
	light.free()

	var level := await start_level(load("res://data/levels/level_01.tres") as LevelData)
	var entities := level.get_node("World/Entities")
	var player := level.player
	var grunt := load("res://data/enemies/grunt.tres") as EnemyData
	# 三個敵人與一個場景人物疊在玩家身上。
	var crowd: Array[Node2D] = []
	for i in 3:
		var enemy := level._create_enemy(grunt)
		enemy.position = player.position + Vector2(4 * i, 0)
		entities.add_child(enemy)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		crowd.append(enemy)
	var npc := NpcActor.new()
	npc.configure(load("res://data/npcs/ah_po.tres") as NpcData, Vector2i.ZERO)
	npc.position = player.position + Vector2(-4, 0)
	entities.add_child(npc)
	crowd.append(npc)
	await frames(4)
	var characters: Array[CanvasItem] = []
	for node in entities.get_children():
		if WorldLayers.is_character(node):
			characters.append(node as CanvasItem)
	check(characters.size() >= 5, "the level has the player and at least four other characters (%d)" % characters.size())
	var ranges: Array[Vector2i] = []
	for node in characters:
		ranges.append(WorldLayers.drawn_z_range(node))
	var player_range := WorldLayers.drawn_z_range(player)
	var interleaved := PackedStringArray()
	for i in characters.size():
		check(ranges[i].x >= WorldLayers.CHARACTERS_BOTTOM and ranges[i].y <= WorldLayers.CHARACTERS_TOP, "%s stays inside the character layers (%s)" % [characters[i].name, ranges[i]])
		if characters[i] != player:
			check(ranges[i].y < player_range.x, "the player is drawn in front of %s (%s < %s)" % [characters[i].name, ranges[i], player_range])
		for j in range(i + 1, characters.size()):
			if not (ranges[i].y < ranges[j].x or ranges[j].y < ranges[i].x):
				interleaved.append("%s%s/%s%s" % [characters[i].name, ranges[i], characters[j].name, ranges[j]])
	check(interleaved.is_empty(), "no two characters interleave their parts: %s" % ", ".join(interleaved))
	# 圖層固定：別的角色離開不會讓剩下的人換組；新來的拿空出來的最低組。
	var kept := crowd[2].z_index
	var freed := crowd[0].z_index
	crowd[0].queue_free()
	await frames(2)
	check(crowd[2].z_index == kept, "a character keeps its layer group when another one leaves (%d)" % crowd[2].z_index)
	var late := level._create_enemy(grunt)
	entities.add_child(late)
	late.process_mode = Node.PROCESS_MODE_DISABLED
	check(late.z_index == freed, "a new character takes the lowest free group (%d, freed %d)" % [late.z_index, freed])
	# 用完所有組：不出錯，多出來的共用最後一組，玩家仍在最前面。
	var flood: Array[Node] = []
	for i in WorldLayers.LEVEL_ACTOR_SLOTS + 2:
		var enemy := level._create_enemy(grunt)
		enemy.position = Vector2(-400, 0)
		entities.add_child(enemy)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		flood.append(enemy)
	var last := WorldLayers.level_actor_z(WorldLayers.LEVEL_ACTOR_SLOTS - 1)
	check((flood[flood.size() - 1] as CanvasItem).z_index == last, "characters beyond the group limit share the last group (%d)" % (flood[flood.size() - 1] as CanvasItem).z_index)
	check(player.z_index == WorldLayers.PLAYER_Z and WorldLayers.level_actor_z(WorldLayers.LEVEL_ACTOR_SLOTS - 1) + WorldLayers.CHARACTER_MAX_Z < WorldLayers.PLAYER_Z + WorldLayers.CHARACTER_MIN_Z, "the player stays in front of the last shared group")
	for node in flood:
		node.queue_free()
	await frames(2)
	# 接觸陰影在所有角色之下；提示框在所有角色之上；前景擺設在所有角色之上且不透明。
	var shadows := 0
	for node in level.find_children("*", "Node2D", true, false):
		if not node is ContactShadow:
			continue
		shadows += 1
		check((node as CanvasItem).z_index < WorldLayers.CHARACTERS_BOTTOM and not (node as CanvasItem).z_as_relative, "contact shadow %s is below every character" % node.name)
	check(shadows > 0, "the level has contact shadows to check")
	var prompts := level.find_children("*", "Node2D", true, false).filter(func(node: Node) -> bool: return node is WorldPrompt)
	check(not prompts.is_empty(), "the level has world prompts to check")
	for node in prompts:
		check(not (node as CanvasItem).z_as_relative and (node as CanvasItem).z_index == WorldLayers.WORLD_PROMPTS, "prompt %s is drawn above every character" % node.name)
	var front := 0
	for node in level.get_tree().get_nodes_in_group(PropNode.GROUP):
		var prop := node as PropNode
		if prop.data.layer == PropData.Layer.FRONT:
			front += 1
			check(prop.z_index == WorldLayers.FRONT_PROPS and is_equal_approx(prop.modulate.a, 1.0), "front prop %s is above every character and opaque" % prop.data.id)
	check(front > 0, "the level has front props to check")
	await end_level(level)
