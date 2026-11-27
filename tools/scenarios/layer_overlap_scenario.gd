class_name LayerOverlapScenario
extends ScenarioBase
## 角色之間與特效、前景的圖層（NE-402）：在第一章街道把角色疊在一起拍近拍。
## 玩家與敵人、玩家與場景人物、敵人與敵人重疊；角色站在霧與雨裡；角色站在前景擺設後面；子彈打在敵人身上。
## 霧、雨、子彈本身很淡或很快，另外在它們的圖層各放一條半透明的「圖層探針」橫條穿過角色胸口：
## 被橫條蓋住的零件畫在那一層之下，蓋在橫條上的零件畫在那一層之上，一眼看得出有沒有被切開。
## 每張近拍都印出畫面裡每個角色零件實際的 z 範圍。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=layer_overlap

const LEVEL := "res://data/levels/level_01.tres"
const GRUNT := "res://data/enemies/grunt.tres"
const HEAVY := "res://data/enemies/heavy_gunner.tres"
const NPC := "res://data/npcs/ah_po.tres"
## 平地的欄（第一段開場附近）。
const OPEN_COL := 20
## 原本標成前景的擺設在第一章街道地圖的位置：[欄, 現在或過去的擺設 id, 檔名]。
const FRONT_SPOTS := [
	[75, ["utility_pole"], "pole"], [156, ["utility_pole"], "pole"],
	[27, ["tree_pine_front", "tree_pine_1"], "pine"], [157, ["tree_fir_front", "tree_fir_1"], "fir"],
	[266, ["cables_hang"], "cables"], [296, ["cables_hang"], "cables"]]
## 近拍範圍（世界像素，以角色腳底往上 30 為中心）與輸出高度。
const ZOOM_SIZE := Vector2(110, 84)
const ZOOM_HEIGHT := 504


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	await clear_enemies()
	await wait(TITLE_CARD_TIME)
	var feet := _floor(OPEN_COL)
	# 固定瞄準方向（不跟著視窗裡的滑鼠）：修前修後的姿勢、鏡頭前瞻與槍燈照到的地方才一樣。
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(&"aim_right")

	# 玩家與敵人：面對面疊在同一格。
	_place(player, feet, 1)
	var grunt := await _spawn(GRUNT, feet + Vector2(6, 0), -1)
	await _shoot("NE-402-overlap-player-enemy", feet)
	# 敵人與敵人。
	_place(player, feet + Vector2(-120, 0), 1)
	var heavy := await _spawn(HEAVY, feet + Vector2(-8, 0), 1)
	await _shoot("NE-402-overlap-enemy-enemy", feet)
	heavy.queue_free()
	# 玩家與場景人物。
	grunt.queue_free()
	await settle(2)
	var npc := NpcActor.new()
	npc.configure(load(NPC) as NpcData, Vector2i(OPEN_COL, 0))
	npc.position = feet + Vector2(6, 0)
	level._entities.add_child(npc)
	_place(player, feet, 1)
	await settle(20)
	await _shoot("NE-402-overlap-player-npc", feet)
	npc.queue_free()

	# 霧與雨：自然的畫面，再加上三條圖層探針（霧、雨、子彈的圖層）。
	_place(player, feet, 1)
	var grunt2 := await _spawn(GRUNT, feet + Vector2(26, 0), -1)
	await settle(10)
	await _shoot("NE-402-weather-natural", feet + Vector2(12, 0))
	var probes: Array[Node] = []
	probes.append(_probe(level._fog, feet + Vector2(-34, -40), Color(0.2, 1.0, 0.4, 0.75)))
	var rain := _find_rain()
	if rain != null:
		probes.append(_probe(rain, feet + Vector2(-34, -30), Color(0.3, 0.6, 1.0, 0.75)))
	probes.append(_probe(level._world.get_node("Projectiles"), feet + Vector2(-34, -20), Color(1.0, 0.3, 0.2, 0.75)))
	probes.append(_probe(level._world.get_node("Fx"), feet + Vector2(-34, -10), Color(1.0, 0.9, 0.2, 0.75)))
	await settle(2)
	await _shoot("NE-402-weather-probes", feet + Vector2(12, 0))
	for probe in probes:
		probe.queue_free()

	# 子彈打在敵人身上：按住射擊，拍命中後的幾格。
	Input.action_press(&"shoot")
	for i in 3:
		await settle(2)
		await _shoot("NE-402-bullet-hit-%d" % i, feet + Vector2(16, 0))
	Input.action_release(&"shoot")
	grunt2.queue_free()

	# 原本標成前景的四種擺設，在地圖上的每個位置都把主角放到它正下方拍一張（範圍包含整件擺設）。
	# 用地圖位置找，不用圖層：改回背景的擺設修前修後才拍得到同一格。
	var index := 0
	for spot: Array in FRONT_SPOTS:
		var prop := _prop_near(spot[1], spot[0])
		if prop == null:
			failures += 1
			push_error("[LayerOverlapScenario] 第 %d 欄附近找不到 %s" % [spot[0], spot[1]])
			continue
		var center_x := prop.global_position.x + prop.data.size.x * 0.5
		var col := clampi(int(center_x / level._layout.tile_size), 0, level._layout.surface_heights.size() - 1)
		var stand := Vector2(center_x, _floor(col).y)
		_place(player, stand, 1)
		await settle(30)
		# 主角站立時頭頂約在腳底往上 58：前景擺設的底邊要在頭頂之上，或整件在走道之外。
		print("FRONT %s layer=%d x=%.0f top=%.0f bottom=%.0f feet=%.0f head=%.0f" % [prop.data.id, prop.data.layer, prop.global_position.x, prop.global_position.y, prop.global_position.y + prop.data.size.y, stand.y, stand.y - 58.0])
		var top := minf(prop.global_position.y, stand.y - 60.0)
		var size := Vector2(maxf(110.0, prop.data.size.x + 40.0), stand.y - top + 16.0)
		await _shoot("NE-402-front-%d-%s" % [spot[0], spot[2]], stand, Vector2(center_x, (top + stand.y + 16.0) * 0.5), size)
		index += 1
	print("FRONT_PROPS %d" % index)
	# 示範：在開闊處臨時放一棵前景樹蓋住主角（正式地圖不這樣擺），看前景擺設是否整件蓋在角色、槍與手臂之上。
	var demo_prop := PropLibrary.find(&"tree_fir_front")
	if demo_prop != null:
		_place(player, feet, 1)
		var demo := PropNode.new()
		demo.setup(demo_prop, Vector2(feet.x - demo_prop.size.x * 0.5 + 10.0, feet.y + 2.0 - demo_prop.size.y))
		level._world.add_child(demo)
		await settle(20)
		await _shoot("NE-402-front-demo", feet, feet + Vector2(0, -60), Vector2(120, 150))
		demo.queue_free()
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
	await finish()


