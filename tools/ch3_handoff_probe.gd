extends "res://tools/ch3_flow_probe.gd"
## 跨章接續探針・第二段（ST-21）：另一個程序在真正的 Main 按「繼續遊戲」，讀第一段（tools/ch2_handoff_probe.tscn）
## 在第二章章末寫的存檔，回到第三章的當舖；檢查前章的旗標、物品、金額與阿勇的選擇都是存檔帶來的，
## 再用同一份進度把第三章玩到章末，最後確認沒有進到還沒做的下一章。不替前章補設任何旗標或物品。
## 用法：godot --path . res://tools/ch3_handoff_probe.tscn -- --save-dir=<第一段的絕對路徑> --out=<截圖資料夾> [--route=full|minimal]

const ProbeMainRoute := preload("res://tools/probe_main_route.gd")
const ENTRY := "res://data/levels/ch3_pawnshop.tres"
## 第二章章末留下、第三章要用的結果（單獨跑第三章時由 _carry_ch2_results() 補上，這裡必須來自存檔）。
const CARRIED_FLAGS: Array[StringName] = [&"ch1_complete", &"ch2_heron_closed", &"ch2_audit_submitted", &"ch2_original_ledger_taken"]
const CARRIED_ITEMS: Array[StringName] = [&"ch2_clinic_index"]

var _save_dir := ""
var _main: Node
var _route_main: ProbeMainRoute


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
	if not _save_dir.is_absolute_path() or not FileAccess.file_exists(_save_dir.path_join("slot.json")):
		push_error("[Ch3HandoffProbe] --save-dir 要指到第一段寫好的存檔資料夾")
		get_tree().quit(2)
		return
	super._ready()


func _enter(area: String, near := Vector2.INF) -> void:
	_level = await _route_main.enter(level_pattern % area, near)


func _run() -> void:
	action_shot_prefix = "ST-21-handoff"
	_shots = {}
	_previous_skip = Settings.get_skip_cutscenes()
	Settings.set_skip_cutscenes(false)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("_run_store", RunSaveStore.new(_save_dir.path_join("slot.json")))
	add_child(_main)
	_route_main = ProbeMainRoute.new(self, _main)
	await _settle(30)
	var data: Dictionary = await _route_main.continue_game()
	_level = _route_main.level()
	_check(str(data.get("level", "")) == ENTRY, "the save from the chapter 2 ending resumes in the chapter 3 pawnshop")
	var saved_credits := int((data.get("progression", {}) as Dictionary).get("credits", -1))
	_check(Progression.credits == saved_credits and saved_credits > 0, "credits come back exactly as the chapter 2 ending left them (%d)" % Progression.credits)
	var missing_flags := CARRIED_FLAGS.filter(func(id: StringName) -> bool: return not GameState.has_flag(id))
	_check(missing_flags.is_empty(), "chapter 2 results come from the save, not the probe (missing %s)" % [missing_flags])
	var missing_items := CARRIED_ITEMS.filter(func(id: StringName) -> bool: return not StoryItems.holds(id))
	_check(missing_items.is_empty(), "the clinic index Rin took in chapter 2 is still in hand (missing %s)" % [missing_items])
	_yong = str(GameState.get_flag(&"yong_link_choice"))
	_check(_yong in ["cut", "keep"], "Yong's link choice from chapter 2 carries over (%s)" % _yong)
	await _settle(20)
	_capture("ST-21-handoff-continue")
	await _play_chapter()
	# 第三章是目前最後一章：章末之後不能接進還沒做的關卡。
	await _settle(60)
	var after := _route_main.level()
	_check(after == null or after.data.resource_path.begins_with("res://data/levels/ch3_"), "the chapter 3 ending does not enter an unfinished chapter")
	Settings.set_skip_cutscenes(_previous_skip)
	print("CH3_HANDOFF route=%s yong=%s credits=%d failures=%d" % [_route, _yong, Progression.credits, _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)


## 正式 Main 的門禁大廳啟用持久結果：直接送頻道不算數，要真的按住互動鍵拔下維修插銷。
## 工作架的穩定度用盡與主角站到插銷前是明示的樣本（同 tests/probes/janus_completion.gd），不代表打完整場頭目戰。
func _stop_gatekeeper() -> void:
	var janus: JanusBoss = null
	for node: Node in _level.channel_sources:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node is JanusBoss:
			janus = node
	_check(janus != null, "the gate hall has the original gatekeeper rack")
	if janus == null:
		return
	janus.health.kill(DamageInfo.create(janus.health.current, Combat.Team.PLAYER, &"probe_frame_stability"))
	await _settle(10)
	var player := _level.player
	player.global_position = janus.global_position + Vector2(janus.call("_pin_local").x, 0)
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	await _settle(4)
	Input.action_press(&"interact")
	for i in 240:
		if janus.pin_pulled:
			break
		await _settle(1)
	Input.action_release(&"interact")
	player.set_physics_process(true)
	_check(janus.pin_pulled and not janus.is_dying(), "holding interact pulls the real maintenance pin without killing the gatekeeper")
	await _wait_flag(&"ch3_janus_disabled", 240)
