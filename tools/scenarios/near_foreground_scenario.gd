class_name NearForegroundScenario
extends ScenarioBase
## 近前景（BG-68）：第三章向陽區與第一章街道各拍幾格，每格同一個畫面拍「有」與「沒有」近前景（只切換近前景的顯示）；
## 街道另外拍一場戰鬥：主角對著兩個敵人開火，看近前景有沒有擋到角色、敵人、子彈。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=near_foreground

const AREAS := {
	"ch3_glass_edge": [14, 30, 48],
	"ch1_street": [24, 96, 160],
}
const GRUNT := "res://data/enemies/grunt.tres"


func run() -> void:
	Settings.use_storage("user://screenshot-probe-settings.cfg")
	Settings.set_reduce_ui_motion(false)
	Settings.set_light_quality(LightQuality.Tier.HIGH)
	Story.auto_skip = true
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	for area: String in AREAS:
		await _open(area)
		var near := level.find_child("NearForeground", true, false) as CanvasItem
		if near == null:
			failures += 1
			push_error("[NearForegroundScenario] %s 沒有近前景" % area)
			continue
		print("NEAR_FOREGROUND %s pieces=%d" % [area, near.get_child_count()])
		for col: int in AREAS[area]:
			_place(col)
			await wait(1.2)
			await _pair(near, "BG-68-%s-%d" % [area, col])
		if area == "ch1_street":
			await _fight(near)
		level.queue_free()
		await settle(4)
	await finish()


func _open(area: String) -> void:
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
	AimInput.set_virtual_gamepad(player, true)
	await wait(TITLE_CARD_TIME)


func _place(col: int) -> void:
	var layout: LevelLayout = level._layout
	var y := layout.surface_heights[col] - 2.0
	player.global_position = Vector2(col * layout.tile_size + 8.0, y)
	player.velocity = Vector2.ZERO
	player.facing = 1
	snap_camera()


## 同一格畫面：有近前景、沒有近前景。
func _pair(near: CanvasItem, file_name: String) -> void:
	capture(file_name)
	await settle(2)
	near.visible = false
	await settle(2)
	capture(file_name + "-without")
	near.visible = true
	await settle(2)


## 戰鬥：兩個敵人站在主角前方，主角朝右連射，拍三格。
func _fight(near: CanvasItem) -> void:
	var col := int(AREAS["ch1_street"][1])
	_place(col)
	var layout: LevelLayout = level._layout
	for offset: int in [7, 11]:
		var enemy := level._create_enemy(load(GRUNT) as EnemyData)
		enemy.position = Vector2((col + offset) * layout.tile_size + 8.0, layout.surface_heights[col + offset] - 2.0)
		level._entities.add_child(enemy)
	await wait(1.0)
	Input.action_press(&"aim_right")
	Input.action_press(&"shoot")
	for i in 3:
		await settle(4)
		await _pair(near, "BG-68-fight-%d" % i)
	Input.action_release(&"shoot")
	Input.action_release(&"aim_right")
	AimInput.set_virtual_gamepad(player, false)
