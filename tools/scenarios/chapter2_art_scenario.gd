class_name Chapter2ArtScenario
extends ScenarioBase
## 截圖情境（NE-55）：第二章各區段的場景美術——材質、立面、道具。玩家站在每個區段的代表位置，各拍一張。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=chapter2_art

## [檔名, 欄, 距地面往上的格數]：往上的格數用於站在平台上的位置（維修走道、陽台）。
const SPOTS: Array = [
	["entrance", 32, 0], ["shaft", 100, 0], ["catwalk", 138, 0], ["mezzanine", 160, 0], ["court", 236, 0],
	["chase", 304, 0], ["power", 350, 0], ["arena", 400, 0], ["transfer", 425, 0], ["ward", 452, 0], ["boss", 492, 0],
]


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
	var layout: LevelLayout = level._layout
	for spot: Array in SPOTS:
		var column := int(spot[1])
		var y := layout.floor_below(column, 4) - 2.0
		if str(spot[0]) == "catwalk":
			y = 8.0 * 16.0 - 2.0
		player.global_position = Vector2(float(column) * layout.tile_size + 8.0, y)
		player.velocity = Vector2.ZERO
		snap_camera()
		await wait(1.5)
		capture("NE-55-%s" % spot[0])
	level.queue_free()
	await settle(4)
