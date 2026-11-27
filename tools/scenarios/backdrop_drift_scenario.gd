class_name BackdropDriftScenario
extends ScenarioBase
## 遠景自己會動（BG-65）：主角站在屋頂不動，每隔幾秒拍一張，共三張，並印出每一層遠景在畫面上的橫向位置。
## 設了漂移的層位置要持續改變、沒設的層不動；有一層都沒動就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=backdrop_drift

const LEVEL := "res://data/levels/ch1_rooftop.tres"
const TILE := 60
const INTERVAL := 4.0
const SHOTS := 3


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	var layout: LevelLayout = level._layout
	player.global_position = Vector2(TILE * layout.tile_size + 8.0, layout.floor_below(TILE, 4) - 2.0)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	var layers: Array[Parallax2D] = []
	for node in level.find_children("*", "Parallax2D", true, false):
		if node.get_parent() is LevelBackground:
			layers.append(node as Parallax2D)
	var first := PackedFloat32Array()
	var moved := 0
	for shot in SHOTS:
		var line := "BACKDROP_DRIFT t=%.0fs" % (shot * INTERVAL)
		for i in layers.size():
			var x := layers[i].get_global_transform_with_canvas().origin.x
			if shot == 0:
				first.append(x)
			elif shot == SHOTS - 1 and absf(x - first[i]) > 1.0 and not is_zero_approx(layers[i].autoscroll.x):
				moved += 1
			line += " | layer%d drift=%.1f x=%.1f" % [i, layers[i].autoscroll.x, x]
		print(line)
		capture("BG-65-drift-%d" % shot)
		if shot < SHOTS - 1:
			await wait(INTERVAL)
	print("BACKDROP_DRIFT moving_layers=%d" % moved)
	if moved == 0:
		failures += 1
		push_error("[BackdropDriftScenario] 沒有任何遠景層在漂移")
	await finish()
