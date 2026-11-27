class_name ColorScriptScenario
extends ScenarioBase
## 色彩腳本（BG-74）：每章幾個區域，主角站在固定的欄位各拍一張，修前修後用同一組位置對照，再拼成整章的縮圖帶。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=color_script

## 區域與主角站的欄（-1：區域的出生點；有些區域在固定欄位會落在沒有燈的地方）。
const SHOTS := [
	["ch1_booth_alley", 20], ["ch1_street", 60], ["ch1_warehouse", -1], ["ch1_rooftop", 30],
	["ch2_harbor_street", 30], ["ch2_market", 40], ["ch2_loading", 30], ["ch2_ledger_office", 20],
	["ch3_plaza", 30], ["ch3_clinic", -1], ["ch3_pump", -1], ["ch3_glass_edge", 30],
	["ch4_factory_approach", -1], ["ch4_factory_loading", 30], ["ch4_nursing_ward", -1],
]


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(true)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	for shot: Array in SHOTS:
		var area: String = shot[0]
		GameState.start_new_run(GameState.difficulties[1])
		level = Level.new()
		level.configure(load("res://data/levels/%s.tres" % area) as LevelData)
		add_child(level)
		await settle(30)
		player = level.player
		player.health.setup(999, 0.0)
		level.hud.visible = false
		level._next_story_trigger = level._layout.story_triggers.size()
		await clear_enemies()
		var layout: LevelLayout = level._layout
		if int(shot[1]) >= 0:
			var col := mini(int(shot[1]), layout.width - 2)
			player.global_position = Vector2(col * layout.tile_size + 8.0, layout.surface_heights[col] - 2.0)
		player.velocity = Vector2.ZERO
		player.facing = 1
		snap_camera()
		await wait(TITLE_CARD_TIME)
		get_tree().paused = true
		await settle(4)
		capture(area)
		get_tree().paused = false
		print("COLOR_SCRIPT %s zone=%s ambient=%s" % [area, level._lighting.zone_id_at(player.global_position.x), level._lighting.current.ambient_color])
		level.queue_free()
		await settle(4)
	await finish()
