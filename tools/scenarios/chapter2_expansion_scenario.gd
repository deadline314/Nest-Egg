class_name Chapter2ExpansionScenario
extends ScenarioBase
## 截圖情境（NE-54）：第二章擴充的實際畫面——中庭、光橋（燈亮與燈暗）、回收燈幕追逐（出發與逼近）、看守長（睡著、醒來、擊敗後閘門打開）、病房區。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=chapter2_expansion


func run() -> void:
	var data := load("res://data/levels/level_02.tres") as LevelData
	GameState.start_new_run(GameState.difficulties[1])
	level = Level.new()
	level.configure(data)
	add_child(level)
	await settle(25)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	await wait(TITLE_CARD_TIME)
	await _court()
	await _bridge()
	await _chase()
	await _arena()
	await _ward()
	level.queue_free()
	await settle(4)


func _go(column: float, extra_height := 0.0) -> void:
	var layout: LevelLayout = level._layout
	var col := int(column)
	var y := layout.surface_heights[col] - 2.0 - extra_height
	if layout.surface_heights[col] < layout.tile_size * 4.0:
		y = layout.floor_below(col, 4) - 2.0
	player.global_position = Vector2(column * layout.tile_size + 8.0, y)
	player.velocity = Vector2.ZERO
	snap_camera()


func _court() -> void:
	_go(226.0)
	await wait(1.4)
	capture("NE-54-court")


## 光橋：站在第二層陽台右端，連拍幾張，看三段路隨燈明滅。
func _bridge() -> void:
	_go(240.0)
	player.global_position.y = 13.0 * 16.0 - 2.0
	snap_camera()
	for i in 4:
		await wait(0.9)
		capture("NE-54-bridge-%d" % i)


func _chase() -> void:
	_go(270.0)
	await wait(0.5)
	_go(273.0)
	await wait(1.6)
	capture("NE-54-chase-start")
	var curtain := level.find_children("*", "LightCurtain", true, false)[0] as LightCurtain
	_go(maxf(274.0, (curtain.front_x + 150.0) / 16.0))
	await wait(0.6)
	capture("NE-54-chase-close")
	_go(330.0)
	await wait(0.4)


func _arena() -> void:
	_go(388.0)
	await wait(0.8)
	capture("NE-54-arena-sleeping")
	_go(398.0)
	await wait(2.2)
	capture("NE-54-arena-fight")
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if (node as Enemy).data.id == &"custodian":
			var info := DamageInfo.create(999, Combat.Team.PLAYER, &"scenario")
			info.ignore_invulnerability = true
			info.bypass_guard = true
			(node as Enemy).hurtbox.receive(info)
	await wait(3.2)
	_go(411.0)
	await wait(0.8)
	capture("NE-54-gate-open")


func _ward() -> void:
	_go(446.0)
	await wait(1.2)
	capture("NE-54-ward")
	_go(456.0)
	await wait(1.4)
	capture("NE-54-ward-cannon")
