class_name PhoneBoothScenario
extends ScenarioBase
## 截圖情境（NE-121）：電話亭的待機、玩家走近、撥號的整段動作（每 0.1 秒一格）與已啟動的亭子。
## 用法：godot res://tools/screenshot.tscn -- --out=/絕對路徑 --scenario=phone_booth

const LIGHTING := "res://data/lighting/market.tres"
const BOOTH_TILE := 30.0
const FRAMES := 14


func run() -> void:
	GameState.clear_checkpoint()
	await open_arena(LIGHTING, 24.0)
	await clear_enemies()
	var booth := Checkpoint.new()
	booth.position = Vector2(BOOTH_TILE * 16.0, FLOOR_Y)
	level._entities.add_child(booth)
	place_player(BOOTH_TILE - 1.0)
	player.facing = 1
	await wait(1.2)
	capture("phone-0-idle")
	await wait(0.5)
	booth.start_call(player)
	for i in FRAMES:
		capture("phone-call-%02d" % i)
		await wait(0.1)
	await wait(0.6)
	capture("phone-2-active")
	await finish()
