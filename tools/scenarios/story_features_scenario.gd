class_name StoryFeaturesScenario
extends RefCounted
## ST-3 框架驗收情境；只讀測試資料，不改第一章來源或舞台。

static func run(host: Node) -> void:
	Story.load_chapter("res://tests/fixtures/story_features.json")
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = false
	var level := Level.new()
	var data := (load("res://data/levels/ch1_pawnshop.tres") as LevelData).duplicate(true)
	data.intro_scene = &""
	for id: String in data.story_triggers:
		Story._seen[StringName(id)] = true
	level.configure(data)
	host.add_child(level)
	await host._settle(10)
	var player := CutscenePlayer.new()
	host.add_child(player)
	player.play(&"test_story_choice", Story._scenes["test_story_choice"])
	for i in 90:
		if player.choice_active():
			break
		await host._settle(1)
	host._capture("ST-3-choice-options")
	player.choose(0)
	await host._wait(0.65)
	host._capture("ST-3-choice-ask")
	player.skip()
	await host._settle(6)
	var card := {"number": 1, "title": "保留下來的記憶", "text": "復原後仍能查看這張記憶卡。", "hint": "回到登記的電話亭，再繼續前進。"}
	for count in [1, 2, 3]:
		GameState.deaths = count
		var screen := DeathScreen.new()
		screen.sequence = Story.death_sequence(&"ch1_kasa", count).duplicate(true)
		# Widen capture intervals without changing production data.
		for step: Dictionary in screen.sequence.steps:
			step.time = 1.5
		screen.setup(card, true)
		host.add_child(screen)
		await host._wait(0.7)
		host._capture("ST-3-death-%d-first" % count)
		if count == 1:
			await host._wait(1.5)
			host._capture("ST-3-death-voice")
			await host._wait(1.5)
			host._capture("ST-3-death-status")
		for i in 1200:
			if screen.sequence_complete:
				break
			await host._settle(1)
		host._capture("ST-3-death-%d-card" % count)
		screen.queue_free()
		await host._settle(3)
	StoryItems.acquire(&"nest07_shard", false)
	var inventory: InventoryScreen = level._inventory
	inventory.open()
	inventory.select_tab(inventory.page_index(StoryItemsPage))
	await host._wait(0.5)
	host._capture("ST-3-story-inventory")
	inventory.close()
	level.queue_free()
	await host._settle(8)
