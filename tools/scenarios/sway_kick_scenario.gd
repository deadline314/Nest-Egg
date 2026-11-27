class_name SwayKickScenario
extends ScenarioBase
## 會搖的擺設被帶動（BG-64）：主角實際按鍵衝刺穿過一件會搖的擺設，拍三張：穿過之前、擺到最遠、回彈停下之後。
## 再在擺設旁邊引爆一次，拍擺到最遠的那一格。印出每一次的最大位移，沒有被帶動就記錯誤。
## 用法（原生 Forward+）：godot --path . res://tools/screenshot.tscn -- --out=<絕對資料夾> --scenario=sway_kick

const LEVEL := "res://data/levels/level_01.tres"
## 要拍的擺設（關卡地圖裡站在地上的第一件）。
const PROP_ID := &"tree_jacaranda"
const APPROACH := 70.0
const TIMEOUT_FRAMES := 600


func run() -> void:
	GameState.start_new_run(GameState.difficulties[1])
	Story.auto_skip = true
	level = Level.new()
	level.configure(load(LEVEL) as LevelData)
	add_child(level)
	await settle(30)
	player = level.player
	player.health.setup(999, 0.0)
	level.hud.visible = false
	level._next_story_trigger = level._layout.story_triggers.size()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		node.queue_free()
	var prop: PropNode
	for node in get_tree().get_nodes_in_group(PropNode.GROUP):
		if (node as PropNode).data.id == PROP_ID:
			prop = node as PropNode
			break
	var kick := prop.find_child("SwayKick", false, false) as SwayKick if prop != null else null
	if kick == null:
		failures += 1
		push_error("[SwayKickScenario] %s 裡找不到會被帶動的 %s" % [LEVEL, PROP_ID])
		await finish()
		return
	var feet_y := prop.position.y + prop.data.size.y
	player.global_position = Vector2(prop.position.x - APPROACH, feet_y)
	player.velocity = Vector2.ZERO
	snap_camera()
	await wait(TITLE_CARD_TIME)
	capture("BG-64-sway-0-rest")
	Input.action_press(&"move_right")
	await settle(6)
	Input.action_press(&"dash")
	var dash_peak := await _capture_at_peak(kick, "BG-64-sway-1-dash-peak")
	Input.action_release(&"dash")
	Input.action_release(&"move_right")
	await _until_rest(kick)
	capture("BG-64-sway-2-settled")
	Fx.explosion(prop.global_position + Vector2(-20.0, prop.data.size.y * 0.5), 40.0, 0, Combat.Team.PLAYER, &"sway_kick_scenario")
	var blast_peak := await _capture_at_peak(kick, "BG-64-sway-3-blast-peak")
	await _until_rest(kick)
	print("SWAY_KICK dash_peak=%.2f blast_peak=%.2f rest_offset=%.2f resting=%s" % [dash_peak, blast_peak, kick.offset(), kick.is_resting()])
	if dash_peak < 1.0 or blast_peak < 1.0 or not kick.is_resting():
		failures += 1
		push_error("[SwayKickScenario] 擺設沒有被帶動或沒有停下：衝刺 %.2f、爆炸 %.2f" % [dash_peak, blast_peak])
	await finish()


## 等擺幅開始變小的那一格拍照（那就是擺到最遠的時候），回傳最大位移（像素）。
func _capture_at_peak(kick: SwayKick, file_name: String) -> float:
	var peak := 0.0
	for i in TIMEOUT_FRAMES:
		await get_tree().process_frame
		var now := absf(kick.offset())
		if peak > 0.5 and now < peak:
			break
		peak = maxf(peak, now)
	capture(file_name)
	return peak


func _until_rest(kick: SwayKick) -> void:
	for i in TIMEOUT_FRAMES:
		if kick.is_resting():
			return
		await get_tree().process_frame
