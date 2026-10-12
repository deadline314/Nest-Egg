class_name MechanismStatesScenario
extends ScenarioBase
## 連續畫面（BG-41、BG-43、BG-44、BG-45）：第二、三章會跟著進度換樣子的機關，各拍「之前」與每個旗標成立之後；
## 最後兩站沒有旗標，拍主角站進玻璃邊緣的光斑與站在外面，對照光斑有沒有真的照亮人。
## 橋梯（摺起→放下）、貨梯與控制箱（紅→黃→綠）、廣場外梯（收起→放下）、排水輪（指針轉過去、紅→綠）、
## 泵室配電盤（關→開）。每一站主角站在機關旁，玩家在場時旗標才成立，所以會演一次轉場。
## 這裡直接設定劇情旗標只是為了拍畫面；正式遊玩時旗標由劇本寫入。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=mechanism_states

## 每一站：關卡、主角站的欄（機關左邊幾格：鏡頭會往前方偏，機關才在畫面中間）、從哪一列往下找地面、檔名、依序成立的旗標。
const STOPS: Array[Dictionary] = [
	{"level": "ch2_loading", "column": 95, "row": 18, "name": "BG-41-bridge-ladder", "flags": [&"ch2_sc1_open"]},
	{"level": "ch3_plaza", "column": 39, "row": 16, "name": "BG-43-freight-lift", "flags": [&"ch3_lift_powered", &"ch3_freight_ready"]},
	{"level": "ch3_plaza", "column": 55, "row": 18, "name": "BG-43-outer-ladder", "flags": [&"ch3_outer_ladder_down"]},
	{"level": "ch3_pump", "column": 25, "row": 10, "name": "BG-44-drain-wheel", "flags": [&"ch3_pump_low"]},
	{"level": "ch3_pump", "column": 59, "row": 16, "name": "BG-44-branch-panel", "flags": [&"ch3_wet_branch_isolated"]},
	{"level": "ch3_glass_edge", "column": 20, "row": 16, "name": "BG-45-sun-patch-inside", "flags": []},
	{"level": "ch3_glass_edge", "column": 25, "row": 16, "name": "BG-45-sun-patch-outside", "flags": []},
]
## 旗標成立後多久拍一張（指針轉動約 1.4 秒，中途拍一張、轉完再拍一張）。
const MID_TURN := 0.6
const AFTER_TURN := 1.4


func run() -> void:
	for stop in STOPS:
		await _open(stop)
		capture("%s-0" % stop["name"])
		var step := 1
		for flag: StringName in stop["flags"]:
			GameState.set_flag(flag, true, false)
			await wait(MID_TURN)
			capture("%s-%d-turning" % [stop["name"], step])
			await wait(AFTER_TURN)
			capture("%s-%d" % [stop["name"], step])
			step += 1
		level.queue_free()
		await settle(6)
	await finish()


func _open(stop: Dictionary) -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load("res://data/levels/%s.tres" % stop["level"]) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	# 只拍機關：敵人停在原地，不讓受擊的畫面效果蓋住機關。
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.set_physics_process(false)
		node.set_process(false)
	var column := int(stop["column"])
	player.global_position = Vector2((column + 0.5) * level._layout.tile_size, level._layout.floor_below(column, int(stop["row"])))
	snap_camera()
	await wait(TITLE_CARD_TIME)
