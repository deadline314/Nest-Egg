extends Node
## 開發工具：自動擷取遊戲畫面（檢查美術、光影、UI 排版用）。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑/資料夾 [--scenario=名稱]
## 情境：all（預設）、settings、mouse_aim、block、story、dynamic_hud、weapons、reload
## 需要可渲染的環境（有 GPU 或軟體 Vulkan / OpenGL）。

const LEVEL_PATH := "res://data/levels/level_01.tres"

var _out_dir := "user://screenshots"
var _scenario := "all"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--scenario="):
			_scenario = arg.trim_prefix("--scenario=")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	add_child(LightKit.create_environment())
	# 劇情演出會暫停遊戲並蓋住畫面；只有 story 情境需要拍到演出。
	Story.auto_skip = _scenario != "story"
	if _scenario == "settings":
		await _run_settings()
		get_tree().quit()
		return
	if _scenario == "story":
		await _run_story()
		get_tree().quit()
		return
	if _scenario == "block":
		await _run_block()
		get_tree().quit()
		return
	if _scenario == "reload":
		await _run_reload()
		get_tree().quit()
		return
	if _scenario == "weapons":
		await _run_weapons()
		get_tree().quit()
		return
	if _scenario == "dynamic_hud":
		await _run_dynamic_hud()
		get_tree().quit()
		return
	if _scenario == "mouse_aim":
		await _run_mouse_aim()
		get_tree().quit()
		return
	var menu := MainMenu.new()
	add_child(menu)
	await _settle(30)
	_capture("01_main_menu")
	menu.queue_free()

	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	await _shoot_at(player, Vector2(250, 240), 25)
	_capture("02_rooftop")
	await _shoot_at(player, Vector2(1480, 320), 40)
	_capture("03_neon_market")
	await _shoot_at(player, Vector2(2780, 320), 20)
	_capture("04_freight_yard")
	await _shoot_at(player, Vector2(4180, 320), 20)
	_capture("05_facility")
	player.global_position = Vector2(5040, 300)
	await _wait(2.5)
	Input.action_press(&"shoot")
	await _settle(25)
	_capture("06_boss")
	Input.action_release(&"shoot")
	var info := DamageInfo.create(999, Combat.Team.ENEMY, &"boss_fan")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	await _wait(1.8)
	_capture("07_death_card")
	get_tree().quit()


## 劇情：開場過場、章節標題、通訊、頭目登場、結尾、章節結束。
func _run_story() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _wait(1.0)
	for i in 2:
		Story._layer.advance()
		Story._layer.advance()
	await _wait(0.8)
	_capture("story_prologue")
	Story.skip_cinematic()
	await _wait(1.2)
	_capture("story_chapter_title")
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(level._layout.story_triggers[4]["x"] + 30.0, 320)
	level_camera_snap()
	await _wait(1.6)
	_capture("story_radio")
	player.global_position = Vector2(level._layout.arena_x + 80.0, 300)
	await _wait(2.0)
	Story._layer.advance()
	await _wait(0.6)
	_capture("story_boss_intro")
	Story.skip_cinematic()
	await _wait(1.0)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := node as Enemy
		if enemy != null and enemy.data.is_boss:
			var lethal := DamageInfo.create(9999, Combat.Team.PLAYER, &"test")
			lethal.ignore_invulnerability = true
			lethal.bypass_guard = true
			enemy.health.take_damage(lethal)
	await _wait(4.6)
	for i in 4:
		Story._layer.advance()
		Story._layer.advance()
	await _wait(1.0)
	_capture("story_epilogue")
	Story.skip_cinematic()
	await _wait(1.5)
	_capture("story_chapter_end")


