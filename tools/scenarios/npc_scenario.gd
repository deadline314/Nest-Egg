class_name NpcScenario
extends RefCounted
## 截圖情境：場景人物。每個人物各拍一張「走近時的提示」與一張「對話中」。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=npc
## screenshot.gd 只負責派發，畫面細節都在這裡。

const LEVELS: Array[String] = ["res://data/levels/level_01.tres", "res://data/levels/level_02.tres"]


static func run(host: Node) -> void:
	for path in LEVELS:
		var data := load(path) as LevelData
		GameState.start_new_run(GameState.difficulties[1])
		var level := Level.new()
		level.configure(data)
		host.add_child(level)
		await host._settle(25)
		level.player.health.setup(999, 0.0)
		for enemy in host.get_tree().get_nodes_in_group(&"enemies"):
			enemy.queue_free()
		for npc: NpcActor in _all_npcs(level):
			await _shoot(host, level, npc, str(data.id))
		level.queue_free()
		await host._settle(4)
	Story.auto_skip = true


static func _all_npcs(level: Level) -> Array[NpcActor]:
	var result: Array[NpcActor] = []
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is NpcActor:
			result.append(node)
		stack.append_array(node.get_children())
	result.sort_custom(func(a: NpcActor, b: NpcActor) -> bool: return a.global_position.x < b.global_position.x)
	return result


static func _shoot(host: Node, level: Level, npc: NpcActor, level_id: String) -> void:
	level.hud.visible = false
	level.player.global_position = npc.global_position + Vector2(-30, -2)
	level.player.velocity = Vector2.ZERO
	host.level_camera_snap()
	await host._settle(45)
	host._capture("npc_%s_%s_near" % [level_id, npc.data.id])
	Story.auto_skip = false
	npc._talk()
	await host._wait(1.2)
	host._capture("npc_%s_%s_talk" % [level_id, npc.data.id])
	for i in 12:
		Story._layer.advance()
		await host._settle(2)
	Story.auto_skip = true
	await host._settle(10)
