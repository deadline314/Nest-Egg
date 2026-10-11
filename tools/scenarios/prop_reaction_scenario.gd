class_name PropReactionScenario
extends ScenarioBase
## 連續畫面（NE-240）：復原館外的交接櫃跟著交盤進度換樣子。正式第一章的交接櫃區，主角站在櫃子旁，
## 依序拍：等收件（藍燈）→ 玩家在場時旗標成立，回執一格一格送出來 → 回執被拿走（綠燈）；
## 再重進關卡一次，確認旗標已成立時直接是結果的樣子、不重播送紙。
## 這裡直接設定劇情旗標只是為了拍畫面；正式遊玩時旗標由劇本的交盤與取回執寫入。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=prop_reaction

const LEVEL := "res://data/levels/ch1_handoff.tres"
const DELIVERED := &"ch1_disk_delivered"
const TAKEN := &"ch1_disk_receipt_taken"


func run() -> void:
	await _open()
	capture("NE-240-cabinet-0-waiting")
	GameState.set_flag(DELIVERED, true, false)
	for frame in 5:
		await wait(0.28)
		capture("NE-240-cabinet-1-feed-%d" % frame)
	await wait(0.6)
	capture("NE-240-cabinet-2-receipt-out")
	GameState.set_flag(TAKEN, true, false)
	await wait(0.4)
	capture("NE-240-cabinet-3-taken")
	level.queue_free()
	await settle(6)
	# 重進關卡：回執已送出、還沒拿——紙直接在那裡，不再送一次。
	GameState.start_new_run(GameState.difficulties[1])
	GameState.set_flag(DELIVERED, true, false)
	await _open(false)
	capture("NE-240-cabinet-4-reenter-receipt-out")
	await finish()


func _open(new_run := true) -> void:
	if new_run:
		GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	level.hud.visible = false
	player.global_position = Vector2(15.0 * 16.0, level._layout.floor_below(15, 10))
	snap_camera()
	await wait(TITLE_CARD_TIME)