## 格擋：舉盾、完美格擋反彈、護盾能量條。
func _run_block() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(340, 320)
	# 清掉場上敵人，只留一個標靶，讓畫面只呈現格擋本身。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	var dummy_data := load("res://data/enemies/grunt.tres") as EnemyData
	var dummy := dummy_data.behavior.new() as Enemy
	dummy.configure(dummy_data)
	dummy.position = player.global_position + Vector2(150, 0)
	player.get_parent().add_child(dummy)
	dummy.set_physics_process(false)
	level_camera_snap()
	await _settle(10)
	var screen := get_viewport().get_canvas_transform() * (player.global_position + Vector2(90, -16))
	Input.warp_mouse(screen * (Vector2(get_window().size) / get_viewport().get_visible_rect().size))
	await _settle(4)
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	# 先擋一發消耗能量，再在完美格擋時間窗內反彈一發。
	Input.action_press(&"block")
	await _wait(0.3)
	ProjectilePool.spawn(spec, player.aim_origin() + Vector2(16, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _wait(0.2)
	Input.action_release(&"block")
	await _settle(2)
	Input.action_press(&"block")
	ProjectilePool.spawn(spec, player.aim_origin() + Vector2(14, -1), Vector2.LEFT, Combat.Team.ENEMY)
	await _settle(3)
	_capture("block_parry")
	await _wait(0.12)
	_capture("block_reflect")
	Input.action_release(&"block")


## 換彈：手槍彈匣偏低的換彈提示、打空後自動換彈（槍口壓低、彈藥環顯示進度）。
func _run_reload() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(330, 320)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level_camera_snap()
	Input.action_press(&"aim_right")
	await _wait(4.5)
	for i in 10:
		player.loadout.consume_ammo()
	await _wait(0.3)
	_capture("reload_low")
	player.loadout.consume_ammo()
	player.loadout.consume_ammo()
	await _wait(0.45)
	_capture("reload_progress")
	Input.action_release(&"aim_right")


## 武器陣容：每把玩家武器各開火一段時間，拼成一張 4×2 的總覽圖。
func _run_weapons() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	player.global_position = Vector2(330, 320)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level_camera_snap()
	Input.action_press(&"aim_right")
	# 等章節標題淡出。
	await _wait(4.5)
	var ids := ["pistol", "smg", "rifle", "spread", "launcher", "laser", "railgun"]
	var sheet := Image.create(1280, 360, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in ids.size():
		player.loadout.equip(load("res://data/weapons/%s.tres" % ids[i]))
		await _settle(4)
		Input.action_press(&"shoot")
		await _wait(0.35)
		var shot := get_viewport().get_texture().get_image()
		Input.action_release(&"shoot")
		shot.convert(Image.FORMAT_RGBA8)
		# 以角色為中心裁一塊，縮成 1/4 格。
		var center := get_viewport().get_canvas_transform() * (player.global_position + Vector2(70, -26))
		var scale := float(shot.get_width()) / get_viewport().get_visible_rect().size.x
		var crop := Rect2i(Vector2i((center * scale) - Vector2(240, 135)), Vector2i(480, 270)).intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		var tile := shot.get_region(crop)
		tile.resize(320, 180)
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i((i % 4) * 320, (i / 4) * 180))
		await _wait(0.4)
	Input.action_release(&"aim_right")
	var path := _out_dir.path_join("weapons_roster.png")
	print("saved %s (%s)" % [path, error_string(sheet.save_png(path))])


## 動態 HUD：受傷彈出（殘影碎裂）、低血量常駐、破防、彈藥環低彈藥。
func _run_dynamic_hud() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.global_position = Vector2(330, 320)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	level_camera_snap()
	# 用右搖桿瞄準，不受系統滑鼠位置影響。
	Input.action_press(&"aim_right")
	await _wait(3.5)
	_capture("dynamic_hud_idle")
	var info := DamageInfo.create(2, Combat.Team.ENEMY, &"test")
	info.ignore_invulnerability = true
	player.health.take_damage(info)
	await _wait(0.12)
	_capture("dynamic_hud_hit")
	await _wait(0.6)
	player.health.take_damage(info)
	player.loadout.equip(load("res://data/weapons/spread.tres"))
	Input.action_press(&"shoot")
	await _wait(1.6)
	Input.action_release(&"shoot")
	await _wait(0.6)
	_capture("dynamic_hud_low")
	Input.action_press(&"block")
	var spec := load("res://data/projectiles/grunt_shot.tres") as ProjectileSpec
	await _wait(0.3)
	player.guard = 1.0
	ProjectilePool.spawn(spec, player.aim_origin() + Vector2(16, 0), Vector2.LEFT, Combat.Team.ENEMY)
	await _wait(0.25)
	_capture("dynamic_hud_break")
	Input.action_release(&"block")
	Input.action_release(&"aim_right")


## 滑鼠瞄準：準星、擴散、命中標記、武器欄。
func _run_mouse_aim() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load(LEVEL_PATH))
	add_child(level)
	await _settle(20)
	var player := level.player
	player.health.setup(999, 0.0)
	for path in ["res://data/weapons/spread.tres", "res://data/weapons/laser.tres"]:
		player.loadout.equip(load(path))
	player.loadout.select(0)
	player.global_position = Vector2(330, 320)
	level_camera_snap()
	await _settle(10)
	# 準星放在角色右上方（敵人方向），按住射擊。
	var screen := get_viewport().get_canvas_transform() * (player.global_position + Vector2(110, -40))
	Input.warp_mouse(screen * (Vector2(get_window().size) / get_viewport().get_visible_rect().size))
	await _settle(4)
	Input.action_press(&"shoot")
	await _settle(14)
	_capture("mouse_aim_firing")
	Input.action_release(&"shoot")
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var settings := SettingsScreen.new()
	layer.add_child(settings)
	settings._tabs.current_tab = 1
	await _settle(10)
	_capture("mouse_bindings")


func _run_settings() -> void:
	var settings := SettingsScreen.new()
	add_child(settings)
	await _settle(20)
	_capture("settings_audio")
	settings._tabs.current_tab = 1
	await _settle(10)
	settings._begin_capture(&"jump", 1)
	await _settle(10)
	_capture("settings_bindings")
	settings._cancel_capture()
	settings.queue_free()


func _shoot_at(player: Player, position: Vector2, frames: int) -> void:
	player.global_position = position
	level_camera_snap()
	await _settle(15)
	Input.action_press(&"shoot")
	Input.action_press(&"move_right")
	await _settle(frames)
	Input.action_release(&"move_right")


func level_camera_snap() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var camera := get_viewport().get_camera_2d() as LevelCamera
		if camera != null:
			camera.snap_to_target()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(file_name + ".png")
	var err := image.save_png(path)
	print("saved %s (%s) fps=%d" % [path, error_string(err), Engine.get_frames_per_second()])
