class_name TimedChallengeScenario
extends ScenarioBase
## 「限時抵達」區域挑戰（NE-418）：第四章廠房接線廊。主角實際按住「往右」跑兩趟：
## 一趟不管輸送帶（帶子往左，逆著跑）、一趟先射馬達讓帶子反轉再跑。保留 HUD，拍倒數中與完成提示，
## 印出兩趟從越過起點到抵達出口花了幾秒、剩幾秒。任何一趟沒在時間內完成就記錯誤（限時要讓正常跑法也來得及）。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=timed_challenge

const LEVEL := "res://data/levels/ch4_factory_relay.tres"
const RUN_LIMIT := 90.0


func run() -> void:
	var against := await _attempt(false)
	var with_belt := await _attempt(true)
	print("TIMED_CHALLENGE against_belt=%s reversed_belt=%s" % [against, with_belt])
	if not str(against).begins_with("done") or not str(with_belt).begins_with("done"):
		failures += 1
		push_error("[TimedChallengeScenario] 兩趟都應該在時間內完成：%s / %s" % [against, with_belt])
	await finish()


func _attempt(reverse_belt: bool) -> String:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level._next_story_trigger = level._layout.story_triggers.size()
	var challenge: AreaChallenge
	for node in get_tree().get_nodes_in_group(AreaChallenge.GROUP):
		challenge = node as AreaChallenge
	var belt := get_tree().get_first_node_in_group(Conveyor.GROUP) as Conveyor
	if challenge == null or belt == null:
		push_error("[TimedChallengeScenario] %s 沒有區域挑戰或輸送帶" % LEVEL)
		level.queue_free()
		await settle(4)
		return "missing"
	await wait(AreaChallenge.INTRO_DELAY + 0.4)
	if reverse_belt:
		belt.reverse()
		await wait(0.2)
	Input.action_press(&"move_right")
	var elapsed := 0.0
	var shot := false
	while elapsed < RUN_LIMIT and not challenge.done and not challenge.failed:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if not shot and challenge.time_left >= 0.0 and challenge.time_left < challenge.data.time_limit - 3.0:
			shot = true
			capture("NE-418-timed-%s-0-running" % ["reversed" if reverse_belt else "against"])
	Input.action_release(&"move_right")
	var used := challenge.data.time_limit - challenge.time_left
	var left := challenge.time_left
	await wait(0.6)
	var result := "done" if challenge.done else ("failed" if challenge.failed else "timeout")
	capture("NE-418-timed-%s-1-%s" % ["reversed" if reverse_belt else "against", result])
	level.queue_free()
	await settle(4)
	return "%s used=%.1fs left=%.1fs" % [result, used, left]
