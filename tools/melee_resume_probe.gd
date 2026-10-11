extends Node
## 近戰招式的成長在「真正退出再續玩」後仍保留（NE-237）：兩個分開的程序走真正的 Main。
##   --mode=write：開新局、進第一章街道、拿單分子鞭、買下回甩、由 Main 存檔後結束程序。
##   --mode=read ：另一個程序從主選單的「繼續」讀回，核對回甩仍解鎖、信用點已扣、手上仍是單分子鞭，並真的接出回甩。
## 用法（存檔放在指定的隔離資料夾，不碰正式存檔）：
##   godot --headless res://tools/melee_resume_probe.tscn -- --mode=write --save-dir=/絕對路徑
##   godot --headless res://tools/melee_resume_probe.tscn -- --mode=read --save-dir=/絕對路徑
const MainScript := preload("res://game/main.gd")
const LEVEL := "res://data/levels/ch1_street.tres"
const WHIP := "res://data/weapons/melee/melee_whip.tres"
const TECHNIQUE := &"technique_whip"
const CREDITS := 500

var mode := ""
var directory := ""
var main: Node
var checks := 0
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--save-dir="):
			directory = arg.trim_prefix("--save-dir=")
	if mode not in ["write", "read"] or not directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("[MeleeResume] 需要 --mode=write|read 與絕對路徑的 --save-dir")
		get_tree().quit(2)
		return
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1


func frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame


func _run() -> void:
	Transition.instant = true
	Story.auto_skip = true
	main = MainScript.new()
	main.set("_run_store", RunSaveStore.new(directory.path_join("slot.json")))
	add_child(main)
	await frames()
	var whip := load(WHIP) as WeaponData
	if mode == "write":
		main.call("_on_start_requested", GameState.difficulties[1])
		await frames(10)
		main.call("_on_area_requested", LEVEL)
		await frames(30)
		var level := main.get("_screen") as Level
		check(level != null, "the real Main opened the street")
		if level != null:
			level.player.loadout.equip(whip)
			Progression.credits = CREDITS
			var technique := Progression.find_upgrade(TECHNIQUE)
			check(technique != null and Progression.buy_upgrade(whip, technique), "the return lash is bought through the real shop rule")
			check(Progression.credits == CREDITS - technique.cost, "the purchase paid its price (%d left)" % Progression.credits)
			main.call("_save_run")
			await frames(5)
			var saved: Dictionary = (main.get("_run_store") as RunSaveStore).read()
			check(saved.has("data") or not saved.is_empty(), "Main wrote the run to the isolated slot")
	else:
		main.call("_on_continue_requested")
		await frames(60)
		var level := main.get("_screen") as Level
		check(level != null and level.data.resource_path == LEVEL, "continue reopened the saved street")
		var technique := Progression.find_upgrade(TECHNIQUE)
		check(technique != null and Progression.has_upgrade(whip, TECHNIQUE), "after a real quit the return lash is still unlocked")
		check(technique != null and Progression.credits == CREDITS - technique.cost, "the paid price stayed paid (%d)" % Progression.credits)
		if level != null:
			var player := level.player
			var holding := player.loadout.active_weapon()
			check(holding != null and holding.id == whip.id, "the mono whip is still in hand (%s)" % (holding.id if holding != null else &"none"))
			# 真的接出回甩：甩打的收招期間再按一次（每格重按，緩衝按真實時間到期）。
			var poses: Array[String] = []
			player._try_melee()
			for i in 240:
				var pose := player.melee_pose()
				if not pose.is_empty() and not poses.has(pose):
					poses.append(pose)
				if pose == "mono_whip_lash" and player.melee_pose_progress() >= 0.7:
					player._try_melee()
				await get_tree().physics_frame
			check(poses.has("mono_whip_return_lash"), "the unlocked return lash actually follows the lash after continuing: %s" % [poses])
	print("MELEE_RESUME %s checks=%d failures=%d" % [mode, checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
