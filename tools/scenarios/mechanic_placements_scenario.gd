class_name MechanicPlacementsScenario
extends ScenarioBase
## 環境機關擺進各章之後的實景（NE-405 起）：每個點載入那個區域、找到指定格附近的機關，
## 主角站在左邊、敵人停住，拍「觸發前」；玩家打中機關後放開敵人，等一下再拍「觸發後」，並印出附近敵人的血量變化。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=mechanic_placements --chapter=ch2
## 新增一個點只要在 PLACEMENTS 加一行：[檔名標籤, 關卡檔, 機關群組, 機關所在格 x（全區域）, 主角站在左邊幾像素（負值＝站在右邊）, 觸發後等幾秒, 站到機關下的敵人位移（可省略）]。
## 有第七欄時，最近的一名敵人被放到機關位置加那個位移並停住到拍完（示範「敵人在那裡時觸發」），其餘敵人照常行動。

const PLACEMENTS := {
	"ch2": [
		["NE-405-loading-crate", "res://data/levels/ch2_loading.tres", SuspendedLoad.GROUP, 73, 170.0, 1.0, Vector2(4.0, 0.0)],
		["NE-405-gate-cable", "res://data/levels/ch2_market_gate.tres", LiveCable.GROUP, 65, 130.0, 1.2],
	],
	"ch3": [
		["NE-406-mezzanine-radio", "res://data/levels/ch3_mezzanine.tres", DecoyRadio.GROUP, 61, -150.0, 2.6],
		["NE-406-mezzanine-cable", "res://data/levels/ch3_mezzanine.tres", LiveCable.GROUP, 63, -150.0, 1.2, Vector2(-24.0, 0.0)],
	],
	"ch4": [
		["NE-407-relay-cable", "res://data/levels/ch4_factory_relay.tres", LiveCable.GROUP, 32, 140.0, 1.2],
	],
}
## 觸發後算「附近」的敵人範圍（像素）。
const NEAR := 260.0


func run() -> void:
	var chapter := "ch2"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chapter="):
			chapter = arg.get_slice("=", 1)
	var spots: Array = PLACEMENTS.get(chapter, [])
	if spots.is_empty():
		failures += 1
		push_error("[MechanicPlacements] 沒有 %s 的擺放點" % chapter)
	for spot: Array in spots:
		await _shoot_spot(spot)
	await finish()


func _shoot_spot(spot: Array) -> void:
	var tag: String = spot[0]
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(spot[1]) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	var prop: Node2D
	for node in get_tree().get_nodes_in_group(spot[2]):
		if int(node.get(&"cell").x) == int(spot[3]):
			prop = node
	if prop == null:
		failures += 1
		push_error("[MechanicPlacements] %s 在格 x=%d 找不到 %s" % [spot[1], spot[3], spot[2]])
		level.queue_free()
		await settle(4)
		return
	var enemies: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null:
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
			enemies.append(enemy)
	await wait(TITLE_CARD_TIME + 0.3)
	var aim := &"aim_right" if float(spot[4]) >= 0.0 else &"aim_left"
	AimInput.set_virtual_gamepad(player, true)
	Input.action_press(aim, 1.0)
	var staged: Enemy
	if spot.size() > 6:
		var best := INF
		for enemy in enemies:
			var distance := absf(enemy.global_position.x - prop.global_position.x)
			if distance < best:
				best = distance
				staged = enemy
		if staged != null:
			staged.global_position = prop.global_position + (spot[6] as Vector2)
	player.global_position = prop.global_position + Vector2(-float(spot[4]), 0.0)
	player.velocity = Vector2.ZERO
	await settle(2)
	snap_camera()
	await wait(0.6)
	capture(tag + "-0-before")
	var before := {}
	for enemy in enemies:
		if absf(enemy.global_position.x - prop.global_position.x) <= NEAR:
			before[enemy] = enemy.health.current
	(prop.get(&"hurtbox") as Hurtbox).receive(DamageInfo.create(1, Combat.Team.PLAYER, &"mechanic_placements"))
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(staged):
		staged.set_physics_process(false)  # 停在原地，但受傷判定照常（整個停用的話判定區也會被移出物理世界）
	await wait(float(spot[5]))
	capture(tag + "-1-after")
	if is_instance_valid(staged):
		staged.set_physics_process(true)
	var report := PackedStringArray()
	for key: Variant in before:
		if is_instance_valid(key):
			var enemy := key as Enemy
			report.append("%s %d->%d%s" % [enemy.data.id, before[key], enemy.health.current, " lured" if enemy.is_lured() else ""])
		else:
			report.append("%d->dead" % before[key])
	print("MECHANIC %s near=%s" % [tag, report])
	Input.action_release(aim)
	AimInput.set_virtual_gamepad(player, false)
	level.queue_free()
	await settle(4)
