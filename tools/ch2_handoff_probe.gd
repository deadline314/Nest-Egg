extends "res://tools/ch2_flow_probe.gd"
## 跨章接續探針・第一段（ST-21）：在真正的 Main 裡新遊戲，帶著第一章收尾的結果從第二章早上一路推到屋頂章末，
## 由 Main 的章末處理存檔並接進第三章的當舖，最後像玩家一樣退出（會存檔）。第二段 tools/ch3_handoff_probe.tscn
## 在另一個程序按「繼續遊戲」，用這份存檔玩第三章，證明前章的結果是真的帶過來的，不是探針自己設的。
## 用法：godot --path . res://tools/ch2_handoff_probe.tscn -- --save-dir=<絕對路徑> --out=<截圖資料夾> [--route=cut|keep]
## 戰鬥與遭遇的銜接方式同第二章流程探針；只驗故事與存檔的接續，不代表真人整章通關。

const ProbeMainRoute := preload("res://tools/probe_main_route.gd")
const NEXT_CHAPTER := "res://data/levels/ch3_pawnshop.tres"

var _save_dir := ""
var _main: Node
var _route_main: ProbeMainRoute


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="):
			_save_dir = arg.trim_prefix("--save-dir=")
	if not _save_dir.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_save_dir) != OK:
		push_error("[Ch2HandoffProbe] 需要可寫入的絕對路徑 --save-dir")
		get_tree().quit(2)
		return
	super._ready()


func _enter(area: String, near := Vector2.INF) -> void:
	_level = await _route_main.enter(level_pattern % area, near)


func _run() -> void:
	action_shot_prefix = "ST-21-handoff"
	_shots = {}
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.set("_run_store", RunSaveStore.new(_save_dir.path_join("slot.json")))
	add_child(_main)
	_route_main = ProbeMainRoute.new(self, _main)
	await _settle(30)
	_check(await _route_main.start_new_game(), "a new game from Main enters the first area")
	_carry_ch1_results()
	await _play_chapter()
	# 屋頂章末：Main 存檔後直接進第三章的當舖（LevelData.next_level），不經過選單或舊的第二章。
	_check(await _route_main.wait_level(NEXT_CHAPTER), "Main carries the run from the chapter 2 ending into the chapter 3 pawnshop")
	_level = _route_main.level()
	var saved: Dictionary = (_main.get("_run_store") as RunSaveStore).read()
	_check(str(saved.get("level", "")) == NEXT_CHAPTER, "the save written at the chapter boundary points at chapter 3 (%s)" % str(saved.get("level", "")).get_file())
	await _settle(30)
	_capture("ST-21-handoff-ch3-entry")
	print("CH2_HANDOFF route=%s credits=%d yong=%s failures=%d" % [_route, Progression.credits, GameState.get_flag(&"yong_link_choice"), _failures])
	_main.call("_quit", 1 if _failures > 0 else 0)
