class_name DeathScenario
extends RefCounted
## 截圖情境：依死亡次數變化的劇情。死亡畫面（1、3、30 次）、芽在 8 次時多問的那一句、30 次時重生後的廣播。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=death
## screenshot.gd 只負責派發，畫面細節都在這裡。


static func run(host: Node) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	var level := Level.new()
	level.configure(load("res://data/levels/level_01.tres"))
	host.add_child(level)
	await host._settle(30)
	level.hud.visible = false
	level.player.health.setup(999, 0.0)
	for enemy in host.get_tree().get_nodes_in_group(&"enemies"):
		enemy.queue_free()
	for id: String in Story.scene_ids():
		Story._seen[StringName(id)] = true
	await _death_screens(host, level)
	await _radios(host, level)
	level.queue_free()
	await host._settle(4)
	GameState.start_new_run(GameState.difficulties[1])


static func _death_screens(host: Node, level: Level) -> void:
	var card := DefeatCodex.unlock(&"grunt_shot")
	for deaths in [1, 3, 30]:
		GameState.deaths = deaths
		var screen := DeathScreen.new()
		screen.setup(card, true)
		level.add_child(screen)
		await host._wait(1.4)
		host._capture("death_%d" % deaths)
		screen.queue_free()
		await host._settle(3)


static func _radios(host: Node, level: Level) -> void:
	level.player.global_position = Vector2(120 * 16.0, 19 * 16.0 - 2.0)
	host.level_camera_snap()
	# 8 次：芽多問一句。
	GameState.deaths = 8
	Story.play(&"radio_shield", false)
	await host._wait(1.6)
	host._capture("death_8_radio")
	await host._wait(3.0)
	# 30 次：重生後廣播念出剛剛死掉的時間。
	GameState.deaths = 30
	GameState.last_death_clock = "11 點 40 分"
	Story.play_respawn_reactions(&"chapter_01")
	await host._wait(1.8)
	host._capture("death_30_radio")
	await host._wait(3.0)
