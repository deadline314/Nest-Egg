extends RefCounted
## 流程探針經由真正的 Main 換區（ST-19、ST-21）：區域切換走 Main 的出入口路由（會照常存檔），而不是探針自己換關卡。
## 讀檔續玩、章末接下一章都由 Main 處理，探針只等畫面換到指定的區域。
## 用法：route = ProbeMainRoute.new(探針, main)；level = await route.enter(路徑, 位置)。探針要提供 _settle(影格) 與 _check(條件, 說明)。

const LIMIT_MSEC := 120000

var _probe: Node
var _main: Node


func _init(probe: Node, main: Node) -> void:
	_probe = probe
	_main = main


## Main 目前顯示的關卡；選單、結算或過場畫面時是 null。
func level() -> Level:
	var screen: Variant = _main.get("_screen") if is_instance_valid(_main) else null
	return screen as Level if screen is Level else null


## 等 Main 換到指定的區域（而且不是 other_than 那一個畫面），逾時回傳 false。
func wait_level(path: String, other_than: Level = null) -> bool:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		var current := level()
		if current != null and current != other_than and current.data.resource_path == path and current.player != null and current.is_inside_tree():
			return true
		await _probe._settle(1)
	return false


## 走 Main 的出入口路由進到區域（已經在那裡就不換），看完進場演出，必要時把主角放到 near。
func enter(path: String, near := Vector2.INF) -> Level:
	var current := level()
	if current == null or current.data.resource_path != path:
		GameState.pending_portal = &""
		_main.call("_on_area_requested", path)
		_probe._check(await wait_level(path, current), "Main routes into %s" % path.get_file())
	var entered := level()
	await _probe._settle(30)
	for i in 2400:
		if not Story.is_cinematic_active():
			break
		Story.skip_cinematic()
		await _probe._settle(4)
	if entered != null and near != Vector2.INF:
		entered.player.global_position = near
		await _probe._settle(20)
	return entered


## 從 Main 開一局新遊戲並看完開場；回傳是否進到第一個區域。
func start_new_game() -> bool:
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	var started := false
	while Time.get_ticks_msec() < deadline and level() == null:
		if not started and not bool(_main.call("_route_pending")):
			_main.call("_on_start_requested", GameState.difficulties[1])
			started = _main.get("_active_run")
		await _probe._settle(30)
	# 開場演出還在播時寫入的東西會在換區時跟著演出一起撤回：先像玩家一樣看完開場。
	for i in 2400:
		if not Story.is_cinematic_active():
			break
		Story.skip_cinematic()
		await _probe._settle(4)
	return level() != null


## 像玩家一樣按「繼續遊戲」：讀出存檔內容、等 Main 回到存檔的區域；回傳讀到的存檔（讀不到是空字典）。
func continue_game() -> Dictionary:
	var store := _main.get("_run_store") as RunSaveStore
	var data: Dictionary = store.read() if store != null else {}
	_probe._check(not data.is_empty(), "the previous process left a readable save")
	var deadline := Time.get_ticks_msec() + LIMIT_MSEC
	while Time.get_ticks_msec() < deadline and bool(_main.call("_route_pending")):
		await _probe._settle(10)
	_main.call("_on_continue_requested")
	var saved_level := str(data.get("level", ""))
	_probe._check(await wait_level(saved_level), "continue lands back in the saved area %s" % saved_level.get_file())
	return data