func _floor(col: int) -> Vector2:
	var layout: LevelLayout = level._layout
	var y := layout.surface_heights[col] - 2.0
	if layout.surface_heights[col] < layout.tile_size * 4.0:
		y = layout.floor_below(col, 4) - 2.0
	return Vector2(col * layout.tile_size + 8.0, y)


func _place(who: Node2D, at: Vector2, facing: int) -> void:
	who.global_position = at
	if who is Player:
		(who as Player).velocity = Vector2.ZERO
		(who as Player).facing = facing
	snap_camera()


## 生成一個敵人，等它站好後停住（不移動、不攻擊），拍到的就是它的待機姿勢。
func _spawn(path: String, at: Vector2, facing: int) -> Enemy:
	var enemy := level._create_enemy(load(path) as EnemyData)
	enemy.position = at
	level._entities.add_child(enemy)
	enemy.facing = facing
	await settle(2)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	# 等開場的出現閃光與畫面效果退掉。
	await wait(1.2)
	return enemy


## 圖層探針：一條半透明橫條，掛在指定圖層底下（繼承它的 z）。
func _probe(layer: Node, world_top_left: Vector2, color: Color) -> Node:
	var bar := Polygon2D.new()
	bar.name = "LayerProbe"
	bar.color = color
	bar.polygon = PackedVector2Array([Vector2.ZERO, Vector2(110, 0), Vector2(110, 6), Vector2(0, 6)])
	layer.add_child(bar)
	bar.global_position = world_top_left
	return bar


func _find_rain() -> Node:
	for child in level._world.get_children():
		if child is RainLayer:
			return child
	return null


## 近拍：存整張畫面與放大的角色範圍，並印出每個角色零件的 z 範圍。
func _shoot(file_name: String, feet: Vector2, center := Vector2.INF, size := ZOOM_SIZE) -> void:
	snap_camera()
	await settle(3)
	var viewport := get_viewport()
	var image := preload("res://tools/viewport_capture.gd").image(viewport)
	var to_screen := viewport.get_final_transform() * viewport.get_canvas_transform()
	if center == Vector2.INF:
		center = feet + Vector2(0, -30)
	var a := to_screen * (center - size * 0.5)
	var b := to_screen * (center + size * 0.5)
	var rect := Rect2i(Vector2i(a), Vector2i(b - a)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.save_png(out_dir.path_join(file_name + "_full.png"))
	if rect.size.x > 4 and rect.size.y > 4:
		var crop := image.get_region(rect)
		crop.resize(int(ZOOM_HEIGHT * float(rect.size.x) / rect.size.y), ZOOM_HEIGHT, Image.INTERPOLATE_NEAREST)
		var err := crop.save_png(out_dir.path_join(file_name + ".png"))
		print("saved %s (%s)" % [file_name, error_string(err)])
	else:
		failures += 1
		push_error("[LayerOverlapScenario] %s 的近拍範圍在畫面外：%s" % [file_name, rect])
	var ranges := PackedStringArray()
	for node in level._entities.get_children():
		if WorldLayers.is_character(node):
			var span := _z_range(node as CanvasItem)
			ranges.append("%s[%d..%d]" % [node.name, span.x, span.y])
	print("LAYERS %s %s" % [file_name, " ".join(ranges)])
	await settle(2)


func _prop_near(ids: Array, col: int) -> PropNode:
	for node in get_tree().get_nodes_in_group(PropNode.GROUP):
		var prop := node as PropNode
		if ids.has(String(prop.data.id)) and absf(prop.global_position.x / level._layout.tile_size - col) <= 3.0:
			return prop
	return null


## 和 WorldLayers.drawn_z_range 相同的算法；留一份在這裡，修前的版本（還沒有那個函式）也能跑這個情境。
static func _z_range(root: CanvasItem) -> Vector2i:
	var low := 1 << 30
	var high := -(1 << 30)
	for node: Node in root.find_children("*", "CanvasItem", true, false):
		var z := root.z_index
		var item: Node = node
		var counted := true
		while item != root:
			var canvas := item as CanvasItem
			if canvas == null or not canvas.visible or not canvas.z_as_relative or canvas.top_level:
				counted = false
				break
			z += canvas.z_index
			item = item.get_parent()
		if counted:
			low = mini(low, z)
			high = maxi(high, z)
	return Vector2i(low, high)
